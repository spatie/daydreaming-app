import XCTest
@testable import Daydreaming

final class HourlyGenerationQueueTests: XCTestCase {
    @MainActor
    func testJobsRunSeriallyAndDuplicatePendingOrCurrentIDsAreIgnored() async {
        let processor = QueueTestProcessor()
        var changes = 0
        let queue = HourlyGenerationQueue(
            process: { try await processor.process($0) },
            remainingBudget: { 24 },
            onChange: { changes += 1 }
        )

        XCTAssertTrue(queue.enqueue(queueJob("first")))
        XCTAssertFalse(queue.enqueue(queueJob("first")))
        await processor.waitForStarts(1)
        XCTAssertFalse(queue.enqueue(queueJob("first")))
        XCTAssertTrue(queue.enqueue(queueJob("second")))
        XCTAssertFalse(queue.enqueue(queueJob("second")))
        XCTAssertEqual(queue.current?.id, "first")
        XCTAssertEqual(queue.pending.map(\.id), ["second"])
        XCTAssertEqual(processor.started, ["first"])

        processor.finish("first")
        await processor.waitForStarts(2)
        XCTAssertEqual(queue.current?.id, "second")
        processor.finish("second")
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })

        XCTAssertEqual(processor.started, ["first", "second"])
        XCTAssertEqual(processor.maximumConcurrent, 1)
        XCTAssertGreaterThan(changes, 0)
    }

    @MainActor
    func testAutomaticJobsAndPromotedDuplicatesPrecedeManualJobsInFIFOOrder() async {
        let processor = QueueTestProcessor()
        let queue = HourlyGenerationQueue(process: { try await processor.process($0) }, remainingBudget: { 24 })
        queue.enqueue(queueJob("in-flight"))
        await processor.waitForStarts(1)

        queue.enqueue(queueJob("manual-one"))
        queue.enqueue(queueJob("promoted", recipeID: "original-snapshot"))
        queue.enqueue(queueJob("automatic-one", priority: .automatic))
        XCTAssertTrue(queue.enqueue(queueJob("promoted", priority: .automatic, recipeID: "new-snapshot")))
        queue.enqueue(queueJob("automatic-two", priority: .automatic))

        XCTAssertEqual(queue.current?.id, "in-flight")
        XCTAssertEqual(queue.pending.map(\.id), ["promoted", "automatic-two", "manual-one"])
        XCTAssertEqual(queue.pending[0].recipeID, "original-snapshot")
        XCTAssertEqual(queue.pending[0].priority, .automatic)
        XCTAssertFalse(queue.enqueue(queueJob("automatic-two", priority: .automatic)))

        let order = ["in-flight", "promoted", "automatic-two", "manual-one"]
        for (index, id) in order.enumerated() {
            await processor.waitForStarts(index + 1)
            XCTAssertEqual(queue.current?.id, id)
            processor.finish(id)
        }
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })
        XCTAssertEqual(processor.started, order)
        XCTAssertEqual(processor.maximumConcurrent, 1)
    }

    @MainActor
    func testAutomaticPromotionPreservesManualAuthorizationWhileAutomaticUpdatesArePaused() async {
        let processor = QueueTestProcessor()
        var processedAuthorizations: [Bool] = []
        let queue = HourlyGenerationQueue(process: { job in
            processedAuthorizations.append(HourWallpaperPaymentPolicy.mayStart(job: job, automaticUpdates: false))
            try await processor.process(job)
        }, remainingBudget: { 24 })
        queue.enqueue(queueJob("current"))
        await processor.waitForStarts(1)
        queue.enqueue(queueJob("explicit-preview"))
        XCTAssertTrue(queue.enqueue(queueJob("explicit-preview", priority: .automatic)))
        XCTAssertEqual(queue.pending.first?.priority, .automatic)
        XCTAssertEqual(queue.pending.first?.userInitiated, true)
        processor.finish("current")
        await processor.waitForStarts(2)
        XCTAssertEqual(queue.current?.userInitiated, true)
        processor.finish("explicit-preview")
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })
        XCTAssertEqual(processedAuthorizations, [true, true])
    }

    @MainActor
    func testManualDuplicateAuthorizesPendingAutomaticWorkWithoutChangingFIFOOrder() {
        let queue = HourlyGenerationQueue(process: { _ in XCTFail("Budget is zero; fake work must not start") }, remainingBudget: { 0 })
        queue.enqueue(queueJob("first", priority: .automatic))
        XCTAssertTrue(queue.enqueue(queueJob("first", priority: .manual)))
        queue.enqueue(queueJob("second", priority: .automatic))
        XCTAssertEqual(queue.pending.map(\.id), ["first", "second"])
        XCTAssertEqual(queue.pending.first?.priority, .automatic)
        XCTAssertEqual(queue.pending.first?.userInitiated, true)
        XCTAssertTrue(HourWallpaperPaymentPolicy.mayStart(job: queue.pending[0], automaticUpdates: false))
        XCTAssertFalse(HourWallpaperPaymentPolicy.mayStart(job: queue.pending[1], automaticUpdates: false))
        queue.clearPending()
    }

    @MainActor
    func testClearPendingPreservesTheCurrentRequestAndAcceptsNewWork() async {
        let processor = QueueTestProcessor()
        let queue = HourlyGenerationQueue(process: { try await processor.process($0) }, remainingBudget: { 24 })
        queue.enqueue(queueJob("current"))
        await processor.waitForStarts(1)
        queue.enqueue(queueJob("discarded"))

        queue.clearPending()
        XCTAssertEqual(queue.current?.id, "current")
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertEqual(processor.concurrent, 1)
        XCTAssertFalse(queue.isLimitPaused)

        queue.enqueue(queueJob("replacement"))
        processor.finish("current")
        await processor.waitForStarts(2)
        XCTAssertEqual(processor.started, ["current", "replacement"])
        processor.finish("replacement")
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })
        XCTAssertEqual(processor.maximumConcurrent, 1)
    }

    @MainActor
    func testSafetyLimitKeepsJobsPendingUntilResumeAndDoesNotChargeCachedJobs() async {
        let processor = QueueTestProcessor()
        let budget = QueueTestBudget(1)
        let queue = HourlyGenerationQueue(
            process: {
                try await processor.process($0)
                if $0.requiresCredit { budget.remaining -= 1 }
            },
            remainingBudget: { budget.remaining }
        )
        queue.enqueue(queueJob("first"))
        queue.enqueue(queueJob("paid-waiting"))
        queue.enqueue(queueJob("cached", requiresCredit: false))
        await processor.waitForStarts(1)
        processor.finish("first")
        await processor.waitForStarts(2)
        XCTAssertEqual(queue.current?.id, "cached")
        XCTAssertEqual(processor.started, ["first", "cached"])
        XCTAssertEqual(budget.remaining, 0)
        processor.finish("cached")
        await waitForQueue(queue, until: { $0.isLimitPaused })

        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.pending.map(\.id), ["paid-waiting"])
        queue.resume()
        XCTAssertTrue(queue.isLimitPaused)
        XCTAssertEqual(processor.started, ["first", "cached"])

        budget.remaining = 1
        queue.resume()
        await processor.waitForStarts(3)
        XCTAssertFalse(queue.isLimitPaused)
        XCTAssertEqual(queue.current?.id, "paid-waiting")
        processor.finish("paid-waiting")
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })

        XCTAssertEqual(processor.started, ["first", "cached", "paid-waiting"])
        XCTAssertEqual(budget.remaining, 0)
        XCTAssertFalse(queue.isLimitPaused)
        XCTAssertEqual(processor.maximumConcurrent, 1)
    }

    @MainActor
    func testCachedAutomaticHeadCanRunWhilePaidManualJobsWaitForBudget() async {
        let processor = QueueTestProcessor()
        let queue = HourlyGenerationQueue(process: { try await processor.process($0) }, remainingBudget: { 0 })
        queue.enqueue(queueJob("paid"))
        XCTAssertTrue(queue.isLimitPaused)
        queue.enqueue(queueJob("cached", priority: .automatic, requiresCredit: false))
        await processor.waitForStarts(1)
        XCTAssertEqual(queue.current?.id, "cached")
        XCTAssertEqual(queue.pending.map(\.id), ["paid"])
        processor.finish("cached")
        await waitForQueue(queue, until: { $0.isLimitPaused })

        queue.clearPending()
        XCTAssertFalse(queue.isLimitPaused)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(queue.current)
        XCTAssertEqual(processor.started, ["cached"])
    }

    @MainActor
    func testDeferredRestoreWaitsForDueAutomaticForecastBeforeUsingSingleDailyCredit() async {
        let processor = QueueTestProcessor()
        let budget = QueueTestBudget(1)
        let forecast = QueuePreparationGate()
        let queue = HourlyGenerationQueue(process: { job in
            try await processor.process(job)
            if job.requiresCredit { budget.remaining -= 1 }
        }, remainingBudget: { budget.remaining })
        queue.restore([queueJob("yesterday-preview")], resumeImmediately: false)
        await Task.yield()
        XCTAssertTrue(processor.started.isEmpty)
        let preparation = Task {
            await queue.prepareBeforeResuming {
                await forecast.wait()
                queue.enqueue(queueJob("due-automatic", priority: .automatic))
            }
        }
        await forecast.waitUntilEntered()
        queue.resume()
        queue.enqueue(queueJob("another-preview"))
        await Task.yield()
        XCTAssertTrue(processor.started.isEmpty)
        forecast.release()
        await preparation.value
        await processor.waitForStarts(1)
        XCTAssertEqual(processor.started, ["due-automatic"])
        processor.finish("due-automatic")
        await waitForQueue(queue, until: { $0.isLimitPaused })
        XCTAssertEqual(budget.remaining, 0)
        XCTAssertEqual(queue.pending.map(\.id), ["yesterday-preview", "another-preview"])
        queue.clearPending()
    }

    @MainActor
    func testPaidCurrentFinishesWhileUnpaidWorkWaitsForAutomaticPreparation() async {
        let processor = QueueTestProcessor()
        let budget = QueueTestBudget(1)
        let forecast = QueuePreparationGate()
        let queue = HourlyGenerationQueue(process: { job in
            try await processor.process(job)
            if job.requiresCredit { budget.remaining -= 1 }
        }, remainingBudget: { budget.remaining })
        queue.enqueue(queueJob("already-running", requiresCredit: false))
        await processor.waitForStarts(1)
        queue.enqueue(queueJob("waiting-preview"))
        let preparation = Task {
            await queue.prepareBeforeResuming {
                await forecast.wait()
                queue.enqueue(queueJob("due-automatic", priority: .automatic))
            }
        }
        await forecast.waitUntilEntered()
        processor.finish("already-running")
        await waitForQueue(queue, until: { $0.current == nil })
        XCTAssertEqual(processor.started, ["already-running"])
        forecast.release()
        await preparation.value
        await processor.waitForStarts(2)
        XCTAssertEqual(queue.current?.id, "due-automatic")
        processor.finish("due-automatic")
        await waitForQueue(queue, until: { $0.isLimitPaused })
        XCTAssertEqual(queue.pending.map(\.id), ["waiting-preview"])
        queue.clearPending()
    }

    @MainActor
    func testExplicitRetryClearsWeatherDelayAndStillRespectsSafetyLimit() async {
        var attempts = 0
        var budget = 1
        let queue = HourlyGenerationQueue(process: { job in
            attempts += 1
            if attempts == 1 {
                throw HourlyGenerationRetry(job: job, reason: .weather, retryAfter: Date().addingTimeInterval(60), underlying: nil)
            }
        }, remainingBudget: { budget })
        queue.enqueue(queueJob("retry"))
        await waitForQueue(queue, until: { $0.retryAfter != nil })
        budget = 0
        queue.retryNow()
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(queue.isLimitPaused)
        budget = 1
        queue.retryNow()
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testCanceledRetryIsDroppedAndFreshSameIDRestartsWithoutErasingOtherWeatherDelay() async {
        let processor = QueueTestProcessor()
        var clock = Date(timeIntervalSince1970: 1_000)
        var heldAttempts = 0
        var errors = 0
        let queue = HourlyGenerationQueue(process: { job in
            if job.id == "held" {
                heldAttempts += 1
                if heldAttempts == 1 {
                    throw HourlyGenerationRetry(job: job, reason: .weather, retryAfter: clock.addingTimeInterval(60), underlying: QueueTestError.failed)
                }
                return
            }
            try await processor.process(job)
        }, remainingBudget: { 24 }, now: { clock })
        queue.onError = { _, _ in errors += 1 }
        queue.enqueue(queueJob("held"))
        await waitForQueue(queue, until: { $0.retryAfter != nil })
        let originalDelay = queue.retryAfter
        queue.enqueue(queueJob("current", priority: .automatic))
        await processor.waitForStarts(1)
        XCTAssertTrue(queue.cancelCurrentBeforePayment())
        queue.enqueue(queueJob("current"))
        XCTAssertEqual(queue.pending.map(\.id), ["held", "current"])
        processor.finish("current", error: HourlyGenerationRetry(job: queueJob("current", priority: .automatic), reason: .weather,
                                                               retryAfter: clock.addingTimeInterval(60), underlying: QueueTestError.failed))
        await processor.waitForStarts(2)
        XCTAssertEqual(processor.started, ["current", "current"])
        XCTAssertEqual(queue.retryAfter, originalDelay)
        XCTAssertEqual(heldAttempts, 1)
        XCTAssertEqual(errors, 1)
        processor.finish("current")
        await waitForQueue(queue, until: { $0.current == nil })
        XCTAssertEqual(queue.pending.map(\.id), ["held"])
        XCTAssertEqual(queue.retryAfter, originalDelay)
        clock = clock.addingTimeInterval(61)
        queue.resume()
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })
        XCTAssertEqual(heldAttempts, 2)
        XCTAssertEqual(errors, 1)
    }

    @MainActor
    func testProcessorFailureIsReportedAndDoesNotPreventTheNextJob() async {
        let processor = QueueTestProcessor()
        var failedIDs: [String] = []
        let queue = HourlyGenerationQueue(process: { try await processor.process($0) }, remainingBudget: { 24 })
        queue.onError = { job, _ in failedIDs.append(job.id) }
        queue.enqueue(queueJob("failed"))
        queue.enqueue(queueJob("next"))
        await processor.waitForStarts(1)
        processor.finish("failed", error: QueueTestError.failed)
        await processor.waitForStarts(2)
        XCTAssertEqual(failedIDs, ["failed"])
        XCTAssertEqual(queue.current?.id, "next")
        processor.finish("next")
        await waitForQueue(queue, until: { $0.current == nil && $0.pending.isEmpty })
        XCTAssertEqual(processor.maximumConcurrent, 1)
    }
}

