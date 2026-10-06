import CryptoKit
import Foundation

/// Removes only the discontinued provider's isolated container state, without reading credentials.
struct CodexLegacyCleanup {
    struct Entry: Equatable {
        let service: String
        let account: String
    }

    static let completionKey = "removedLegacyCodexContainerV1"
    let home: URL
    let defaults: UserDefaults
    let deleteEntry: (Entry) throws -> Void
    let removeHome: (URL) throws -> Void

    static func entries(home: URL) -> [Entry] {
        let canonical = home.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let namespace = String(digest.prefix(16))
        return [Entry(service: "Codex Auth", account: "cli|" + namespace),
                Entry(service: "codex", account: "secrets|" + namespace)]
    }

    @discardableResult
    func run() -> Bool {
        if defaults.bool(forKey: Self.completionKey) { return true }
        var complete = true
        for entry in Self.entries(home: home) {
            do { try deleteEntry(entry) } catch { complete = false }
        }
        // Abandoned source copies and generated images are removed even if an old ACL refuses deletion.
        do { try removeHome(home) } catch { complete = false }
        if complete { defaults.set(true, forKey: Self.completionKey) }
        return complete
    }

    static func isIsolatedHome(_ home: URL, containerData: URL) -> Bool {
        let suffix = "Library/Application Support/Daydreaming/Codex"
        let expected = containerData.standardizedFileURL.appendingPathComponent(suffix, isDirectory: true)
        let canonicalExpected = containerData.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent(suffix, isDirectory: true)
        return home.standardizedFileURL.path == expected.standardizedFileURL.path
            && home.resolvingSymlinksInPath().standardizedFileURL.path == canonicalExpected.standardizedFileURL.path
    }

    @MainActor
    static func runIfNeeded() {
        guard Bundle.main.bundleIdentifier == AppRuntime.productionBundleID,
              !AppRuntime.isPreview, !AppRuntime.isRunningTests else { return }
        let containerData = FileManager.default.homeDirectoryForCurrentUser
        // Never use the unsandboxed user home or a personal Codex directory.
        guard containerData.lastPathComponent == "Data",
              containerData.deletingLastPathComponent().lastPathComponent == AppRuntime.productionBundleID,
              containerData.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Containers"
        else { return }
        let home = containerData.appendingPathComponent("Library/Application Support/Daydreaming/Codex", isDirectory: true)
        guard isIsolatedHome(home, containerData: containerData) else { return }
        CodexLegacyCleanup(home: home, defaults: .standard, deleteEntry: { entry in
            // The existing backend suppresses ACL UI and uses an exact service/account query.
            try SecurityKeychainBackend(account: entry.account).remove(service: entry.service, storage: .legacy)
        }, removeHome: { directory in
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }).run()
    }
}
