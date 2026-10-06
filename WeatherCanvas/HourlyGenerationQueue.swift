import Foundation

enum GenerationRenderProfile: String, Codable, Equatable, Sendable {
    case wallpaper, quickPreview

    func model(for settings: CanvasSettings) -> ImageModel { self == .quickPreview ? .fast : settings.model }
    func quality(for settings: CanvasSettings) -> ImageQuality { self == .quickPreview ? .low : settings.quality }
    var maximumInputPixelSize: Int { self == .quickPreview ? 512 : 2_560 }

    func availableBudget(totalRemaining: Int, previewsToday: Int) -> Int {
        self == .quickPreview ? max(0, totalRemaining - 2) : max(0, totalRemaining)
    }
}

struct HourlyGenerationJob: Identifiable, Codable, Equatable, Sendable {
    enum Priority: String, Codable, Equatable, Sendable { case automatic, manual }
    struct Intent: OptionSet, Codable, Equatable, Sendable {
        let rawValue: Int
        static let preview = Intent(rawValue: 1)
        static let automaticWallpaper = Intent(rawValue: 2)
        static let manualWallpaper = Intent(rawValue: 4)
    }

    let id: String
    let hour: Int
    let date: Date
    let recipeID: String
    let weather: WeatherSnapshot
    let settings: CanvasSettings
    let sourcePath: String
    var priority: Priority
    var requiresCredit: Bool
    var forceFresh: Bool
    var userInitiated: Bool
    var intent: Intent
    let renderProfile: GenerationRenderProfile
    var usesSavedRecipe: Bool

    init(id: String, hour: Int, date: Date, recipeID: String, weather: WeatherSnapshot, settings: CanvasSettings,
         sourcePath: String, priority: Priority, requiresCredit: Bool, forceFresh: Bool = false,
         userInitiated: Bool = false, intent: Intent? = nil, renderProfile: GenerationRenderProfile = .wallpaper,
         usesSavedRecipe: Bool = false) {
        self.id = id; self.hour = hour; self.date = date; self.recipeID = recipeID
        self.weather = weather; self.settings = settings; self.sourcePath = sourcePath
        self.priority = priority; self.requiresCredit = requiresCredit; self.forceFresh = forceFresh
        self.userInitiated = userInitiated || priority == .manual
        self.intent = intent ?? (priority == .automatic ? .automaticWallpaper : .preview)
        self.renderProfile = renderProfile
        self.usesSavedRecipe = usesSavedRecipe
    }

    private enum CodingKeys: String, CodingKey {
        case id, hour, date, recipeID, weather, settings, sourcePath, priority, requiresCredit, forceFresh, userInitiated, intent, renderProfile, usesSavedRecipe
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        hour = try values.decode(Int.self, forKey: .hour)
        date = try values.decode(Date.self, forKey: .date)
        recipeID = try values.decode(String.self, forKey: .recipeID)
        weather = try values.decode(WeatherSnapshot.self, forKey: .weather)
        settings = try values.decode(CanvasSettings.self, forKey: .settings)
        sourcePath = try values.decode(String.self, forKey: .sourcePath)
        priority = try values.decode(Priority.self, forKey: .priority)
        requiresCredit = try values.decode(Bool.self, forKey: .requiresCredit)
        forceFresh = try values.decodeIfPresent(Bool.self, forKey: .forceFresh) ?? false
        userInitiated = try values.decodeIfPresent(Bool.self, forKey: .userInitiated) ?? (priority == .manual)
        intent = try values.decodeIfPresent(Intent.self, forKey: .intent) ?? (priority == .automatic ? .automaticWallpaper : .preview)
        renderProfile = try values.decodeIfPresent(GenerationRenderProfile.self, forKey: .renderProfile) ?? .wallpaper
        usesSavedRecipe = try values.decodeIfPresent(Bool.self, forKey: .usesSavedRecipe) ?? false
    }

    var isAutomaticOnly: Bool { intent == .automaticWallpaper && !userInitiated }

