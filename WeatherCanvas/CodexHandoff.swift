import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An explicit handoff to the stock desktop app, not an automatic image provider.
enum CodexHandoff {
    struct Request: Sendable {
        let sourceURL: URL
        let instructions: String
    }

    struct Export: Sendable {
        let folderURL: URL
        let pictureURL: URL
        let instructionsURL: URL
        let chatURL: URL
    }

    static let installationURL = URL(string: "https://learn.chatgpt.com/docs/image-generation")!

    @MainActor static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "codex://threads/new")!) != nil
    }

    @MainActor static func chooseFolderAndOpen(_ request: Request) async throws -> URL? {
        guard isAvailable else { throw CodexHandoffError.appNotInstalled }
        let panel = NSOpenPanel()
        panel.title = "Send Your Picture to Codex"
        panel.message = "Choose where to save your picture and instructions. Codex opens a new chat for you to review and send."
        panel.prompt = "Prepare for Codex"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let folder = panel.url else { return nil }

        let worker = Task.detached(priority: .userInitiated) {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            return try export(request, to: folder)
        }
        let prepared = try await withTaskCancellationHandler {
            let result = try await worker.value
            if Task.isCancelled {
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                try? FileManager.default.removeItem(at: result.folderURL)
                throw CancellationError()
            }
            return result
        } onCancel: { worker.cancel() }

        guard NSWorkspace.shared.open(prepared.chatURL) else {
            throw CodexHandoffError.couldNotOpen(folder: prepared.folderURL)
        }
        return prepared.folderURL
    }

    /// Writes only the selected picture and the supplied instructions. No credentials or context files.
    static func export(_ request: Request, to parent: URL) throws -> Export {
        try Task.checkCancellation()
        guard request.sourceURL.isFileURL, parent.isFileURL else { throw CodexHandoffError.invalidFolder }
        let folder = parent.appendingPathComponent("Daydreaming-Codex-" + UUID().uuidString, isDirectory: true)
        let picture = folder.appendingPathComponent("reference.png")
        let instructionsFile = folder.appendingPathComponent("instructions.txt")
        let instructions = composerText(for: request.instructions)
        let url = try chatURL(folder: folder, prompt: instructions)

        // ImageStore normalizes orientation. PNG export leaves private original metadata behind.
        let image = try ImageStore.orientedImage(from: request.sourceURL, maximumPixelSize: 8_192)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            guard let destination = CGImageDestinationCreateWithURL(
                picture as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { throw ImageStoreError.unreadableImage }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.unreadableImage }
            try instructions.write(to: instructionsFile, atomically: true, encoding: .utf8)
            try Task.checkCancellation()
            return Export(folderURL: folder, pictureURL: picture, instructionsURL: instructionsFile, chatURL: url)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func composerText(for instructions: String) -> String {
        """
        Use image generation to edit reference.png in this folder into one wallpaper variation. Preserve its framing and recognizable subjects. Save the resulting picture in this folder. Do not change other files.

        My Daydreaming idea:
        \(instructions.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    static func chatURL(folder: URL, prompt: String) throws -> URL {
        guard folder.isFileURL else { throw CodexHandoffError.invalidFolder }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "path", value: folder.path), URLQueryItem(name: "prompt", value: prompt)]
        guard let url = components.url else { throw CodexHandoffError.invalidFolder }
        return url
    }
}

enum CodexHandoffError: LocalizedError {
    case appNotInstalled
    case invalidFolder
    case couldNotOpen(folder: URL)

    var errorDescription: String? {
        switch self {
        case .appNotInstalled:
            "Install the Codex desktop app to create there. Daydreaming opens a prepared chat; you review and send it yourself."
        case .invalidFolder:
            "Choose a local folder for your Codex picture and instructions."
        case .couldNotOpen(let folder):
            "Codex could not open. Your picture and instructions are saved in \(folder.lastPathComponent)."
        }
    }
}
