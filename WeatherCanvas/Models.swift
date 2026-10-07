import Foundation

enum UpdateInterval: String, CaseIterable, Codable, Identifiable, Sendable {
    case everyMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hourly
    case everyThreeHours
    case twiceDaily
    case daily
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyMinute: "Every minute"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        case .hourly: "Every hour"
        case .everyThreeHours: "Every 3 hours"
        case .twiceDaily: "Morning and evening"
        case .daily: "Once a day"
        case .weekly: "Once a week"
        case .monthly: "Once a month"
        case .custom: "Custom…"
        }
    }

    func minutes(customMinutes: Int) -> Int {
        switch self {
        case .everyMinute: 1
        case .fiveMinutes: 5
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        case .hourly: 60
        case .everyThreeHours: 180
        case .twiceDaily: 720
        case .daily: 1_440
        case .weekly: 10_080
        case .monthly: 43_200
        case .custom: max(1, min(customMinutes, 43_200))
        }
    }
}

enum FrequencyUnit: String, CaseIterable, Identifiable {
    case minutes, hours, days, weeks
    var id: String { rawValue }
    var minutes: Int {
        switch self {
        case .minutes: 1
        case .hours: 60
        case .days: 1_440
        case .weeks: 10_080
        }
    }
    var maximum: Int { 43_200 / minutes }
}

enum ImageModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case precise = "gpt-image-2.5-sunburst"
    case fast = "gpt-image-2.5-flare"

    var id: String { rawValue }
    var title: String { self == .precise ? "Precise" : "Faster" }
}

enum ImageQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }
    var title: String { rawValue == "xhigh" ? "Extra high" : rawValue.capitalized }
}

enum WeatherChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case clear
    case cloudy
    case rain
    case storm
    case snow
    case fog

    var id: String { rawValue }
    var title: String { self == .automatic ? "Local Weather" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .automatic: "location"
        case .clear: "sun.max"
        case .cloudy: "cloud"
        case .rain: "cloud.rain"
        case .storm: "cloud.bolt.rain"
        case .snow: "cloud.snow"
        case .fog: "cloud.fog"
        }
    }
}

struct WeatherPlace: Codable, Equatable, Sendable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200
            && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    var id: String { String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude) }
}

enum WeatherLocationSelection: Codable, Equatable, Sendable {
    case current
    case fixed(WeatherPlace)

    var fixedPlace: WeatherPlace? {
        if case .fixed(let place) = self { return place }
        return nil
    }
    var cacheIdentity: String? { fixedPlace.map { "weather-location:\($0.id)" } }
    var isValid: Bool { fixedPlace?.isValid ?? true }
}

enum WallpaperAppearance: String, Codable, Sendable {
    case light, dark

    var title: String { self == .dark ? "Dark Mode" : "Light Mode" }
}

enum MainPresentation: Equatable {
    case picture, customize, original, savedWallpapers, crop
}

enum WallpaperActivity {
    case idle, checkingWeather, readingSources, generating, applying, waitingForLocation, failed

    var symbol: String {
        switch self {
        case .idle: "checkmark.circle"
        case .checkingWeather: "cloud.sun"
        case .readingSources: "text.page"
        case .generating: "sparkles"
        case .applying: "desktopcomputer"
        case .waitingForLocation: "location"
        case .failed: "exclamationmark.circle"
        }
    }
}

enum WallpaperRecovery {
    case weather, apiKey, billing, image, retry

    var title: String {
        switch self {
        case .weather: "Weather Location…"
        case .apiKey: "Image AI Settings…"
        case .billing: "Check Image Provider Billing"
        case .image: "Choose a Picture…"
        case .retry: "Try Again"
        }
    }
}

enum WallpaperSchedule {
    static func shouldCheck(at date: Date, nextCheck: Date?, automatic: Bool, userInitiated: Bool) -> Bool {
        if userInitiated { return true }
        guard automatic else { return false }
        return nextCheck.map { date >= $0 } ?? true
    }

    static func revisedCheck(pinned: Date, proposed: Date) -> Date { min(pinned, proposed) }
}

enum OnboardingLocationState {
    case notRequested, requesting, allowed, denied
}

enum BuiltInPicture {
    static let digest = "fd6f041edf371d667bf7958ad4aa21f4ed7d466e92fdb201f20b7248b52dc7f8"
}

