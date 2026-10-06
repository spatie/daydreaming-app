import XCTest
@testable import Daydreaming

final class HourlyGenerationProcessorTests: XCTestCase {
    @MainActor
    func testQuickCacheIsReusedWhenWallpaperReuseIsOffButCannotSatisfyAFullJob() async throws {
        let harness = ProcessorHarness()
        harness.settings.reuseMatchingImages = false
        let quick = harness.job(intent: .preview, renderProfile: .quickPreview)
        harness.cachedIDs.insert(quick.id)
        try await harness.processor.process(quick)
        XCTAssertEqual(harness.readCount, 0)
        XCTAssertTrue(harness.created.isEmpty)
        try await harness.processor.process(harness.job(intent: .manualWallpaper))
        XCTAssertEqual(harness.created.map(\.renderProfile), [.wallpaper])
        XCTAssertEqual(harness.applied.count, 1)
    }

    @MainActor
    func testQuickPreviewStopsBeforePaymentWhenItsWindowBecomesUnavailable() async throws {
        let harness = ProcessorHarness()
        harness.readGate = ProcessorGate()
        let task = Task { try await harness.processor.process(harness.job(intent: .preview, renderProfile: .quickPreview)) }
        await eventually { harness.readCount == 1 }
        harness.allowsPreview = false
        harness.readGate?.release()
        try await task.value
        XCTAssertTrue(harness.created.isEmpty)
        XCTAssertEqual(harness.ledger.count(on: harness.clock), 0)
    }