    func merged(with other: Self) -> Self {
        guard renderProfile == other.renderProfile else { return self }
        var result = self
        result.intent.formUnion(other.intent)
        result.userInitiated = userInitiated || other.userInitiated
        result.forceFresh = forceFresh || other.forceFresh
        result.usesSavedRecipe = usesSavedRecipe || other.usesSavedRecipe
        result.requiresCredit = requiresCredit || other.requiresCredit || result.forceFresh
        if other.priority == .automatic { result.priority = .automatic }
        return result
    }
}

struct HourlyGenerationRetry: Error {
    enum Reason: Sendable { case budget, weather }
    let job: HourlyGenerationJob
    let reason: Reason
    let retryAfter: Date?
    let underlying: Error?
}

@MainActor
final class HourlyGenerationQueue {
    private(set) var pending: [HourlyGenerationJob] = []
    private(set) var current: HourlyGenerationJob?
    private(set) var isLimitPaused = false
    var retryAfter: Date? { pending.compactMap { retryDelays[$0.id] }.min() }
    private var retryDelays: [String: Date] = [:]
    var onChange: (@MainActor () -> Void)?
    var onError: (@MainActor (HourlyGenerationJob, Error) -> Void)?
    var onDiscard: (@MainActor (HourlyGenerationJob) -> Void)?
    private(set) var isPaymentSent = false
    private(set) var isCurrentCancelled = false

    private let process: @MainActor (HourlyGenerationJob) async throws -> Void
    private let remainingBudget: @MainActor () -> Int
    private let budgetForJob: (@MainActor (HourlyGenerationJob) -> Int)?
    private let shouldKeep: @MainActor (HourlyGenerationJob, Date) -> Bool
    private let now: @MainActor () -> Date
    private var worker: Task<Void, Never>?
    private var deferredStarts = Set<UUID>()
    private var cancellationRevision = 0
    private var suspendedForAppUpdate = false

    init(process: @escaping @MainActor (HourlyGenerationJob) async throws -> Void,
         remainingBudget: @escaping @MainActor () -> Int,
         budgetForJob: (@MainActor (HourlyGenerationJob) -> Int)? = nil, onChange: (@MainActor () -> Void)? = nil,
         shouldKeep: @escaping @MainActor (HourlyGenerationJob, Date) -> Bool = { _, _ in true },
         now: @escaping @MainActor () -> Date = { .now }) {
        self.process = process; self.remainingBudget = remainingBudget
        self.budgetForJob = budgetForJob
        self.shouldKeep = shouldKeep; self.now = now; self.onChange = onChange
    }

    @discardableResult
    func enqueue(_ job: HourlyGenerationJob) -> Bool {
        guard canKeep(job, at: now()) else {
            if job.renderProfile == .quickPreview { onDiscard?(job) }
            return false
        }
        pruneInvalidPending()
        if job.intent.contains(.automaticWallpaper) { removeSupersededAutomatic(by: job) }
        if let active = current, !isCurrentCancelled, active.id == job.id, active.renderProfile == job.renderProfile {
            let merged: HourlyGenerationJob
            if Calendar.current.isDate(active.date, inSameDayAs: job.date) {
                merged = active.merged(with: job)
            } else {
                merged = job.merged(with: validIntent(active, for: job.date))
            }
            guard merged != active else { return false }
            current = merged
            onChange?()
            return true
        }
        if let index = pending.firstIndex(where: { $0.id == job.id && $0.renderProfile == job.renderProfile }) {
            let merged = pending[index].merged(with: job)
            guard merged != pending[index] else { return false }
            let promoted = merged.priority != pending[index].priority
            pending[index] = merged
            if promoted { pending.remove(at: index); insert(merged) }
        } else { insert(job) }
        onChange?()
        startWorkerIfNeeded()
        return true
    }

