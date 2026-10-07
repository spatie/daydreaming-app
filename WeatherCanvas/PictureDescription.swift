import CoreML
import ImageIO
import OSLog
import SwiftUI
import Vision

/// Display metadata only. Naming a picture never changes its recipe or cache key.
struct PictureDescriptionText: View {
    let sourceURL: URL?
    let digest: String?
    let fallback: String
    @State private var description: String?
    private var identity: String { digest ?? sourceURL?.path ?? fallback }

    var body: some View {
        Text(description ?? (sourceURL == nil ? fallback : "Your picture"))
            .task(id: identity) {
                description = nil
                guard let sourceURL else { return }
                let result = await PictureDescriptionStore.shared.description(for: sourceURL, digest: digest)
                guard !Task.isCancelled else { return }
                description = result
            }
    }
}

/// One small CPU analysis per original, shared across the sidebar and history.
actor PictureDescriptionStore {
    static let shared = PictureDescriptionStore(cacheURL: ImageStore.root.appendingPathComponent("picture-descriptions.json"))
    private let cacheURL: URL?
    private let classify: @Sendable (URL) async -> String?
    private var descriptions: [String: String]
    private var inFlight: [String: Task<String?, Never>] = [:]

    init(cacheURL: URL?, classify: @escaping @Sendable (URL) async -> String? = PictureDescriptionStore.classifyImage) {
        self.cacheURL = cacheURL
        self.classify = classify
        descriptions = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func description(for url: URL, digest: String?) async -> String? {
        let key = "v1:" + (digest ?? url.standardizedFileURL.path)
        if let saved = descriptions[key] { return saved }
        if let task = inFlight[key] { return await task.value }
        let classify = classify
        let task = Task.detached(priority: .utility) { await classify(url) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        guard let result else { return nil }
        descriptions[key] = result
        if let cacheURL {
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(descriptions).write(to: cacheURL, options: .atomic)
            } catch {
                Logger(subsystem: "be.spatie.daydreaming", category: "PictureDescription")
                    .notice("Could not save picture descriptions: \(error.localizedDescription, privacy: .private)")
            }
        }
        return result
    }

    nonisolated private static func classifyImage(at url: URL) async -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        var request = ClassifyImageRequest()
        for (stage, devices) in request.supportedComputeStageDevices {
            guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else { return nil }
            request.setComputeDevice(cpu, for: stage)
        }
        do {
            let observations = try await request.perform(on: image)
            return PictureDescription.make(from: observations.map { .init(identifier: $0.identifier, confidence: $0.confidence) })
        } catch { return nil }
    }
}

enum PictureDescription {
    struct Classification: Sendable {
        let identifier: String
        let confidence: Float
    }

    static func make(from observations: [Classification]) -> String {
        let scores = Dictionary(observations.map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max)
        func score(_ identifiers: String...) -> Float { identifiers.map { scores[$0] ?? 0 }.max() ?? 0 }
        let subject: String
        if score("city", "cityscape", "skyscraper") >= 0.3
            || (score("street", "road") >= 0.3 && score("apartment", "building", "house") >= 0.18) {
            subject = "City view"
        } else if score("mountain", "cliff", "canyon") >= 0.3 { subject = "Mountain landscape" }
        else if score("beach", "coast", "seashore") >= 0.3 { subject = "Coastline" }
        else if score("forest", "woodland") >= 0.3 { subject = "Forest" }
        else if score("lake", "river") >= 0.3 { subject = "Waterside landscape" }
        else if score("flower", "flowers") >= 0.5 { subject = "Flowers" }
        else if score("dog") >= 0.5 { subject = "Dog" }
        else if score("cat") >= 0.5 { subject = "Cat" }
        else if score("abstract", "art", "painting", "drawing", "illustration") >= 0.3 { subject = "Artwork" }
        else if score("tree", "plant") >= 0.5 { subject = "Green landscape" }
        else if score("sky", "cloudy") >= 0.5 { subject = "Clouds and sky" }
        else if score("outdoor", "land") >= 0.5 { subject = "Landscape" }
        else { subject = "Your picture" }
        if score("sunset_sunrise") >= 0.5 && subject != "Your picture" && subject != "Artwork" {
            return subject + " in golden light"
        }
        return subject
    }
}