enum WallpaperStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case natural, subtle, watercolor, cinematic

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func prompt(extraInstructions: String) -> String {
        let instructions = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        switch self {
        case .natural:
            if instructions.isEmpty { return CanvasSettings.defaultPrompt }
            base = CanvasSettings.defaultPrompt + " Preserve the composition, main subjects, and style so it remains recognizably the same picture."
        case .subtle:
            base = "Preserve the picture's composition, subjects, and style. Make subtle changes to its lighting and atmosphere for the current time and weather. Keep the scene recognizable."
        case .watercolor:
            base = "Preserve the picture's composition and subjects. Repaint the same scene as a delicate watercolor, with lighting and atmosphere that reflect the current time and weather."
        case .cinematic:
            base = "Preserve the picture's composition, subjects, and visual identity. Add cinematic lighting and rich atmosphere that reflect the current time and weather. Keep the same recognizable scene."
        }
        return instructions.isEmpty ? base : base + "\n\n" + extraInstructions
    }
}

struct CanvasSettings: Codable, Equatable, Sendable {
    static let defaultPrompt = "Update my picture according to the current time and weather conditions."

    var sourcePath: String?
    var uncroppedSourcePath: String?
    var sourceCrop: PictureCrop?
    var sourceDigest: String?
    var originalPictureDigest: String?
    var pictureName: String?
    var promptTemplate = defaultPrompt
    var style: WallpaperStyle = .natural
    var extraInstructions = ""
    var legacyCustomPrompt: String?
    var interval: UpdateInterval = .hourly
    var customMinutes = 60
    var weatherChoice: WeatherChoice = .automatic
    var weatherLocation: WeatherLocationSelection = .current
    var systemAppearance: WallpaperAppearance?
    var model: ImageModel = .precise
    var quality: ImageQuality = .high
    var imageProvider: ImageProviderConfiguration = .openAI
    var imageProviderConfigurations: [String: ImageProviderConfiguration] = [:]
    var reuseMatchingImages = true
    var automaticUpdates = false
    var dailyGenerationLimit = 24
    var promptFileBookmarks: [String: Data] = [:]
    var unresolvedPromptFiles: [LegacyPromptFileReference] = []

    var intervalMinutes: Int { interval.minutes(customMinutes: customMinutes) }

