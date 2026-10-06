import XCTest
@testable import Daydreaming

final class AppModelHourlyTests: XCTestCase {

    @MainActor
    func testChoosingYosemitePreviewsSourceWithoutClaimingDesktopWasChanged() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let previous = fake.directory.appendingPathComponent("previous.jpg")
        try Data("previous source".utf8).write(to: previous)
        fake.settings.sourcePath = previous.path
        fake.settings.sourceDigest = "previous-picture"
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded(userInitiated: true)
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        let desktop = model.displayedImageURL
        let updated = model.lastUpdated
        model.useBuiltInPicture(replaceCurrent: true)
        XCTAssertEqual(model.displayedImageURL, desktop)
        XCTAssertEqual(model.lastUpdated, updated)
        XCTAssertEqual(model.canvasImageURL, fake.source)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied.count, 1)
    }

    @MainActor
    func testRejectedKeyShowsBlockedUpdatesAndPreservesActualDesktop() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.restoreOriginal()
        let applied = model.displayedImageURL
        let updated = model.lastUpdated
        model.settings.automaticUpdates = true
        fake.creationError = ImageClientError.invalidKey
        await model.refreshIfNeeded(force: true, userInitiated: true)
        await appEventually { model.activity == .failed && !model.isGenerating }
        XCTAssertEqual(model.automaticUpdateStatus, "Updates blocked · replace API key")
        XCTAssertEqual(model.displayedImageURL, applied)
        XCTAssertEqual(model.lastUpdated, updated)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertTrue(model.desktopPictureDescription?.contains("original") == true)
    }

    @MainActor
    func testAppUpdateKeepsQueuedEditedPreviewAndRejectsCreationDuringQuitHandshake() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded(userInitiated: true)
        await appEventually { fake.created.count == 1 }
        model.setPreviewHour(16)
        model.schedulePromptUpdate(draft: "An edited scene")
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { model.isPreviewGenerationScheduled && fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.pending.contains { $0.settings.promptTemplate == "An edited scene" } }
        let pending = fake.pending
        model.prepareForAppUpdate()
        model.generateNow()
        model.cancelPromptUpdate()
        model.savePrompt("An edited scene", generatesDraft: false)
        XCTAssertFalse(model.canGenerate)
        XCTAssertFalse(model.canConfirmWallpaper)
        XCTAssertEqual(model.settings.promptTemplate, "An edited scene")
        XCTAssertEqual(fake.pending, pending)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertEqual(fake.pending, pending)
    }

    @MainActor
    func testAppUpdateFreezesNewRequestsAndPreservesPendingWorkAfterPaidResultFinishes() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded(userInitiated: true)
        await appEventually { fake.created.count == 1 }
        model.setPreviewHour(16)
        model.enqueuePreviewHour()
        await appEventually { model.pendingHourCount == 1 }
        model.prepareForAppUpdate()
        fake.creationGate?.release()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        await model.refreshIfNeeded(force: true, userInitiated: true)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertEqual(fake.pending.count, 1)
        XCTAssertEqual(fake.pending.first?.hour, 16)
        XCTAssertTrue(model.settings.automaticUpdates)

        let restored = fake.model(nextCheck: fake.clock.addingTimeInterval(3_600))
        defer { restored.stopBackgroundTasks() }
        await restored.refreshIfNeeded()
        await appEventually { fake.created.count == 2 && !restored.isGenerating }
        XCTAssertEqual(fake.created.last?.hour, 16)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertTrue(fake.pending.isEmpty)
    }

    @MainActor
    func testSetupCannotFinishWithOldPictureWhileReplacementIsImporting() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.weatherChoice = .clear
        fake.importGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        XCTAssertTrue(model.restartOnboarding())
        model.importImage(fake.source)
        await appEventually { fake.importStarts == 1 }
        XCTAssertTrue(model.isImportingPicture)
        XCTAssertFalse(model.canGenerate)
        model.finishOnboarding()
        XCTAssertFalse(model.onboardingComplete)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        fake.importGate?.release()
        await appEventually { !model.isImportingPicture }
        model.finishOnboarding(createFirstWallpaper: false)
        XCTAssertTrue(model.onboardingComplete)
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testChoosingReusableYosemiteInvalidatesPendingReplacementImport() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.importGate = AppHourlyGate()
        let previous = fake.directory.appendingPathComponent("previous.jpg")
        try Data("previous".utf8).write(to: previous)
        fake.settings.sourcePath = previous.path
        let replacement = fake.directory.appendingPathComponent("replacement.jpg")
        try Data("replacement".utf8).write(to: replacement)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.importImage(replacement)
        await appEventually { fake.importStarts == 1 }
        model.useBuiltInPicture(replaceCurrent: true)
        XCTAssertFalse(model.isImportingPicture)
        fake.importGate?.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.sourceImageURL, fake.source)
        XCTAssertEqual(model.settings.pictureName, "Yosemite Valley")
        XCTAssertFalse(model.pictureHistoryEntries.contains { $0.digest == replacement.lastPathComponent })
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testReplacementImportCannotBeOverwrittenByCancelledImportAndKeepsCorrectHistoryName() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.pictureName = "Previous picture"
        fake.importGate = AppHourlyGate()
        let first = fake.directory.appendingPathComponent("first.jpg")
        let second = fake.directory.appendingPathComponent("second.jpg")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.importImage(first)
        await appEventually { fake.importStarts == 1 }
        model.importImage(second)
        await appEventually { fake.importStarts == 2 }
        fake.importGate?.release()
        await appEventually { model.settings.sourcePath == second.path }
        XCTAssertEqual(model.settings.pictureName, "second.jpg")
        XCTAssertEqual(model.pictureHistoryEntries.first { $0.digest == second.lastPathComponent }?.name, "second.jpg")
        XCTAssertFalse(model.pictureHistoryEntries.contains { $0.digest == first.lastPathComponent })
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
    }


    @MainActor
    func testClearingCacheKeepsDesktopFileWhenOriginalIsMissing() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        let desktop = try XCTUnwrap(model.displayedImageURL)
        let bytes = try Data(contentsOf: desktop)
        let updated = model.lastUpdated
        try FileManager.default.removeItem(at: fake.source)
        model.clearCache()
        XCTAssertEqual(try Data(contentsOf: desktop), bytes)
        XCTAssertEqual(model.displayedImageURL, desktop)
        XCTAssertEqual(model.lastUpdated, updated)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(model.recovery, .image)
    }
    @MainActor
    func testLedgerDecodingMigratesLegacyCountsOnlyWhenCurrentHistoryIsAbsent() throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let migrated = try AppModel.decodedGenerationLedger(data: nil, legacyDay: "2026-10-06", legacyCount: 7)
        XCTAssertEqual(migrated.count(on: fake.clock), 7)
        var current = ImageGenerationLedger()
        let attempt = current.reserve(at: fake.clock)
        current.complete(attempt)
        let decoded = try AppModel.decodedGenerationLedger(data: JSONEncoder().encode(current),
                                                           legacyDay: "2026-10-06", legacyCount: 7)
        XCTAssertEqual(decoded.count(on: fake.clock), 1)
        XCTAssertThrowsError(try AppModel.decodedGenerationLedger(data: Data("{broken ledger".utf8),
                                                                 legacyDay: "2026-10-06", legacyCount: 0))
    }

    @MainActor
    func testUnreadableLedgerBlocksRestoredAutomaticManualAndPreviewChargesWithoutOverwritingIt() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let unreadable = Data("{broken paid request history".utf8)
        fake.ledgerData = unreadable
        fake.pending = [fake.job(hour: 14, intent: .automaticWallpaper)]
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        XCTAssertNotNil(model.generationStorageError)
        XCTAssertEqual(model.remainingGenerations, 0)
        XCTAssertFalse(model.canGenerate)
        XCTAssertFalse(model.canCreateDraft)
        model.settings.dailyGenerationLimit = 288
        await model.refreshIfNeeded()
        await model.refreshIfNeeded(userInitiated: true)
        model.generateNow()
        model.endScrubbingPreview(hour: 8)
        await model.adoptDisplayedPictureAsWallpaper()
        await Task.yield()
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledgerWrites, 0)
        XCTAssertEqual(fake.ledgerData, unreadable)
        XCTAssertEqual(model.remainingGenerations, 0)
    }

    @MainActor
    func testUnreadableLedgerStillAllowsCachedWallpaperApplicationWithoutPayment() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let saved = fake.directory.appendingPathComponent("already-paid.png")
        try Data("paid wallpaper".utf8).write(to: saved)
        var cache = HourWallpaperCache(directory: fake.directory)
        let recipe = HourWallpaperCache.recipeID(for: fake.settings, date: fake.clock)
        try cache.record(pictureID: HourWallpaperCache.pictureID(for: fake.settings), recipeID: recipe, hour: 14,
                         weather: WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: fake.clock),
                         url: saved, settingsSnapshot: fake.settings)
        let unreadable = Data("broken ledger".utf8)
        fake.ledgerData = unreadable
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied == [saved] && !model.isGenerating }
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledgerWrites, 0)
        XCTAssertEqual(fake.ledgerData, unreadable)
        XCTAssertEqual(model.remainingGenerations, 0)
    }

    @MainActor
    func testUnreadableWallpaperHistoryBlocksNewChargesAndPreservesPurchasedFiles() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let index = fake.directory.appendingPathComponent("hour-wallpapers.json")
        let unreadable = Data("broken wallpaper history".utf8)
        try unreadable.write(to: index)
        let purchased = fake.directory.appendingPathComponent("purchased.png")
        let purchasedBytes = Data("paid picture".utf8)
        try purchasedBytes.write(to: purchased)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded(userInitiated: true)
        XCTAssertEqual(model.remainingGenerations, 0)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertEqual(try Data(contentsOf: index), unreadable)
        XCTAssertEqual(try Data(contentsOf: purchased), purchasedBytes)
    }

    @MainActor
    func testRestoringOriginalRecordsSuccessfulApplyButNotFailure() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        let generated = model.displayedImageURL
        let firstUpdate = model.lastUpdated
        fake.clock = fake.clock.addingTimeInterval(10)
        fake.failApply = true
        model.restoreOriginal()
        XCTAssertEqual(model.displayedImageURL, generated)
        XCTAssertEqual(model.lastUpdated, firstUpdate)
        fake.failApply = false
        model.restoreOriginal()
        XCTAssertEqual(model.displayedImageURL, fake.source)
        XCTAssertEqual(model.lastUpdated, fake.clock)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertFalse(model.settings.automaticUpdates)
    }

    @MainActor
    func testClearingGeneratedImagesRecordsOriginalApplyWithoutAnotherCharge() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        fake.clock = fake.clock.addingTimeInterval(10)
        model.clearCache()
        XCTAssertEqual(model.displayedImageURL, fake.source)
        XCTAssertEqual(model.lastUpdated, fake.clock)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(HourWallpaperCache(directory: fake.directory).entries.isEmpty)
        fake.clock = fake.clock.addingTimeInterval(10)
        model.clearCache()
        XCTAssertEqual(model.lastUpdated, fake.clock.addingTimeInterval(-10))
    }

    @MainActor
    func testRestoredEveningDeadlineRunsOnceWhenDueOrOverdue() async throws {
        for minutesLate in [0, 55] {
            let fake = try AppHourlyFake()
            defer { fake.removeFiles() }
            let due = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: fake.clock)!
            fake.clock = due.addingTimeInterval(Double(minutesLate) * 60)
            fake.settings.interval = .twiceDaily
            let model = fake.model(nextCheck: due)
            defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
            XCTAssertEqual(model.nextCheck(after: fake.clock), due)
            await model.refreshIfNeeded()
            await appEventually { fake.applied.count == 1 && !model.isGenerating }
            await model.refreshIfNeeded()
            XCTAssertEqual(fake.created.count, 1)
            XCTAssertEqual(fake.created[0].hour, 19)
            XCTAssertEqual(fake.applied.count, 1)
            XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
            XCTAssertEqual(model.lastUpdated, fake.clock)
        }
    }

    @MainActor
    func testRestoringDifferentFrequencyPreservesAnIntentionallyLaterDeadline() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.interval = .monthly
        let pinned = Calendar.current.date(byAdding: .day, value: 45, to: fake.clock)!
        let model = fake.model(nextCheck: pinned)
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        XCTAssertEqual(model.nextCheck(after: fake.clock), pinned)
        await model.refreshIfNeeded()
        XCTAssertEqual(model.nextCheck(after: fake.clock), pinned)
        XCTAssertEqual(fake.weatherCalls, 0)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testRestoringAnUnscheduledEveningRecipeStillCreatesTheInitialWallpaper() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.clock = Calendar.current.date(bySettingHour: 19, minute: 55, second: 0, of: fake.clock)!
        fake.settings.interval = .twiceDaily
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(model.lastUpdated, fake.clock)
    }

    @MainActor
    func testConfirmWhilePaidPreviewRunsQueuesOneFullWallpaperAndNeverAppliesThePreview() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 8)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 }
        XCTAssertEqual(fake.created[0].renderProfile, .quickPreview)
        XCTAssertNil(model.lastUpdated)
        XCTAssertTrue(model.canConfirmWallpaper)
        await model.adoptDisplayedPictureAsWallpaper()
        await model.adoptDisplayedPictureAsWallpaper()
        XCTAssertTrue(model.settings.automaticUpdates)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.pending.filter { $0.renderProfile == .wallpaper }.count, 1)
        fake.creationGate?.release()
        await appEventually { fake.created.count == 2 && fake.applied.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.renderProfile, .wallpaper)
        XCTAssertEqual(fake.applied, [try XCTUnwrap(model.displayedImageURL)])
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertEqual(model.lastUpdated, fake.clock)
        XCTAssertTrue(model.isCurrentRecipeAdopted)
    }

    @MainActor
    func testReconfirmingRunningWallpaperIsFreeEvenWhenImageReuseIsDisabled() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.reuseMatchingImages = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        model.setPreviewHour(8)
        XCTAssertTrue(model.canConfirmWallpaper)
        await model.adoptDisplayedPictureAsWallpaper()
        XCTAssertNil(model.selectedPreviewHour)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

    @MainActor
    func testReconfirmingRunningWallpaperCancelsAnUnpaidPreviewBeforeSending() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        fake.beforeSendGate = AppHourlyGate()
        model.endScrubbingPreview(hour: 8)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.createPreparations == 2 }
        await model.adoptDisplayedPictureAsWallpaper()
        fake.beforeSendGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertNil(model.selectedPreviewHour)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

    @MainActor
    func testReconfirmingRunningWallpaperLetsAPaidPreviewFinishWithoutApplyingIt() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        fake.creationGate = AppHourlyGate()
        model.endScrubbingPreview(hour: 8)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 2 }
        await model.adoptDisplayedPictureAsWallpaper()
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertNil(model.selectedPreviewHour)
        XCTAssertEqual(fake.created.count, 2)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
    }

    @MainActor
    func testConfirmationDuringFullCreationCoalescesIntoItsPaidRequest() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.generateNow()
        await appEventually { fake.created.count == 1 }
        XCTAssertFalse(model.canGenerate)
        XCTAssertTrue(model.canConfirmWallpaper)
        await model.adoptDisplayedPictureAsWallpaper()
        await model.adoptDisplayedPictureAsWallpaper()
        fake.creationGate?.release()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        XCTAssertTrue(model.settings.automaticUpdates)
        XCTAssertTrue(model.isCurrentRecipeAdopted)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

    @MainActor
    func testFrequencyChangeWithdrawsAutomaticForecastBeforeItCanCharge() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        let preparing = Task { await model.refreshIfNeeded() }
        await appEventually { fake.weatherCalls == 1 }
        model.settings.interval = .monthly
        fake.weatherGate?.release()
        await preparing.value
        await model.refreshIfNeeded()
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertTrue(fake.pending.isEmpty)
    }

    @MainActor
    func testFrequencyChangeWithdrawsAutomaticRequestJustBeforePayment() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.beforeSendGate = AppHourlyGate()
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.createPreparations == 1 }
        model.settings.interval = .monthly
        fake.beforeSendGate?.release()
        await appEventually { !model.isGenerating }
        await model.refreshIfNeeded()
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertTrue(fake.ledger.reservations.isEmpty)
    }

    @MainActor
    func testFrequencyChangePreservesAnExplicitRequestMergedIntoAutomaticWork() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        let preparing = Task { await model.refreshIfNeeded() }
        await appEventually { fake.weatherCalls == 1 }
        model.generateNow()
        await appEventually { model.isPreparingManualCreation }
        model.settings.interval = .monthly
        fake.weatherGate?.release()
        await preparing.value
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.created[0].intent.contains(.manualWallpaper))
    }

    @MainActor
    func testFrequencyChangeLetsPaidAutomaticImageFinishAndDefersNextUpdate() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.ledger.count(on: fake.clock) == 1 }
        model.settings.interval = .monthly
        fake.creationGate?.release()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertTrue(fake.ledger.reservations.isEmpty)
        XCTAssertEqual(model.nextCheck(after: fake.clock), Calendar.current.date(byAdding: .month, value: 1, to: fake.clock))
    }

    @MainActor
    func testChangingFrequencyDoesNotCreateOrApplyAndHonorsLongerDeadline() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model(nextCheck: fake.clock.addingTimeInterval(3_600))
        let recipe = HourWallpaperCache.recipeID(for: model.settings, date: fake.clock)
        model.settings.interval = .monthly
        let next = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: 1, to: fake.clock))
        XCTAssertEqual(model.nextCheck(after: fake.clock), next)
        XCTAssertEqual(HourWallpaperCache.recipeID(for: model.settings, date: fake.clock), recipe)
        fake.clock = Calendar.current.date(byAdding: .day, value: 1, to: fake.clock)!
        await model.refreshIfNeeded()
        XCTAssertEqual(fake.weatherCalls, 0)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        fake.clock = next
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(model.nextCheck(after: next), Calendar.current.date(byAdding: .month, value: 1, to: next))
    }

    @MainActor
    func testMinuteFrequencyRunsOnlyAtDeadlineAndReusesPaidImage() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        model.settings.interval = .everyMinute
        let next = fake.clock.addingTimeInterval(60)
        XCTAssertEqual(model.nextCheck(after: fake.clock), next)
        await model.refreshIfNeeded()
        XCTAssertTrue(fake.created.isEmpty)
        fake.clock = next
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        fake.clock = next.addingTimeInterval(60)
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 2 && !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertEqual(model.nextCheck(after: fake.clock), fake.clock.addingTimeInterval(60))
    }

    @MainActor
    func testFrequencyChangePreservesApplyOnlyRetryAndItsPaidImage() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.failApply = true
        fake.settings.reuseMatchingImages = false
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { !model.isGenerating && model.activity == .failed }
        let saved = try XCTUnwrap(fake.applicationRetry)
        model.settings.interval = .weekly
        XCTAssertEqual(fake.applicationRetry?.url, saved.url)
        fake.failApply = false
        fake.clock = fake.clock.addingTimeInterval(61)
        await model.refreshIfNeeded()
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied, [saved.url, saved.url])
        XCTAssertEqual(model.nextCheck(after: fake.clock), Calendar.current.date(byAdding: .weekOfYear, value: 1, to: fake.clock))
    }

    @MainActor
    func testSavedVariationBrowsingStaysOnSelectedOriginalWithoutChargesOrQueueChanges() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        try seedSavedVariations(fake)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let before = model.settings
        let desktop = model.displayedImageURL
        let pending = fake.pending
        let ledger = fake.ledger
        XCTAssertEqual(model.savedVariationsForSelectedPicture.count, 3)
        for _ in 0..<8 { model.browseSavedVariation(direction: 1) }
        XCTAssertEqual(model.selectedSavedWallpaper?.entry.hour, 10)
        XCTAssertTrue(model.isBrowsingSavedVariations)
        XCTAssertTrue(model.savedVariationCaption?.contains("3 of 3") == true)
        XCTAssertNotNil(model.previewPresentation.resultURL)
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.displayedImageURL, desktop)
        XCTAssertEqual(fake.pending, pending)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), ledger.count(on: fake.clock))
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.sleeper.sleepCalls, 0)
        for _ in 0..<8 { model.browseSavedVariation(direction: -1) }
        XCTAssertEqual(model.selectedSavedWallpaper?.entry.hour, 12)
        model.backToLivePreview()
        XCTAssertFalse(model.isBrowsingSavedVariations)
        XCTAssertEqual(model.canvasImageURL, desktop)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testBrowsingDoesNotCancelPendingPreviewAndKeepsItsResultInHistory() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        try seedSavedVariations(fake)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        model.browseSavedVariation(direction: 1)
        let shown = model.canvasImageURL
        XCTAssertEqual(model.selectedPreviewHour, 16)
        XCTAssertTrue(model.isPreviewGenerationScheduled)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.hour, 16)
        XCTAssertEqual(model.canvasImageURL, shown)
        XCTAssertTrue(model.isBrowsingSavedVariations)
        model.backToLivePreview()
        XCTAssertNotEqual(model.canvasImageURL, shown)
        XCTAssertEqual(model.previewPresentation.requestedHour, 16)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testIdeaAndSliderChangesLeaveSavedBrowsing() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        try seedSavedVariations(fake)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.browseSavedVariation(direction: 1)
        model.setPreviewHour(17)
        XCTAssertFalse(model.isBrowsingSavedVariations)
        XCTAssertNil(model.selectedSavedWallpaper)
        model.browseSavedVariation(direction: 1)
        model.schedulePromptUpdate(draft: "Warm light")
        XCTAssertFalse(model.isBrowsingSavedVariations)
        XCTAssertNil(model.selectedSavedWallpaper)
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testCurrentWeatherIsIndependentOfSavedHourAndRefreshesWithoutPaidJobs() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.weatherLabel = "rainy"
        try seedSavedVariations(fake)
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.browseSavedVariation(direction: 1)
        await model.refreshWorkspaceWeather()
        XCTAssertEqual(model.workspaceWeather?.label, "rainy")
        XCTAssertEqual(model.previewWeather?.label, "clear")
        for _ in 0..<10 { await model.refreshWorkspaceWeather() }
        XCTAssertEqual(fake.weatherCalls, 1)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        fake.clock = fake.clock.addingTimeInterval(901)
        await model.refreshWorkspaceWeather()
        XCTAssertEqual(fake.weatherCalls, 2)
        model.settings.weatherChoice = .snow
        await model.refreshWorkspaceWeather()
        XCTAssertEqual(model.workspaceWeather?.label, WeatherChoice.snow.rawValue)
        XCTAssertEqual(fake.weatherCalls, 2)
    }

    @MainActor
    private func seedSavedVariations(_ fake: AppHourlyFake) throws {
        var cache = HourWallpaperCache(directory: fake.directory)
        for hour in 10...12 {
            var snapshot = fake.settings
            snapshot.originalPictureDigest = "fake-picture"
            if hour == 11 { snapshot.sourceDigest = "cropped-picture" }
            let file = fake.directory.appendingPathComponent("saved-\(hour).png")
            try Data("saved variation".utf8).write(to: file)
            try cache.record(pictureID: HourWallpaperCache.pictureID(for: snapshot),
                             recipeID: HourWallpaperCache.recipeID(for: snapshot), hour: hour,
                             weather: WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: fake.clock),
                             url: file, createdAt: fake.clock.addingTimeInterval(Double(hour)),
                             settingsSnapshot: snapshot, sourceDigest: "fake-picture")
        }
        var other = fake.settings
        other.sourceDigest = "other-picture"
        other.originalPictureDigest = "other-picture"
        let file = fake.directory.appendingPathComponent("other-picture.png")
        try Data("other saved variation".utf8).write(to: file)
        try cache.record(pictureID: "other-picture", recipeID: HourWallpaperCache.recipeID(for: other), hour: 13,
                         weather: WeatherSnapshot(label: "snowy", symbol: "cloud.snow", fetchedAt: fake.clock),
                         url: file, settingsSnapshot: other, sourceDigest: "other-picture")
    }

    @MainActor
    func testWorkspaceChoiceAutomaticallyMakesOnePreviewAndNeverAppliesIt() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll(); fake.choiceSleeper.cancelAll() }
        let desktop = model.displayedImageURL
        let picture = fake.directory.appendingPathComponent("chosen-landscape.jpg")
        try Data("new chosen original".utf8).write(to: picture)
        model.chooseWorkspacePicture(picture, prompt: "Keep the mountains clear")
        XCTAssertEqual(model.canvasImageURL, picture)
        XCTAssertTrue(fake.created.isEmpty)
        await appEventually { model.stagedPictureURL == nil && fake.sleeper.waitingCount == 1 }
        XCTAssertEqual(model.sourceImageURL, picture)
        XCTAssertEqual(model.settings.promptTemplate, "Keep the mountains clear")
        XCTAssertEqual(model.sourceImageName, "chosen-landscape.jpg")
        XCTAssertEqual(model.displayedImageURL, desktop)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testSwitchingBackToPreviousPictureReusesItsPreviewWithoutAnotherCharge() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll(); fake.choiceSleeper.cancelAll() }
        let first = fake.directory.appendingPathComponent("first.jpg")
        let second = fake.directory.appendingPathComponent("second.jpg")
        try Data("first source".utf8).write(to: first)
        try Data("second source".utf8).write(to: second)
        model.chooseWorkspacePicture(first, prompt: "Evening mist")
        await appEventually { model.stagedPictureURL == nil && fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        let saved = try XCTUnwrap(model.savedWallpaperGroups.flatMap(\.wallpapers).first)
        model.chooseWorkspacePicture(second, prompt: "Warm morning")
        await appEventually { model.stagedPictureURL == nil && fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        model.chooseHistoryPicture(digest: "first.jpg", variation: saved)
        await appEventually { model.stagedPictureURL == nil && model.sourceImageURL == first }
        XCTAssertEqual(model.settings.promptTemplate, "Evening mist")
        XCTAssertEqual(model.canvasImageURL, saved.url)
        XCTAssertEqual(fake.created.count, 2)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertTrue(model.savedWallpaperGroups.flatMap(\.wallpapers).contains { $0.id == saved.id })
    }

    @MainActor
    func testTypingInEmptyWorkspaceMakesNoPreview() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.sourcePath = nil
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.schedulePromptUpdate(draft: "A quiet evening")
        model.savePrompt("A quiet evening")
        XCTAssertEqual(fake.sleeper.sleepCalls, 0)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertNil(model.sourceImageURL)
        XCTAssertFalse(model.canGenerate)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testDroppedPictureIsImmediateAndCancelRestoresRecipeWithoutCharge() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.setPreviewHour(16)
        let before = model.settings
        let canvas = model.canvasImageURL
        let desktop = model.displayedImageURL
        let picture = fake.directory.appendingPathComponent("new-picture.jpg")
        try Data("new chosen original".utf8).write(to: picture)
        model.stagePicture(picture)
        XCTAssertEqual(model.canvasImageURL, picture)
        XCTAssertEqual(model.settings, before)
        await model.refreshIfNeeded(force: true, userInitiated: true)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertTrue(fake.created.isEmpty)
        model.cancelStagedPicture()
        XCTAssertEqual(model.canvasImageURL, canvas)
        XCTAssertEqual(model.displayedImageURL, desktop)
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.selectedPreviewHour, 16)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testPictureConfirmationMakesOnePreviewAndKeepsDesktopUntouched() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let desktop = model.displayedImageURL
        let picture = fake.directory.appendingPathComponent("my-landscape.jpg")
        try Data("new chosen original".utf8).write(to: picture)
        model.stagePicture(picture)
        await model.confirmStagedPicture(prompt: "Keep it warm", crop: nil)
        XCTAssertNil(model.stagedPictureURL)
        XCTAssertEqual(model.settings.promptTemplate, "Keep it warm")
        XCTAssertEqual(model.sourceImageURL, picture)
        XCTAssertEqual(model.canvasImageURL, picture)
        XCTAssertEqual(model.displayedImageURL, desktop)
        XCTAssertFalse(model.settings.automaticUpdates)
        XCTAssertTrue(fake.created.isEmpty)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(model.pictureHistoryEntries.count, 2)
        let variation = try XCTUnwrap(model.savedWallpaperGroups.flatMap(\.wallpapers).first)
        XCTAssertEqual(variation.entry.sourceDigest, picture.lastPathComponent)
        XCTAssertEqual(variation.entry.sourcePicturePath, picture.path)
        // A second Return cannot confirm or submit the same staged picture again.
        await model.confirmStagedPicture(prompt: "Keep it warm", crop: nil)
        XCTAssertEqual(fake.created.count, 1)
    }

    @MainActor
    func testUseAdoptsRecipeAndCreatesOnlyOneFullQualityDesktopWallpaperWithoutRaisingChosenQuality() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.quality = .medium
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.stagePicture(fake.source)
        await model.confirmStagedPicture(prompt: "Follow the light", crop: nil)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        let draftURL = model.canvasImageURL
        fake.creationGate = AppHourlyGate()
        await model.adoptDisplayedPictureAsWallpaper()
        await appEventually { fake.created.count == 2 }
        await model.adoptDisplayedPictureAsWallpaper()
        XCTAssertEqual(fake.created.count, 2)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.created.last?.renderProfile, .wallpaper)
        XCTAssertEqual(fake.created.last?.settings.quality, .medium)
        XCTAssertTrue(model.settings.automaticUpdates)
        XCTAssertTrue(model.isMakingCurrentWallpaper)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating && fake.applied.count == 1 }
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertEqual(fake.applied.first, model.displayedImageURL)
        XCTAssertNotEqual(fake.applied.first, draftURL)
    }

    @MainActor
    func testConfirmingNewPictureCachesPaidOldResultButNeverAppliesIt() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.created.count == 1 }
        let picture = fake.directory.appendingPathComponent("another-picture.jpg")
        try Data("another original".utf8).write(to: picture)
        model.stagePicture(picture)
        await model.confirmStagedPicture(prompt: "Use evening light", crop: nil)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertEqual(model.sourceImageURL, picture)
        XCTAssertTrue(model.savedWallpaperGroups.flatMap(\.wallpapers).contains { $0.entry.pictureID == "fake-picture" })
        XCTAssertEqual(model.canvasImageURL, picture)
    }

    @MainActor
    func testClosingUnconfirmedPictureChoiceLetsScheduledWallpaperRun() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.stagePicture(fake.source)
        await model.refreshIfNeeded()
        XCTAssertTrue(fake.created.isEmpty)
        model.pictureChoiceWindowClosed()
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 }
        XCTAssertNil(model.stagedPictureURL)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.created.first?.renderProfile, .wallpaper)
    }

    @MainActor
    func testResumeAfterConfirmReturnsToPreviousWallpaperRecipe() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let previous = model.settings
        model.stagePicture(fake.source)
        await model.confirmStagedPicture(prompt: "An experimental painting", crop: nil)
        XCTAssertTrue(model.hasUnadoptedPicture)
        XCTAssertEqual(model.automaticUpdateActionTitle, "Resume Previous Wallpaper")
        XCTAssertTrue(model.detail.contains("paused until"))
        model.startAutomatic()
        XCTAssertEqual(model.settings.promptTemplate, previous.promptTemplate)
        XCTAssertEqual(model.settings.sourcePath, previous.sourcePath)
        XCTAssertTrue(model.settings.automaticUpdates)
        XCTAssertFalse(model.hasUnadoptedPicture)
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testAbandonedPictureChoiceExpiresWithoutChangingTheRecipeOrCharging() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let previous = model.settings
        model.stagePicture(fake.source)
        XCTAssertEqual(model.wallpaperAdoptionStatus, "Waiting for you to confirm the new picture.")
        await appEventually { fake.choiceSleeper.waitingCount == 1 }
        XCTAssertEqual(fake.choiceSleeper.requestedSeconds, [600])
        fake.choiceSleeper.wakeAll()
        await appEventually { model.stagedPictureURL == nil }
        XCTAssertEqual(model.settings, previous)
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testDesktopStatusOnlyBecomesAdoptedAfterFullWallpaperApplies() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        XCTAssertFalse(model.isCurrentRecipeAdopted)
        XCTAssertEqual(model.wallpaperAdoptionStatus, "Not on your desktop yet")
        await model.adoptDisplayedPictureAsWallpaper()
        await appEventually { fake.applied.count == 1 }
        XCTAssertTrue(model.isCurrentRecipeAdopted)
        XCTAssertEqual(model.wallpaperAdoptionStatus, "On your desktop · changes through the day")
        XCTAssertTrue(model.desktopPictureDescription?.contains(model.hourLabel(14)) == true)
        model.stopAutomatic()
        XCTAssertEqual(model.wallpaperAdoptionStatus, "On your desktop · updates paused")
        XCTAssertEqual(model.automaticUpdateStatus, "Automatic updates paused")
        model.settings.automaticUpdates = true
        model.savePrompt("Different light", generatesDraft: false)
        XCTAssertFalse(model.isCurrentRecipeAdopted)
        XCTAssertEqual(model.wallpaperAdoptionStatus, "Not on your desktop yet")
    }

    @MainActor
    func testHistoryRestagingKeepsSelectedVariationCropAndInstructionsWithoutCharging() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.sourceCrop = PictureCrop(imageSize: CGSize(width: 1200, height: 800), targetAspectRatio: 16.0 / 9, zoom: 2)
        fake.settings.promptTemplate = "Golden mist"
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 }
        let variation = try XCTUnwrap(model.savedWallpaperGroups.flatMap(\.wallpapers).first)
        let original = try XCTUnwrap(model.pictureHistoryEntries.first)
        model.stageHistoryPicture(digest: original.digest, variation: variation)
        XCTAssertEqual(model.stagedPictureInstructions, "Golden mist")
        XCTAssertEqual(model.stagedPictureCrop, fake.settings.sourceCrop)
        XCTAssertEqual(fake.created.count, 1)
        model.cancelStagedPicture()
    }

    @MainActor
    func testFailedWallpaperAdoptionShowsRecoveryAndKeepsExistingDesktop() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.creationError = ImageClientError.invalidResponse
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let desktop = model.displayedImageURL
        await model.adoptDisplayedPictureAsWallpaper()
        await appEventually { model.activity == .failed }
        XCTAssertEqual(model.recovery, .retry)
        XCTAssertTrue(model.status.contains("Couldn't"))
        XCTAssertEqual(model.displayedImageURL, desktop)
        XCTAssertFalse(model.isCurrentRecipeAdopted)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

    @MainActor
    func testRestartSetupKeepsPictureKeyAndPromptAndCancelsAnUnpaidDraft() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.promptTemplate = "My saved picture instructions"
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }

        XCTAssertTrue(model.restartOnboarding())
        XCTAssertFalse(model.onboardingComplete)
        XCTAssertFalse(model.settings.automaticUpdates)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertEqual(model.sourceImageURL, fake.source)
        XCTAssertEqual(model.displayedImageURL, fake.source)
        XCTAssertEqual(model.settings.promptTemplate, "My saved picture instructions")
        XCTAssertNil(model.selectedPreviewHour)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertTrue(fake.pending.isEmpty)
        await appEventually { fake.sleeper.waitingCount == 0 }
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)

        model.schedulePromptUpdate(draft: "Uncommitted setup instructions")
        model.endScrubbingPreview(hour: 17)
        model.generateNow()
        await model.adoptDisplayedPictureAsWallpaper()
        await model.refreshIfNeeded(force: true, userInitiated: true)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertTrue(fake.created.isEmpty)
        model.finishOnboarding(createFirstWallpaper: false)
        XCTAssertTrue(model.onboardingComplete)
        XCTAssertFalse(model.settings.automaticUpdates)
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testRestartSetupWaitsForAnInFlightRequestInsteadOfInterruptingIt() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.created.count == 1 && model.isGenerating }
        XCTAssertFalse(model.restartOnboarding())
        XCTAssertTrue(model.onboardingComplete)
        XCTAssertTrue(model.settings.automaticUpdates)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

















    @MainActor
    func testNowDraftPreparationDoesNotClaimOldDesktopAsRequestedOutput() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        let desktop = try XCTUnwrap(model.displayedImageURL)
        model.settings.automaticUpdates = false
        fake.creationGate = AppHourlyGate()
        model.schedulePromptUpdate(draft: "A new scene for Now")
        await appEventually { fake.sleeper.waitingCount == 1 }
        XCTAssertFalse(model.isPreviewOnDesktop)
        XCTAssertEqual(model.previewDetail, "Idea changed")
        fake.sleeper.wakeAll()
        await appEventually { model.isPreviewGenerationScheduled && fake.sleeper.waitingCount == 1 }
        XCTAssertEqual(model.previewPresentation.state, .preparing)
        XCTAssertNil(model.previewPresentation.resultURL)
        XCTAssertEqual(model.previewPresentation.fallbackURL, desktop)
        XCTAssertFalse(model.isPreviewOnDesktop)
        XCTAssertTrue(model.isCreatingVisiblePreview)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 2 }
        XCTAssertEqual(model.previewPresentation.state, .creating)
        XCTAssertNil(model.previewPresentation.resultURL)
        XCTAssertFalse(model.isPreviewOnDesktop)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(model.previewPresentation.state, .ready)
        XCTAssertTrue(model.previewPresentation.isDraft)
        XCTAssertNotEqual(model.previewPresentation.resultURL, desktop)
        XCTAssertEqual(model.displayedImageURL, desktop)
        model.cancelPromptUpdate()
        XCTAssertEqual(model.previewPresentation.state, .onDesktop)
        XCTAssertEqual(model.previewPresentation.resultURL, desktop)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
    }

    @MainActor
    func testRequestedDraftPresentationMovesFromPreparingToCreatingToReadyWithoutMockOutput() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.weatherGate = AppHourlyGate()
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        XCTAssertEqual(model.previewPresentation.state, .preparing)
        XCTAssertNil(model.previewPresentation.resultURL)
        fake.sleeper.wakeAll()
        await appEventually { fake.weatherCalls == 1 }
        XCTAssertEqual(model.previewPresentation.state, .preparing)
        fake.weatherGate?.release()
        await appEventually { fake.created.count == 1 }
        XCTAssertEqual(model.previewPresentation.state, .creating)
        XCTAssertEqual(model.previewHeadline, "Creating a preview for \(model.hourLabel(16))…")
        XCTAssertNil(model.previewPresentation.resultURL)
        XCTAssertFalse(model.isPreviewOnDesktop)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(model.previewPresentation.state, .ready)
        XCTAssertTrue(model.previewPresentation.isDraft)
        XCTAssertEqual(model.previewPresentation.resultURL, model.canvasImageURL)
        XCTAssertNil(model.previewPresentation.fallbackURL)
        XCTAssertEqual(model.hourAvailability, [16: .quickPreview])
        XCTAssertNil(model.desktopWallpaperHour)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }



    @MainActor
    func testSelectedHourQueueCountDoesNotIncludeOtherHoursOrClaimTheirCreation() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.created.count == 1 }
        model.setPreviewHour(16)
        model.generateNow()
        await appEventually { model.pendingHourCount == 1 }
        model.setPreviewHour(17)
        model.generateNow()
        await appEventually { model.pendingHourCount == 2 }
        fake.weatherLabel = "rain"
        model.setPreviewHour(16)
        model.generateNow()
        await appEventually { model.pendingHourCount == 3 }
        XCTAssertEqual(model.currentCreationHour, 14)
        XCTAssertEqual(model.previewPresentation.state, .queued)
        XCTAssertEqual(model.previewPresentation.selectedHourPendingCount, 2)
        XCTAssertEqual(model.previewDetail, "2 queued")
        XCTAssertFalse(model.isPreviewOnDesktop)
        XCTAssertNil(model.previewPresentation.resultURL)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating && model.pendingHourCount == 0 }
    }



    @MainActor
    func testActualSchedulerDoesNotPrepareChangedWeatherWhileDesktopRequestIsAlreadyPaid() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.created.count == 1 }
        XCTAssertNil(model.queueCancellationTitle)
        fake.clock = fake.clock.addingTimeInterval(31)
        fake.weatherLabel = "rain"
        await model.refreshIfNeeded()
        await model.refreshIfNeeded()
        XCTAssertEqual(fake.weatherCalls, 1)
        XCTAssertEqual(model.pendingHourCount, 0)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.ledger.reservations.isEmpty)
        XCTAssertEqual(fake.applied.count, 1)
    }

    @MainActor
    func testActualApplicationFailureRetriesSavedURLAndSurvivesRestoreWithoutBuyingAgain() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.reuseMatchingImages = false
        fake.failApply = true
        let first = fake.model()
        await first.refreshIfNeeded()
        await appEventually { !first.isGenerating && first.activity == .failed }
        XCTAssertNil(first.lastUpdated)
        let saved = try XCTUnwrap(fake.applicationRetry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.url.path))
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        fake.clock = fake.clock.addingTimeInterval(61)
        await first.refreshIfNeeded()
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied, [saved.url, saved.url])
        XCTAssertNil(first.lastUpdated)
        let restored = fake.model()
        fake.failApply = false
        await restored.refreshIfNeeded()
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(restored.displayedImageURL, saved.url)
        XCTAssertEqual(restored.lastUpdated, fake.clock)
        XCTAssertNil(fake.applicationRetry)
        XCTAssertTrue(fake.ledger.reservations.isEmpty)
    }

    @MainActor
    func testActualFailedPreviewNeverChangesAutomaticDeadlineOrBackoff() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let deadline = fake.clock.addingTimeInterval(3600)
        fake.creationError = AppHourlyError.failed
        let model = fake.model(nextCheck: deadline)
        model.setPreviewHour(16)
        model.enqueuePreviewHour()
        await appEventually { !model.isGenerating && model.activity == .failed }
        XCTAssertEqual(model.nextCheck(after: fake.clock), deadline)
        XCTAssertEqual(fake.created.first?.intent, .preview)
        fake.creationError = nil
        fake.clock = deadline
        await model.refreshIfNeeded()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.intent, .automaticWallpaper)
    }

    @MainActor
    func testActualManualNowUpgradesForecastPreparationAndRemainsAuthorizedOnPause() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        let automatic = Task { await model.refreshIfNeeded() }
        await appEventually { fake.weatherCalls == 1 }
        XCTAssertEqual(model.queueCancellationTitle, "Cancel Creation")
        model.generateNow()
        await appEventually { model.isPreparingManualCreation }
        model.stopAutomatic()
        fake.weatherGate?.release()
        await automatic.value
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertTrue(fake.created[0].intent.contains(.manualWallpaper))
        XCTAssertTrue(fake.created[0].userInitiated)
        XCTAssertTrue(fake.created[0].forceFresh)
        XCTAssertEqual(fake.applied.count, 1)
    }

    @MainActor
    func testActualConfirmedManualRequestShowsSkippedStatusIfHourChangesBeforeForecast() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        model.generateNow()
        await appEventually { fake.weatherCalls == 1 }
        fake.clock = fake.clock.addingTimeInterval(3600)
        fake.weatherGate?.release()
        await appEventually { model.queueCancellationTitle == nil }
        XCTAssertEqual(model.status, "Your \(model.hourLabel(14)) request was skipped because the hour changed.")
        XCTAssertEqual(model.wallpaperSummary(at: fake.clock), model.status)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testActualRestoreDefersPreviewUntilDueAutomaticHasForecastAndUsesOnlyCredit() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.dailyGenerationLimit = 1
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fake.clock)!
        fake.pending = [fake.job(hour: 16, date: yesterday, intent: .preview)]
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        XCTAssertEqual(model.pendingHourCount, 1)
        XCTAssertEqual(model.queueCancellationTitle, "Cancel Queued Wallpapers")
        XCTAssertTrue(fake.created.isEmpty)
        let refresh = Task { await model.refreshIfNeeded() }
        await appEventually { fake.weatherCalls == 1 }
        await model.refreshIfNeeded()
        XCTAssertTrue(fake.created.isEmpty)
        fake.weatherGate?.release()
        await refresh.value
        await appEventually { model.isQueueLimitPaused }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.created.first?.intent, .automaticWallpaper)
        XCTAssertEqual(fake.pending.map(\.hour), [16])
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        model.cancelQueue()
    }

    @MainActor
    func testActualRestoreFiltersChangedRecipeAndStaleDesktopAndReportsLaterExpiredManual() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fake.clock)!
        var changed = fake.settings
        changed.promptTemplate = "Another prompt"
        fake.pending = [fake.job(hour: 14, date: yesterday, intent: .manualWallpaper),
                        fake.job(hour: 16, intent: .preview, settings: changed),
                        fake.job(hour: 14, intent: .manualWallpaper)]
        let model = fake.model()
        XCTAssertEqual(model.pendingHourCount, 1)
        fake.clock = fake.clock.addingTimeInterval(3600)
        await model.refreshIfNeeded()
        XCTAssertEqual(model.pendingHourCount, 0)
        XCTAssertEqual(model.status, "Your \(model.hourLabel(14)) request was skipped because the hour changed.")
        XCTAssertEqual(model.wallpaperSummary(at: fake.clock), model.status)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.pending.isEmpty)
    }

    @MainActor
    func testActualUnpaidCancellationAndStopAfterPaidRequestUseDifferentPolicies() async throws {
        let unpaid = try AppHourlyFake()
        defer { unpaid.removeFiles() }
        unpaid.readGate = AppHourlyGate()
        let first = unpaid.model()
        await first.refreshIfNeeded()
        await appEventually { unpaid.readCalls == 1 }
        XCTAssertEqual(first.queueCancellationTitle, "Cancel Creation")
        XCTAssertEqual(first.queueCancellationHour, 14)
        first.cancelQueue()
        unpaid.readGate?.release()
        await appEventually { !first.isGenerating }
        XCTAssertTrue(unpaid.created.isEmpty)
        XCTAssertEqual(unpaid.ledger.count(on: unpaid.clock), 0)
        XCTAssertTrue(first.settings.automaticUpdates)

        let paid = try AppHourlyFake()
        defer { paid.removeFiles() }
        paid.creationGate = AppHourlyGate()
        let second = paid.model()
        await second.refreshIfNeeded()
        await appEventually { paid.created.count == 1 }
        XCTAssertNil(second.queueCancellationTitle)
        second.cancelQueue()
        paid.creationGate?.release()
        await appEventually { !second.isGenerating }
        XCTAssertEqual(paid.created.count, 1)
        XCTAssertEqual(paid.ledger.count(on: paid.clock), 1)
        XCTAssertTrue(paid.ledger.reservations.isEmpty)
        XCTAssertEqual(HourWallpaperCache(directory: paid.directory).entries.count, 1)
        XCTAssertEqual(paid.applied.count, 1)
        XCTAssertTrue(second.settings.automaticUpdates)
    }

    @MainActor
    func testActualCancellationStopsForecastAndPreparedClientBeforeSending() async throws {
        let forecasting = try AppHourlyFake()
        defer { forecasting.removeFiles() }
        forecasting.weatherGate = AppHourlyGate()
        let first = forecasting.model()
        let refresh = Task { await first.refreshIfNeeded() }
        await appEventually { forecasting.weatherCalls == 1 }
        XCTAssertEqual(first.queueCancellationTitle, "Cancel Creation")
        XCTAssertEqual(first.queueCancellationHour, 14)
        first.cancelQueue()
        forecasting.weatherGate?.release()
        await refresh.value
        XCTAssertTrue(forecasting.created.isEmpty)
        XCTAssertEqual(first.pendingHourCount, 0)
        XCTAssertNil(first.queueCancellationTitle)
        XCTAssertTrue(first.settings.automaticUpdates)

        let prepared = try AppHourlyFake()
        defer { prepared.removeFiles() }
        prepared.beforeSendGate = AppHourlyGate()
        let second = prepared.model()
        await second.refreshIfNeeded()
        await appEventually { prepared.createPreparations == 1 }
        XCTAssertEqual(second.queueCancellationTitle, "Cancel Creation")
        second.cancelQueue()
        prepared.beforeSendGate?.release()
        await appEventually { !second.isGenerating }
        XCTAssertTrue(prepared.created.isEmpty)
        XCTAssertEqual(prepared.ledger.count(on: prepared.clock), 0)
        XCTAssertTrue(prepared.ledger.reservations.isEmpty)
        XCTAssertTrue(HourWallpaperCache(directory: prepared.directory).entries.isEmpty)
    }

    @MainActor
    func testCanceledRolloverForecastMappedToUnavailableIsNeverRestoredOrPaid() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.runsBackgroundTasks = true
        fake.wrapsWeatherCancellation = true
        fake.weatherGate = AppHourlyGate()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fake.clock)!
        fake.pending = [fake.job(hour: 16, date: yesterday, intent: .preview)]
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await appEventually { fake.weatherCalls == 1 }
        model.cancelQueue()
        fake.weatherGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(model.pendingHourCount, 0)
        XCTAssertTrue(fake.pending.isEmpty)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertNotEqual(model.activity, .failed)
        fake.clock = fake.clock.addingTimeInterval(61)
        await model.refreshIfNeeded()
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testFreshSameIDCreationQueuedWhileCanceledWorkerSettlesStartsWithoutAnotherTick() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.readGate = AppHourlyGate()
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.readCalls == 1 }
        model.cancelQueue()
        XCTAssertTrue(model.settings.automaticUpdates)
        XCTAssertTrue(model.canGenerate)
        model.generateNow()
        await appEventually { model.pendingHourCount == 1 }
        fake.readGate?.release()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.readCalls, 2)
        XCTAssertTrue(fake.created[0].intent.contains(.manualWallpaper))
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertTrue(fake.pending.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

    @MainActor
    func testFreshSameBasePreparationSurvivesLateCanceledForecastCleanup() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.wrapsWeatherCancellation = true
        let oldForecast = AppHourlyGate()
        let newForecast = AppHourlyGate()
        fake.weatherGates = [1: oldForecast, 2: newForecast]
        let model = fake.model()
        let old = Task { await model.refreshIfNeeded() }
        await appEventually { fake.weatherCalls == 1 }
        model.cancelQueue()
        model.generateNow()
        await appEventually { fake.weatherCalls == 2 && model.isPreparingManualCreation }
        oldForecast.release()
        await old.value
        XCTAssertTrue(model.isPreparingManualCreation)
        XCTAssertEqual(model.queueCancellationTitle, "Cancel Creation")
        XCTAssertNotEqual(model.activity, .failed)
        newForecast.release()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(model.settings.automaticUpdates)
    }

    @MainActor
    func testExplicitCreateAfterApplicationFailureIsFreshWhileTryAgainUsesSavedOutput() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.failApply = true
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.applicationRetry != nil && !model.isGenerating }
        let saved = try XCTUnwrap(fake.applicationRetry)
        fake.failApply = false
        model.retryUpdate()
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(model.displayedImageURL, saved.url)
        fake.failApply = true
        model.generateNow()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertNotNil(fake.applicationRetry)
        fake.failApply = false
        model.generateNow()
        await appEventually { fake.created.count == 3 && !model.isGenerating }
        XCTAssertNotEqual(model.displayedImageURL, saved.url)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 3)
    }

    @MainActor
    func testInjectedBackgroundResumeRecoversWeatherHoldWithoutManualRefresh() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.runsBackgroundTasks = true
        fake.weatherError = WeatherContextError.forecastUnavailable
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fake.clock)!
        fake.pending = [fake.job(hour: 16, date: yesterday, intent: .preview)]
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await appEventually { fake.weatherCalls == 1 && fake.sleeper.waitingCount > 0 }
        XCTAssertEqual(model.pendingHourCount, 1)
        XCTAssertFalse(model.isQueueLimitPaused)
        fake.clock = fake.clock.addingTimeInterval(61)
        fake.sleeper.wakeAll()
        await appEventually { fake.weatherCalls == 2 && !model.isGenerating && fake.sleeper.waitingCount > 0 }
        XCTAssertEqual(model.pendingHourCount, 1)
        XCTAssertTrue(fake.created.isEmpty)
        fake.weatherError = nil
        fake.clock = fake.clock.addingTimeInterval(61)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.weatherCalls, 3)
        XCTAssertEqual(model.pendingHourCount, 0)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
    }

    @MainActor
    func testInjectedSchedulerAndBudgetResumePrioritizeTodayAutomaticAtRollover() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.dailyGenerationLimit = 1
        fake.runsBackgroundTasks = true
        _ = fake.ledger.reserve(at: fake.clock)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fake.clock)!
        fake.pending = [fake.job(hour: 16, date: yesterday, intent: .preview)]
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await appEventually { model.isQueueLimitPaused && fake.sleeper.waitingCount > 0 }
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertFalse(fake.sleeper.requestedSeconds.isEmpty)
        XCTAssertTrue(fake.sleeper.requestedSeconds.allSatisfy { $0 == 30 })
        fake.clock = Calendar.current.date(byAdding: .day, value: 1, to: fake.clock)!
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && model.isQueueLimitPaused }
        XCTAssertEqual(fake.created.first?.intent, .automaticWallpaper)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.pending.map(\.hour), [16])
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        model.cancelQueue()
    }

    @MainActor
    func testCancelUnpaidAutomaticKeepsSchedulerOnAndWaitsForNextSlot() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.runsBackgroundTasks = true
        fake.readGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await appEventually { fake.readCalls == 1 }
        model.cancelQueue()
        fake.readGate?.release()
        await appEventually { !model.isGenerating && fake.sleeper.waitingCount > 0 }
        XCTAssertTrue(model.settings.automaticUpdates)
        let next = try XCTUnwrap(model.nextCheck(after: fake.clock))
        XCTAssertGreaterThan(next, fake.clock)
        fake.clock = fake.clock.addingTimeInterval(31)
        fake.sleeper.wakeAll()
        await appEventually { fake.sleeper.waitingCount > 0 }
        XCTAssertTrue(fake.created.isEmpty)
        fake.clock = next
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.applied.count, 1)
    }

    @MainActor
    func testRealPromptSourceFlowStopsAfterAuthorizationOnCancelWithoutWebsiteFileOrPayment() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.useRealSourceBody = true
        fake.settings.automaticUpdates = false
        fake.settings.promptTemplate = "Use /fixture/context.md"
        let authorization = AppHourlyGate()
        var authorizations = 0
        var websites = 0
        var files = 0
        fake.sourceServices = AppModelPromptSourceServices(isActive: { true }, authorize: { _, _, allowInteraction in
            XCTAssertTrue(allowInteraction)
            authorizations += 1
            await authorization.wait()
            return PromptFileAuthorizationResult(bookmarks: ["/fixture/context.md": Data("fake grant".utf8)], warnings: [])
        }, readWebsite: { _ in
            websites += 1
            return PromptContextResult(promptText: "", warnings: [])
        }, readFile: { _, _ in
            files += 1
            return PromptFileReadResult(text: "Fake file", refreshedBookmark: nil)
        })
        let model = fake.model()
        model.generateNow()
        await appEventually { authorizations == 1 }
        model.cancelQueue()
        authorization.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(websites, 0)
        XCTAssertEqual(files, 0)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testRealPromptSourceFlowDiscardsChangedRecipeAfterWebsiteAndCancellationInFileRead() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.useRealSourceBody = true
        fake.settings.promptTemplate = "Use https://example.com/daily and /fixture/context.md"
        let website = AppHourlyGate()
        let file = AppHourlyGate()
        var websiteCalls = 0
        var fileCalls = 0
        fake.sourceServices = AppModelPromptSourceServices(isActive: { true }, authorize: { _, grants, _ in
            var granted = grants
            granted["/fixture/context.md"] = Data("fake grant".utf8)
            return PromptFileAuthorizationResult(bookmarks: granted, warnings: [])
        }, readWebsite: { _ in
            websiteCalls += 1
            await website.wait()
            return PromptContextResult(promptText: "Fake website", warnings: [])
        }, readFile: { _, _ in
            fileCalls += 1
            await file.wait()
            throw CancellationError()
        })
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { websiteCalls == 1 }
        model.savePrompt("A different prompt")
        website.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(fileCalls, 0)
        XCTAssertTrue(fake.created.isEmpty)
        model.savePrompt("Use /fixture/context.md")
        model.setPreviewHour(16)
        model.enqueuePreviewHour()
        await appEventually { fileCalls == 1 }
        file.release()
        await appEventually { !model.isGenerating }
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertNotEqual(model.activity, .failed)
    }

    @MainActor
    func testApplicationFailureDoesNotBlockPreviewResumingAfterBudgetIncrease() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.dailyGenerationLimit = 1
        fake.failApply = true
        fake.runsBackgroundTasks = true
        fake.pending = [fake.job(hour: 16, intent: .preview)]
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await appEventually { fake.applicationRetry != nil && !model.isGenerating }
        await appEventually { model.isQueueLimitPaused }
        XCTAssertEqual(fake.created.count, 1)
        model.settings.dailyGenerationLimit = 2
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.intent, .preview)
        XCTAssertNotNil(fake.applicationRetry)
        XCTAssertEqual(model.pendingHourCount, 0)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertTrue(fake.sleeper.requestedSeconds.allSatisfy { $0 == 30 })
    }

    @MainActor
    func testApplicationFailureDoesNotBlockTimerResumingHeldPreviewWeather() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.failApply = true
        fake.runsBackgroundTasks = true
        fake.weatherErrors[2] = WeatherContextError.forecastUnavailable
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: fake.clock)!
        fake.pending = [fake.job(hour: 16, date: yesterday, intent: .preview)]
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await appEventually { fake.applicationRetry != nil && fake.weatherCalls == 2 && !model.isGenerating && fake.sleeper.waitingCount > 0 }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(model.pendingHourCount, 1)
        fake.clock = fake.clock.addingTimeInterval(61)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.hour, 16)
        XCTAssertEqual(fake.created.last?.intent, .preview)
        XCTAssertNotNil(fake.applicationRetry)
        XCTAssertEqual(model.pendingHourCount, 0)
    }

    @MainActor
    func testClearingCacheRemovesApplicationRetryAndMissingSavedPictureCannotBeApplied() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.failApply = true
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.applicationRetry != nil && !model.isGenerating }
        let missing = try XCTUnwrap(fake.applicationRetry)
        try FileManager.default.removeItem(at: missing.url)
        model.retryUpdate()
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertNil(fake.applicationRetry)
        XCTAssertEqual(model.status, "Saved wallpaper is unavailable")
        model.generateNow()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertNotNil(fake.applicationRetry)
        model.clearCache()
        XCTAssertNil(fake.applicationRetry)
        XCTAssertTrue(HourWallpaperCache(directory: fake.directory).entries.isEmpty)
        XCTAssertEqual(model.displayedImageURL, fake.source)
        XCTAssertFalse(model.settings.automaticUpdates)
        XCTAssertEqual(fake.created.count, 2)
    }

    @MainActor
    func testVisiblePreviewFailureRetriesPreviewInsteadOfAnOlderSavedApplicationFailure() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.failApply = true
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.applicationRetry != nil && !model.isGenerating }
        fake.creationError = AppHourlyError.failed
        model.setPreviewHour(16)
        model.enqueuePreviewHour()
        await appEventually { fake.created.count == 2 && !model.isGenerating && model.activity == .failed }
        XCTAssertNotNil(fake.applicationRetry)
        let applies = fake.applied.count
        fake.creationError = nil
        model.retryUpdate()
        await appEventually { fake.created.count == 3 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.hour, 16)
        XCTAssertEqual(fake.created.last?.intent, .preview)
        XCTAssertEqual(fake.applied.count, applies)
        XCTAssertNotNil(fake.applicationRetry)
    }

    @MainActor
    func testRetryFromNowAfterUnrelatedPreviewFailurePreparesCurrentWeatherInsteadOfOlderApplicationRetry() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.failApply = true
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.applicationRetry != nil && !model.isGenerating }
        let saved = try XCTUnwrap(fake.applicationRetry)
        fake.creationError = AppHourlyError.failed
        model.setPreviewHour(16)
        model.enqueuePreviewHour()
        await appEventually { fake.created.count == 2 && !model.isGenerating && model.activity == .failed }
        XCTAssertNotNil(fake.applicationRetry)
        model.backToNow()
        fake.weatherLabel = "rain"
        fake.creationError = nil
        fake.failApply = false
        fake.weatherGate = AppHourlyGate()
        let applies = fake.applied.count
        model.retryUpdate()
        await appEventually { fake.weatherCalls == 3 }
        XCTAssertNil(fake.applicationRetry)
        XCTAssertEqual(fake.applied.count, applies)
        fake.weatherGate?.release()
        await appEventually { fake.created.count == 3 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.hour, 14)
        XCTAssertEqual(fake.created.last?.weather.label, "rain")
        XCTAssertTrue(fake.created.last?.intent.contains(.manualWallpaper) == true)
        XCTAssertEqual(fake.applied.count, applies + 1)
        XCTAssertNotEqual(fake.applied.last, saved.url)
        XCTAssertEqual(model.displayedImageURL, fake.applied.last)
        XCTAssertNil(fake.applicationRetry)
    }

    @MainActor
    func testSentCurrentHasOnlyQueuedWorkCancellationAndItCannotCancelPaidWallpaper() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        await model.refreshIfNeeded()
        await appEventually { fake.created.count == 1 }
        XCTAssertNil(model.queueCancellationTitle)
        XCTAssertNil(model.queueCancellationHour)
        model.setPreviewHour(16)
        model.enqueuePreviewHour()
        await appEventually { model.pendingHourCount == 1 }
        XCTAssertEqual(model.queueCancellationTitle, "Cancel Queued Wallpapers")
        XCTAssertNil(model.queueCancellationHour)
        model.cancelQueue()
        XCTAssertEqual(model.pendingHourCount, 0)
        XCTAssertNil(model.queueCancellationTitle)
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertTrue(model.settings.automaticUpdates)
    }

    @MainActor
    func testScrubbingCreatesOnlyTheSettledHourAndRevisitingItUsesTheRealCache() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.reuseMatchingImages = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.setPreviewHour(16)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.sleeper.sleepCalls, 0)
        model.beginScrubbingPreview()
        model.setPreviewHour(17)
        model.setPreviewHour(18)
        model.endScrubbingPreview(hour: 18)
        await appEventually { fake.sleeper.waitingCount == 1 }
        model.beginScrubbingPreview()
        model.setPreviewHour(19)
        model.endScrubbingPreview(hour: 19)
        await appEventually { fake.sleeper.sleepCalls == 2 && fake.sleeper.waitingCount == 1 }
        XCTAssertTrue(fake.created.isEmpty)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.hour, 19)
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.created.first?.intent, .preview)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertNotNil(model.previewImageURL)
        XCTAssertTrue(model.isShowingQuickPreview)
        XCTAssertEqual(fake.sleeper.requestedSeconds, [0.8, 0.8])
        model.backToNow()
        model.endScrubbingPreview(hour: 19)
        XCTAssertEqual(fake.sleeper.sleepCalls, 2)
        XCTAssertEqual(fake.created.count, 1)
    }

    @MainActor
    func testSettledPromptDraftCreatesOneQuickPreviewForTheLatestText() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let committed = model.settings
        model.setPreviewHour(16)
        model.schedulePromptUpdate(draft: "First draft")
        await appEventually { fake.sleeper.waitingCount == 1 }
        model.schedulePromptUpdate(draft: "Final draft")
        await appEventually { fake.sleeper.sleepCalls == 2 && fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { model.isPreviewGenerationScheduled && fake.sleeper.waitingCount == 1 }
        XCTAssertEqual(model.settings, committed)
        XCTAssertTrue(fake.created.isEmpty)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.settings.promptTemplate, "Final draft")
        XCTAssertEqual(fake.created.first?.hour, 16)
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.sleeper.requestedSeconds, [3.0, 3.0, 0.8])
        XCTAssertTrue(fake.applied.isEmpty)
        model.schedulePromptUpdate(draft: "Discard this draft")
        await appEventually { fake.sleeper.waitingCount == 1 }
        model.cancelPromptUpdate()
        await appEventually { fake.sleeper.waitingCount == 0 }
        XCTAssertEqual(model.settings, committed)
        XCTAssertNil(model.previewImageURL)
        XCTAssertEqual(fake.created.count, 1)
    }

    @MainActor
    func testEscapeCancelsUnpaidDraftPreviewAndLeavesCommittedSettingsUnchanged() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let committed = model.settings
        model.setPreviewHour(16)
        model.schedulePromptUpdate(draft: "An uncommitted scene")
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { model.isPreviewGenerationScheduled && fake.sleeper.waitingCount == 1 }
        XCTAssertEqual(model.settings, committed)
        fake.sleeper.wakeAll()
        await appEventually { fake.weatherCalls == 1 }
        model.cancelPromptUpdate()
        fake.weatherGate?.release()
        await appEventually { model.queueCancellationTitle == nil && !model.isGenerating }
        XCTAssertEqual(model.settings, committed)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertNil(model.previewImageURL)
        XCTAssertEqual(model.pendingHourCount, 0)
    }

    @MainActor
    func testIdleDraftAndEscapePreserveQueuedFullPreviewAndPaidDesktopRequest() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let committed = model.settings
        model.generateNow()
        await appEventually { fake.created.count == 1 }
        model.setPreviewHour(16)
        model.requestCreation()
        await appEventually { fake.pending.count == 1 }
        let fullPreview = try XCTUnwrap(fake.pending.first)
        XCTAssertEqual(fullPreview.renderProfile, .wallpaper)
        model.schedulePromptUpdate(draft: "Only a draft preview")
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { model.isPreviewGenerationScheduled && fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.pending.count == 2 }
        XCTAssertEqual(model.settings, committed)
        XCTAssertEqual(fake.pending.first, fullPreview)
        XCTAssertEqual(fake.pending.last?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.pending.last?.settings.promptTemplate, "Only a draft preview")
        model.cancelPromptUpdate()
        XCTAssertEqual(fake.pending, [fullPreview])
        XCTAssertEqual(model.settings, committed)
        fake.creationGate?.release()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertTrue(fake.created.allSatisfy { $0.renderProfile == .wallpaper && $0.settings == committed })
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 0)
    }

    @MainActor
    func testDraftPreviewDoesNotClearSavedApplicationRetryAndCommitReusesItsPreview() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.failApply = true
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let committed = model.settings
        model.generateNow()
        await appEventually { fake.applicationRetry != nil && !model.isGenerating }
        let saved = fake.applicationRetry
        model.setPreviewHour(16)
        model.schedulePromptUpdate(draft: "A preview before committing")
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { model.isPreviewGenerationScheduled && fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        let draftPicture = try XCTUnwrap(model.previewImageURL)
        XCTAssertEqual(model.settings, committed)
        XCTAssertEqual(fake.applicationRetry, saved)
        model.savePrompt("A preview before committing")
        XCTAssertEqual(model.settings.promptTemplate, "A preview before committing")
        XCTAssertEqual(model.previewImageURL, draftPicture)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertEqual(fake.created.count, 2)
    }

    @MainActor
    func testSliderMovementAndBackToNowPreserveAnExplicitFullPreviewPreparation() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.weatherGate = AppHourlyGate()
        let model = fake.model()
        model.setPreviewHour(16)
        model.requestCreation()
        await appEventually { fake.weatherCalls == 1 }
        model.beginScrubbingPreview()
        model.setPreviewHour(17)
        model.backToNow()
        XCTAssertEqual(model.queueCancellationHour, 16)
        fake.weatherGate?.release()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.hour, 16)
        XCTAssertEqual(fake.created.first?.renderProfile, .wallpaper)
        XCTAssertEqual(fake.created.first?.intent, .preview)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testChangedPromptInvalidatesAnUnpaidPreviewForecastBeforeCreatingTheNewRecipe() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let oldForecast = AppHourlyGate()
        fake.weatherGates[1] = oldForecast
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.weatherCalls == 1 }
        model.savePrompt("The updated scene")
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        oldForecast.release()
        await appEventually { model.queueCancellationTitle == nil }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.created.first?.settings.promptTemplate, "The updated scene")
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testAutomaticPreviewReservesTwoDesktopRequestsWithinSharedSafetyLimit() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.dailyGenerationLimit = 12
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        for hour in 0..<10 {
            model.endScrubbingPreview(hour: hour)
            await appEventually { fake.sleeper.waitingCount == 1 }
            fake.sleeper.wakeAll()
            await appEventually { fake.created.count == hour + 1 && !model.isGenerating }
        }
        model.endScrubbingPreview(hour: 10)
        XCTAssertEqual(fake.sleeper.waitingCount, 0)
        XCTAssertEqual(fake.created.count, 10)
        XCTAssertEqual(model.remainingGenerations, 2)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 10)
        XCTAssertNotNil(model.previewGenerationNotice)
        model.backToNow()
        model.requestCreation()
        await appEventually { fake.created.count == 11 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.renderProfile, .wallpaper)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(model.usageCountLabel, "10 previews · 1 wallpaper today")
        XCTAssertEqual(model.remainingGenerations, 1)
        XCTAssertEqual(model.pendingHourCount, 0)
    }

    @MainActor
    func testPromptCommitAtNowCreatesOnlyQuickPreviewAndExplicitCreationCreatesFullWallpaperWithoutConfirmation() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.savePrompt("A new current-hour scene")
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.hour, 14)
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.created.first?.intent, .preview)
        XCTAssertTrue(fake.applied.isEmpty)
        XCTAssertEqual(model.displayedImageURL, fake.source)
        XCTAssertNotEqual(model.canvasImageURL, fake.source)
        XCTAssertTrue(model.isShowingQuickPreview)
        model.requestCreation()
        XCTAssertNil(model.presentation)
        await appEventually { fake.created.count == 2 && !model.isGenerating }
        XCTAssertEqual(fake.created.last?.renderProfile, .wallpaper)
        XCTAssertTrue(fake.created.last?.intent.contains(.manualWallpaper) == true)
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertEqual(model.canvasImageURL, model.displayedImageURL)
        XCTAssertFalse(model.isShowingQuickPreview)
    }

    @MainActor
    func testCropOpeningCancelsDraftDebounceAndUnpaidSendWithoutRestartingOnCancel() async throws {
        for heldBeforeSend in [false, true] {
            let fake = try AppHourlyFake()
            defer { fake.removeFiles() }
            fake.settings.automaticUpdates = false
            if heldBeforeSend { fake.beforeSendGate = AppHourlyGate() }
            let model = fake.model()
            defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
            model.endScrubbingPreview(hour: 16)
            await appEventually { fake.sleeper.waitingCount == 1 }
            if heldBeforeSend {
                fake.sleeper.wakeAll()
                await appEventually { fake.createPreparations == 1 }
            }
            model.presentation = .crop
            XCTAssertFalse(model.isPreviewGenerationScheduled)
            model.endScrubbingPreview(hour: 17)
            model.schedulePromptUpdate(draft: "Do not create while cropping")
            XCTAssertFalse(model.isPreviewGenerationScheduled)
            model.presentation = nil
            fake.beforeSendGate?.release()
            fake.sleeper.wakeAll()
            await appEventually { !model.isGenerating && fake.sleeper.waitingCount == 0 }
            XCTAssertTrue(fake.created.isEmpty)
            XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
            XCTAssertEqual(fake.weatherCalls, heldBeforeSend ? 1 : 0)
            XCTAssertTrue(fake.pending.isEmpty)
        }
    }

    @MainActor
    func testCropOpeningDropsQueuedDraftButDoesNotPauseUnpaidDesktopCreation() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.readGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        await model.refreshIfNeeded()
        await appEventually { fake.readCalls == 1 }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { model.pendingHourCount == 1 }
        model.presentation = .crop
        XCTAssertEqual(model.pendingHourCount, 0)
        XCTAssertTrue(model.settings.automaticUpdates)
        fake.readGate?.release()
        await appEventually { fake.applied.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.created.first?.renderProfile, .wallpaper)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 0)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        model.presentation = nil
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertEqual(fake.created.count, 1)
    }

    @MainActor
    func testInactiveWindowDoesNotCreatePreviewsBeforeOrAfterDebounceOrBeforeSending() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.previewWindowActive = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        model.schedulePromptUpdate(draft: "Background draft")
        XCTAssertEqual(fake.sleeper.sleepCalls, 0)
        XCTAssertTrue(fake.created.isEmpty)
        fake.previewWindowActive = true
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.previewWindowActive = false
        fake.sleeper.wakeAll()
        await appEventually { !model.isPreviewGenerationScheduled }
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.weatherCalls, 0)
        fake.previewWindowActive = true
        fake.beforeSendGate = AppHourlyGate()
        model.endScrubbingPreview(hour: 17)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.createPreparations == 1 }
        fake.previewWindowActive = false
        fake.beforeSendGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testCreateDraftAvailabilityExplainsReservedWallpaperRequestsAndCropEditing() throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.dailyGenerationLimit = 3
        let wallpaper = fake.ledger.reserve(at: fake.clock)
        fake.ledger.complete(wallpaper)
        let limited = fake.model()
        defer { limited.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        XCTAssertEqual(limited.remainingGenerations, 2)
        XCTAssertTrue(limited.canGenerate)
        XCTAssertFalse(limited.canCreateDraft)
        XCTAssertEqual(limited.draftCreationUnavailableReason, "The last two daily requests are reserved for wallpapers.")

        let available = try AppHourlyFake()
        defer { available.removeFiles() }
        available.settings.automaticUpdates = false
        let model = available.model()
        defer { model.stopBackgroundTasks(); available.sleeper.cancelAll() }
        XCTAssertTrue(model.canCreateDraft)
        XCTAssertNil(model.draftCreationUnavailableReason)
        model.presentation = .crop
        XCTAssertTrue(model.canGenerate)
        XCTAssertFalse(model.canCreateDraft)
        XCTAssertEqual(model.draftCreationUnavailableReason, "Finish cropping your picture first.")
        model.presentation = nil
        XCTAssertTrue(model.canCreateDraft)
        XCTAssertNil(model.draftCreationUnavailableReason)
    }

    @MainActor
    func testMoreThanTwelveDraftsRemainAvailableAfterRestoreButSmallSharedLimitReservesDesktopRequests() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        for _ in 0..<12 {
            let attempt = fake.ledger.reserve(at: fake.clock, profile: .quickPreview)
            fake.ledger.complete(attempt)
        }
        let restored = fake.model()
        defer { restored.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        XCTAssertEqual(restored.usageCountLabel, "12 previews · 0 wallpapers today")
        XCTAssertTrue(restored.canGenerate)
        XCTAssertTrue(restored.canCreateDraft)
        XCTAssertNil(restored.draftCreationUnavailableReason)
        restored.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        XCTAssertNil(restored.previewGenerationNotice)
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !restored.isGenerating }
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 13)
        XCTAssertEqual(restored.usageCountLabel, "13 previews · 0 wallpapers today")
        XCTAssertEqual(restored.remainingGenerations, 11)
        XCTAssertTrue(restored.canCreateDraft)
        XCTAssertNil(restored.draftCreationUnavailableReason)
        let small = try AppHourlyFake()
        defer { small.removeFiles() }
        small.settings.automaticUpdates = false
        small.settings.dailyGenerationLimit = 2
        let smallLimit = small.model()
        defer { smallLimit.stopBackgroundTasks(); small.sleeper.cancelAll() }
        smallLimit.endScrubbingPreview(hour: 17)
        XCTAssertEqual(small.sleeper.sleepCalls, 0)
        XCTAssertNotNil(smallLimit.previewGenerationNotice)
        XCTAssertFalse(smallLimit.canCreateDraft)
        XCTAssertTrue(smallLimit.canGenerate)
        XCTAssertEqual(smallLimit.draftCreationUnavailableReason, "The last two daily requests are reserved for wallpapers.")
        XCTAssertTrue(small.created.isEmpty)
    }

    @MainActor
    func testMatchingFullWallpaperWinsOverQuickPreviewWithoutAnotherPaidRequest() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.setPreviewHour(16)
        model.requestCreation()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.renderProfile, .wallpaper)
        let full = try XCTUnwrap(model.previewImageURL)
        model.backToNow()
        model.endScrubbingPreview(hour: 16)
        XCTAssertEqual(fake.sleeper.sleepCalls, 0)
        XCTAssertEqual(model.previewImageURL, full)
        XCTAssertFalse(model.isShowingQuickPreview)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 0)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testSettledSliderAtNowCreatesQuickPreviewAndExplicitCreationCancelsPlannedPreview() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 14)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertNil(model.selectedPreviewHour)
        XCTAssertTrue(model.isShowingQuickPreview)
        XCTAssertEqual(fake.created.first?.intent, .preview)
        XCTAssertTrue(fake.applied.isEmpty)
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        model.requestCreation()
        await appEventually { fake.created.count == 2 && !model.isGenerating && fake.sleeper.waitingCount == 0 }
        XCTAssertEqual(fake.created.last?.hour, 16)
        XCTAssertEqual(fake.created.last?.renderProfile, .wallpaper)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 1)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 2)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
    }

    @MainActor
    func testDeselectedPaidPreviewFinishesInCacheAndReopeningDoesNotReplayIt() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.creationGate = AppHourlyGate()
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 }
        model.backToNow()
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertTrue(fake.pending.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
        let reopened = fake.model()
        reopened.setPreviewHour(16)
        XCTAssertNotNil(reopened.previewImageURL)
        XCTAssertFalse(reopened.isPreviewGenerationScheduled)
        XCTAssertEqual(fake.created.count, 1)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 1)
    }

    @MainActor
    func testDateScopedPreviewTimerClearsSpinnerAfterMidnightWithoutSendingRequest() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.settings.promptTemplate = "Scene for {{date}}"
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        XCTAssertTrue(model.isPreviewGenerationScheduled)
        fake.clock = Calendar.current.date(byAdding: .day, value: 1, to: fake.clock)!
        fake.sleeper.wakeAll()
        await appEventually { !model.isPreviewGenerationScheduled }
        XCTAssertFalse(model.isCreatingVisiblePreview)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.weatherCalls, 0)
    }













    @MainActor
    func testGalleryExportUsesFriendlyNameAndDeletingUnusedEntryDoesNotTouchLedger() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.endScrubbingPreview(hour: 16)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        let item = try XCTUnwrap(model.savedWallpaperGroups.first?.wallpapers.first)
        let export = try XCTUnwrap(model.savedWallpaperExportURL(item))
        XCTAssertTrue(export.lastPathComponent.hasPrefix("Daydreaming "))
        XCTAssertTrue(export.lastPathComponent.contains("16h"))
        XCTAssertFalse(export.lastPathComponent.contains(item.entry.filename))
        XCTAssertEqual(try Data(contentsOf: export), try Data(contentsOf: item.url))
        XCTAssertTrue(model.deleteSavedWallpaper(item))
        XCTAssertTrue(model.savedWallpaperGroups.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertEqual(fake.created.count, 1)
    }

    @MainActor
    func testCompleteCropDismissesEditorThenSchedulesExactlyOneChargedDraft() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.setPreviewHour(16)
        model.presentation = .crop
        let crop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2)
        try await model.completeCrop(crop)
        XCTAssertNil(model.presentation)
        XCTAssertEqual(model.settings.sourceCrop, crop)
        XCTAssertTrue(model.isPreviewGenerationScheduled)
        await appEventually { fake.sleeper.waitingCount == 1 }
        XCTAssertEqual(fake.sleeper.requestedSeconds, [0.8])
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.cropSources, [fake.source])
        XCTAssertEqual(fake.created.first?.hour, 16)
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertEqual(fake.ledger.previewCount(on: fake.clock), 1)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testUncroppedDefaultFillDoneKeepsRecipeAndMakesNoPreview() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.originalImageSize = CGSize(width: 3000, height: 2000)
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let recipe = HourWallpaperCache.recipeID(for: model.settings)
        model.presentation = .crop
        let defaultFill = PictureCrop.editingBaseline(savedCrop: nil, imageSize: fake.originalImageSize,
                                                       displayAspectRatio: 16.0 / 10)
        try await model.completeCrop(defaultFill, displayAspectRatio: 16.0 / 10)
        XCTAssertNil(model.presentation)
        XCTAssertNil(model.settings.sourceCrop)
        XCTAssertEqual(HourWallpaperCache.recipeID(for: model.settings), recipe)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertTrue(fake.cropSources.isEmpty)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testSettledDisplayRatioWithDoneDoesNotChangeRecipeOrCharge() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.originalImageSize = CGSize(width: 3000, height: 2000)
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let recipe = HourWallpaperCache.recipeID(for: model.settings)
        model.presentation = .crop
        // Resizing preserves the screen ratio. Moving displays replaces the opening fill baseline.
        for aspect: CGFloat in [16.0 / 9, 16.0 / 10, 1.6001] {
            let settled = PictureCrop.editingBaseline(savedCrop: nil, imageSize: fake.originalImageSize,
                                                       displayAspectRatio: aspect)
            try await model.completeCrop(settled, displayAspectRatio: aspect)
            XCTAssertNil(model.settings.sourceCrop)
            XCTAssertEqual(HourWallpaperCache.recipeID(for: model.settings), recipe)
        }
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertTrue(fake.cropSources.isEmpty)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testActualCropPanCreatesExactlyOneCountedPreview() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.originalImageSize = CGSize(width: 3000, height: 2000)
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let recipe = HourWallpaperCache.recipeID(for: model.settings)
        model.presentation = .crop
        let defaultFill = PictureCrop.editingBaseline(savedCrop: nil, imageSize: fake.originalImageSize,
                                                       displayAspectRatio: 16.0 / 10)
        let panned = defaultFill.moved(by: CGSize(width: 0, height: 0.05))
        try await model.completeCrop(panned, displayAspectRatio: 16.0 / 10)
        XCTAssertNotNil(model.settings.sourceCrop)
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: model.settings), recipe)
        await appEventually { fake.sleeper.waitingCount == 1 }
        fake.sleeper.wakeAll()
        await appEventually { fake.created.count == 1 && !model.isGenerating }
        XCTAssertEqual(fake.created.first?.renderProfile, .quickPreview)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 1)
        XCTAssertTrue(fake.applied.isEmpty)
    }

    @MainActor
    func testUnchangedCropDismissesWithoutImportOrCharge() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        let crop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2)
        fake.settings.sourceCrop = crop
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        model.presentation = .crop
        try await model.completeCrop(crop)
        XCTAssertNil(model.presentation)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertTrue(fake.cropSources.isEmpty)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testCropMissingOriginalDismissesAndOffersPictureRecoveryWithoutCharging() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        try FileManager.default.removeItem(at: fake.source)
        model.presentation = .crop
        XCTAssertNil(model.presentation)
        XCTAssertEqual(model.status, "Choose your picture again")
        XCTAssertEqual(model.recovery, .image)
        try await model.completeCrop(.original)
        XCTAssertNil(model.presentation)
        XCTAssertEqual(model.recovery, .image)
        XCTAssertFalse(model.isPreviewGenerationScheduled)
        XCTAssertTrue(fake.cropSources.isEmpty)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
    }

    @MainActor
    func testCropCommitRetainsUncroppedPictureAndChangesRecipeOnlyOnSave() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let originalBytes = try Data(contentsOf: fake.source)
        let oldRecipe = HourWallpaperCache.recipeID(for: model.settings)
        let crop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2)
        let previousDesktop = model.displayedImageURL
        try await model.commitCrop(crop)
        XCTAssertEqual(model.displayedImageURL, previousDesktop)
        XCTAssertEqual(model.canvasImageURL, model.sourceImageURL)
        XCTAssertEqual(model.uncroppedImageURL, fake.source)
        XCTAssertEqual(model.settings.sourceCrop, crop)
        XCTAssertNotEqual(model.sourceImageURL, fake.source)
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: model.settings), oldRecipe)
        XCTAssertEqual(try Data(contentsOf: fake.source), originalBytes)
        XCTAssertEqual(fake.cropSources, [fake.source])
        try await model.commitCrop(.original)
        XCTAssertEqual(model.uncroppedImageURL, fake.source)
        XCTAssertEqual(fake.cropSources, [fake.source, fake.source])
        XCTAssertEqual(try Data(contentsOf: fake.source), originalBytes)
        XCTAssertTrue(fake.created.isEmpty)
        XCTAssertTrue(fake.applied.isEmpty)
    }



    @MainActor
    func testReusingYosemiteClearsPreviousUncroppedPictureAndFraming() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        let model = fake.model()
        defer { model.stopBackgroundTasks(); fake.sleeper.cancelAll() }
        let crop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2, zoom: 2)
        try await model.commitCrop(crop)
        XCTAssertNotNil(model.settings.uncroppedSourcePath)
        XCTAssertNotNil(model.settings.sourceCrop)
        XCTAssertNotEqual(model.sourceImageURL, fake.source)
        model.useBuiltInPicture(replaceCurrent: true)
        XCTAssertEqual(model.sourceImageURL, fake.source)
        XCTAssertEqual(model.uncroppedImageURL, fake.source)
        XCTAssertNil(model.settings.uncroppedSourcePath)
        XCTAssertNil(model.settings.sourceCrop)
        XCTAssertEqual(model.settings.sourceDigest, BuiltInPicture.digest)
        XCTAssertTrue(fake.created.isEmpty)
    }

    @MainActor
    func testInjectedFixtureLivesThroughBackgroundTurnsAndReleasesAfterShutdown() async throws {
        var externalFixture: AppHourlyFake? = try AppHourlyFake()
        externalFixture?.runsBackgroundTasks = true
        let directory = try XCTUnwrap(externalFixture?.directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        weak var weakFixture = externalFixture
        var model: AppModel? = try XCTUnwrap(externalFixture).model()
        externalFixture = nil
        await appEventually { weakFixture?.created.count == 1 && model?.isGenerating == false && (weakFixture?.sleeper.waitingCount ?? 0) > 0 }
        XCTAssertNotNil(weakFixture)
        weakFixture?.clock = try XCTUnwrap(weakFixture?.clock).addingTimeInterval(31)
        weakFixture?.sleeper.wakeAll()
        await appEventually { (weakFixture?.sleeper.sleepCalls ?? 0) >= 2 && (weakFixture?.sleeper.waitingCount ?? 0) > 0 }
        model?.stopBackgroundTasks()
        weakFixture?.sleeper.cancelAll()
        model = nil
        await appEventually { weakFixture == nil }
        XCTAssertNil(weakFixture)
    }

    @MainActor
    func testActualSendDayAccountingRefundsOldDay4xxWithoutChargingFollowingDay() async throws {
        let fake = try AppHourlyFake()
        defer { fake.removeFiles() }
        fake.settings.automaticUpdates = false
        fake.creationGate = AppHourlyGate()
        fake.rejection = 429
        let sendDay = fake.clock
        let model = fake.model()
        model.generateNow()
        await appEventually { fake.created.count == 1 }
        XCTAssertEqual(fake.ledger.count(on: sendDay), 1)
        fake.clock = Calendar.current.date(byAdding: .day, value: 1, to: fake.clock)!
        fake.creationGate?.release()
        await appEventually { !model.isGenerating }
        XCTAssertEqual(fake.ledger.count(on: sendDay), 0)
        XCTAssertEqual(fake.ledger.count(on: fake.clock), 0)
        XCTAssertEqual(model.generatedToday, 0)
        XCTAssertTrue(fake.ledger.reservations.isEmpty)
    }
}

