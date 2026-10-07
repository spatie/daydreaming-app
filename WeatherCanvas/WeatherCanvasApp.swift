import AppKit
import SwiftUI

@main
struct DaydreamingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        if AppRuntime.isPreview && !AppRuntime.isRunningTests && !ProcessInfo.processInfo.arguments.contains("-design-preview") {
            // LaunchServices can omit fixture arguments. Never initialize production services.
            exit(EXIT_SUCCESS)
        }
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        UpdaterManager.shared.observeImageWork(model.$isGenerating)
        UpdaterManager.shared.beforeInstallation = { [weak model] in model?.prepareForAppUpdate() }
    }

    var body: some Scene {
        Window("Daydreaming", id: "main") {
            ContentView().environmentObject(model)
        }
        .defaultLaunchBehavior(AppRuntime.isRunningTests && !ProcessInfo.processInfo.arguments.contains("-design-preview") ? .suppressed : .automatic)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.automatic)
        .defaultSize(width: 1000, height: 720)
        .commands { DaydreamingCommands(model: model) }

        MenuBarExtra(isInserted: Binding(
            get: { model.showMenuBar },
            set: { if model.showMenuBar != $0 { model.showMenuBar = $0 } }
        )) { MenuBarContent().environmentObject(model) } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel(model.hasMenuActivity ? "Daydreaming · Generating" : "Daydreaming")
        }
    }
}

private struct DaydreamingCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject private var updater = UpdaterManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Daydreaming") { CommunityWindowController.showAbout() }
        }
        CommandGroup(replacing: .help) {
            Button("Daydreaming Help") { NSWorkspace.shared.open(URL(string: "https://getdaydreaming.com/support")!) }
            Button(AppCopy.askForAFeature) { CommunityWindowController.showSubmission() }
            Divider()
            Button("Send Us a Postcard…") { CommunityWindowController.showAbout(postcard: true) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindowController.show(model: model) }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("Choose Picture…") { present(.picture) }
                .keyboardShortcut("o")
                .disabled(model.presentation == .crop)
        }
        CommandMenu("Wallpaper") {
            Button(model.queueCancellationTitle ?? "Cancel Queued Wallpapers") { model.cancelQueue() }
                .disabled(model.queueCancellationTitle == nil)
            Button("Customize…") { present(.customize) }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(model.presentation == .crop || !model.onboardingComplete)
            Button("Previous Pictures…") { model.openSavedWallpapers() }
                .disabled(model.presentation == .crop || !model.onboardingComplete)
            Button("Open Picture & Idea in Codex…") { Task { await model.createInCodex() } }
                .disabled(model.codexHandoffRequest == nil || model.isPreparingCodexHandoff)
                .help("Review and send your picture and idea in the Codex app. Automatic updates use the AI selected in Settings.")
            Button("Crop Picture…") { present(.crop) }
                .disabled(model.presentation == .crop || !model.onboardingComplete || model.uncroppedImageURL == nil)
            Divider()
            Button("Update Now") { Task { await model.refreshIfNeeded(userInitiated: true) } }
                .keyboardShortcut("r")
                .help("Creates a full-quality wallpaper for the current time. Uses \(model.imageCreditName).")
                .disabled(model.presentation == .crop || !model.canGenerate || model.isMakingCurrentWallpaper || model.stagedPictureURL != nil)
            Toggle("Refresh Wallpaper Automatically", isOn: model.automaticUpdatesMenuBinding)
            .disabled(model.presentation == .crop)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!model.onboardingComplete || !model.hasSavedKey || model.sourceImageURL == nil)

        }
    }

    private func present(_ presentation: MainPresentation) {
        guard model.presentation != .crop else { return }
        openWindow(id: "main")
        model.presentation = presentation
        NSApp.activate()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openMainWindow: (() -> Void)?
    static var commitMainPrompt: (() -> Void)?
    private let updater = UpdaterManager.shared
    private var installationReportingTask: Task<Void, Never>?
    private var windowObservers: [NSObjectProtocol] = []
    private var closingWindows = Set<ObjectIdentifier>()

    func applicationWillFinishLaunching(_ notification: Notification) {
        updater.onPresentationChanged = { [weak self] in self?.updateDockPresence() }
        NSWindow.allowsAutomaticWindowTabbing = false
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification]
        for name in names {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let windowID = (notification.object as? NSWindow).map(ObjectIdentifier.init)
                let isClosing = notification.name == NSWindow.willCloseNotification
                let isBecomingKey = notification.name == NSWindow.didBecomeKeyNotification
                MainActor.assumeIsolated {
                    if let windowID {
                        if isClosing { self?.closingWindows.insert(windowID) }
                        if isBecomingKey { self?.closingWindows.remove(windowID) }
                    }
                    self?.updateDockPresence()
                }
            })
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater.start()
        updateDockPresence()
        #if !DEBUG
        guard !AppRuntime.isPreview, !AppRuntime.isRunningTests else { return }
        installationReportingTask = Task {
            while !Task.isCancelled {
                _ = await InstallationReporter.shared.reportIfDue()
                do { try await Task.sleep(for: .seconds(3_600)) }
                catch { return }
            }
        }
        #endif
    }

    private func updateDockPresence() {
        guard !AppRuntime.isRunningTests else { return }
        #if DEBUG
        // Background drawing fixtures must not change the owner's foreground application.
        if AppRuntime.isPreview && ProcessInfo.processInfo.arguments.contains("-snapshot-to") { return }
        #endif
        // Occlusion is deliberately ignored: another app covering Daydreaming should not hide it from the Dock.
        let windows = NSApp.windows.map { window in
            DockPresencePolicy.WindowState(isAuxiliary: window is NSPanel, isTitled: window.styleMask.contains(.titled),
                                           isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                                           isClosing: closingWindows.contains(ObjectIdentifier(window)))
        }
        let policy: NSApplication.ActivationPolicy = (updater.isPresentingUpdateUI || DockPresencePolicy.showsDock(for: windows)) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .regular, !AppRuntime.isPreview { NSApp.activate() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        installationReportingTask?.cancel()
        InstallationReporter.shared.cancelPendingReport()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.commitMainPrompt?()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Self.openMainWindow?()
        sender.activate()
        return true
    }
}