    func nextWallpaperDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch interval {
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        default: return RenderContext(date: date, weather: "", intervalMinutes: intervalMinutes).nextCheckAfterApplying
        }
    }

    var frequencyTitle: String {
        guard interval == .custom else { return interval.title }
        for unit in FrequencyUnit.allCases.reversed() where intervalMinutes.isMultiple(of: unit.minutes) {
            let amount = intervalMinutes / unit.minutes
            return "Every \(amount) \(amount == 1 ? String(unit.rawValue.dropLast()) : unit.rawValue)"
        }
        return interval.title
    }

    init() {}

    mutating func updateWallpaperInstructions(style: WallpaperStyle, extraInstructions: String) {
        if style != .natural || style != self.style || extraInstructions != self.extraInstructions {
            legacyCustomPrompt = nil
        }
        self.style = style
        self.extraInstructions = extraInstructions
        promptTemplate = legacyCustomPrompt ?? style.prompt(extraInstructions: extraInstructions)
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath, uncroppedSourcePath, sourceCrop, sourceDigest, originalPictureDigest, pictureName, promptTemplate, style, extraInstructions, legacyCustomPrompt, interval, customMinutes
        case weatherChoice, weatherLocation, systemAppearance, model, quality, imageProvider, imageProviderConfigurations, reuseMatchingImages, automaticUpdates
        case dailyGenerationLimit, promptFileBookmarks, unresolvedPromptFiles, contextSources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try values.decodeIfPresent(String.self, forKey: .sourcePath)
        uncroppedSourcePath = try values.decodeIfPresent(String.self, forKey: .uncroppedSourcePath)
        sourceCrop = try values.decodeIfPresent(PictureCrop.self, forKey: .sourceCrop)
        sourceDigest = try values.decodeIfPresent(String.self, forKey: .sourceDigest)
        originalPictureDigest = try values.decodeIfPresent(String.self, forKey: .originalPictureDigest)
        pictureName = try values.decodeIfPresent(String.self, forKey: .pictureName)
        promptTemplate = try values.decodeIfPresent(String.self, forKey: .promptTemplate) ?? Self.defaultPrompt
        style = try values.decodeIfPresent(WallpaperStyle.self, forKey: .style) ?? .natural
        let builtInDefaults = [
            Self.defaultPrompt,
            "Adjust this image for the time of day and the local weather.",
            "Update my picture for the current time and weather",
            "Update my base image for the current time and weather",
            "Preserve the composition, subjects, and style of the original image. Reimagine its lighting and atmosphere for {{time}} with {{weather}} weather. Keep it recognizable as the same scene.",
        ]
        extraInstructions = try values.decodeIfPresent(String.self, forKey: .extraInstructions)
            ?? (builtInDefaults.contains(promptTemplate) ? "" : promptTemplate)
        legacyCustomPrompt = try values.decodeIfPresent(String.self, forKey: .legacyCustomPrompt)
        if style == .natural && !builtInDefaults.contains(promptTemplate)
            && legacyCustomPrompt == nil
            && (!values.contains(.style) || !values.contains(.extraInstructions)
                || extraInstructions.isEmpty || promptTemplate == extraInstructions) {
            // Preserve custom prompts until their style or instructions are edited.
            legacyCustomPrompt = promptTemplate
            extraInstructions = promptTemplate
        }
        if builtInDefaults.contains(promptTemplate) {
            if legacyCustomPrompt == promptTemplate { legacyCustomPrompt = nil }
            if extraInstructions == promptTemplate { extraInstructions = "" }
            promptTemplate = Self.defaultPrompt
        }
        interval = try values.decodeIfPresent(UpdateInterval.self, forKey: .interval) ?? .hourly
        customMinutes = try values.decodeIfPresent(Int.self, forKey: .customMinutes) ?? 60
        weatherChoice = try values.decodeIfPresent(WeatherChoice.self, forKey: .weatherChoice) ?? .automatic
        let location = (try? values.decode(WeatherLocationSelection.self, forKey: .weatherLocation)) ?? .current
        weatherLocation = location.isValid ? location : .current
        systemAppearance = try values.decodeIfPresent(WallpaperAppearance.self, forKey: .systemAppearance)
        model = try values.decodeIfPresent(ImageModel.self, forKey: .model) ?? .precise
        quality = try values.decodeIfPresent(ImageQuality.self, forKey: .quality) ?? .high
        if let legacy = try? values.decode(String.self, forKey: .imageProvider) {
            // Retired experimental settings used a string. Preserve the prior migration.
            imageProvider = ["codex", "openAIAPI"].contains(legacy) ? .openAI : .init(driverID: legacy)
        } else {
            imageProvider = try values.decodeIfPresent(ImageProviderConfiguration.self, forKey: .imageProvider) ?? .openAI
        }
        imageProviderConfigurations = try values.decodeIfPresent([String: ImageProviderConfiguration].self, forKey: .imageProviderConfigurations) ?? [:]
        reuseMatchingImages = try values.decodeIfPresent(Bool.self, forKey: .reuseMatchingImages) ?? true
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? false
        dailyGenerationLimit = try values.decodeIfPresent(Int.self, forKey: .dailyGenerationLimit) ?? 24
        promptFileBookmarks = try values.decodeIfPresent([String: Data].self, forKey: .promptFileBookmarks) ?? [:]
        unresolvedPromptFiles = try values.decodeIfPresent([LegacyPromptFileReference].self, forKey: .unresolvedPromptFiles) ?? []
        let previousSources = try values.decodeIfPresent([ContextSource].self, forKey: .contextSources) ?? []
        migrateSources(previousSources)
    }

    mutating func migrateSources(_ sources: [ContextSource], bookmarks: any PromptFileBookmarkBackend = SecurityScopedPromptFileBookmarks()) {
        var references: [String] = []
        for source in sources {
            switch source {
            case let .webPage(url, _): references.append(url.absoluteString)
            case let .localFile(name, bookmark, _):
                guard let path = try? PromptFileReader.resolvedPath(bookmark: bookmark, bookmarks: bookmarks) else {
                    let reference = LegacyPromptFileReference(name: name, bookmark: bookmark)
                    if !unresolvedPromptFiles.contains(reference) { unresolvedPromptFiles.append(reference) }
                    continue
                }
                promptFileBookmarks[path] = bookmark
                references.append("\"" + path + "\"")
            }
        }
        var existingURLs = Set(PromptLinkDetector.rawURLs(in: promptTemplate).map(\.absoluteString))
        var existingPaths = Set(LocalPromptFileDetector.allPaths(in: promptTemplate))
        let missing = references.filter { value in
            if value.hasPrefix("\"") { return existingPaths.insert(String(value.dropFirst().dropLast())).inserted }
            return existingURLs.insert(value).inserted
        }
        guard !missing.isEmpty else { return }
        promptTemplate += "\n\n" + missing.joined(separator: "\n")
        legacyCustomPrompt = promptTemplate
        extraInstructions = promptTemplate
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(sourcePath, forKey: .sourcePath)
        try values.encodeIfPresent(uncroppedSourcePath, forKey: .uncroppedSourcePath)
        try values.encodeIfPresent(sourceCrop, forKey: .sourceCrop)
        try values.encodeIfPresent(sourceDigest, forKey: .sourceDigest)
        try values.encodeIfPresent(originalPictureDigest, forKey: .originalPictureDigest)
        try values.encodeIfPresent(pictureName, forKey: .pictureName)
        try values.encode(promptTemplate, forKey: .promptTemplate)
        try values.encode(style, forKey: .style)
        try values.encode(extraInstructions, forKey: .extraInstructions)
        try values.encodeIfPresent(legacyCustomPrompt, forKey: .legacyCustomPrompt)
        try values.encode(interval, forKey: .interval)
        try values.encode(customMinutes, forKey: .customMinutes)
        try values.encode(weatherChoice, forKey: .weatherChoice)
        if weatherLocation != .current { try values.encode(weatherLocation, forKey: .weatherLocation) }
        try values.encodeIfPresent(systemAppearance, forKey: .systemAppearance)
        try values.encode(model, forKey: .model)
        try values.encode(quality, forKey: .quality)
        try values.encode(imageProvider, forKey: .imageProvider)
        try values.encode(imageProviderConfigurations, forKey: .imageProviderConfigurations)
        try values.encode(reuseMatchingImages, forKey: .reuseMatchingImages)
        try values.encode(automaticUpdates, forKey: .automaticUpdates)
        try values.encode(dailyGenerationLimit, forKey: .dailyGenerationLimit)
        try values.encode(promptFileBookmarks, forKey: .promptFileBookmarks)
        try values.encode(unresolvedPromptFiles, forKey: .unresolvedPromptFiles)
    }
}

