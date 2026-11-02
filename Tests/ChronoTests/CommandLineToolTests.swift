import Foundation
import Testing
@testable import Chrono

struct CommandLineToolTests {
    /// A scratch tree: an unwritable (missing) folder, two writable bins, and a fake app executable.
    private func scratch() throws -> (root: URL, missing: URL, first: URL, second: URL, app: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chrono-cli-\(UUID().uuidString)")
        let first = root.appendingPathComponent("usr/local/bin"), second = root.appendingPathComponent("home/bin")
        let app = root.appendingPathComponent("Applications/Chrono.app/Contents/MacOS/Chrono")
        for folder in [first, second, app.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: app.path, contents: Data())
        return (root, root.appendingPathComponent("missing/bin"), first, second, app)
    }

    @Test func installsInFirstWritableFolderAndRemoves() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let tool = CommandLineTool(folders: [s.missing, s.first, s.second], target: s.app)
        #expect(tool.status == .notInstalled)
        let link = try tool.install()
        #expect(link == s.first.appendingPathComponent("chrono"))
        #expect(tool.status == .installed(link, byHomebrew: false))
        try tool.remove()
        #expect(tool.status == .notInstalled)
        #expect(FileManager.default.fileExists(atPath: s.app.path))
    }

    @Test func skipsAnotherChronoAndLeavesIt() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let other = s.first.appendingPathComponent("chrono")
        FileManager.default.createFile(atPath: other.path, contents: Data("#!/bin/sh\n".utf8))
        let tool = CommandLineTool(folders: [s.first, s.second], target: s.app)
        #expect(tool.status == .taken(other))
        let link = try tool.install()
        #expect(link == s.second.appendingPathComponent("chrono"))
        #expect(tool.status == .installed(link, byHomebrew: false))
        try tool.remove()
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func linkToSomethingElseIsNotRemoved() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let link = s.first.appendingPathComponent("chrono")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr/bin/top"))
        let tool = CommandLineTool(folders: [s.first], target: s.app)
        #expect(tool.status == .taken(link))
        try tool.remove()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == "/usr/bin/top")
    }

    @Test func homebrewLinkIsReportedAndKept() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let prefix = s.root.appendingPathComponent("opt/homebrew"), bin = prefix.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("Caskroom/chrono"), withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("chrono")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: s.app)
        let tool = CommandLineTool(folders: [s.first, bin], target: s.app)
        #expect(tool.status == .installed(link, byHomebrew: true))
        try tool.remove()
        #expect(tool.status == .installed(link, byHomebrew: true))
    }

    @Test func refusesATranslocatedCopy() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Chrono.app/Contents/MacOS/Chrono")
        let tool = CommandLineTool(folders: [s.first], target: translocated)
        #expect(throws: CommandLineTool.InstallError.self) { try tool.install() }
        #expect(!FileManager.default.fileExists(atPath: s.first.appendingPathComponent("chrono").path))
    }

    @Test func reportsWhenNoFolderIsWritable() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let tool = CommandLineTool(folders: [s.missing], target: s.app)
        #expect(throws: CommandLineTool.InstallError.self) { try tool.install() }
    }
}
