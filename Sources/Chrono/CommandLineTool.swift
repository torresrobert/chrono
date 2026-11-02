import Foundation

/// Links `chrono` (the terminal view) onto the PATH from Settings, for copies not installed by Homebrew.
/// It never asks for an admin password: it uses the first folder the user can already write to.
struct CommandLineTool {
    enum Status: Equatable {
        /// A `chrono` link to this copy of the app. `byHomebrew` links belong to the cask.
        case installed(URL, byHomebrew: Bool)
        /// A `chrono` that isn't a link to this app; left alone.
        case taken(URL)
        case notInstalled
    }

    enum InstallError: LocalizedError {
        case translocated, noWritableFolder

        var errorDescription: String? {
            switch self {
            case .translocated: "Move Chrono to the Applications folder first. macOS is running it from a temporary copy."
            case .noWritableFolder: "No folder on your PATH can be written to without an admin password."
            }
        }
    }

    /// Searched in order. ~/.local/bin is created if needed, but a shell only finds it if it's on the PATH.
    let folders: [URL]
    /// The app's own executable, which `chrono` links to.
    let target: URL
    var fileManager = FileManager.default

    static let standard = CommandLineTool(
        folders: [URL(fileURLWithPath: "/usr/local/bin"), URL(fileURLWithPath: "/opt/homebrew/bin"),
                  FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")],
        target: URL(fileURLWithPath: Bundle.main.executablePath ?? "/Applications/Chrono.app/Contents/MacOS/Chrono"))

    var status: Status {
        var taken: URL?
        for folder in folders {
            let link = folder.appendingPathComponent("chrono")
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else {
                if taken == nil, fileManager.fileExists(atPath: link.path) { taken = link }
                continue
            }
            let resolved = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path == target.standardizedFileURL.resolvingSymlinksInPath().path else {
                if taken == nil { taken = link }
                continue
            }
            // The cask's link sits in Homebrew's bin and is recorded in its Caskroom.
            let caskroom = folder.deletingLastPathComponent().appendingPathComponent("Caskroom/chrono")
            return .installed(link, byHomebrew: fileManager.fileExists(atPath: caskroom.path))
        }
        return taken.map(Status.taken) ?? .notInstalled
    }

    /// Creates the link in the first writable folder and returns it.
    func install() throws -> URL {
        guard !target.path.contains("/AppTranslocation/") else { throw InstallError.translocated }
        for folder in folders {
            if !fileManager.fileExists(atPath: folder.path), folder.lastPathComponent == "bin",
               folder.deletingLastPathComponent().lastPathComponent == ".local" {
                try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let link = folder.appendingPathComponent("chrono")
            let occupied = (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil
                || fileManager.fileExists(atPath: link.path)
            guard fileManager.isWritableFile(atPath: folder.path), !occupied else { continue }
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
            return link
        }
        throw InstallError.noWritableFolder
    }

    /// Removes a link this app made. Homebrew's link and anything that isn't a link to Chrono stay.
    func remove() throws {
        guard case .installed(let link, byHomebrew: false) = status else { return }
        try fileManager.removeItem(at: link)
    }

    /// True when a shell started from Terminal would find a command in `folder`: macOS adds the
    /// folders listed in /etc/paths and /etc/paths.d to every login shell's PATH.
    static func onDefaultPath(_ folder: URL) -> Bool {
        let lists = ["/etc/paths"] + ((try? FileManager.default.contentsOfDirectory(atPath: "/etc/paths.d"))?
            .map { "/etc/paths.d/" + $0 } ?? [])
        let entries = lists.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .flatMap { $0.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) } }
        return entries.contains(folder.path)
    }
}
