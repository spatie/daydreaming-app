import Foundation

enum UpdateInterval: String, CaseIterable, Codable, Identifiable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hourly
    case everyThreeHours
    case twiceDaily
    case daily
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        case .hourly: "Every hour"
        case .everyThreeHours: "Every 3 hours"
        case .twiceDaily: "Twice a day"
        case .daily: "Once a day"
        case .custom: "Custom"
        }
    }

    func minutes(customMinutes: Int) -> Int {
        switch self {
        case .fiveMinutes: 5
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        case .hourly: 60
        case .everyThreeHours: 180
        case .twiceDaily: 720
        case .daily: 1_440
        case .custom: max(5, min(customMinutes, 1_440))
        }
    }
}

enum ImageModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case precise = "gpt-image-2.5-sunburst"
    case fast = "gpt-image-2.5-flare"

    var id: String { rawValue }
    var title: String { self == .precise ? "Precise" : "Faster" }
}

enum ImageQuality: String, CaseIterable, Codable, Identifiable, Sendable {
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
    var title: String { rawValue.capitalized }
}

struct CanvasSettings: Codable, Equatable, Sendable {
    static let defaultPrompt = "Update my base image for the current time and weather"

    var sourcePath: String?
    var sourceDigest: String?
    var promptTemplate = defaultPrompt
    var interval: UpdateInterval = .twiceDaily
    var customMinutes = 60
    var weatherChoice: WeatherChoice = .automatic
    var model: ImageModel = .precise
    var quality: ImageQuality = .high
    var reuseMatchingImages = true
    var automaticUpdates = false
    var dailyGenerationLimit = 288
    var contextSources: [ContextSource] = []

    var intervalMinutes: Int { interval.minutes(customMinutes: customMinutes) }
    var possibleDailySlots: Int { Int(ceil(1_440.0 / Double(intervalMinutes))) }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case sourcePath, sourceDigest, promptTemplate, interval, customMinutes
        case weatherChoice, model, quality, reuseMatchingImages, automaticUpdates
        case dailyGenerationLimit, contextSources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try values.decodeIfPresent(String.self, forKey: .sourcePath)
        sourceDigest = try values.decodeIfPresent(String.self, forKey: .sourceDigest)
        promptTemplate = try values.decodeIfPresent(String.self, forKey: .promptTemplate) ?? Self.defaultPrompt
        interval = try values.decodeIfPresent(UpdateInterval.self, forKey: .interval) ?? .twiceDaily
        customMinutes = try values.decodeIfPresent(Int.self, forKey: .customMinutes) ?? 60
        weatherChoice = try values.decodeIfPresent(WeatherChoice.self, forKey: .weatherChoice) ?? .automatic
        model = try values.decodeIfPresent(ImageModel.self, forKey: .model) ?? .precise
        quality = try values.decodeIfPresent(ImageQuality.self, forKey: .quality) ?? .high
        reuseMatchingImages = try values.decodeIfPresent(Bool.self, forKey: .reuseMatchingImages) ?? true
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? false
        dailyGenerationLimit = try values.decodeIfPresent(Int.self, forKey: .dailyGenerationLimit) ?? 288
        contextSources = try values.decodeIfPresent([ContextSource].self, forKey: .contextSources) ?? []
    }
}

struct WeatherSnapshot: Equatable, Sendable {
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
        return minuteOfDay / intervalMinutes
    }

    var localDay: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    var slotDate: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let minuteOfDay = min(1_439, slot * intervalMinutes + intervalMinutes / 2)
        return calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: date
        ) ?? start
    }
}