    @MainActor
    func testYesterdayQuickIsDroppedWithoutWeatherReadAndTodaysWallpaperStillRuns() async throws {
        let harness = ProcessorHarness()
        harness.settings.promptTemplate = "Paint {{date}}"
        let oldQuick = harness.job(date: harness.yesterday, intent: .preview, renderProfile: .quickPreview)
        try await harness.processor.process(oldQuick)
        XCTAssertEqual(harness.weatherCount, 0)
        XCTAssertEqual(harness.readCount, 0)
        XCTAssertTrue(harness.created.isEmpty)
        let queue = harness.makeQueue()
        XCTAssertFalse(queue.enqueue(oldQuick))
        queue.enqueue(harness.job(intent: .automaticWallpaper))
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.created.map(\.renderProfile), [.wallpaper])
        XCTAssertEqual(harness.ledger.count(on: harness.clock), 1)
        XCTAssertEqual(harness.ledger.previewCount(on: harness.clock), 0)
        XCTAssertEqual(harness.applied.map(\.renderProfile), [.wallpaper])
    }

    @MainActor
    func testBudgetLostDuringQuickReadDropsTheJobWithoutCarryingIt() async {
        let harness = ProcessorHarness()
        harness.readGate = ProcessorGate()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(intent: .preview, renderProfile: .quickPreview))
        await eventually { harness.readCount == 1 }
        for _ in 0..<22 { _ = harness.ledger.reserve(at: harness.clock) }
        harness.readGate?.release()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertTrue(harness.created.isEmpty)
        XCTAssertEqual(harness.ledger.previewCount(on: harness.clock), 0)
        XCTAssertFalse(queue.isLimitPaused)
        queue.enqueue(harness.job(intent: .manualWallpaper))
        await eventually { harness.created.count == 1 && queue.current == nil }
        XCTAssertEqual(harness.created.map(\.renderProfile), [.wallpaper])
    }

    @MainActor
    func testQuickDraftUsesSeparateSettingsAndNeverChangesCommittedWallpaperRecipe() async throws {
        let harness = ProcessorHarness()
        let saved = harness.settings
        var draft = saved
        draft.promptTemplate = "A watercolor sunset draft"
        harness.previewSettings = draft
        let quick = harness.job(settings: draft, intent: .preview, renderProfile: .quickPreview)
        XCTAssertFalse(HourlyJobValidity.canKeep(quick, settings: saved, at: harness.clock, sourceIsAvailable: true))
        XCTAssertTrue(HourlyJobValidity.canKeep(quick, settings: saved, at: harness.clock, sourceIsAvailable: true, previewSettings: draft))
        try await harness.processor.process(quick)
        XCTAssertEqual(harness.created.first?.settings.promptTemplate, draft.promptTemplate)
        XCTAssertEqual(harness.settings, saved)
        XCTAssertTrue(harness.applied.isEmpty)
        try await harness.processor.process(harness.job(intent: .manualWallpaper))
        XCTAssertEqual(harness.created.last?.settings, saved)
        XCTAssertEqual(harness.applied.map(\.renderProfile), [.wallpaper])
    }

    func testCompletingReservationKeepsSendDayCountAndRefundCannotRepeat() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        var ledger = ImageGenerationLedger()
        let paid = ledger.reserve(at: today)
        ledger.complete(paid)
        XCTAssertEqual(ledger.count(on: today), 1)
        XCTAssertTrue(ledger.reservations.isEmpty)
        ledger.refund(paid)
        XCTAssertEqual(ledger.count(on: today), 1)
        let rejected = ledger.reserve(at: today)
        ledger.refund(rejected)
        ledger.refund(rejected)
        XCTAssertEqual(ledger.count(on: today), 1)
        XCTAssertTrue(ledger.reservations.isEmpty)
    }

    @MainActor
    func testPausingDuringSourceReadPreventsPaymentButExplicitPreviewCanContinue() async throws {
        let automatic = ProcessorHarness()
        automatic.readGate = ProcessorGate()
        let task = Task { try await automatic.processor.process(automatic.job(intent: .automaticWallpaper)) }
        await eventually { automatic.readCount == 1 }
        automatic.settings.automaticUpdates = false
        automatic.readGate?.release()
        try await task.value
        XCTAssertTrue(automatic.created.isEmpty)
        XCTAssertEqual(automatic.ledger.count(on: automatic.clock), 0)

        let preview = ProcessorHarness()
        preview.settings.automaticUpdates = false
        try await preview.processor.process(preview.job(intent: .preview))
        XCTAssertEqual(preview.created.count, 1)
        XCTAssertTrue(preview.applied.isEmpty)
    }

    @MainActor
    func testAlreadySentRequestFinishesAndCachesAfterPauseWithoutApplyingDesktop() async throws {
        let harness = ProcessorHarness()
        harness.creationGate = ProcessorGate()
        let task = Task { try await harness.processor.process(harness.job(intent: .automaticWallpaper)) }
        await eventually { harness.created.count == 1 }
        XCTAssertEqual(harness.ledger.count(on: harness.clock), 1)
        harness.settings.automaticUpdates = false
        harness.creationGate?.release()
        try await task.value
        XCTAssertEqual(harness.recorded.count, 1)
        XCTAssertTrue(harness.applied.isEmpty)
    }

    @MainActor
    func testStaleDesktopJobsCannotReadOrPayAndExplicitPastHourPreviewCannotApply() async throws {
        let harness = ProcessorHarness()
        for intent: HourlyGenerationJob.Intent in [.automaticWallpaper, .manualWallpaper] {
            try await harness.processor.process(harness.job(hour: 13, intent: intent))
            try await harness.processor.process(harness.job(date: harness.yesterday, intent: intent))
        }
        XCTAssertEqual(harness.readCount, 0)
        XCTAssertEqual(harness.weatherCount, 0)
        XCTAssertTrue(harness.created.isEmpty)
        try await harness.processor.process(harness.job(hour: 13, intent: .preview))
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertTrue(harness.applied.isEmpty)
    }

    @MainActor
    func testNextDayWeatherFailurePreservesQueueAndRetriesOnlyAfterDelay() async {
        let harness = ProcessorHarness()
        harness.failWeather = true
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(hour: 16, date: harness.yesterday, intent: .preview))
        await eventually { queue.retryAfter != nil }
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertFalse(queue.isLimitPaused)
        XCTAssertEqual(harness.weatherCount, 1)
        queue.resume()
        queue.resume()
        XCTAssertEqual(harness.weatherCount, 1)
        harness.failWeather = false
        harness.clock = harness.clock.addingTimeInterval(61)
        queue.resume()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.weatherCount, 2)
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.created.first?.date, Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: harness.clock))
    }

    @MainActor
    func testDisappearedCachedPictureWithZeroBudgetPausesInsteadOfRetryingForever() async {
        let harness = ProcessorHarness()
        let reservationDay = harness.clock
        for _ in 0..<24 { _ = harness.ledger.reserve(at: reservationDay) }
        let queue = harness.makeQueue()
        var errors = 0
        queue.onError = { _, _ in errors += 1 }
        var formerlyCached = harness.job(intent: .preview)
        formerlyCached.requiresCredit = false
        queue.enqueue(formerlyCached)
        await eventually { queue.isLimitPaused }
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(queue.pending.first?.requiresCredit, true)
        XCTAssertEqual(harness.readCount, 0)
        XCTAssertTrue(harness.created.isEmpty)
        queue.clearPending()
    }

    @MainActor
    func testHeldPreviewWeatherRetryDoesNotDelayReadyAutomaticRequest() async {
        let harness = ProcessorHarness()
        harness.failWeather = true
        harness.weatherGate = ProcessorGate()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(hour: 16, date: harness.yesterday, intent: .preview))
        await eventually { harness.weatherCount == 1 }
        queue.enqueue(harness.job(intent: .automaticWallpaper))
        harness.weatherGate?.release()
        await eventually { harness.created.count == 1 && queue.retryAfter != nil }
        XCTAssertEqual(harness.created.first?.intent, .automaticWallpaper)
        XCTAssertEqual(harness.applied.count, 1)
        XCTAssertEqual(queue.pending.map(\.hour), [16])
        XCTAssertEqual(harness.weatherCount, 1)
        XCTAssertFalse(queue.isLimitPaused)
        queue.clearPending()
    }

    @MainActor
    func testNextDayForcedPreviewConvergesWithTodayAutomaticAndChargesOnce() async {
        let harness = ProcessorHarness()
        harness.settings.promptTemplate = "Paint {{date}}"
        harness.weatherGate = ProcessorGate()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(date: harness.yesterday, intent: .preview, forceFresh: true))
        await eventually { harness.weatherCount == 1 }
        queue.enqueue(harness.job(intent: .automaticWallpaper))
        harness.weatherGate?.release()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.ledger.count(on: harness.clock), 1)
        XCTAssertEqual(harness.applied.count, 1)
        XCTAssertTrue(harness.created[0].intent.contains(.preview))
        XCTAssertTrue(harness.created[0].intent.contains(.automaticWallpaper))
    }

    @MainActor
    func testWeatherRetryPreservesTodayIntentMergedIntoOldDayPreview() async {
        let harness = ProcessorHarness()
        harness.failWeather = true
        harness.weatherGate = ProcessorGate()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(date: harness.yesterday, intent: .preview, forceFresh: true))
        await eventually { harness.weatherCount == 1 }
        queue.enqueue(harness.job(intent: .automaticWallpaper))
        harness.weatherGate?.release()
        await eventually { queue.retryAfter != nil }
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.date, harness.clock)
        XCTAssertTrue(queue.pending.first?.intent.contains(.automaticWallpaper) == true)
        XCTAssertTrue(queue.pending.first?.userInitiated == true)
        harness.failWeather = false
        harness.clock = harness.clock.addingTimeInterval(61)
        queue.resume()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.applied.count, 1)
    }

    @MainActor
    func testExpiredDesktopIntentCannotReturnWhenMergedPreviewRollsToNextDay() async {
        let harness = ProcessorHarness()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(date: harness.yesterday, intent: [.preview, .manualWallpaper, .automaticWallpaper], forceFresh: true))
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.created.first?.intent, .preview)
        XCTAssertTrue(harness.applied.isEmpty)
    }

    @MainActor
    func testAutomaticIntentMergedDuringPaidRequestAppliesOnlyMatchingCurrentHour() async {
        let harness = ProcessorHarness()
        harness.creationGate = ProcessorGate()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(intent: .preview, forceFresh: true))
        await eventually { harness.created.count == 1 }
        queue.enqueue(harness.job(intent: .automaticWallpaper))
        harness.creationGate?.release()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.applied.count, 1)
    }

    @MainActor
    func testDifferentWeatherOnSameDayNeverCoalesces() async {
        let harness = ProcessorHarness()
        harness.readGate = ProcessorGate()
        let queue = harness.makeQueue()
        queue.enqueue(harness.job(intent: .preview, weather: "clear", forceFresh: true))
        await eventually { harness.readCount == 1 }
        queue.enqueue(harness.job(intent: .preview, weather: "rain", forceFresh: true))
        harness.readGate?.release()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(harness.created.map { $0.weather.label }, ["clear", "rain"])
        XCTAssertEqual(harness.ledger.count(on: harness.clock), 2)
    }

    @MainActor
    func testCacheHitAvoidsSourcesAndPaymentButExplicitFreshCreationDoesNot() async throws {
        let harness = ProcessorHarness()
        let job = harness.job(intent: .preview)
        harness.cachedIDs.insert(job.id)
        try await harness.processor.process(job)
        XCTAssertEqual(harness.readCount, 0)
        XCTAssertTrue(harness.created.isEmpty)
        var fresh = job
        fresh.forceFresh = true
        try await harness.processor.process(fresh)
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.ledger.count(on: harness.clock), 1)
    }

    @MainActor
    func testRequestStartDayIsChargedAndOnlyDefinite4xxRejectionRefunds() async throws {
        let timedOut = ProcessorHarness()
        timedOut.creationGate = ProcessorGate()
        timedOut.creationError = ProcessorError.requestFailed
        let sendDay = timedOut.clock
        let task = Task { try await timedOut.processor.process(timedOut.job(intent: .preview)) }
        await eventually { timedOut.created.count == 1 }
        timedOut.clock = Calendar.current.date(byAdding: .day, value: 1, to: timedOut.clock)!
        timedOut.creationGate?.release()
        do { try await task.value; XCTFail("Expected request failure") } catch {}
        XCTAssertEqual(timedOut.ledger.count(on: sendDay), 1)
        XCTAssertEqual(timedOut.ledger.count(on: timedOut.clock), 0)

        let rejected = ProcessorHarness()
        rejected.rejection = 429
        do { try await rejected.processor.process(rejected.job(intent: .preview)); XCTFail("Expected rejection") } catch {}
        XCTAssertEqual(rejected.ledger.count(on: rejected.clock), 0)
        let serverFailure = ProcessorHarness()
        serverFailure.rejection = 500
        do { try await serverFailure.processor.process(serverFailure.job(intent: .preview)); XCTFail("Expected server failure") } catch {}
        XCTAssertEqual(serverFailure.ledger.count(on: serverFailure.clock), 1)
    }

    @MainActor
    func testInvalidWeatherRetryDoesNotStallNewRecipeWorkOrPublishOldError() async {
        let harness = ProcessorHarness()
        harness.failWeather = true
        harness.weatherGate = ProcessorGate()
        let queue = harness.makeQueue()
        var errors = 0
        queue.onError = { _, _ in errors += 1 }
        queue.enqueue(harness.job(date: harness.yesterday, intent: .preview))
        await eventually { harness.weatherCount == 1 }
        harness.settings.promptTemplate = "A new prompt"
        queue.enqueue(harness.job(hour: 15, intent: .preview))
        harness.weatherGate?.release()
        await eventually { queue.current == nil && queue.pending.isEmpty }
        XCTAssertEqual(errors, 0)
        XCTAssertEqual(harness.created.count, 1)
        XCTAssertEqual(harness.created.first?.settings.promptTemplate, "A new prompt")
        XCTAssertNil(queue.retryAfter)
    }

    @MainActor
    func testPendingJobsRoundTripAndRestoreRejectsStaleDesktopAndChangedRecipe() throws {
        let harness = ProcessorHarness()
        let preview = harness.job(date: harness.yesterday, intent: .preview, forceFresh: true)
        let desktop = harness.job(date: harness.yesterday, intent: .manualWallpaper)
        let automatic = harness.job(hour: 13, intent: .automaticWallpaper)
        var otherSettings = harness.settings
        otherSettings.promptTemplate = "Different recipe"
        let changed = harness.job(settings: otherSettings, intent: .preview)
        let data = try JSONEncoder().encode([preview, preview, desktop, automatic, changed])
        let restored = try JSONDecoder().decode([HourlyGenerationJob].self, from: data)
        XCTAssertEqual(restored.first, preview)
        let queue = HourlyGenerationQueue(process: { _ in XCTFail("Budget zero") }, remainingBudget: { 0 },
                                         shouldKeep: { job, date in HourlyJobValidity.canKeep(job, settings: harness.settings, at: date, sourceIsAvailable: true) },
                                         now: { harness.clock })
        queue.restore(restored)
        XCTAssertEqual(queue.pending, [preview])
        XCTAssertTrue(queue.isLimitPaused)
        var changedFlag = false
        queue.onChange = { changedFlag = !queue.isLimitPaused && queue.pending.isEmpty }
        harness.settings.promptTemplate = "Another recipe"
        queue.resume()
        XCTAssertTrue(changedFlag)
        XCTAssertFalse(queue.isLimitPaused)
    }
}

