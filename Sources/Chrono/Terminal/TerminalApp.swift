import Darwin
import Foundation

/// `chrono`: the terminal view. The app's own binary runs it when invoked under that name
/// (a symlink on the PATH) or with `--terminal`, so there's one signed binary to ship.
@MainActor
enum TerminalApp {
    static let usage = """
    usage: chrono [--interval SECONDS]

    Chrono's live view for the terminal: CPU, GPU, memory, disk, network, sensors and the
    busiest processes, with the menu bar app's history charts.

      1–5, r     chart range: Live, 1H, 24H, 7D, 30D
      tab, ← →   chart metric
      c, m       sort processes by CPU or memory
      q          quit

    When output isn't a terminal, prints the current readings once.
    """

    static func run(arguments: [String]) -> Never {
        var interval = Settings.shared.interval
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--terminal":
                continue
            case "-h", "--help":
                print(usage)
                exit(0)
            case "-s", "--interval":
                guard let value = rest.popFirst().flatMap(Double.init), value >= 0.5 else {
                    fail("--interval needs a number of seconds, 0.5 or more")
                }
                interval = value
            default:
                fail("unknown option: \(argument)")
            }
        }
        guard isatty(STDOUT_FILENO) == 1 else {
            Diagnostics.dump()
            exit(0)
        }
        TerminalSession(interval: interval).run()
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("chrono: \(message)\n\n\(usage)\n".utf8))
        exit(64)
    }
}

@MainActor
private final class TerminalSession {
    private let store = Store()
    private let terminal = Terminal()
    private var dashboard: Dashboard
    private let interval: Double
    private var sources: [DispatchSourceProtocol] = []

    init(interval: Double) {
        self.interval = interval
        dashboard = Dashboard(store: store, interval: interval)
    }

    func run() -> Never {
        store.processConsumers = 1
        // Prime the rate counters so the first frame shows real numbers instead of zeros.
        store.refreshNow()
        Thread.sleep(forTimeInterval: 0.5)

        terminal.enter()
        handleSignals()
        handleInput()
        store.onUpdate = { [weak self] in self?.draw() }
        store.start(interval: interval)
        draw()
        RunLoop.main.run()
        quit()
    }

    private func draw() {
        let size = terminal.size
        terminal.draw(dashboard.lines(width: size.width, height: size.height), colors: .current)
    }

    private func quit() -> Never {
        terminal.leave()
        exit(0)
    }

    private func handleSignals() {
        let handlers: [(Int32, () -> Void)] = [
            (SIGWINCH, { [unowned self] in draw() }),
            (SIGINT, { [unowned self] in quit() }),
            (SIGTERM, { [unowned self] in quit() }),
            (SIGHUP, { [unowned self] in quit() }),
            // ^Z: give the shell its terminal back, stop, and take over again on `fg`.
            (SIGTSTP, { [unowned self] in
                terminal.leave()
                kill(getpid(), SIGSTOP)
                terminal.enter()
                draw()
            }),
        ]
        for (number, handler) in handlers {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { handler() } }
            source.resume()
            sources.append(source)
        }
    }

    private func handleInput() {
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler { [unowned self] in
            MainActor.assumeIsolated {
                var buffer = [UInt8](repeating: 0, count: 64)
                let count = read(STDIN_FILENO, &buffer, buffer.count)
                guard count > 0 else { return source.cancel() }
                handle(Array(buffer.prefix(count)))
            }
        }
        source.resume()
        sources.append(source)
    }

    private func handle(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            // Arrow keys and shift-tab arrive as ESC [ <letter>.
            if bytes[i] == 0x1B, i + 2 < bytes.count, bytes[i + 1] == UInt8(ascii: "[") {
                switch bytes[i + 2] {
                case UInt8(ascii: "C"): dashboard.cycleMetric(by: 1)
                case UInt8(ascii: "D"), UInt8(ascii: "Z"): dashboard.cycleMetric(by: -1)
                default: break
                }
                i += 3
                continue
            }
            switch bytes[i] {
            case UInt8(ascii: "q"), UInt8(ascii: "Q"), 0x03: quit()
            case 0x09: dashboard.cycleMetric(by: 1)
            case UInt8(ascii: "1")...UInt8(ascii: "5"):
                dashboard.range = HistoryRange.allCases[Int(bytes[i] - UInt8(ascii: "1"))]
            case UInt8(ascii: "r"): dashboard.cycleRange()
            case UInt8(ascii: "c"): dashboard.sortByMemory = false
            case UInt8(ascii: "m"): dashboard.sortByMemory = true
            default: break
            }
            i += 1
        }
        draw()
    }
}
