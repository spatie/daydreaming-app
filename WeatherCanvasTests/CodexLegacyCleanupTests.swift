import Foundation
import XCTest
@testable import Daydreaming

final class CodexLegacyCleanupTests: XCTestCase {
    func testCleanupDeletesOnlyTheTwoIsolatedEntriesAndRunsOnce() throws {
        let suite = "LegacyCleanup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = URL(fileURLWithPath: "/fixture/Containers/be.spatie.daydreaming/Data/Library/Application Support/Daydreaming/Codex")
        var deleted: [CodexLegacyCleanup.Entry] = []
        var removed: [URL] = []
        let cleanup = CodexLegacyCleanup(home: home, defaults: defaults,
            deleteEntry: { deleted.append($0) }, removeHome: { removed.append($0) })
        XCTAssertTrue(cleanup.run())
        XCTAssertTrue(cleanup.run())
        XCTAssertEqual(deleted, CodexLegacyCleanup.entries(home: home))
        XCTAssertEqual(deleted.map(\.service), ["Codex Auth", "codex"])
        XCTAssertFalse(deleted.contains { $0.service.contains("openai") || $0.account == "image-api-key" })
        XCTAssertNotEqual(deleted, CodexLegacyCleanup.entries(home: URL(fileURLWithPath: "/Users/person/.codex")))
        XCTAssertEqual(removed, [home])
    }

    func testFailedDeletionDoesNotPreventHomeCleanupAndCanRetrySafely() throws {
        let suite = "LegacyCleanup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = URL(fileURLWithPath: "/fixture/Codex")
        var fail = true
        var removals = 0
        let cleanup = CodexLegacyCleanup(home: home, defaults: defaults,
            deleteEntry: { _ in if fail { throw CocoaError(.fileWriteNoPermission) } },
            removeHome: { _ in removals += 1 })
        XCTAssertFalse(cleanup.run())
        XCTAssertFalse(defaults.bool(forKey: CodexLegacyCleanup.completionKey))
        XCTAssertEqual(removals, 1)
        fail = false
        XCTAssertTrue(cleanup.run())
        XCTAssertTrue(defaults.bool(forKey: CodexLegacyCleanup.completionKey))
        XCTAssertEqual(removals, 2)
    }

    func testOldHomeIsRemovedWithoutTouchingPicturesOrPersonalCodex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyCleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldHome = root.appendingPathComponent("Daydreaming/Codex")
        let work = oldHome.appendingPathComponent("Work/job")
        let pictures = root.appendingPathComponent("Daydreaming/Pictures")
        let personal = root.appendingPathComponent(".codex")
        for directory in [work, pictures, personal] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: directory.appendingPathComponent("keep.txt"))
        }
        let suite = "LegacyCleanup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cleanup = CodexLegacyCleanup(home: oldHome, defaults: defaults, deleteEntry: { _ in },
            removeHome: { try FileManager.default.removeItem(at: $0) })
        XCTAssertTrue(cleanup.run())
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldHome.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pictures.appendingPathComponent("keep.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: personal.appendingPathComponent("keep.txt").path))
    }

    func testIsolationRejectsPersonalHomeAndSymlinkToIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyCleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("Containers/be.spatie.daydreaming/Data")
        let expected = container.appendingPathComponent("Library/Application Support/Daydreaming/Codex")
        XCTAssertTrue(CodexLegacyCleanup.isIsolatedHome(expected, containerData: container))
        let personal = root.appendingPathComponent(".codex")
        XCTAssertFalse(CodexLegacyCleanup.isIsolatedHome(personal, containerData: container))
        try FileManager.default.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: expected, withDestinationURL: personal)
        XCTAssertFalse(CodexLegacyCleanup.isIsolatedHome(expected, containerData: container))
    }
}