private enum ProcessorError: Error { case weatherUnavailable, requestFailed }

@MainActor
private final class ProcessorGate {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        released = true
        let continuations = waiting
        waiting.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

@MainActor
private final class ProcessorHarness {
    var clock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 14))!
    var settings = CanvasSettings()
    var previewSettings: CanvasSettings?
    var ledger = ImageGenerationLedger()
    var created: [HourlyGenerationJob] = []
    var recorded: [HourlyGenerationJob] = []
    var applied: [HourlyGenerationJob] = []
    var readCount = 0
    var weatherCount = 0
    var cachedIDs: Set<String> = []
    var readGate: ProcessorGate?
    var creationGate: ProcessorGate?
    var weatherGate: ProcessorGate?
    var failWeather = false
    var allowsPreview = true
    var rejection: Int?
    var creationError: Error?
    var queue: HourlyGenerationQueue?
    var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: clock)! }
    lazy var processor = HourlyGenerationProcessor(services: .init(
        now: { [unowned self] in clock },
        settings: { [unowned self] in settings },
        settingsForJob: { [unowned self] in $0.renderProfile == .quickPreview ? previewSettings ?? settings : settings },
        remainingBudget: { [unowned self] in 24 - ledger.count(on: clock) },
        budgetForJob: { [unowned self] in $0.renderProfile.availableBudget(totalRemaining: 24 - ledger.count(on: clock), previewsToday: ledger.previewCount(on: clock)) },
        permitsPreview: { [unowned self] in allowsPreview },
        weather: { [unowned self] _, date in
            weatherCount += 1
            await weatherGate?.wait()
            if failWeather { throw ProcessorError.weatherUnavailable }
            return WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: date)
        },
        canonicalize: { [unowned self] in queue?.updateCurrent($0) ?? $0 },
        latestIntent: { [unowned self] job in queue?.current.map { job.merged(with: $0) } ?? job },
        cached: { [unowned self] in cachedIDs.contains($0.id) ? URL(fileURLWithPath: "/fixture/cache.png") : nil },
        readPrompt: { [unowned self] _ in readCount += 1; await readGate?.wait(); return "Fake prompt" },
        destination: { URL(fileURLWithPath: "/fixture/\($0.id).png") },
        create: { [unowned self] job, _, willSend, didReject in
            try willSend()
            created.append(job)
            await creationGate?.wait()
            if let rejection { didReject(rejection); throw ProcessorError.requestFailed }
            if let creationError { throw creationError }
            return Data("fake image".utf8)
        },
        reserve: { [unowned self] in ledger.reserve(at: $0) },
        reserveForProfile: { [unowned self] in ledger.reserve(at: $0, profile: $1) },
        refund: { [unowned self] in ledger.refund($0) },
        write: { _, _ in },
        record: { [unowned self] job, _ in recorded.append(job); cachedIDs.insert(job.id) },
        apply: { [unowned self] job, _ in applied.append(job) },
        completed: { _, _, _ in }
    ))

    init() { settings.automaticUpdates = true; settings.sourcePath = "/fixture/picture.png" }

    func makeQueue() -> HourlyGenerationQueue {
        let result = HourlyGenerationQueue(process: { [unowned self] in try await processor.process($0) },
                                           remainingBudget: { [unowned self] in 24 - ledger.count(on: clock) },
                                           budgetForJob: { [unowned self] in $0.renderProfile.availableBudget(totalRemaining: 24 - ledger.count(on: clock), previewsToday: ledger.previewCount(on: clock)) },
                                           shouldKeep: { [unowned self] job, date in HourlyJobValidity.canKeep(job, settings: settings, at: date,
                                                                                                          sourceIsAvailable: true, previewSettings: previewSettings) },
                                           now: { [unowned self] in clock })
        queue = result
        return result
    }

    func job(hour: Int = 14, date: Date? = nil, settings snapshot: CanvasSettings? = nil,
             intent: HourlyGenerationJob.Intent, weather: String = "clear", forceFresh: Bool = false,
             renderProfile: GenerationRenderProfile = .wallpaper) -> HourlyGenerationJob {
        let date = date ?? clock
        let snapshot = snapshot ?? settings
        let recipe = HourWallpaperCache.recipeID(for: snapshot, date: date)
        return HourlyGenerationJob(id: HourWallpaperCache.jobID(recipeID: recipe, hour: hour, weather: weather, renderProfile: renderProfile),
                                   hour: hour, date: date, recipeID: recipe,
                                   weather: WeatherSnapshot(label: weather, symbol: "sun.max", fetchedAt: date),
                                   settings: snapshot, sourcePath: "/fixture/picture.png",
                                   priority: intent == .automaticWallpaper ? .automatic : .manual,
                                   requiresCredit: true, forceFresh: forceFresh,
                                   userInitiated: intent != .automaticWallpaper, intent: intent, renderProfile: renderProfile)
    }
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Fake processor did not reach the expected state", file: file, line: line)
}
