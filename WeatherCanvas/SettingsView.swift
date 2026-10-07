import AppKit
import CoreLocation
import SwiftUI

private enum WallpaperQuality: String, CaseIterable, Identifiable {
    case good = "Good"
    case better = "Better"
    case best = "Best"

    var id: String { rawValue }
    var imageModel: ImageModel { self == .good ? .fast : .precise }
    var imageQuality: ImageQuality {
        switch self {
        case .good: .medium
        case .better: .high
        case .best: .xhigh
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, imageAI, wallpapers, storage
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .imageAI: "Image AI"
        case .wallpapers: "Wallpapers"
        case .storage: "Storage"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .imageAI: "sparkles"
        case .wallpapers: "photo"
        case .storage: "externaldrive"
        }
    }
    var color: Color {
        switch self {
        case .general: .gray
        case .imageAI: .purple
        case .wallpapers: .orange
        case .storage: .blue
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    private(set) var history: [SettingsPane]
    private(set) var index = 0
    init(pane: SettingsPane) { history = [pane] }
    var pane: SettingsPane { history[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < history.count }
    func select(_ pane: SettingsPane) {
        guard pane != self.pane else { return }
        history = Array(history.prefix(index + 1)) + [pane]
        index = history.count - 1
    }
    func goBack() { if canGoBack { index -= 1 } }
    func goForward() { if canGoForward { index += 1 } }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var instance: SettingsWindowController?
    private let navigation: SettingsNavigation

    static func show(model: AppModel, pane: SettingsPane? = nil) {
        let controller: SettingsWindowController
        if let existing = instance {
            controller = existing
            if let pane { controller.navigation.select(pane) }
        } else {
            controller = SettingsWindowController(model: model, pane: pane ?? .general)
            instance = controller
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        if !AppRuntime.isPreview { NSApp.activate() }
    }

    static func closeSettings() { instance?.close() }

    private init(model: AppModel, pane: SettingsPane) {
        navigation = SettingsNavigation(pane: pane)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("daydreaming.settings")
        window.toolbarStyle = .automatic
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Daydreaming.Settings.Panes")
        window.contentViewController = NSHostingController(rootView: SettingsView(navigation: navigation).environmentObject(model))
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { Self.instance = nil }
}

struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdaterManager.shared
    @AppStorage("installationReports.isEnabled") private var sharesInstallationStatistics = true
    @AppStorage("confirmedHiddenMenuBar") private var confirmedHiddenMenuBar = false
    @State private var storageError: String?
    @State private var showingClearConfirmation = false
    @State private var showingHideMenuBarConfirmation = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: Binding<SettingsPane?>(
                get: { navigation.pane },
                set: { if let pane = $0 { navigation.select(pane) } }
            )) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(pane.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 4)
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
            .toolbar(removing: .sidebarToggle)
            .navigationTitle("Settings")
        } detail: {
            paneContent
                .navigationTitle(navigation.pane.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.left", action: navigation.goBack)
                    .disabled(!navigation.canGoBack)
                Button("Forward", systemImage: "chevron.right", action: navigation.goForward)
                    .disabled(!navigation.canGoForward)
            }
        }
    }

    private var paneContent: some View {
        Form {
            switch navigation.pane {
            case .general: generalSections
            case .imageAI: ImageConnectionSettingsView()
            case .wallpapers: wallpaperSection
            case .storage: storageSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .alert("Hide the Menu Bar Icon?", isPresented: $showingHideMenuBarConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Icon") {
                confirmedHiddenMenuBar = true
                model.showMenuBar = false
            }
        } message: {
            Text("Daydreaming keeps running without a menu bar or Dock icon. Open it from Applications or Spotlight to return. You can restore the icon in Settings.")
        }
        .alert("Clear Saved Previews and Wallpapers?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Saved Images", role: .destructive) {
                guard !model.isGenerating else { return }
                storageError = nil
                model.clearCache()
                if model.activity == .failed { storageError = model.detail }
            }
        } message: {
            Text("This deletes saved previews and wallpapers, restores your original on all screens, and pauses updates. Previous original pictures are kept. Creating replacements uses \(model.imageCreditName).")
        }
        .onChange(of: sharesInstallationStatistics) { _, enabled in
            InstallationReporter.shared.isEnabled = enabled
            if enabled { Task { _ = await InstallationReporter.shared.reportIfDue() } }
        }
    }

    private var generalSections: some View {
        Group {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Show in Menu Bar", isOn: Binding(
                    get: { model.showMenuBar },
                    set: { visible in
                        if visible || confirmedHiddenMenuBar {
                            model.showMenuBar = visible
                        } else {
                            showingHideMenuBarConfirmation = true
                        }
                    }
                ))
                Button("Run Setup Again…") {
                    if model.restartOnboarding() { SettingsWindowController.closeSettings() }
                }
                .disabled(!model.onboardingComplete || model.isGenerating)
                .help(model.isGenerating ? "Finish the current wallpaper first." : "Revisit setup with your picture and API key kept. Automatic updates pause.")
            }

