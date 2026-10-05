import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: CanvasSettings {
        didSet { saveSettings() }
    }

    @Published private(set) var displayedImageURL: URL?
    @Published private(set) var status = "Choose an image to begin"
    @Published private(set) var detail = "Your source image and generated wallpapers stay on this Mac."
    @Published private(set) var isGenerating = false
    @Published private(set) var hasSavedKey = KeychainStore.read() != nil
    @Published private(set) var generatedToday = 0
    @Published private(set) var latestWeather: WeatherSnapshot?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var license: LicensePayload?
    @Published private(set) var contextPreview: ContextPreview = .empty
    @Published private(set) var isReadingSources = false
    @Published var showMenuBar = UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar") }
    }
    @Published var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete") {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: "onboardingComplete") }
    }

    private let locationReader = LocationReader()
    private let weatherProvider = WeatherContextProvider()
    private let imageClient = OpenAIImageClient()
    private var scheduler: Task<Void, Never>?
    private var lastAppliedKey: String?
    private var lastScheduledSlot: String?
    private var lastScheduledSettings: CanvasSettings?
    private var nextRetryAt = Date.distantPast
    private var consecutiveFailures = 0
    private var wakeObserver: NSObjectProtocol?

    init() {
        let currentData = UserDefaults.standard.data(forKey: "settings")
        let previousData = UserDefaults(suiteName: "be.spatie.weathercanvas")?.data(forKey: "settings")
        if let data = currentData ?? previousData,
           let saved = try? JSONDecoder().decode(CanvasSettings.self, from: data) {
            settings = saved
        } else {
            settings = CanvasSettings()
        }

        if currentData == nil,
           let sourcePath = settings.sourcePath,
           FileManager.default.fileExists(atPath: sourcePath),
           let imported = try? ImageStore.importImage(from: URL(fileURLWithPath: sourcePath)) {
            settings.sourcePath = imported.originalURL.path
            settings.sourceDigest = imported.digest
        }
        if let sourcePath = settings.sourcePath, !ImageStore.owns(sourcePath) {
            if let imported = try? ImageStore.importImage(from: URL(fileURLWithPath: sourcePath)) {
                settings.sourcePath = imported.originalURL.path
                settings.sourceDigest = imported.digest
            } else {
                settings.sourcePath = nil
                settings.sourceDigest = nil
                settings.automaticUpdates = false
                onboardingComplete = false
                status = "Choose your base image again"
                detail = "The original needs to be selected again for this installed app."
            }
        }
        if settings.sourcePath == nil ||
            !FileManager.default.fileExists(atPath: settings.sourcePath ?? "") {
            settings.automaticUpdates = false
            onboardingComplete = false
        }
        if !onboardingComplete {
            settings.automaticUpdates = false
        }
        if currentData == nil && previousData != nil {
            saveSettings()
        }

        if let path = UserDefaults.standard.string(forKey: "displayedImagePath"),
           ImageStore.owns(path),
           FileManager.default.fileExists(atPath: path) {
            displayedImageURL = URL(fileURLWithPath: path)
        } else if let path = settings.sourcePath {
            displayedImageURL = URL(fileURLWithPath: path)
        }

        generatedToday = Self.savedGenerationCount()
        license = try? LicenseManager.shared.currentLicense()
        if license == nil && settings.possibleDailySlots > 2 {
            settings.interval = .twiceDaily
        }
        let previousDefault = "Preserve the composition, subjects, and style of the original image. Reimagine its lighting and atmosphere for {{time}} with {{weather}} weather. Keep it recognizable as the same scene."
        if settings.promptTemplate == previousDefault {
            settings.promptTemplate = CanvasSettings.defaultPrompt
        }
        locationReader.onLocation = { [weak self] in
            guard let self, self.settings.automaticUpdates else { return }
            Task { await self.refreshIfNeeded() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfNeeded() }
        }

        if settings.automaticUpdates {
            beginScheduling()
        }
    }

    var sourceImageURL: URL? {
        guard let path = settings.sourcePath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    var cacheSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: ImageStore.cacheSize(), countStyle: .file)
    }

    var hasProLicense: Bool { license != nil }

    var availableIntervals: [UpdateInterval] {
        hasProLicense ? UpdateInterval.allCases : [.twiceDaily, .daily]
    }

    func activateLicense(_ token: String) -> Bool {
        do {
            license = try LicenseManager.shared.activate(token)
            status = "License activated"
            detail = "All update intervals are now available."
            return true
        } catch {
            show(error)
            return false
        }
    }

    func removeLicense() {
        do {
            try LicenseManager.shared.remove()
            license = nil
            if settings.possibleDailySlots > 2 {
                settings.interval = .twiceDaily
            }
            status = "Using the free plan"
            detail = "You can create up to two new images each day."
        } catch {
            show(error)
        }
    }

    func addSource(_ source: ContextSource, preview: ContextPreview) {
        guard settings.contextSources.count < 5 else {
            show(ContextSourceError.tooManySources)
            return
        }
        settings.contextSources.append(source)
        contextPreview = preview
    }

    func removeSource(_ source: ContextSource) {
        settings.contextSources.removeAll { $0.id == source.id }
        contextPreview = .empty
    }

    func previewSources() {
        guard !isReadingSources else { return }
        isReadingSources = true
        Task {
            defer { isReadingSources = false }
            do {
                contextPreview = try await ContextSourceReader().readAll(settings.contextSources)
            } catch {
                show(error)
            }
        }
    }

    func importImage(_ selectedURL: URL) {
        let access = selectedURL.startAccessingSecurityScopedResource()
        defer { if access { selectedURL.stopAccessingSecurityScopedResource() } }

        do {
            let imported = try ImageStore.importImage(from: selectedURL)
            settings.sourcePath = imported.originalURL.path
            settings.sourceDigest = imported.digest
            displayedImageURL = imported.originalURL
            UserDefaults.standard.set(imported.originalURL.path, forKey: "displayedImagePath")
            lastAppliedKey = nil
            lastScheduledSlot = nil
            nextRetryAt = .distantPast
            consecutiveFailures = 0
            status = "Image ready"
            detail = "Your original is safely copied into the app. Generate a preview or start automatic updates."
        } catch {
            show(error)
        }
    }

    func saveKey(_ key: String) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            status = "Enter an API key first"
            return false
        }

        do {
            try KeychainStore.save(cleaned)
            hasSavedKey = true
            status = "API key saved"
            detail = "The key is stored in your Mac's Keychain. Images are sent directly to OpenAI."
            return true
        } catch {
            show(error)
            return false
        }
    }

    func removeKey() {
        do {
            try KeychainStore.remove()
            hasSavedKey = false
            stopAutomatic()
            status = "API key removed"
        } catch {
            show(error)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            show(error)
        }
    }

    func startAutomatic() {
        guard sourceImageURL != nil else {
            status = "Choose an image first"
            return
        }

        guard hasSavedKey else {
            status = "Save an API key first"
            return
        }

        settings.automaticUpdates = true
        lastAppliedKey = nil
        lastScheduledSlot = nil
        nextRetryAt = .distantPast
        consecutiveFailures = 0
        beginScheduling()
        status = "Automatic updates are on"
        detail = "Daydreaming checks the selected interval while your Mac is awake."
    }

    func finishOnboarding() {
        guard sourceImageURL != nil, hasSavedKey else { return }
        onboardingComplete = true
        startAutomatic()
    }

    func stopAutomatic() {
        settings.automaticUpdates = false
        scheduler?.cancel()
        scheduler = nil
        status = "Automatic updates are paused"
        detail = "Your current wallpaper stays in place."
    }

    func generateNow() {
        Task { await refreshIfNeeded(force: true) }
    }

    func clearCache() {
        do {
            if let sourceImageURL, displayedImageURL != sourceImageURL {
                try WallpaperController.apply(sourceImageURL)
            }
            try ImageStore.clearCache()
            displayedImageURL = sourceImageURL
            if let sourceImageURL {
                UserDefaults.standard.set(sourceImageURL.path, forKey: "displayedImagePath")
            }
            lastAppliedKey = nil
            lastScheduledSlot = nil
            status = "Generated images cleared"
            detail = "Your original image is still saved."
        } catch {
            show(error)
        }
    }

    private func beginScheduling() {
        scheduler?.cancel()
        if settings.weatherChoice == .automatic {
            locationReader.request()
        }

        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func refreshIfNeeded(force: Bool = false) async {
        guard !isGenerating else { return }
        if !force && Date() < nextRetryAt { return }
        license = try? LicenseManager.shared.currentLicense()
        if license == nil && settings.possibleDailySlots > 2 {
            settings.interval = .twiceDaily
        }
        guard let sourcePath = settings.sourcePath,
              FileManager.default.fileExists(atPath: sourcePath) else {
            status = "Choose an image first"
            return
        }
        guard let key = KeychainStore.read() else {
            status = "Save an API key first"
            return
        }
        guard !settings.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Write a prompt first"
            return
        }

        let now = Date()
        let renderSettings = settings
        let intervalMinutes = renderSettings.intervalMinutes
        let timeContext = RenderContext(date: now, weather: "", intervalMinutes: intervalMinutes)
        let scheduledSlot = "\(timeContext.localDay):\(timeContext.slot)"
        if !force && scheduledSlot == lastScheduledSlot && renderSettings == lastScheduledSettings {
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        do {
            status = settings.weatherChoice == .automatic ? "Checking local weather" : "Preparing your wallpaper"
            detail = "Looking for an image that already matches."
            let weather = try await weatherLabel()
            let context = RenderContext(date: now, weather: weather, intervalMinutes: intervalMinutes)
            let basePrompt = PromptRenderer.render(renderSettings.promptTemplate, context: context)
            if !renderSettings.contextSources.isEmpty {
                status = "Reading connected sources"
                detail = "Extracting the selected text for this image."
            }
            let preview = try await ContextSourceReader().readAll(renderSettings.contextSources)
            contextPreview = preview
            let prompt = preview.promptText.isEmpty
                ? basePrompt
                : basePrompt + "\n\n" + preview.promptText
            let size = try ImageStore.outputSize(for: sourcePath)
            let cacheKey = ImageStore.cacheKey(
                settings: renderSettings,
                context: context,
                renderedPrompt: prompt,
                size: size,
                forceFresh: force
            )
            let destination = try ImageStore.cacheURL(for: cacheKey)
            if !force && cacheKey == lastAppliedKey {
                consecutiveFailures = 0
                nextRetryAt = .distantPast
                lastScheduledSlot = scheduledSlot
                lastScheduledSettings = renderSettings
                status = "Wallpaper is up to date"
                detail = "The current image still matches the time and weather."
                return
            }

            if !FileManager.default.fileExists(atPath: destination.path) {
                generatedToday = Self.savedGenerationCount()
                license = try LicenseManager.shared.currentLicense()
                let dailyLimit = min(renderSettings.dailyGenerationLimit, license == nil ? 2 : 288)
                guard generatedToday < dailyLimit else {
                    consecutiveFailures = 0
                    nextRetryAt = .distantPast
                    lastScheduledSlot = scheduledSlot
                    lastScheduledSettings = renderSettings
                    status = "Daily image limit reached"
                    detail = license == nil
                        ? "The free plan allows two new images each day. Your wallpaper stays in place."
                        : "Increase your safety limit in settings or wait until tomorrow. Your wallpaper stays in place."
                    return
                }

                status = "Creating your wallpaper"
                detail = "Editing the original with \(renderSettings.model.title). This can take a minute."
                let image = try await imageClient.edit(
                    sourceURL: ImageStore.uploadURL(for: sourcePath),
                    prompt: prompt,
                    apiKey: key,
                    model: renderSettings.model,
                    quality: renderSettings.quality,
                    size: size
                )
                try image.write(to: destination, options: .atomic)
                Self.recordGeneration()
                generatedToday = Self.savedGenerationCount()
            } else {
                status = "Applying a saved image"
                detail = "This time and weather combination is already in your cache."
            }

            guard settings == renderSettings else {
                status = "Settings changed"
                detail = "The next update will use your latest choices."
                return
            }

            try WallpaperController.apply(destination)
            displayedImageURL = destination
            UserDefaults.standard.set(destination.path, forKey: "displayedImagePath")
            lastAppliedKey = cacheKey
            consecutiveFailures = 0
            nextRetryAt = .distantPast
            lastScheduledSlot = scheduledSlot
            lastScheduledSettings = renderSettings
            status = "Wallpaper updated"
            let imageCount = generatedToday == 1 ? "1 new image" : "\(generatedToday) new images"
            detail = "\(weather.capitalized) at \(DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)). \(imageCount) today."
        } catch {
            show(error)
            if case WeatherContextError.waitingForLocation = error {
                return
            }
            let seconds = min(3_600, 60 * (1 << min(consecutiveFailures, 6)))
            consecutiveFailures += 1
            nextRetryAt = Date().addingTimeInterval(TimeInterval(seconds))
            detail += " Daydreaming will try again later."
        }
    }

    private func weatherLabel() async throws -> String {
        switch settings.weatherChoice {
        case .automatic:
            guard let location = locationReader.location else {
                locationReader.request()
                if locationReader.authorizationStatus == .denied || locationReader.authorizationStatus == .restricted {
                    throw WeatherContextError.locationPermissionRequired
                }
                throw WeatherContextError.waitingForLocation
            }

            let snapshot = try await weatherProvider.current(at: location)
            latestWeather = snapshot
            return snapshot.label
        default:
            return settings.weatherChoice.rawValue
        }
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "settings")
    }

    private func show(_ error: Error) {
        status = "Something went wrong"
        detail = error.localizedDescription
    }

    private static func savedGenerationCount() -> Int {
        let today = RenderContext(date: .now, weather: "", intervalMinutes: 1_440).localDay
        guard UserDefaults.standard.string(forKey: "generationDay") == today else { return 0 }
        return UserDefaults.standard.integer(forKey: "generationCount")
    }

    private static func recordGeneration() {
        let today = RenderContext(date: .now, weather: "", intervalMinutes: 1_440).localDay
        let count = UserDefaults.standard.string(forKey: "generationDay") == today
            ? UserDefaults.standard.integer(forKey: "generationCount") : 0
        UserDefaults.standard.set(today, forKey: "generationDay")
        UserDefaults.standard.set(count + 1, forKey: "generationCount")
    }
}