struct LegacyPromptFileReference: Codable, Equatable, Sendable {
    let name: String
    let bookmark: Data
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let label: String
    let symbol: String
    let fetchedAt: Date
}

struct RenderContext: Sendable {
    let date: Date
    let weather: String
    let intervalMinutes: Int

    var slot: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if intervalMinutes == 720 { return (420..<1_140).contains(minuteOfDay) ? 0 : 1 }
        return minuteOfDay / intervalMinutes
    }

    var localDay: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    var slotDate: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let minuteOfDay = intervalMinutes == 720 ? (slot == 0 ? 420 : 1_140)
            : (intervalMinutes == 1_440 ? 420 : min(1_439, slot * intervalMinutes + intervalMinutes / 2))
        return calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: date
        ) ?? start
    }

    var nextSlotDate: Date {
        let calendar = Calendar.current
        if intervalMinutes > 1_440 {
            return calendar.date(byAdding: .minute, value: intervalMinutes, to: date) ?? date
        }
        if intervalMinutes == 720 || intervalMinutes == 1_440 {
            let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date) ?? date
            if date < morning { return morning }
            if intervalMinutes == 720 {
                let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: date) ?? date
                if date < evening { return evening }
            }
            return calendar.date(byAdding: .day, value: 1, to: morning) ?? date
        }
        let minutes = (slot + 1) * intervalMinutes
        guard minutes < 1_440 else {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) ?? date
    }

    var nextCheckAfterApplying: Date {
        // An early first creation already supplies today's daily wallpaper.
        if intervalMinutes == 1_440, Calendar.current.isDate(nextSlotDate, inSameDayAs: date) {
            return Calendar.current.date(byAdding: .day, value: 1, to: nextSlotDate) ?? nextSlotDate
        }
        return nextSlotDate
    }
}
