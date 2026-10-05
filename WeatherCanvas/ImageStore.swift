import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImportedImage {
    let originalURL: URL
    let uploadURL: URL
    let digest: String
}

enum ImageStore {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daydreaming", isDirectory: true)
    }

    static var cacheDirectory: URL { root.appendingPathComponent("Cache", isDirectory: true) }

    static func importImage(from selectedURL: URL) throws -> ImportedImage {
        let directory = root.appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileExtension = selectedURL.pathExtension.isEmpty ? "jpg" : selectedURL.pathExtension.lowercased()
        let originalURL = directory.appendingPathComponent("original.\(fileExtension)")
        try FileManager.default.copyItem(at: selectedURL, to: originalURL)

        let originalData = try Data(contentsOf: originalURL)
        let digest = SHA256.hash(data: originalData).map { String(format: "%02x", $0) }.joined()
        let uploadURL = directory.appendingPathComponent("upload.jpg")
        try makeUploadImage(from: originalURL, to: uploadURL)

        return ImportedImage(originalURL: originalURL, uploadURL: uploadURL, digest: digest)
    }

    static func uploadURL(for sourcePath: String) -> URL {
        URL(fileURLWithPath: sourcePath).deletingLastPathComponent().appendingPathComponent("upload.jpg")
    }

    static func outputSize(for sourcePath: String) throws -> String {
        let url = uploadURL(for: sourcePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageStoreError.unreadableImage
        }

        let longEdge = 2_560.0
        let scale = longEdge / Double(max(width, height))
        let outputWidth = max(864, Int((Double(width) * scale / 16).rounded()) * 16)
        let outputHeight = max(864, Int((Double(height) * scale / 16).rounded()) * 16)

        return "\(outputWidth)x\(outputHeight)"
    }

    static func cacheURL(for key: String) throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        return cacheDirectory.appendingPathComponent("\(key).png")
    }

    static func cacheKey(
        settings: CanvasSettings,
        context: RenderContext,
        renderedPrompt: String,
        size: String,
        forceFresh: Bool
    ) -> String {
        var parts = [
            settings.sourceDigest ?? "",
            renderedPrompt,
            settings.model.rawValue,
            settings.quality.rawValue,
            size,
            context.weather,
            String(context.intervalMinutes),
            String(context.slot),
        ]

        if !settings.reuseMatchingImages {
            parts.append(context.localDay)
        }

        if forceFresh {
            parts.append(UUID().uuidString)
        }

        let data = Data(parts.joined(separator: "\u{0}").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func cacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return enumerator.compactMap { item -> Int64? in
            guard let url = item as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize.map(Int64.init)
        }.reduce(0, +)
    }

    static func clearCache() throws {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    private static func makeUploadImage(from originalURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil) else {
            throw ImageStoreError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_560,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw ImageStoreError.unreadableImage
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw ImageStoreError.unreadableImage
        }
    }
}

enum ImageStoreError: LocalizedError {
    case unreadableImage

    var errorDescription: String? { "This image could not be read. Try a JPEG, PNG, or HEIC file." }
}