private enum QueueTestError: Error {
    case failed
}

@MainActor
private final class QueuePreparationGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async {
        for _ in 0..<10_000 {
            if entered { return }
            await Task.yield()
        }
        XCTFail("Fake forecast preparation did not begin")
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class QueueTestBudget {
    var remaining: Int
    init(_ remaining: Int) { self.remaining = remaining }
}

@MainActor
private final class QueueTestProcessor {
    private(set) var started: [String] = []
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0
    private var finishes: [String: CheckedContinuation<Void, Error>] = [:]

    func process(_ job: HourlyGenerationJob) async throws {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        started.append(job.id)
        try await withCheckedThrowingContinuation { finishes[job.id] = $0 }
    }

    func waitForStarts(_ count: Int) async {
        for _ in 0..<10_000 {
            if started.count >= count { return }
            await Task.yield()
        }
        XCTFail("Fake processor did not start \(count) requests")
    }

    func finish(_ id: String, error: Error? = nil) {
        guard let continuation = finishes.removeValue(forKey: id) else {
            XCTFail("No running fake request for \(id)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

@MainActor
private func waitForQueue(
    _ queue: HourlyGenerationQueue,
    until condition: @escaping @MainActor (HourlyGenerationQueue) -> Bool
) async {
    for _ in 0..<10_000 {
        if condition(queue) { return }
        await Task.yield()
    }
    XCTFail("Fake queue did not reach the expected state")
}

private func queueJob(
    _ id: String,
    priority: HourlyGenerationJob.Priority = .manual,
    requiresCredit: Bool = true,
    recipeID: String = "recipe"
) -> HourlyGenerationJob {
    let date = Date(timeIntervalSince1970: 1_000)
    return HourlyGenerationJob(
        id: id,
        hour: 12,
        date: date,
        recipeID: recipeID,
        weather: WeatherSnapshot(label: "Clear", symbol: "sun.max", fetchedAt: date),
        settings: CanvasSettings(),
        sourcePath: "/fixture/picture.png",
        priority: priority,
        requiresCredit: requiresCredit
    )
}