    /// After a next-day rewrite, coalesce the canonical target before paying.
    func updateCurrent(_ rewritten: HourlyGenerationJob) -> HourlyGenerationJob {
        var merged = rewritten
        if let current { merged = merged.merged(with: validIntent(current, for: rewritten.date)) }
        let duplicateIndices = pending.indices.filter { index in
            let candidate = pending[index]
            guard candidate.renderProfile == rewritten.renderProfile else { return false }
            if Calendar.current.isDate(candidate.date, inSameDayAs: rewritten.date) {
                return candidate.id == rewritten.id
            }
            return candidate.intent.contains(.preview) && candidate.userInitiated
                && candidate.hour == rewritten.hour
                && HourWallpaperCache.recipeID(for: candidate.settings, date: rewritten.date) == rewritten.recipeID
        }
        for index in duplicateIndices.reversed() {
            merged = merged.merged(with: validIntent(pending.remove(at: index), for: rewritten.date))
        }
        current = merged
        onChange?()
        return merged
    }

    private func validIntent(_ job: HourlyGenerationJob, for date: Date) -> HourlyGenerationJob {
        var result = job
        if !Calendar.current.isDate(job.date, inSameDayAs: date)
            || job.hour != Calendar.current.component(.hour, from: now()) {
            result.intent.remove(.manualWallpaper)
            result.intent.remove(.automaticWallpaper)
            result.priority = .manual
        }
        return result
    }

    func hasDesktopRequest(hour: Int, date: Date, recipeID: String) -> Bool {
        (isCurrentCancelled ? pending : [current].compactMap { $0 } + pending).contains {
            $0.renderProfile == .wallpaper && $0.hour == hour && Calendar.current.isDate($0.date, inSameDayAs: date)
                && HourWallpaperCache.recipeID(for: $0.settings, date: date) == recipeID
                && !$0.intent.intersection([.automaticWallpaper, .manualWallpaper]).isEmpty
        }
    }

    func removeAutomaticRequests(hour: Int, date: Date) {
        pending.removeAll { $0.isAutomaticOnly && $0.hour == hour && Calendar.current.isDate($0.date, inSameDayAs: date) }
        onChange?()
    }

    func markPaymentSent() { isPaymentSent = true; onChange?() }

    @discardableResult
    func cancelCurrentBeforePayment() -> Bool {
        guard current != nil, !isPaymentSent else { return false }
        cancellationRevision += 1
        isCurrentCancelled = true
        worker?.cancel()
        onChange?()
        return true
    }

    func clearPending() {
        pending.removeAll(); isLimitPaused = false; retryDelays.removeAll()
        onChange?()
    }

    func removePendingPreviews() {
        let removedIDs = Set(pending.filter { $0.renderProfile == .quickPreview && $0.intent == .preview }.map(\.id))
        pending.removeAll { $0.renderProfile == .quickPreview && $0.intent == .preview }
        for id in removedIDs { retryDelays.removeValue(forKey: id) }
        if pending.isEmpty { isLimitPaused = false }
        onChange?()
    }

    func removePendingDesktopRequestsKeepingPreviews() {
        let removedIDs = Set(pending.filter { !$0.intent.contains(.preview) }.map(\.id))
        pending.removeAll { !$0.intent.contains(.preview) }
        for index in pending.indices {
            pending[index].intent = .preview
            pending[index].priority = .manual
            if pending[index].renderProfile == .wallpaper { pending[index].usesSavedRecipe = true }
        }
        for id in removedIDs { retryDelays.removeValue(forKey: id) }
        if pending.isEmpty { isLimitPaused = false }
        onChange?()
    }

    func removeAutomaticOnly() {
        let removedIDs = Set(pending.filter(\.isAutomaticOnly).map(\.id))
        pending.removeAll(where: \.isAutomaticOnly)
        for id in removedIDs { retryDelays.removeValue(forKey: id) }
        for index in pending.indices where pending[index].intent.contains(.preview) {
            pending[index].intent.remove(.automaticWallpaper)
            pending[index].priority = .manual
        }
        if pending.isEmpty { isLimitPaused = false; retryDelays.removeAll() }
        onChange?()
    }

