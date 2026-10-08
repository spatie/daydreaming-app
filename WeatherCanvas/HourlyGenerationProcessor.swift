import Foundation

struct ImageGenerationAttempt: Codable, Equatable, Sendable {
    let id: String
    let day: String
}

struct ImageGenerationLedger: Codable, Sendable {
    private(set) var counts: [String: Int] = [:]
    private(set) var reservations: [String: String] = [:]
    private(set) var previewCounts: [String: Int] = [:]
    private var reservationProfiles: [String: GenerationRenderProfile] = [:]

    init(counts: [String: Int] = [:]) { self.counts = counts }

    func count(on date: Date) -> Int { counts[Self.day(date), default: 0] }
    func previewCount(on date: Date) -> Int { previewCounts[Self.day(date), default: 0] }

    mutating func reserve(at date: Date, profile: GenerationRenderProfile = .wallpaper) -> ImageGenerationAttempt {
        let day = Self.day(date)
        let attempt = ImageGenerationAttempt(id: UUID().uuidString, day: day)
        counts[day, default: 0] += 1
        reservations[attempt.id] = day
        reservationProfiles[attempt.id] = profile
        if profile == .quickPreview { previewCounts[day, default: 0] += 1 }
        let cutoff = Self.day(Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date)
        counts = counts.filter { $0.key >= cutoff }
        previewCounts = previewCounts.filter { $0.key >= cutoff }
        reservations = reservations.filter { $0.value >= cutoff }
        reservationProfiles = reservationProfiles.filter { reservations[$0.key] != nil }
        return attempt
    }

    mutating func complete(_ attempt: ImageGenerationAttempt) {
        reservations.removeValue(forKey: attempt.id)
        reservationProfiles.removeValue(forKey: attempt.id)
    }
    mutating func clearInterruptedReservations() { reservations.removeAll(); reservationProfiles.removeAll() }

    mutating func refund(_ attempt: ImageGenerationAttempt) {
        guard reservations.removeValue(forKey: attempt.id) == attempt.day else { return }
        let profile = reservationProfiles.removeValue(forKey: attempt.id) ?? .wallpaper
        counts[attempt.day] = max(0, counts[attempt.day, default: 0] - 1)
        if profile == .quickPreview { previewCounts[attempt.day] = max(0, previewCounts[attempt.day, default: 0] - 1) }
    }

    private enum CodingKeys: String, CodingKey { case counts, reservations, previewCounts, reservationProfiles }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        counts = try values.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        reservations = try values.decodeIfPresent([String: String].self, forKey: .reservations) ?? [:]
        previewCounts = try values.decodeIfPresent([String: Int].self, forKey: .previewCounts) ?? [:]
        reservationProfiles = try values.decodeIfPresent([String: GenerationRenderProfile].self, forKey: .reservationProfiles) ?? [:]
    }

    private static func day(_ date: Date) -> String {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
}

@MainActor
final class HourlyGenerationProcessor {
    @MainActor
    struct Services {
        var now: @MainActor () -> Date = { .now }
        let settings: @MainActor () -> CanvasSettings
        var settingsForJob: (@MainActor (HourlyGenerationJob) -> CanvasSettings)? = nil
        let remainingBudget: @MainActor () -> Int
        var budgetForJob: (@MainActor (HourlyGenerationJob) -> Int)? = nil
        var permitsPreview: @MainActor () -> Bool = { true }
        var permitsDesktopApplication: @MainActor (HourlyGenerationJob) -> Bool = { _ in true }
        let weather: @MainActor (HourlyGenerationJob, Date) async throws -> WeatherSnapshot
        let canonicalize: @MainActor (HourlyGenerationJob) -> HourlyGenerationJob
        var latestIntent: @MainActor (HourlyGenerationJob) -> HourlyGenerationJob = { $0 }
        let cached: @MainActor (HourlyGenerationJob) -> URL?
        let readPrompt: @MainActor (HourlyGenerationJob) async throws -> String
        let destination: @MainActor (HourlyGenerationJob) throws -> URL
        let create: @MainActor (HourlyGenerationJob, String, @escaping @MainActor () throws -> Void,
                     @escaping @MainActor (Int) -> Void) async throws -> Data
        let reserve: @MainActor (Date) -> ImageGenerationAttempt
        var reserveForProfile: (@MainActor (Date, GenerationRenderProfile) -> ImageGenerationAttempt)? = nil
        let refund: @MainActor (ImageGenerationAttempt) -> Void
        var finishAttempt: @MainActor (ImageGenerationAttempt) -> Void = { _ in }
        let write: @MainActor (Data, URL) throws -> Void
        let record: @MainActor (HourlyGenerationJob, URL) throws -> Void
        let apply: @MainActor (HourlyGenerationJob, URL) throws -> Void
        var skipped: @MainActor (HourlyGenerationJob) -> Void = { _ in }
        let completed: @MainActor (HourlyGenerationJob, URL, Bool) -> Void
        var awaitPermission: @MainActor () async throws -> Void = {}
    }

    private let services: Services
    init(services: Services) { self.services = services }

