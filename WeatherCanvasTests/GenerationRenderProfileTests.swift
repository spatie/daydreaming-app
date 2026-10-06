import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Daydreaming

final class GenerationRenderProfileTests: XCTestCase {
    func testQuickPreviewUsesFastLowQualityAndReservesDesktopBudget() {
        var settings = CanvasSettings()
        settings.model = .precise
        settings.quality = .xhigh
        XCTAssertEqual(GenerationRenderProfile.quickPreview.model(for: settings), .fast)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.quality(for: settings), .low)
        XCTAssertEqual(GenerationRenderProfile.wallpaper.model(for: settings), .precise)
        XCTAssertEqual(GenerationRenderProfile.wallpaper.quality(for: settings), .xhigh)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.maximumInputPixelSize, 512)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 24, previewsToday: 0), 22)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 9, previewsToday: 8), 7)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 3, previewsToday: 0), 1)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 2, previewsToday: 0), 0)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 24, previewsToday: 12), 22)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 4, previewsToday: 20), 2)
        XCTAssertEqual(GenerationRenderProfile.quickPreview.availableBudget(totalRemaining: 2, previewsToday: 22), 0)
        XCTAssertEqual(GenerationRenderProfile.wallpaper.availableBudget(totalRemaining: 2, previewsToday: 22), 2)
    }

    func testQuickDimensionsRespectAPIConstraintsAndKeepOrientation() throws {
        for (width, height) in [(1_920, 1_080), (1_600, 1_000), (3_440, 1_440), (1_080, 1_920), (1_000, 1_000), (3_000, 1_000), (1_000, 3_000), (8_000, 400), (400, 8_000)] {
            let dimensions = try ImageStore.outputDimensions(width: width, height: height, renderProfile: .quickPreview)
            XCTAssertEqual(dimensions.width % 16, 0)
            XCTAssertEqual(dimensions.height % 16, 0)
            XCTAssertGreaterThanOrEqual(dimensions.width * dimensions.height, 655_360)
            XCTAssertLessThanOrEqual(dimensions.width * dimensions.height, 8_294_400)
            XCTAssertLessThanOrEqual(Double(max(dimensions.width, dimensions.height)) / Double(min(dimensions.width, dimensions.height)), 3)
            XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), 1_424)
            XCTAssertEqual(dimensions.width >= dimensions.height, width >= height)
        }
        XCTAssertEqual(try ImageStore.outputDimensions(width: 1_920, height: 1_080).size, "2560x1440")
        XCTAssertEqual(try ImageStore.outputDimensions(width: 1_000, height: 1_000, renderProfile: .quickPreview).size, "816x816")
        XCTAssertEqual(try ImageStore.outputDimensions(width: 1_600, height: 1_000, renderProfile: .quickPreview).size, "1024x640")
        XCTAssertEqual(try ImageStore.outputDimensions(width: 1_920, height: 1_080, renderProfile: .quickPreview).size, "1088x608")
        XCTAssertThrowsError(try ImageStore.outputDimensions(width: 0, height: 100, renderProfile: .quickPreview))
    }

    func testPreviewUploadIs512AndIgnoresLegacy1024UploadWithoutChangingFullUpload() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.jpg")
        let fullUpload = ImageStore.uploadURL(for: source.path)
        let context = try XCTUnwrap(CGContext(data: nil, width: 2_560, height: 1_440, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2_560, height: 1_440))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(fullUpload as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let before = try Data(contentsOf: fullUpload)
        let legacy = directory.appendingPathComponent("preview-upload.jpg")
        try before.write(to: legacy)
        _ = try ImageStore.outputSize(for: source.path, renderProfile: .quickPreview)
        let preview = ImageStore.uploadURL(for: source.path, renderProfile: .quickPreview)
        let previewSource = try XCTUnwrap(CGImageSourceCreateWithURL(preview as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(previewSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 512)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 288)
        XCTAssertEqual(try Data(contentsOf: fullUpload), before)
        XCTAssertEqual(try Data(contentsOf: legacy), before)
    }

    func testQuickCacheIsSeparateAndPreviewPrefersMatchingFullWallpaper() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        let quick = directory.appendingPathComponent("quick.png")
        let full = directory.appendingPathComponent("full.png")
        try Data("fake quick".utf8).write(to: quick)
        try Data("fake full".utf8).write(to: full)
        let weather = WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: .now)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14, weather: weather, url: quick, renderProfile: .quickPreview)
        XCTAssertNil(cache.exact(pictureID: "picture", recipeID: "recipe", hour: 14, weather: "clear"))
        let preview = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: "recipe", hour: 14, weather: "clear"))
        XCTAssertEqual(preview.entry.renderProfile, .quickPreview)
        XCTAssertFalse(preview.usesOldRecipe)
        XCTAssertFalse(preview.needsUpdate)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14, weather: weather, url: full)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14, weather: weather, url: quick, renderProfile: .quickPreview)
        XCTAssertEqual(cache.entries.count, 2)
        XCTAssertEqual(cache.preview(pictureID: "picture", recipeID: "recipe", hour: 14, weather: "clear")?.url, full)
        XCTAssertEqual(cache.exact(pictureID: "picture", recipeID: "recipe", hour: 14, weather: "clear", renderProfile: .quickPreview)?.url, quick)
        XCTAssertEqual(HourWallpaperCache(directory: directory).entries, cache.entries)
    }

    func testOldCacheAndPendingJobsDecodeAsFullWallpapers() throws {
        let job = profileJob(.wallpaper)
        var jobJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
        jobJSON.removeValue(forKey: "renderProfile")
        XCTAssertEqual(try JSONDecoder().decode(HourlyGenerationJob.self, from: JSONSerialization.data(withJSONObject: jobJSON)).renderProfile, .wallpaper)
        let entry = HourWallpaperCache.Entry(pictureID: "picture", recipeID: "recipe", hour: 14, weather: job.weather,
                                             filename: "old.png", createdAt: job.date, promptRecipeID: nil)
        var entryJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        entryJSON.removeValue(forKey: "renderProfile")
        XCTAssertEqual(try JSONDecoder().decode(HourWallpaperCache.Entry.self, from: JSONSerialization.data(withJSONObject: entryJSON)).renderProfile, .wallpaper)
        XCTAssertEqual(try JSONDecoder().decode(HourlyGenerationJob.self, from: JSONEncoder().encode(profileJob(.quickPreview))).renderProfile, .quickPreview)
    }

    func testProfileIDsDoNotMergeAndQuickResultsCannotApplyAsWallpapers() {
        let quick = profileJob(.quickPreview)
        var full = profileJob(.wallpaper)
        full.intent = .manualWallpaper
        XCTAssertNotEqual(quick.id, full.id)
        XCTAssertEqual(quick.merged(with: full), quick)
        var malformed = quick
        malformed.intent = [.preview, .manualWallpaper, .automaticWallpaper]
        XCTAssertFalse(HourWallpaperApplicationPolicy.shouldApply(job: malformed, currentRecipeID: malformed.recipeID, currentHour: 14, automaticUpdates: true))
        XCTAssertFalse(HourWallpaperPaymentPolicy.mayStart(job: malformed, automaticUpdates: true))
        XCTAssertTrue(HourWallpaperPaymentPolicy.mayStart(job: quick, automaticUpdates: false))
    }

    func testPreviewLedgerPersistsRefundsAndKeepsInterruptedSendsCounted() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var ledger = ImageGenerationLedger()
        let quick = ledger.reserve(at: date, profile: .quickPreview)
        let full = ledger.reserve(at: date)
        XCTAssertEqual(ledger.count(on: date), 2)
        XCTAssertEqual(ledger.previewCount(on: date), 1)
        ledger = try JSONDecoder().decode(ImageGenerationLedger.self, from: JSONEncoder().encode(ledger))
        ledger.refund(quick)
        ledger.refund(quick)
        XCTAssertEqual(ledger.count(on: date), 1)
        XCTAssertEqual(ledger.previewCount(on: date), 0)
        ledger.complete(full)
        _ = ledger.reserve(at: date, profile: .quickPreview)
        ledger.clearInterruptedReservations()
        XCTAssertEqual(ledger.count(on: date), 2)
        XCTAssertEqual(ledger.previewCount(on: date), 1)
        XCTAssertTrue(ledger.reservations.isEmpty)
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        oldJSON.removeValue(forKey: "previewCounts")
        oldJSON.removeValue(forKey: "reservationProfiles")
        let legacy = try JSONDecoder().decode(ImageGenerationLedger.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertEqual(legacy.count(on: date), 2)
        XCTAssertEqual(legacy.previewCount(on: date), 0)
    }

    @MainActor
    func testBudgetBlockedQuickPreviewIsDroppedAndWallpaperCanStillRun() async {
        var started: [GenerationRenderProfile] = []
        let queue = HourlyGenerationQueue(process: { started.append($0.renderProfile) }, remainingBudget: { 2 },
                                         budgetForJob: { $0.renderProfile.availableBudget(totalRemaining: 2, previewsToday: 0) })
        XCTAssertFalse(queue.enqueue(profileJob(.quickPreview)))
        var full = profileJob(.wallpaper)
        full.intent = .manualWallpaper
        queue.enqueue(full)
        for _ in 0..<10_000 {
            if started == [.wallpaper], queue.current == nil { break }
            await Task.yield()
        }
        XCTAssertEqual(started, [.wallpaper])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertFalse(queue.isLimitPaused)
        queue.clearPending()
    }

    @MainActor
    func testRemovingSupersededPreviewsKeepsDesktopAndMergedRequests() {
        let queue = HourlyGenerationQueue(process: { _ in XCTFail("Budget is zero") }, remainingBudget: { 0 })
        var full = profileJob(.wallpaper)
        full.intent = [.preview, .manualWallpaper]
        let explicitFullPreview = profileJob(.wallpaper, hour: 15)
        queue.restore([full, explicitFullPreview], resumeImmediately: false)
        queue.removePendingPreviews()
        XCTAssertEqual(queue.pending, [full, explicitFullPreview])
    }

    @MainActor
    func testSliderCancellationRemovesQuickOnlyAndRejectsYesterdayQuickJobs() {
        let queue = HourlyGenerationQueue(process: { _ in XCTFail("Worker is deferred") }, remainingBudget: { 24 })
        let quick = profileJob(.quickPreview)
        let explicitFullPreview = profileJob(.wallpaper)
        queue.restore([quick, explicitFullPreview], resumeImmediately: false)
        queue.removePendingPreviews()
        XCTAssertEqual(queue.pending, [explicitFullPreview])
        queue.clearPending()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let oldQuick = profileJob(.quickPreview, date: yesterday)
        XCTAssertFalse(queue.enqueue(oldQuick))
        queue.restore([oldQuick], resumeImmediately: false)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testCachePruningEvictsQuickBeforeOlderFullWallpaper() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        let full = directory.appendingPathComponent("old-full.png")
        let quick = directory.appendingPathComponent("new-quick.png")
        try Data("full".utf8).write(to: full)
        try Data("quick".utf8).write(to: quick)
        let weather = WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: .now)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14, weather: weather, url: full)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14, weather: weather, url: quick, renderProfile: .quickPreview)
        try cache.prune(preserving: [], maximumEntries: 1)
        XCTAssertEqual(cache.entries.map(\.renderProfile), [.wallpaper])
        XCTAssertTrue(FileManager.default.fileExists(atPath: full.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quick.path))
    }

    private func profileJob(_ profile: GenerationRenderProfile, hour: Int = 14, date: Date = .now) -> HourlyGenerationJob {
        return HourlyGenerationJob(id: HourWallpaperCache.jobID(recipeID: "recipe", hour: hour, weather: "clear", renderProfile: profile),
                                   hour: hour, date: date, recipeID: "recipe",
                                   weather: WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: date),
                                   settings: CanvasSettings(), sourcePath: "/fixture/picture.jpg", priority: .manual,
                                   requiresCredit: true, intent: .preview, renderProfile: profile)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