    func restore(_ jobs: [HourlyGenerationJob], resumeImmediately: Bool = true) {
        guard current == nil else { return }
        pending.removeAll()
        retryDelays.removeAll()
        for job in jobs.prefix(288) where canKeep(job, at: now()) {
            if job.intent.contains(.automaticWallpaper) { removeSupersededAutomatic(by: job) }
            if let index = pending.firstIndex(where: { $0.id == job.id && $0.renderProfile == job.renderProfile }) { pending[index] = pending[index].merged(with: job) }
            else { insert(job) }
        }
        onChange?()
        if resumeImmediately { startWorkerIfNeeded() }
    }

    /// Hold unpaid work while a due automatic job obtains its forecast and enters the queue.
    func prepareBeforeResuming(_ preparation: @MainActor () async -> Void) async {
        let token = UUID()
        deferredStarts.insert(token)
        await preparation()
        deferredStarts.remove(token)
        startWorkerIfNeeded()
    }

    func releasePreparationHolds() { deferredStarts.removeAll(); startWorkerIfNeeded() }

    func resume() { startWorkerIfNeeded() }

    /// Keep pending jobs for restoration after relaunch without admitting another request.
    func suspendForAppUpdate() {
        suspendedForAppUpdate = true
    }

    /// A deliberate retry bypasses the weather delay while preserving the credit limit.
    func retryNow(resumeImmediately: Bool = true) {
        retryDelays.removeAll()
        if resumeImmediately { startWorkerIfNeeded() }
    }

    private func removeSupersededAutomatic(by job: HourlyGenerationJob) {
        pending.removeAll { $0.isAutomaticOnly && $0.id != job.id }
        for index in pending.indices where pending[index].hour != job.hour && pending[index].intent.contains(.preview) {
            pending[index].intent.remove(.automaticWallpaper)
            pending[index].priority = .manual
        }
    }

    private func insert(_ job: HourlyGenerationJob) {
        if job.priority == .automatic, let index = pending.firstIndex(where: { $0.priority == .manual }) {
            pending.insert(job, at: index)
        } else { pending.append(job) }
    }

    private func pruneInvalidPending() {
        let discarded = pending.filter { !canKeep($0, at: now()) }
        guard !discarded.isEmpty else { return }
        let ids = Set(discarded.map(\.id))
        pending.removeAll { ids.contains($0.id) }
        for id in ids { retryDelays.removeValue(forKey: id) }
        for job in discarded { onDiscard?(job) }
        onChange?()
    }

    private func nextReadyIndex() -> Int? {
        let ready = pending.indices.filter { index in retryDelays[pending[index].id].map { now() >= $0 } ?? true }
        return ready.first { !pending[$0].requiresCredit || availableBudget(for: pending[$0]) > 0 } ?? ready.first
    }

    private func availableBudget(for job: HourlyGenerationJob) -> Int { budgetForJob?(job) ?? remainingBudget() }

    private func canKeep(_ job: HourlyGenerationJob, at date: Date) -> Bool {
        if job.renderProfile == .quickPreview {
            guard Calendar.current.isDate(job.date, inSameDayAs: date),
                  !job.requiresCredit || availableBudget(for: job) > 0 else { return false }
        }
        return shouldKeep(job, date)
    }

    private func startWorkerIfNeeded() {
        guard !suspendedForAppUpdate, worker == nil, deferredStarts.isEmpty else { return }
        pruneInvalidPending()
        guard !pending.isEmpty else {
            let changed = isLimitPaused
            isLimitPaused = false; retryDelays.removeAll()
            if changed { onChange?() }
            return
        }
        guard let index = nextReadyIndex() else { return }
        let next = pending[index]
        retryDelays.removeValue(forKey: next.id)
        guard !next.requiresCredit || availableBudget(for: next) > 0 else {
            if !isLimitPaused { isLimitPaused = true; onChange?() }
            return
        }
        isLimitPaused = false
        worker = Task { [weak self] in
            guard let self else { return }
            await self.drain()
        }
        onChange?()
    }