            Section("App Updates") {
                Toggle("Automatically Check for Updates", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.setAutomaticallyChecks($0) }
                ))
                .disabled(!updater.isEnabled)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                if !updater.isEnabled {
                    Text("Updates will be available after the first release.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Share Installation Statistics", isOn: $sharesInstallationStatistics)
                    .help("Reports a random installation ID, app version and macOS version. Pictures, ideas and API keys are never included.")
            }
        }
    }

    private var wallpaperSection: some View {
        Group {
            Section {
                Picker("Wallpaper Quality", selection: qualitySelection) {
                    if qualitySelection.wrappedValue == nil {
                        Text("Current Settings").tag(Optional<WallpaperQuality>.none)
                    }
                    ForEach(WallpaperQuality.allCases) { quality in
                        Text(quality.rawValue).tag(Optional(quality))
                    }
                }
                .help("Desktop wallpaper quality. Previews use low quality for speed. Higher quality can cost more.")
                Text("Previews use low quality for speed.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(
                    "Images per Day: \(model.settings.dailyGenerationLimit)",
                    value: $model.settings.dailyGenerationLimit,
                    in: 1...288
                )
                .help("Maximum new previews and wallpapers per day. Reusing saved images does not count.")
                LabeledContent("Today", value: model.usageCountLabel)
                    .foregroundStyle(.secondary)
            }
            Section("Local Weather") {
                WeatherLocationControls()
                LabeledContent("Location", value: model.weatherLocationStatus)
                LabeledContent("Forecast", value: model.workspaceWeather?.label.capitalized ?? "Unavailable")
                if let weather = model.workspaceWeather {
                    LabeledContent("Retrieved", value: weather.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                if model.settings.weatherLocation == .current {
                    if model.needsWeatherLocationAccess {
                        Button("Allow Location Access…") { model.requestLocalWeatherAccess() }
                    } else {
                        Button("Refresh Location") { model.refreshWeatherLocation() }
                    }
                }
                Text("Forecast from MET Norway. Apple Maps finds places; Current Location uses your Mac’s approximate location.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let lastUpdated = model.lastUpdated {
                Section("Your Desktop") {
                    LabeledContent("Last Updated", value: lastUpdated.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private var storageSection: some View {
        Group {
            Section {
                HStack {
                    LabeledContent("Image Storage", value: model.cacheSizeLabel)
                        .help("Storage used by saved previews and wallpapers. Original pictures are stored separately.")
                    Button("Clear…", role: .destructive) { showingClearConfirmation = true }
                        .disabled(model.isGenerating)
                }
                Button(AppCopy.previousPictures) { model.openSavedWallpapers() }
                    .help(AppCopy.previousPicturesHelp)
                if let storageError { inlineError(storageError) }
            }
        }
    }

    private var qualitySelection: Binding<WallpaperQuality?> {
        Binding(
            get: {
                WallpaperQuality.allCases.first {
                    $0.imageModel == model.settings.model && $0.imageQuality == model.settings.quality
                }
            },
            set: { quality in
                guard let quality else { return }
                var settings = model.settings
                settings.model = quality.imageModel
                settings.quality = quality.imageQuality
                model.settings = settings
            }
        )
    }

    private func inlineError(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Error: \(text)")
    }
}

struct WeatherLocationControls: View {
    var compact = false
    @EnvironmentObject private var model: AppModel
    @State private var choosingFixed = false
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var picturePlace: WeatherPlace?

    private var isFixed: Bool { choosingFixed || model.settings.weatherLocation.fixedPlace != nil }
    private var originalPath: String? { model.settings.uncroppedSourcePath ?? model.settings.sourcePath }

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    controls
                    Text(model.weatherLocationStatus).font(.caption).foregroundStyle(.secondary)
                    if model.needsWeatherLocationAccess && !isFixed {
                        Button("Allow Location Access…") { model.refreshWeatherLocation() }.buttonStyle(.borderless)
                    }
                }
            } else { controls }
        }
        .task(id: originalPath) {
            picturePlace = nil
            guard let path = originalPath else { return }
            let place = await Task.detached(priority: .utility) {
                ImageStore.pictureLocation(at: URL(fileURLWithPath: path))
            }.value
            guard !Task.isCancelled, let place else { return }
            let named = await WeatherPlaceLookup.named(place)
            guard !Task.isCancelled else { return }
            picturePlace = named
        }
        .onDisappear { stopSearch() }
    }

    private var controls: some View {
        Group {
            Picker(compact ? "" : "Use weather from", selection: Binding(
                get: { isFixed },
                set: { fixed in
                    choosingFixed = fixed
                    stopSearch()
                    results = []
                    searchMessage = nil
                    if !fixed { model.setWeatherLocation(.current) }
                }
            )) {
                Text("Current Location").tag(false)
                Text("Fixed Location").tag(true)
            }
            .labelsHidden().pickerStyle(.menu)
            .accessibilityLabel("Weather location")
            .help("Current Location follows your Mac. Fixed Location always uses the weather in the place you choose.")

            if isFixed {
                HStack {
                    TextField("Town or city", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(findPlaces)
                        .accessibilityLabel("Search for a weather location")
                    Button("Search", action: findPlaces)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
                if isSearching { ProgressView("Finding places…").controlSize(.small) }
                ForEach(results.prefix(5)) { place in
                    Button { choose(place) } label: {
                        Label(place.name, systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Use the weather in this place. Does not create an image or change your desktop.")
                }
                if let searchMessage { Text(searchMessage).font(.callout).foregroundStyle(.secondary) }
                if model.settings.weatherLocation.fixedPlace == nil {
                    Text("Search and choose a place. Until then, your current location stays in use.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let picturePlace {
                    Button("Use Picture Location: \(picturePlace.name)") { choose(picturePlace) }
                        .help("Uses the GPS location saved in your original picture as a fixed weather location.")
                }
            }
        }
    }

    private func findPlaces() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stopSearch()
        results = []
        searchMessage = nil
        isSearching = true
        searchTask = Task { @MainActor in
            do {
                let places = try await WeatherPlaceLookup.search(text)
                guard !Task.isCancelled else { return }
                results = places
                searchMessage = places.isEmpty ? "No places found. Try a town and country." : nil
            } catch {
                guard !Task.isCancelled else { return }
                searchMessage = "Places could not be loaded. Try again when you’re connected."
            }
            isSearching = false
            searchTask = nil
        }
    }

    private func choose(_ place: WeatherPlace) {
        stopSearch()
        results = []
        searchMessage = nil
        query = ""
        model.setWeatherLocation(.fixed(place))
    }

    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}
