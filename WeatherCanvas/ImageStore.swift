import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImportedImage: Sendable {
    let originalURL: URL
    let uploadURL: URL
    let digest: String
}

struct ImageOutputDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
    var size: String { "\(width)x\(height)" }
}

enum ImageStore {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daydreaming", isDirectory: true)
    }

    static var cacheDirectory: URL { root.appendingPathComponent("Cache", isDirectory: true) }

    static func owns(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized.hasPrefix(root.standardizedFileURL.path + "/")
    }

    static func importImage(from selectedURL: URL, storageRoot: URL? = nil) throws -> ImportedImage {
        try Task.checkCancellation()
        let directory = (storageRoot ?? root).appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileExtension = selectedURL.pathExtension.isEmpty ? "jpg" : selectedURL.pathExtension.lowercased()
        let originalURL = directory.appendingPathComponent("original.\(fileExtension)")
        do {
            // Copy validated bytes, never an external symlink that could break the saved original later.
            let originalData = try Data(contentsOf: selectedURL)
            guard CGImageSourceCreateWithData(originalData as CFData, nil) != nil else { throw ImageStoreError.unreadableImage }
            try originalData.write(to: originalURL, options: .atomic)
            try Task.checkCancellation()
            let digest = SHA256.hash(data: originalData).map { String(format: "%02x", $0) }.joined()
            let uploadURL = directory.appendingPathComponent("upload.jpg")
            try makeUploadImage(from: originalURL, to: uploadURL)
            try Task.checkCancellation()
            return ImportedImage(originalURL: originalURL, uploadURL: uploadURL, digest: digest)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Keep file access alive in the worker, even if the caller cancels during decoding.
    static func importImageInBackground(from selectedURL: URL, storageRoot: URL? = nil) async throws -> ImportedImage {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            let access = selectedURL.startAccessingSecurityScopedResource()
            defer { if access { selectedURL.stopAccessingSecurityScopedResource() } }
            return try importImage(from: selectedURL, storageRoot: storageRoot)
        }
        return try await withTaskCancellationHandler {
            let imported = try await worker.value
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: imported.originalURL.deletingLastPathComponent())
                throw CancellationError()
            }
            return imported
        } onCancel: { worker.cancel() }
    }

    /// Decode and crop off the main actor. The selected picture is never overwritten.
    static func cropImage(from selectedURL: URL, crop: PictureCrop, storageRoot: URL? = nil) throws -> ImportedImage {
        let image = try orientedImage(from: selectedURL, maximumPixelSize: 8_192)
        guard let cropped = image.cropping(to: crop.pixelRect(width: image.width, height: image.height)) else {
            throw ImageStoreError.unreadableImage
        }
        let directory = (storageRoot ?? root).appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let originalURL = directory.appendingPathComponent("original.png")
            guard let destination = CGImageDestinationCreateWithURL(originalURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageStoreError.unreadableImage
            }
            CGImageDestinationAddImage(destination, cropped, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.unreadableImage }
            let digest = SHA256.hash(data: try Data(contentsOf: originalURL)).map { String(format: "%02x", $0) }.joined()
            let uploadURL = directory.appendingPathComponent("upload.jpg")
            try makeUploadImage(from: originalURL, to: uploadURL)
            return ImportedImage(originalURL: originalURL, uploadURL: uploadURL, digest: digest)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func orientedImage(from url: URL, maximumPixelSize: Int = 1_600) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
              ] as CFDictionary) else { throw ImageStoreError.unreadableImage }
        return image
    }

    static func uploadURL(for sourcePath: String, renderProfile: GenerationRenderProfile = .wallpaper) -> URL {
        URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
            .appendingPathComponent(renderProfile == .quickPreview ? "preview-upload-\(renderProfile.maximumInputPixelSize).jpg" : "upload.jpg")
    }

    static func outputSize(for sourcePath: String, renderProfile: GenerationRenderProfile = .wallpaper) throws -> String {
        let url = uploadURL(for: sourcePath, renderProfile: renderProfile)
        if renderProfile == .quickPreview, !FileManager.default.fileExists(atPath: url.path) {
            try makeUploadImage(from: uploadURL(for: sourcePath), to: url, maximumPixelSize: renderProfile.maximumInputPixelSize)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageStoreError.unreadableImage
        }

        return try outputDimensions(width: width, height: height, renderProfile: renderProfile).size
    }

    static func outputDimensions(width: Int, height: Int, renderProfile: GenerationRenderProfile = .wallpaper) throws -> ImageOutputDimensions {
        guard width > 0, height > 0 else { throw ImageStoreError.unreadableImage }
        if renderProfile == .quickPreview {
            let ratio = min(3, max(1.0 / 3, Double(width) / Double(height)))
            let longToShort = max(ratio, 1 / ratio)
            var longEdge = Int(ceil(sqrt(655_360 * longToShort) / 16)) * 16
            while true {
                let shortEdge = max(16, Int((Double(longEdge) / longToShort / 16).rounded()) * 16)
                let actualRatio = Double(longEdge) / Double(shortEdge)
                if longEdge * shortEdge >= 655_360, actualRatio <= 3 {
                    return width >= height ? ImageOutputDimensions(width: longEdge, height: shortEdge)
                        : ImageOutputDimensions(width: shortEdge, height: longEdge)
                }
                longEdge += 16
            }
        }
        let longEdge = 2_560.0
        let scale = longEdge / Double(max(width, height))
        let outputWidth = max(864, Int((Double(width) * scale / 16).rounded()) * 16)
        let outputHeight = max(864, Int((Double(height) * scale / 16).rounded()) * 16)

        return ImageOutputDimensions(width: outputWidth, height: outputHeight)
    }

    static func cacheURL(for key: String) throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        return cacheDirectory.appendingPathComponent("\(key).png")
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

    private static func makeUploadImage(from originalURL: URL, to destinationURL: URL, maximumPixelSize: Int = 2_560) throws {
        guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil) else {
            throw ImageStoreError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
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
    case originalRequiredForCacheClear

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "This image could not be read. Try a JPEG, PNG, or HEIC file."
        case .originalRequiredForCacheClear: "Choose your original picture again before clearing images. Your current wallpaper has been kept."
        }
    }
}