    func process(_ original: HourlyGenerationJob) async throws {
        try Task.checkCancellation()
        try await services.awaitPermission()
        let now = services.now()
        guard canContinue(original, at: now) else { return }
        var job = original
        if !Calendar.current.isDate(original.date, inSameDayAs: now) {
            // Only explicit previews survive into another day. Desktop requests expire.
            guard job.intent.contains(.preview) else { return }
            let date = Calendar.current.date(bySettingHour: job.hour, minute: 0, second: 0, of: now) ?? now
            let weather: WeatherSnapshot
            do {
                weather = try await services.weather(job, date)
                try Task.checkCancellation()
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                throw HourlyGenerationRetry(job: job, reason: .weather,
                                            retryAfter: services.now().addingTimeInterval(60), underlying: error)
            }
            let recipe = HourWallpaperCache.recipeID(for: job.settings, date: date)
            job = HourlyGenerationJob(id: HourWallpaperCache.jobID(recipeID: recipe, hour: job.hour, weather: weather.cacheKey, renderProfile: job.renderProfile),
                                      hour: job.hour, date: date, recipeID: recipe, weather: weather, settings: job.settings,
                                      sourcePath: job.sourcePath, priority: .manual, requiresCredit: true,
                                      forceFresh: job.forceFresh, userInitiated: true, intent: .preview, renderProfile: job.renderProfile,
                                      usesSavedRecipe: job.usesSavedRecipe)
        }
        job = services.canonicalize(job)
        guard canContinue(job, at: services.now()) else { return }
        let destination: URL
        if !job.forceFresh, (job.renderProfile == .quickPreview || job.settings.reuseMatchingImages), let cached = services.cached(job) {
            destination = cached
        } else {
            guard availableBudget(for: job) > 0 else { throw budgetRetry(job) }
            let prompt = try await services.readPrompt(job)
            try Task.checkCancellation()
            job = services.canonicalize(job)
            guard canContinue(job, at: services.now()) else { return }
            destination = try services.destination(job)
            let paymentJob = job
            var reservation: ImageGenerationAttempt?
            defer { if let reservation { services.finishAttempt(reservation) } }
            do {
                let image = try await services.create(job, prompt, { [self] in
                    try Task.checkCancellation()
                    // This runs after the request body is prepared, immediately before sending.
                    guard canContinue(paymentJob, at: services.now()) else {
                        throw ProcessingControl.noLongerAuthorized
                    }
                    guard Calendar.current.isDate(paymentJob.date, inSameDayAs: services.now()) else {
                        throw HourlyGenerationRetry(job: paymentJob, reason: .weather, retryAfter: services.now(), underlying: nil)
                    }
                    guard availableBudget(for: paymentJob) > 0 else { throw budgetRetry(paymentJob) }
                    if reservation == nil {
                        reservation = services.reserveForProfile?(services.now(), paymentJob.renderProfile) ?? services.reserve(services.now())
                    }
                }, { [self] status in
                    guard (400..<500).contains(status), let attempt = reservation else { return }
                    services.refund(attempt)
                    reservation = nil
                })
                try services.write(image, destination)
                try services.record(job, destination)
            } catch ProcessingControl.noLongerAuthorized { return }
        }
        try await services.awaitPermission()
        job = services.latestIntent(job)
        let current = services.settings()
        let shouldApply = services.permitsDesktopApplication(job) && Calendar.current.isDate(job.date, inSameDayAs: services.now()) && HourWallpaperApplicationPolicy.shouldApply(
            job: job, currentRecipeID: HourWallpaperCache.recipeID(for: current, date: services.now()),
            currentHour: Calendar.current.component(.hour, from: services.now()), automaticUpdates: current.automaticUpdates
        )
        if shouldApply {
            do { try services.apply(job, destination) }
            catch { throw WallpaperApplicationFailure(saved: SavedWallpaperApplication(job: job, url: destination), underlying: error) }
        }
        services.completed(job, destination, shouldApply)
    }

    private func canContinue(_ job: HourlyGenerationJob, at date: Date) -> Bool {
        guard job.renderProfile == .wallpaper || job.intent == .preview else { return false }
        guard job.renderProfile == .wallpaper || Calendar.current.isDate(job.date, inSameDayAs: date) else { return false }
        guard job.renderProfile == .wallpaper || services.permitsPreview() else { return false }
        guard validRecipe(job, at: date) else { return false }
        guard mayContinue(job, at: date) else {
            if job.intent.contains(.manualWallpaper),
               !Calendar.current.isDate(job.date, inSameDayAs: date) || job.hour != Calendar.current.component(.hour, from: date) {
                services.skipped(job)
            }
            return false
        }
        return true
    }

    private func validRecipe(_ job: HourlyGenerationJob, at date: Date) -> Bool {
        HourWallpaperCache.recipeID(for: job.settings, date: date)
            == HourWallpaperCache.recipeID(for: services.settingsForJob?(job) ?? services.settings(), date: date)
    }

    private func mayContinue(_ job: HourlyGenerationJob, at date: Date) -> Bool {
        if job.intent.contains(.preview) { return job.userInitiated }
        guard Calendar.current.isDate(job.date, inSameDayAs: date),
              job.hour == Calendar.current.component(.hour, from: date) else { return false }
        return HourWallpaperPaymentPolicy.mayStart(job: job, automaticUpdates: (services.settingsForJob?(job) ?? services.settings()).automaticUpdates)
    }

    private func budgetRetry(_ job: HourlyGenerationJob) -> HourlyGenerationRetry {
        var waiting = job
        waiting.requiresCredit = true
        return HourlyGenerationRetry(job: waiting, reason: .budget, retryAfter: nil, underlying: nil)
    }

    private func availableBudget(for job: HourlyGenerationJob) -> Int { services.budgetForJob?(job) ?? services.remainingBudget() }
}

private enum ProcessingControl: Error { case noLongerAuthorized }
