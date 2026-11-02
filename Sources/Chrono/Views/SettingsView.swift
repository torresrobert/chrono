import SwiftUI

enum Links {
    static let repository = URL(string: "https://github.com/torresrobert/chrono")!
    static let issues = URL(string: "https://github.com/torresrobert/chrono/issues")!
    static let torresLabs = URL(string: "https://torresrobert.com")!
}

struct SettingsView: View {
    @Bindable var settings: Settings
    let store: Store
    @State private var launchAtLogin = Settings.shared.launchAtLogin

    var body: some View {
        Form {
            SwiftUI.Section("Menu Bar") {
                ForEach(Module.allCases) { module in
                    Toggle(isOn: Binding(get: { settings.isEnabled(module) },
                                         set: { settings.set(module, enabled: $0) })) {
                        Label(module.title, systemImage: module.symbol)
                    }
                    .disabled(module == .battery && store.battery == nil && !settings.isEnabled(.battery))
                }
                Picker("Style", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("CPU shows", selection: $settings.cpuMenuBar) {
                    ForEach(CPUMenuBarDisplay.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!settings.isEnabled(.cpu))
                Toggle("Show captions (CPU, MEM…)", isOn: $settings.showLabels)
            }
            SwiftUI.Section("General") {
                Picker("Update every", selection: $settings.interval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Picker("Temperature", selection: $settings.fahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                LabeledContent("Accent") {
                    HStack(spacing: 8) {
                        ForEach(Accent.allCases) { accent in
                            AccentSwatch(accent: accent, selected: settings.accent == accent) {
                                settings.accent = accent
                            }
                        }
                    }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        settings.launchAtLogin = on
                        launchAtLogin = settings.launchAtLogin
                    }
            }
            SwiftUI.Section("Terminal") {
                CommandLineToolRow()
            }
            SwiftUI.Section("This Mac") {
                LabeledContent("Model", value: SystemInfo.current.model)
                LabeledContent("Chip", value: SystemInfo.current.chip)
                LabeledContent("Memory", value: Format.bytes(SystemInfo.current.memory))
                LabeledContent("Cores", value: store.clusters.map { "\($0.cores.count) \($0.name)" }.joined(separator: " + "))
            }
            SwiftUI.Section {
                AboutView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
    }
}

/// Installs `chrono`, the terminal view, for copies of the app that Homebrew didn't install.
private struct CommandLineToolRow: View {
    @State private var status = CommandLineTool.standard.status
    @State private var failure: String?

    var body: some View {
        LabeledContent {
            switch status {
            case .installed(_, byHomebrew: true), .taken:
                EmptyView()
            case .installed:
                Button("Remove") { run { try CommandLineTool.standard.remove() } }
            case .notInstalled:
                Button("Install") { run { _ = try CommandLineTool.standard.install() } }
            }
        } label: {
            Text("Command-line tool")
            Text(detail).foregroundStyle(failure == nil ? Theme.textSecondary : Theme.negative)
        }
        .onAppear { status = CommandLineTool.standard.status }
    }

    private var detail: String {
        if let failure { return failure }
        switch status {
        case .installed(let link, let byHomebrew):
            let path = (link.path as NSString).abbreviatingWithTildeInPath
            if byHomebrew { return "Installed by Homebrew at \(path)." }
            return CommandLineTool.onDefaultPath(link.deletingLastPathComponent())
                ? "Type chrono in Terminal. Installed at \(path)."
                : "Installed at \(path). If your shell can't find chrono, add \((link.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) to your PATH."
        case .taken(let link):
            return "Another chrono is already at \((link.path as NSString).abbreviatingWithTildeInPath)."
        case .notInstalled:
            return "Shows these readings in Terminal, for SSH sessions with no menu bar."
        }
    }

    private func run(_ change: () throws -> Void) {
        do {
            try change()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        status = CommandLineTool.standard.status
    }
}

private struct AccentSwatch: View {
    let accent: Accent
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle().fill(accent.color)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
                .overlay(Circle().strokeBorder(accent.color, lineWidth: selected ? 1 : 0).padding(-2.5))
        }
        .buttonStyle(.plain)
        .help(accent.title)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Chrono").font(.title3.weight(.bold))
                    Text("v\(version)").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Text("System telemetry for your Mac.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                Text("Free and open source under the MIT License. No network access, no analytics — everything stays on this Mac.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Link("Source code", destination: Links.repository)
                    Link("Report an issue", destination: Links.issues)
                    Link("Torres Labs", destination: Links.torresLabs)
                }
                .font(.caption.weight(.medium))
                .padding(.top, 2)
                Text("© 2026 Torres Labs LLC")
                    .font(.caption2).foregroundStyle(Theme.textSecondary).padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