private enum AppHourlyError: Error { case failed }

@MainActor
private final class AppHourlyGate {
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() {
        released = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }
}

@MainActor
private final class AppHourlyFake {
    var clock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 14))!
    var settings = CanvasSettings()
    let directory: URL
    let source: URL
    var ledger = ImageGenerationLedger()
    var ledgerData: Data?
    var ledgerWrites = 0
    var pending: [HourlyGenerationJob] = []
    var applicationRetry: SavedWallpaperApplication?
    var weatherLabel = "clear"
    var weatherCalls = 0
    var readCalls = 0
    var created: [HourlyGenerationJob] = []
    var applied: [URL] = []
    var weatherGate: AppHourlyGate?
    var weatherGates: [Int: AppHourlyGate] = [:]
    var readGate: AppHourlyGate?
    var creationGate: AppHourlyGate?
    var beforeSendGate: AppHourlyGate?
    var importGate: AppHourlyGate?
    var importStarts = 0
    var createPreparations = 0
    var weatherError: Error?
    var weatherErrors: [Int: Error] = [:]
    var wrapsWeatherCancellation = false
    var runsBackgroundTasks = false
    let sleeper = AppHourlySleeper()
    let choiceSleeper = AppHourlySleeper()
    var useRealSourceBody = false
    var sourceServices: AppModelPromptSourceServices?
    var creationError: Error?
    var rejection: Int?
    var failApply = false
    var previewWindowActive = true
    var cropSources: [URL] = []
    var originalImageSize = CGSize(width: 800, height: 600)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("source.jpg")
        try Data("fake base picture".utf8).write(to: source)
        settings.sourcePath = source.path
        settings.sourceDigest = "fake-picture"
        settings.weatherChoice = .automatic
        settings.automaticUpdates = true
    }

    func model(nextCheck: Date? = nil) -> AppModel {
        let promptReader: (@MainActor @Sendable (HourlyGenerationJob) async throws -> String)?
        if useRealSourceBody { promptReader = nil }
        else {
            promptReader = { [self] _ in
                readCalls += 1
                await readGate?.wait()
                return "Fake prompt"
            }
        }
        var services = AppModelHourlyServices(
            now: { [self] in clock },
            sourceAvailable: { [self] path in path.hasPrefix(directory.path + "/") && FileManager.default.fileExists(atPath: path) },
            weather: { [self] _, date in
                weatherCalls += 1
                let call = weatherCalls
                let gate = weatherGates[call] ?? weatherGate
                await gate?.wait()
                if wrapsWeatherCancellation && Task.isCancelled { throw WeatherContextError.forecastUnavailable }
                try Task.checkCancellation()
                if let error = weatherErrors[call] ?? weatherError { throw error }
                return WeatherSnapshot(label: weatherLabel, symbol: "sun.max", fetchedAt: date)
            },
            readPrompt: promptReader,
            create: { [self] job, _, willSend, didReject in
                createPreparations += 1
                await beforeSendGate?.wait()
                try willSend()
                created.append(job)
                await creationGate?.wait()
                if let rejection { didReject(rejection); throw AppHourlyError.failed }
                if let creationError { throw creationError }
                return Data("fake generated picture".utf8)
            },
            cacheDirectory: directory,
            apply: { [self] in applied.append($0); if failApply { throw AppHourlyError.failed } },
            loadLedger: { [self] in
                if let ledgerData { return try AppModel.decodedGenerationLedger(data: ledgerData, legacyDay: nil, legacyCount: 0) }
                return ledger
            },
            saveLedger: { [self] in
                ledgerWrites += 1
                ledger = roundTrip($0)
                if ledgerData != nil { ledgerData = try? JSONEncoder().encode($0) }
            },
            loadPending: { [self] in pending },
            savePending: { [self] in pending = roundTrip($0) },
            loadApplicationRetry: { [self] in applicationRetry },
            saveApplicationRetry: { [self] in applicationRetry = $0.map { roundTrip($0) } }
        )
        services.runsBackgroundTasks = runsBackgroundTasks
        services.sleep = { [self] seconds in try await sleeper.sleep(seconds) }
        services.promptSources = sourceServices
        services.isPreviewWindowActive = { [self] in previewWindowActive }
        services.importPicture = { [self] url in
            importStarts += 1
            await importGate?.wait()
            return ImportedImage(originalURL: url, uploadURL: url, digest: url.lastPathComponent)
        }
        services.pictureChoiceSleep = { [self] seconds in try await choiceSleeper.sleep(seconds) }
        services.reusableBuiltInPicture = { [self] in source }
        services.originalImageSize = { [self] _ in originalImageSize }
        services.cropPicture = { [self] url, _ in
            cropSources.append(url)
            let cropped = directory.appendingPathComponent("crop-\(UUID().uuidString).png")
            try Data("fake cropped picture".utf8).write(to: cropped)
            return ImportedImage(originalURL: cropped, uploadURL: cropped, digest: UUID().uuidString)
        }
        services.clearCache = { [self] in
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "png" || file.lastPathComponent == "hour-wallpapers.json" {
                try FileManager.default.removeItem(at: file)
            }
        }
        return AppModel(settings: settings, hourlyServices: services, nextScheduledCheck: nextCheck)
    }

    func job(hour: Int, date: Date? = nil, intent: HourlyGenerationJob.Intent, settings snapshot: CanvasSettings? = nil) -> HourlyGenerationJob {
        let date = date ?? clock
        let snapshot = snapshot ?? settings
        let recipe = HourWallpaperCache.recipeID(for: snapshot, date: date)
        return HourlyGenerationJob(id: HourWallpaperCache.jobID(recipeID: recipe, hour: hour, weather: "clear"),
                                   hour: hour, date: date, recipeID: recipe,
                                   weather: WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: date),
                                   settings: snapshot, sourcePath: source.path,
                                   priority: intent == .automaticWallpaper ? .automatic : .manual,
                                   requiresCredit: true, forceFresh: intent == .preview, userInitiated: intent != .automaticWallpaper, intent: intent)
    }

    private func roundTrip<T: Codable>(_ value: T) -> T {
        do { return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) }
        catch { XCTFail("Fake persisted value did not round-trip: \(error)"); return value }
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class AppHourlySleeper {
    private var waits: [(UUID, CheckedContinuation<Void, Error>)] = []
    private(set) var sleepCalls = 0
    private(set) var requestedSeconds: [TimeInterval] = []
    var waitingCount: Int { waits.count }
    func sleep(_ seconds: TimeInterval) async throws {
        requestedSeconds.append(seconds)
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepCalls += 1
                waits.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }
    private func cancel(_ id: UUID) {
        guard let index = waits.firstIndex(where: { $0.0 == id }) else { return }
        waits.remove(at: index).1.resume(throwing: CancellationError())
    }
    func wakeAll() {
        let ready = waits
        waits.removeAll()
        for (_, waiter) in ready { waiter.resume() }
    }
    func cancelAll() {
        let ready = waits
        waits.removeAll()
        for (_, waiter) in ready { waiter.resume(throwing: CancellationError()) }
    }
}

@MainActor
private func appEventually(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Actual AppModel did not reach expected fake-backed state", file: file, line: line)
}