    private func drain() async {
        while !suspendedForAppUpdate && !pending.isEmpty {
            if Task.isCancelled { break }
            if !deferredStarts.isEmpty { worker = nil; onChange?(); return }
            pruneInvalidPending()
            guard !pending.isEmpty else { break }
            guard let index = nextReadyIndex() else {
                worker = nil; isLimitPaused = false; onChange?(); return
            }
            let next = pending[index]
            retryDelays.removeValue(forKey: next.id)
            guard !next.requiresCredit || availableBudget(for: next) > 0 else {
                worker = nil; isLimitPaused = true; onChange?(); return
            }
            pending.remove(at: index); current = next; isPaymentSent = false; isCurrentCancelled = false; isLimitPaused = false; onChange?()
            let revision = cancellationRevision
            do { try await process(next) }
            catch let retry as HourlyGenerationRetry {
                guard !Task.isCancelled, revision == cancellationRevision else { break }
                var waiting = retry.job
                if let current, current.id == waiting.id {
                    if Calendar.current.isDate(current.date, inSameDayAs: waiting.date) {
                        waiting = waiting.merged(with: current)
                    } else {
                        waiting = current.merged(with: validIntent(waiting, for: current.date))
                    }
                }
                if retry.reason == .budget { waiting.requiresCredit = true }
                guard canKeep(waiting, at: now()) else {
                    if waiting.renderProfile == .quickPreview { onDiscard?(waiting) }
                    current = nil; isPaymentSent = false; onChange?(); continue
                }
                pending.removeAll { $0.id == waiting.id }
                insert(waiting)
                if let delay = retry.retryAfter { retryDelays[waiting.id] = delay }
                else { retryDelays.removeValue(forKey: waiting.id) }
                current = nil; isPaymentSent = false
                onError?(waiting, retry); onChange?()
                // The held job keeps its own delay. Ready automatic jobs retain priority.
                continue
            } catch is CancellationError {
                // Cancellation only reaches unpaid work. Already-sent requests are allowed to finish.
            } catch {
                if !Task.isCancelled, revision == cancellationRevision { onError?(current ?? next, error) }
            }
            current = nil; isPaymentSent = false; onChange?()
            if Task.isCancelled { break }
        }
        current = nil; worker = nil; isPaymentSent = false; isCurrentCancelled = false; isLimitPaused = false
        let pendingIDs = Set(pending.map(\.id))
        retryDelays = retryDelays.filter { pendingIDs.contains($0.key) }
        onChange?()
        if !pending.isEmpty { startWorkerIfNeeded() }
    }
}


enum HourlyJobValidity {
    static func canKeep(_ job: HourlyGenerationJob, settings: CanvasSettings, at date: Date, sourceIsAvailable: Bool,
                        previewSettings: CanvasSettings? = nil) -> Bool {
        let currentSettings = job.renderProfile == .quickPreview ? previewSettings ?? settings : settings
        guard sourceIsAvailable, (0...23).contains(job.hour), job.intent.rawValue > 0, job.intent.rawValue < 8,
              HourWallpaperCache.recipeID(for: job.settings, date: date) == HourWallpaperCache.recipeID(for: currentSettings, date: date) else { return false }
        guard job.renderProfile == .wallpaper || job.intent == .preview else { return false }
        guard job.renderProfile == .wallpaper || Calendar.current.isDate(job.date, inSameDayAs: date) else { return false }
        if job.intent.contains(.preview), job.userInitiated { return true }
        guard Calendar.current.isDate(job.date, inSameDayAs: date), job.hour == Calendar.current.component(.hour, from: date) else { return false }
        return HourWallpaperPaymentPolicy.mayStart(job: job, automaticUpdates: settings.automaticUpdates)
    }
}
