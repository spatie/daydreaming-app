import CryptoKit
import Foundation

struct HourWallpaperCache: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let pictureID: String
        let recipeID: String
        let hour: Int
        let weather: WeatherSnapshot
        let filename: String
        let createdAt: Date
        var promptRecipeID: String?
        var renderProfile: GenerationRenderProfile = .wallpaper
        var settingsSnapshot: CanvasSettings?
        var sourceDigest: String?
        var sourcePicturePath: String?

        private enum CodingKeys: String, CodingKey {
            case pictureID, recipeID, hour, weather, filename, createdAt, promptRecipeID, renderProfile, settingsSnapshot, sourceDigest, sourcePicturePath
        }
    }

    struct Match: Equatable, Sendable {
        let entry: Entry
        let url: URL
        let usesOldRecipe: Bool
        let needsUpdate: Bool
        let weatherChanged: Bool
    }

    let directory: URL
    private(set) var entries: [Entry]
    private(set) var hasUnreadableIndex: Bool
    private var indexURL: URL { directory.appendingPathComponent("hour-wallpapers.json") }

    init(directory: URL) {
        self.directory = directory
        let url = directory.appendingPathComponent("hour-wallpapers.json")
        let loaded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }
        hasUnreadableIndex = loaded == nil && FileManager.default.fileExists(atPath: url.path)
        entries = loaded ?? []
    }

    static func pictureID(for settings: CanvasSettings) -> String {
        settings.sourceDigest ?? settings.sourcePath ?? ""
    }

    static func recipeID(for settings: CanvasSettings, date: Date = .now) -> String {
        var parts = [
            pictureID(for: settings), settings.promptTemplate, settings.style.rawValue,
            settings.model.rawValue, settings.quality.rawValue, settings.weatherChoice.rawValue,
        ]

        if let location = settings.weatherLocation.cacheIdentity { parts.append(location) }
        if let appearance = settings.systemAppearance { parts.append("macos-appearance:" + appearance.rawValue) }
        if let crop = settings.sourceCrop { parts.append(cropFingerprint(crop)) }
        if let provider = settings.imageProvider.cacheIdentity { parts.append(provider) }
        if settings.promptTemplate.contains("{{date}}") || !PromptLinkDetector.urls(in: settings.promptTemplate).isEmpty
            || LocalPromptFileDetector.allPaths(in: settings.promptTemplate).contains(where: { PromptFileReader.isSupported(URL(fileURLWithPath: $0)) }) {
            parts.append(String(Calendar.current.startOfDay(for: date).timeIntervalSince1970))
        }
        return digest(parts.joined(separator: "\u{0}"))
    }

    static func promptRecipeID(for settings: CanvasSettings) -> String {
        var parts = [pictureID(for: settings), settings.promptTemplate, settings.style.rawValue,
                     settings.model.rawValue, settings.quality.rawValue, settings.weatherChoice.rawValue]

        if let location = settings.weatherLocation.cacheIdentity { parts.append(location) }
        if let appearance = settings.systemAppearance { parts.append("macos-appearance:" + appearance.rawValue) }
        if let crop = settings.sourceCrop { parts.append(cropFingerprint(crop)) }
        if let provider = settings.imageProvider.cacheIdentity { parts.append(provider) }
        return digest(parts.joined(separator: "\u{0}"))
    }

    private static func cropFingerprint(_ crop: PictureCrop) -> String {
        let rect = crop.normalizedRect
        let coordinates = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
            .map { String(Double($0).bitPattern) }.joined(separator: ":")
        return "crop:\(coordinates):\(crop.usesOriginalRatio)"
    }

    static func jobID(recipeID: String, hour: Int, weather: String, renderProfile: GenerationRenderProfile = .wallpaper) -> String {
        var parts = [recipeID, String(hour), weather]
        if renderProfile == .quickPreview { parts.append(renderProfile.rawValue) }
        return digest(parts.joined(separator: "\u{0}"))
    }

    func exact(pictureID: String, recipeID: String, hour: Int, weather: String?, renderProfile: GenerationRenderProfile = .wallpaper) -> Match? {
        entries.reversed().first {
            $0.pictureID == pictureID && $0.recipeID == recipeID && $0.hour == hour
                && $0.renderProfile == renderProfile
                && (weather == nil || $0.weather.cacheKey == weather) && validURL(for: $0) != nil
        }.flatMap { entry in
            validURL(for: entry).map { Match(entry: entry, url: $0, usesOldRecipe: false, needsUpdate: false, weatherChanged: false) }
        }
    }

    func preview(pictureID: String, recipeID: String, hour: Int, weather: String?, promptRecipeID: String? = nil) -> Match? {
        if let exact = exact(pictureID: pictureID, recipeID: recipeID, hour: hour, weather: weather) { return exact }
        if let quick = exact(pictureID: pictureID, recipeID: recipeID, hour: hour, weather: weather, renderProfile: .quickPreview) { return quick }
        let sameRecipe = entries.reversed().filter {
            $0.pictureID == pictureID && $0.recipeID == recipeID && $0.hour == hour && validURL(for: $0) != nil
        }
        let matchingRecipe = sameRecipe.filter { $0.renderProfile == .wallpaper }
            + sameRecipe.filter { $0.renderProfile == .quickPreview }
        if let entry = matchingRecipe.first, let url = validURL(for: entry) {
            return Match(entry: entry, url: url, usesOldRecipe: false, needsUpdate: true, weatherChanged: true)
        }
        let candidates = entries.reversed().filter {
            $0.pictureID == pictureID && $0.hour == hour && $0.recipeID != recipeID && validURL(for: $0) != nil
        }
        let preferred = candidates.filter { $0.renderProfile == .wallpaper } + candidates.filter { $0.renderProfile == .quickPreview }
        let entry = preferred.first { weather == nil || $0.weather.cacheKey == weather } ?? preferred.first
        guard let entry, let url = validURL(for: entry) else { return nil }
        let samePrompt = promptRecipeID != nil && entry.promptRecipeID == promptRecipeID
        return Match(entry: entry, url: url, usesOldRecipe: !samePrompt, needsUpdate: true,
                     weatherChanged: weather != nil && entry.weather.cacheKey != weather)
    }

    mutating func record(pictureID: String, recipeID: String, hour: Int, weather: WeatherSnapshot,
                         url: URL, createdAt: Date = .now, promptRecipeID: String? = nil,
                         renderProfile: GenerationRenderProfile = .wallpaper, settingsSnapshot: CanvasSettings? = nil,
                         sourceDigest: String? = nil, sourcePicturePath: String? = nil) throws {
        guard !hasUnreadableIndex else { throw HourWallpaperCacheError.unreadableIndex }
        guard (0...23).contains(hour), url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { throw HourWallpaperCacheError.invalidPicture }
        entries.removeAll { $0.filename == url.lastPathComponent }
        entries.append(Entry(pictureID: pictureID, recipeID: recipeID, hour: hour, weather: weather,
                             filename: url.lastPathComponent, createdAt: createdAt, promptRecipeID: promptRecipeID,
                             renderProfile: renderProfile, settingsSnapshot: settingsSnapshot, sourceDigest: sourceDigest, sourcePicturePath: sourcePicturePath))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }

    mutating func prune(preserving urls: [URL], maximumEntries: Int = 192, maximumBytes: Int64 = 512_000_000) throws {
        guard !hasUnreadableIndex else { throw HourWallpaperCacheError.unreadableIndex }
        let protected = Set(urls.map(\.lastPathComponent))
        entries = entries.filter { validURL(for: $0) != nil }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let indexed = Set(entries.map(\.filename))
        for file in files where file.pathExtension == "png" && !indexed.contains(file.lastPathComponent) && !protected.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        var total = entries.reduce(Int64(0)) { count, entry in
            count + Int64((try? directory.appendingPathComponent(entry.filename).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        while entries.count > maximumEntries || total > maximumBytes {
            guard let index = entries.firstIndex(where: { $0.renderProfile == .quickPreview && !protected.contains($0.filename) })
                ?? entries.firstIndex(where: { !protected.contains($0.filename) }) else { break }
            let entry = entries.remove(at: index)
            let url = directory.appendingPathComponent(entry.filename)
            total -= Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            try? FileManager.default.removeItem(at: url)
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
        }
    }

    mutating func clear() { entries.removeAll(); hasUnreadableIndex = false }

    func url(for entry: Entry) -> URL? { validURL(for: entry) }

    mutating func delete(_ entry: Entry) throws {
        guard !hasUnreadableIndex else { throw HourWallpaperCacheError.unreadableIndex }
        guard entries.contains(entry), let url = validURL(for: entry) else { throw HourWallpaperCacheError.invalidPicture }
        try FileManager.default.removeItem(at: url)
        entries.removeAll { $0.filename == entry.filename }
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }

    mutating func delete(_ removed: [Entry]) throws {
        guard !hasUnreadableIndex else { throw HourWallpaperCacheError.unreadableIndex }
        guard removed.allSatisfy(entries.contains) else { throw HourWallpaperCacheError.invalidPicture }
        let files = removed.compactMap { validURL(for: $0) }
        let filenames = Set(removed.map(\.filename))
        let updated = entries.filter { !filenames.contains($0.filename) }
        guard updated != entries else { return }
        try JSONEncoder().encode(updated).write(to: indexURL, options: .atomic)
        entries = updated
        for url in files { try FileManager.default.removeItem(at: url) }
    }

    private func validURL(for entry: Entry) -> URL? {
        guard !entry.filename.isEmpty, entry.filename == URL(fileURLWithPath: entry.filename).lastPathComponent,
              !entry.filename.contains("/"), entry.filename != ".", entry.filename != ".." else { return nil }
        let url = directory.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum HourWallpaperCacheError: LocalizedError {
    case invalidPicture, unreadableIndex
    var errorDescription: String? {
        switch self {
        case .invalidPicture: "The saved wallpaper could not be found."
        case .unreadableIndex: "Saved wallpaper history could not be read. Your picture files are still on this Mac."
        }
    }
}

extension HourWallpaperCache.Entry {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pictureID = try values.decode(String.self, forKey: .pictureID)
        recipeID = try values.decode(String.self, forKey: .recipeID)
        hour = try values.decode(Int.self, forKey: .hour)
        weather = try values.decode(WeatherSnapshot.self, forKey: .weather)
        filename = try values.decode(String.self, forKey: .filename)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        promptRecipeID = try values.decodeIfPresent(String.self, forKey: .promptRecipeID)
        renderProfile = try values.decodeIfPresent(GenerationRenderProfile.self, forKey: .renderProfile) ?? .wallpaper
        settingsSnapshot = try values.decodeIfPresent(CanvasSettings.self, forKey: .settingsSnapshot)
        sourceDigest = try values.decodeIfPresent(String.self, forKey: .sourceDigest)
        sourcePicturePath = try values.decodeIfPresent(String.self, forKey: .sourcePicturePath)
    }
}

enum HourWallpaperApplicationPolicy {
    static func shouldApply(job: HourlyGenerationJob, currentRecipeID: String, currentHour: Int,
                            automaticUpdates: Bool) -> Bool {
        guard job.renderProfile == .wallpaper, job.recipeID == currentRecipeID, job.hour == currentHour else { return false }
        if job.intent.contains(.manualWallpaper) { return true }
        return automaticUpdates && job.intent.contains(.automaticWallpaper)
    }
}

/// Pausing automatic updates withdraws permission to start automatic-only requests.
enum HourWallpaperPaymentPolicy {
    static func mayStart(job: HourlyGenerationJob, automaticUpdates: Bool) -> Bool {
        if job.renderProfile == .quickPreview { return job.userInitiated && job.intent == .preview }
        return job.userInitiated || job.intent.contains(.manualWallpaper)
            || (job.intent.contains(.automaticWallpaper) && automaticUpdates)
    }
}