enum DockPresencePolicy {
    struct WindowState {
        var isAuxiliary = false
        var isTitled = true
        var isVisible = true
        var isMiniaturized = false
        var isClosing = false
    }
    static func showsDock(for windows: [WindowState]) -> Bool {
        windows.contains { !$0.isAuxiliary && $0.isTitled && !$0.isClosing && ($0.isVisible || $0.isMiniaturized) }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Daydreaming…") { showMainWindow() }
        if model.onboardingComplete {
            Button("Settings…") {
                NSApp.activate()
                SettingsWindowController.show(model: model)
            }
            Divider()
            Button("Update Now") { Task { await model.refreshIfNeeded(userInitiated: true) } }
                .help("Creates a full-quality wallpaper for the current time. Uses \(model.imageCreditName).")
                .disabled(model.presentation == .crop || !model.canGenerate || model.isMakingCurrentWallpaper || model.stagedPictureURL != nil)
            Toggle("Refresh Wallpaper Automatically", isOn: model.automaticUpdatesMenuBinding)
            .disabled(model.presentation == .crop)
            .disabled(!model.hasSavedKey || model.sourceImageURL == nil)
            if let title = model.queueCancellationTitle {
                Button(title) { model.cancelQueue() }
            }
        }
        Divider()
        Button(AppCopy.askForAFeature) { CommunityWindowController.showSubmission() }
        Divider()
        Button("Quit Daydreaming") { NSApp.terminate(nil) }
        Divider()
        Text(model.menuUpdateStatus ?? "Ready when you are")
            .help([model.detail, model.lastGenerationMenuLabel].filter { !$0.isEmpty }.joined(separator: "\n"))
            .disabled(true)
        Label(model.menuWeatherStatus, systemImage: model.workspaceWeather?.symbol ?? "cloud")
            .help("Weather data: MET Norway. Uses the latest local forecast.")
            .disabled(true)
    }

    private func present(_ presentation: MainPresentation) {
        showMainWindow()
        model.presentation = presentation
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

private extension AppModel {
    var automaticUpdatesMenuBinding: Binding<Bool> {
        Binding(
            get: { self.settings.automaticUpdates },
            set: { isEnabled in
                if isEnabled { self.startAutomatic() }
                else { self.stopAutomatic() }
            }
        )
    }
}

@MainActor
private enum MenuBarIcon {
    static let image: NSImage = {
        let original = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "Daydreaming")!
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            original.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            return true
        }
        image.isTemplate = true
        return image
    }()
}
