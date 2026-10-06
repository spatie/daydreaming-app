import AppKit
import Foundation
import UniformTypeIdentifiers

struct PromptFileAuthorizationResult: Sendable {
    let bookmarks: [String: Data]
    let warnings: [String]
}

/// Ask once before the first creation that uses a file. Reading a prompt never opens a panel.
@MainActor
final class PromptFileAuthorization {
    typealias Chooser = @MainActor @Sendable (String) async throws -> URL?
    typealias AttemptRecorder = @MainActor @Sendable (String) -> Void
    typealias IdentityMatcher = @Sendable (URL, URL) -> Bool
    private let chooser: Chooser
    private let bookmarkBackend: any PromptFileBookmarkBackend
    private let onAttempt: AttemptRecorder?
    private var attemptedPaths: Set<String>
    private var pendingPaths = Set<String>()
    private let identityMatcher: IdentityMatcher
    private let usesNativeChooser: Bool
    private var referencedPaths: Set<String>?

    init(bookmarkBackend: any PromptFileBookmarkBackend = SecurityScopedPromptFileBookmarks(),
         initialAttempts: Set<String> = [],
         onAttempt: AttemptRecorder? = nil,
         identityMatcher: @escaping IdentityMatcher = PromptFileAuthorization.matchesFile,
         chooser: Chooser? = nil) {
        self.bookmarkBackend = bookmarkBackend
        self.attemptedPaths = Set(initialAttempts.compactMap { LocalPromptFileDetector.normalizedPath($0) })
        self.onAttempt = onAttempt
        self.chooser = chooser ?? PromptFileAuthorization.chooseFile
        self.usesNativeChooser = chooser == nil
        self.identityMatcher = identityMatcher
    }

    @discardableResult
    func retainAttempts(for prompt: String) -> Set<String> {
        let paths = Set(LocalPromptFileDetector.allPaths(in: prompt))
        referencedPaths = paths
        attemptedPaths.formIntersection(paths)
        return attemptedPaths
    }

    func authorizeMissing(prompt: String, bookmarks: [String: Data], allowInteraction: Bool = true) async -> PromptFileAuthorizationResult {
        var granted = bookmarks
        var warnings: [String] = []
        for path in LocalPromptFileDetector.paths(in: prompt) {
            guard granted[path] == nil else { continue }
            let proposedURL = URL(fileURLWithPath: path)
            guard PromptFileReader.isSupported(proposedURL) else {
                warnings.append("\(proposedURL.lastPathComponent) is not a supported text file.")
                continue
            }
            guard allowInteraction,
                  !usesNativeChooser || (!AppRuntime.isPreview && !AppRuntime.isRunningTests && NSApp.isActive) else {
                warnings.append("Create a wallpaper from Daydreaming to allow access to \(proposedURL.lastPathComponent).")
                continue
            }
            guard !attemptedPaths.contains(path), pendingPaths.insert(path).inserted else {
                warnings.append(Self.notGrantedWarning(for: proposedURL))
                continue
            }
            let chosenURL: URL?
            do {
                chosenURL = try await chooser(path)
            } catch {
                pendingPaths.remove(path)
                warnings.append(Self.notGrantedWarning(for: proposedURL))
                continue
            }
            pendingPaths.remove(path)
            if referencedPaths?.contains(path) != false {
                attemptedPaths.insert(path)
                onAttempt?(path)
            }
            guard let chosenURL, chosenURL.isFileURL,
                  identityMatcher(proposedURL, chosenURL) else {
                warnings.append(Self.notGrantedWarning(for: proposedURL))
                continue
            }
            do {
                granted[path] = try bookmarkBackend.make(url: chosenURL)
            } catch {
                warnings.append(Self.notGrantedWarning(for: proposedURL))
            }
        }
        return PromptFileAuthorizationResult(bookmarks: granted, warnings: warnings)
    }

    private static func notGrantedWarning(for url: URL) -> String {
        "Access to \(url.lastPathComponent) was not granted. Your wallpaper uses the rest of your instructions."
    }

    private static func chooseFile(_ path: String) async throws -> URL? {
        guard !AppRuntime.isPreview, !AppRuntime.isRunningTests, NSApp.isActive else { throw CancellationError() }
        NSApp.activate()
        let url = URL(fileURLWithPath: path)
        let panel = NSOpenPanel()
        panel.title = "Allow Access to This File"
        panel.message = "Daydreaming needs your permission to read \(url.lastPathComponent). Its text can be sent to your selected image provider when creating your wallpaper."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = PromptFileReader.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.showsHiddenFiles = url.lastPathComponent.hasPrefix(".")
        return try await PromptFilePanelSession(panel: panel).run()
    }

    nonisolated private static func matchesFile(_ proposed: URL, _ chosen: URL) -> Bool {
        if proposed.standardizedFileURL == chosen.standardizedFileURL
            || proposed.resolvingSymlinksInPath().standardizedFileURL == chosen.resolvingSymlinksInPath().standardizedFileURL {
            return true
        }
        guard let proposedID = (try? proposed.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject,
              let chosenID = (try? chosen.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject else { return false }
        return proposedID.isEqual(chosenID)
    }
}

@MainActor
private final class PromptFilePanelSession {
    private let panel: NSOpenPanel
    private var interrupted = false
    private var inactiveObserver: NSObjectProtocol?
    private var timeout: Task<Void, Never>?

    init(panel: NSOpenPanel) { self.panel = panel }

    func run() async throws -> URL? {
        inactiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interruptIfNoLongerVisible() }
        }
        timeout = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120))
                self?.interrupt()
            } catch { }
        }
        defer {
            if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
            timeout?.cancel()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                panel.begin { [self] response in
                    if interrupted { continuation.resume(throwing: CancellationError()) }
                    else { continuation.resume(returning: response == .OK ? panel.url : nil) }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.interrupt() }
        }
    }

    private func interrupt() {
        interrupted = true
        panel.cancel(nil)
    }

    private func interruptIfNoLongerVisible() {
        guard !panel.isVisible else { return }
        interrupt()
    }
}
