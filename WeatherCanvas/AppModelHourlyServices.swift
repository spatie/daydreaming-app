import Foundation

/// Explicit injection keeps application orchestration testable without enabling native services in test bundles.
@MainActor
struct AppModelHourlyServices {
    let now: @MainActor () -> Date
    let sourceAvailable: @MainActor (String) -> Bool
    let weather: @MainActor (WeatherChoice, Date) async throws -> WeatherSnapshot
    let readPrompt: (@MainActor (HourlyGenerationJob) async throws -> String)?
    let create: @MainActor (HourlyGenerationJob, String, @escaping @MainActor () throws -> Void,
                            @escaping @MainActor (Int) -> Void) async throws -> Data
    let cacheDirectory: URL
    let apply: @MainActor (URL) throws -> Void
    let loadLedger: @MainActor () throws -> ImageGenerationLedger
    let saveLedger: @MainActor (ImageGenerationLedger) -> Void
    let loadPending: @MainActor () -> [HourlyGenerationJob]
    let savePending: @MainActor ([HourlyGenerationJob]) -> Void
    let loadApplicationRetry: @MainActor () -> SavedWallpaperApplication?
    let saveApplicationRetry: @MainActor (SavedWallpaperApplication?) -> Void
    var runsBackgroundTasks = false
    var sleep: (@MainActor (TimeInterval) async throws -> Void)?
    var promptSources: AppModelPromptSourceServices?
    var clearCache: (@MainActor () throws -> Void)?
    var isPreviewWindowActive: (@MainActor () -> Bool)?
    var showInFinder: (@MainActor (URL) -> Void)?
    var originalImageSize: (@MainActor (URL) async throws -> CGSize)?
    var cropPicture: (@MainActor (URL, PictureCrop) async throws -> ImportedImage)?
    var reusableBuiltInPicture: (@MainActor () -> URL?)?
    var importPicture: (@MainActor (URL) async throws -> ImportedImage)?
    var pictureChoiceSleep: (@MainActor (TimeInterval) async throws -> Void)?
}

struct SavedWallpaperApplication: Codable, Equatable, Sendable {
    let job: HourlyGenerationJob
    let url: URL
}

struct WallpaperApplicationFailure: Error {
    let saved: SavedWallpaperApplication
    let underlying: Error
}
