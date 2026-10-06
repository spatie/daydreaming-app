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

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdaterManager.shared
    @AppStorage("installationReports.isEnabled") private var sharesInstallationStatistics = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage("confirmedHiddenMenuBar") private var confirmedHiddenMenuBar = false
    @State private var keyDraft = ""
    @State private var isEditingKey = false
    @State private var keyError: String?
    @State private var storageError: String?
    @State private var showingClearConfirmation = false
    @State private var showingKeyRemoval = false
    @State private var showingHideMenuBarConfirmation = false
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        Form {
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
                    if model.restartOnboarding() { dismiss() }
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

            Section("OpenAI API Key") {
                if let message = model.keyRecoveryMessage { inlineError(message) }
                if model.hasSavedKey {
                    HStack {
                        Label("OpenAI key saved", systemImage: "key.fill")
                        Spacer()
                        if !isEditingKey {
                            Button("Replace…") {
                                keyError = nil
                                isEditingKey = true
                                keyFieldFocused = true
                            }
                        }
                        Button("Remove…", role: .destructive) { showingKeyRemoval = true }
                            .disabled(model.isGenerating)
                    }
                }
                if !model.hasSavedKey || isEditingKey {
                    HStack {
                        SecureField(model.hasSavedKey ? "Replacement key" : "OpenAI API key", text: $keyDraft)
                            .focused($keyFieldFocused)
                            .onSubmit { saveKey() }
                        if model.hasSavedKey {
                            Button("Cancel") { cancelKeyEditing() }
                                .keyboardShortcut(.cancelAction)
                        }
                        Button("Save") { saveKey() }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                if let keyError { inlineError(keyError) }
                HStack {
                    Text("Stored in Keychain.")
                    Spacer()
                    Link("Manage Keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                }
                .font(.caption).foregroundStyle(.secondary)
            }

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
            } footer: {
                Text("Creating sends your picture and prompt context to OpenAI. OpenAI bills your API key for each new image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 540, idealHeight: 600)
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
            Text("This deletes saved previews and wallpapers, restores your original on all screens, and pauses updates. Previous original pictures are kept. Creating replacements uses OpenAI credit.")
        }
        .alert("Remove Your OpenAI API Key?", isPresented: $showingKeyRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Key", role: .destructive) {
                guard !model.isGenerating else { return }
                model.removeKey()
                keyError = model.hasSavedKey ? model.detail : nil
                cancelKeyEditing()
            }
        } message: {
            Text("Updates will pause. Your current wallpaper and saved pictures stay on this Mac. You can add a key again later.")
        }
        .onChange(of: sharesInstallationStatistics) { _, enabled in
            InstallationReporter.shared.isEnabled = enabled
            if enabled { Task { _ = await InstallationReporter.shared.reportIfDue() } }
        }
        .onDisappear { cancelKeyEditing() }
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

    private func saveKey() {
        guard !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        keyError = nil
        if model.saveKey(keyDraft) {
            cancelKeyEditing()
        } else {
            keyError = model.detail
        }
    }

    private func cancelKeyEditing() {
        keyDraft = ""
        isEditingKey = false
        keyFieldFocused = false
    }

    private func inlineError(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Error: \(text)")
    }
}
