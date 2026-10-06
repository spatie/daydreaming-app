import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PictureConfirmationKeyboard {
    enum EscapeAction { case endEditing, cancelPicture }
    static func escape(isEditing: Bool) -> EscapeAction { isEditing ? .endEditing : .cancelPicture }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var editingPrompt = false
    @State private var promptDraft = ""
    @State private var promptAtEditStart = ""
    @State private var sliderHour = Double(Calendar.current.component(.hour, from: .now))
    @State private var draggingTime = false
    @State private var showsSavedPrompt = false
    @FocusState private var promptFocused: Bool
    @FocusState private var wallpaperFocused: Bool
    @FocusState private var timelineFocused: Bool
    @State private var cropDraft: PictureCrop?
    @State private var cropAtStart: PictureCrop?
    @State private var cropImageSize = CGSize(width: 16, height: 9)
    @State private var savingCrop = false
    @State private var cropError: String?
    @State private var stagedCrop: PictureCrop?
    @State private var stagedImageSize = CGSize(width: 16, height: 9)
    @State private var cropLoadRevision = 0
    @State private var promptBeforeStaging: String?
    @State private var sourceBeforeStaging: String?
    @State private var showingPromptHelp = false
    @State private var hasLoadedInstructions = false
    @State private var customizeWidth: CGFloat = 500
    @State private var galleryWidth: CGFloat = 900
    @State private var galleryHeight: CGFloat = 600
    @State private var workspaceSize = CGSize(width: 1000, height: 668)
    @State private var displayAspectRatio = 16.0 / 9.0
    @State private var displayName = "this display"
    @State private var hasMultipleDisplays = false
    @State private var waitingEffectsActive = false
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var minimumWindowSize = CGSize(width: 760, height: 560)
    @State private var logoInertia = LogoWindowInertia()

    var body: some View {
        Group {
            if model.onboardingComplete {
                wallpaper
            } else {
                OnboardingView(showingImporter: presentation(.picture))
            }
        }
        .frame(minWidth: minimumWindowSize.width, idealWidth: 1000, minHeight: minimumWindowSize.height, idealHeight: 720)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { workspaceSize = $0 }
        .background(WindowViewport(onWindowAvailable: { window in
            model.setPreviewWindow(window)
            let name = window.screen?.localizedName ?? "this display"
            let multiple = NSScreen.screens.count > 1
            let effectsActive = NSApp.isActive && window.isVisible && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            let visible = window.screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            let minimum = WallpaperWindowGeometry.minimumSize(visibleSize: visible)
            let display = window.screen?.frame.size ?? CGSize(width: 1440, height: 900)
            let ratio = display.width / max(1, display.height)
            if minimum != minimumWindowSize || ratio != displayAspectRatio || name != displayName || multiple != hasMultipleDisplays
                || effectsActive != waitingEffectsActive || lowPower != lowPowerMode {
                DispatchQueue.main.async {
                    minimumWindowSize = minimum; displayAspectRatio = ratio
                    displayName = name; hasMultipleDisplays = multiple
                    waitingEffectsActive = effectsActive; lowPowerMode = lowPower
                }
            }
        }, onWindowMoved: { origin in
            guard waitingEffectsActive, !reduceMotion, !lowPowerMode,
                  !reduceTransparency, contrast != .increased else { return }
            DispatchQueue.main.async {
                logoInertia.moved(to: origin, at: Date.timeIntervalSinceReferenceDate)
            }
        }))
        .onChange(of: waitingEffectsActive) { _, active in
            if active { Task { await model.refreshWorkspaceWeather() } }
        }
        .navigationTitle("Daydreaming")
        .toolbar { mainToolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background {
            LogoBackdrop(isActive: waitingEffectsActive, inertia: logoInertia)
                .ignoresSafeArea(.container, edges: .top)
        }
        .fileImporter(isPresented: presentation(.picture), allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                if model.onboardingComplete { model.chooseWorkspacePicture(url, prompt: promptDraft) }
                else { model.importImage(url) }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isConfirmingPicture, model.presentation != .crop, let url = urls.first, url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { return false }
            if model.onboardingComplete { model.chooseWorkspacePicture(url, prompt: promptDraft) }
            else { model.importImage(url) }
            return true
        }
        .sheet(isPresented: presentation(.customize)) {
            CustomizeView(width: customizeWidth).environmentObject(model)
        }
        .sheet(isPresented: presentation(.savedWallpapers)) {
            SavedWallpapersView(width: galleryWidth, height: galleryHeight, displayAspectRatio: displayAspectRatio,
                                displayName: hasMultipleDisplays ? displayName : nil)
                .environmentObject(model)
        }
        .onChange(of: model.presentation) { previous, presentation in
            if presentation != nil { commitPrompt(generatesDraft: false) }
            if presentation == .crop {
                cropDraft = model.settings.sourceCrop
                cropAtStart = nil
                cropError = nil
                promptFocused = false
            }
            if presentation == .customize {
                customizeWidth = min(500, max(320, workspaceSize.width))
            }
            if presentation == .savedWallpapers {
                galleryWidth = min(900, max(360, workspaceSize.width))
                galleryHeight = min(600, max(420, workspaceSize.height - 40))
            }
            if previous == .crop && presentation == nil { wallpaperFocused = true }
        }
        .onChange(of: model.stagedPictureURL) { previous, staged in
            stagedCrop = model.stagedPictureCrop
            cropLoadRevision = 0
            if staged != nil {
                if previous == nil { promptBeforeStaging = promptDraft; sourceBeforeStaging = model.settings.sourcePath }
                if let instructions = model.stagedPictureInstructions { promptDraft = PromptRenderer.editableText(instructions) }
                model.cancelPromptUpdate()
                promptFocused = false
                editingPrompt = false
            } else {
                if previous != nil {
                    promptDraft = PromptRenderer.editableText(model.settings.promptTemplate)
                }
                promptBeforeStaging = nil
                sourceBeforeStaging = nil
            }
        }
        .onChange(of: model.selectedPreviewHour) { _, hour in
            sliderHour = Double(hour ?? Calendar.current.component(.hour, from: .now))
        }
        .onDisappear { commitPrompt(generatesDraft: false); model.pictureChoiceWindowClosed(); model.cancelPromptUpdate(); AppDelegate.commitMainPrompt = nil; model.backToNow() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow { model.pictureChoiceWindowClosed(window) }
        }
        .onKeyPress(.escape) {
            guard model.isBrowsingSavedVariations, !promptFocused else { return .ignored }
            model.backToLivePreview()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard model.onboardingComplete, model.presentation == nil, model.stagedPictureURL == nil, wallpaperFocused, !editingPrompt else { return .ignored }
            stepHour(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard model.onboardingComplete, model.presentation == nil, model.stagedPictureURL == nil, wallpaperFocused, !editingPrompt else { return .ignored }
            stepHour(1)
            return .handled
        }
        .onAppear {
            AppDelegate.openMainWindow = { openWindow(id: "main") }
            AppDelegate.commitMainPrompt = { commitPrompt() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-design-preview") {
                let args = ProcessInfo.processInfo.arguments
                if !args.contains("-snapshot-to") { NSApp.activate() }
                if let index = args.firstIndex(of: "-preview-settings"), args.indices.contains(index + 1),
                   Bundle.main.bundleIdentifier?.hasPrefix("be.spatie.daydreaming.preview") == true {
                    SettingsWindowController.show(model: model, pane: SettingsPane(rawValue: args[index + 1]) ?? .general)
                }
                DesignSnapshot.captureIfRequested()
            }
            #endif
        }
    }

    private var wallpaper: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                creativeSidebar
                    .frame(width: workspaceSize.width < 860 ? 240 : 280)
                Divider()
                previewWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var hasPicture: Bool { model.stagedPictureURL != nil || model.sourceImageURL != nil }
    private var isCropping: Bool { model.presentation == .crop }
    private var sidebarPictureURL: URL? { model.stagedPictureURL ?? model.sourceImageURL }
    private var compactWorkspace: Bool { workspaceSize.height < 600 }

    private var creativeSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compactWorkspace ? 18 : 28) {
                VStack(alignment: .leading, spacing: 12) {
                    CreationStepHeading(number: 1, title: "Your picture")
                    Button { choosePicture() } label: {
                        Group {
                            if let url = sidebarPictureURL {
                                WallpaperPreview(url: url, label: "Change your original picture", fillsFrame: true)
                            } else {
                                VStack(spacing: 10) {
                                    Image(systemName: "photo").font(.title2.weight(.light))
                                    Text("Choose a picture…").font(.callout.weight(.medium))
                                    Text("or drop one anywhere in this window")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.accentColor.opacity(0.035))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                }
                            }
                        }
                        .frame(height: compactWorkspace ? 100 : 140)
                        .clipShape(.rect(cornerRadius: 9))
                        .contentShape(.rect(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hasPicture ? "Change picture" : "Choose a picture")
                    .help("Choose a picture, or drop one anywhere in this window.")
                    if hasPicture {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(model.stagedPictureURL != nil ? model.stagedPictureName : model.sourceImageName)
                                .font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Button("Change…") { choosePicture() }.buttonStyle(.borderless).font(.caption)
                        }
                        Text("Or drop a picture anywhere.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your picture")
                VStack(alignment: .leading, spacing: 10) {
                    promptHeading
                    promptEditor
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your idea")
                WallpaperFrequencyPicker()
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency || contrast == .increased ? 1 : 0.5))
        .disabled(isCropping || model.isConfirmingPicture)
    }

    private var previewWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if isCropping { Text("Crop your original").font(.headline) }
                    else { CreationStepHeading(number: 4, title: "Preview") }
                    if !isCropping {
                        if let caption = model.savedVariationCaption ?? model.shownPictureDescription {
                            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if let made = model.shownPictureCreationDescription {
                            Text(made).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if hasPicture && !isCropping {
                    Button("Crop picture", systemImage: "crop") {
                        commitPrompt(generatesDraft: false)
                        promptFocused = false
                        model.presentation = .crop
                    }
                    .disabled(model.stagedPictureURL != nil || model.uncroppedImageURL == nil)
                    .help("Frame your original picture here, before making new variations.")
                }
            }
            Group {
                if isCropping, let source = model.uncroppedImageURL {
                    CropPictureView(sourceURL: source, screenAspectRatio: displayAspectRatio,
                                    showsActions: false, showsControls: false,
                                    onSelectionChange: { crop in
                                        cropDraft = crop
                                    }, onBaselineChange: { cropAtStart = $0 }, onImageSizeChange: { cropImageSize = $0 },
                                    initialCrop: cropDraft, onClose: nil, imageCopy: model.imageCopy) { _ in }
                        .disabled(savingCrop)
                } else if hasPicture { artwork }
                else { emptyPreview }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isCropping {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drag to move. Pinch or scroll to zoom.")
                        .font(.caption).foregroundStyle(.secondary)
                    cropZoom
                }
                .disabled(savingCrop)
            } else if hasPicture {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Preview the day").font(.callout.weight(.medium))
                            Spacer()
                        }
                        Text(model.imageCopy.previewTimeNotice)
                            .font(.caption).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        timeSlider(now: timeline.date)
                    }
                    .onChange(of: timeline.date) { _, date in
                        if model.selectedPreviewHour == nil && !draggingTime {
                            sliderHour = Double(Calendar.current.component(.hour, from: date))
                        }
                    }
                }
                .disabled(model.stagedPictureURL != nil)
            }
            Divider()
            confirmationBar
        }
        .padding(compactWorkspace ? 20 : 28)
    }

    private var emptyPreview: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text("Choose a picture to see it change through the day.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try it with Yosemite Valley") {
                if let url = model.builtInPictureURL { model.chooseWorkspacePicture(url, prompt: promptDraft) }
            }
            .buttonStyle(.borderless)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1) }
    }

    private var artwork: some View {
        WallpaperPreview(url: model.canvasImageURL, label: previewAccessibilityLabel,
                         fullBleed: true, displayAspectRatio: displayAspectRatio,
                         preloadURLs: model.previewNeighbourURLs)
            .blur(radius: shouldObscureArtwork ? 12 : 0)
            .opacity(shouldObscureArtwork ? 0.35 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: shouldObscureArtwork)
            .overlay {
                if showsPreviewWaiting {
                    DreamingArtwork(url: model.canvasImageURL, displayAspectRatio: displayAspectRatio,
                                    isActive: waitingEffectsActive, lowPowerMode: lowPowerMode)
                        .allowsHitTesting(false)
                }
            }
            .background(PreviewSavedVariationScrolling(
                enabled: !isCropping && model.stagedPictureURL == nil && !model.savedVariationsForSelectedPicture.isEmpty,
                onStep: { model.browseSavedVariation(direction: $0) }))
            .help("Scroll up or down over the preview to browse saved variations of this picture.")
            .accessibilityValue(model.shownPictureAccessibilityDescription)
            .accessibilityAdjustableAction { direction in
                model.browseSavedVariation(direction: direction == .increment ? 1 : -1)
            }
            .focusable()
            .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
            .focused($wallpaperFocused)
            .overlay {
                if shouldObscureArtwork {
                    if showsPreviewWaiting {
                        PreviewWaitingView(title: waitingTitle, isActive: waitingEffectsActive && !lowPowerMode)
                            .allowsHitTesting(false)
                    } else {
                        VStack(spacing: 12) {
                            Text(model.previewHeadline).font(.headline)
                            if let reason = model.draftCreationUnavailableReason {
                                Text(reason).font(.callout).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            if model.hasImageConnection && model.canCreateDraft {
                                Button("Make Preview") { model.schedulePreviewGeneration(hour: displayedHour, explicit: true) }
                                    .help(model.usageHelp)
                            } else if model.hasImageConnection {
                                Button("Change Limit…") { SettingsWindowController.show(model: model, pane: .wallpapers) }.buttonStyle(.borderless)
                            }
                        }
                        .padding(22).frame(maxWidth: 320)
                        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1) }
                    }
                }
            }
    }

    private var shouldObscureArtwork: Bool {
        showsPreviewWaiting || (model.previewPresentation.resultURL == nil && model.selectedPreviewHour != nil)
    }

    private var showsPreviewWaiting: Bool {
        if model.stagedPictureURL != nil && model.stagedPictureError == nil { return true }
        #if DEBUG
        if model.isGenerating, ProcessInfo.processInfo.arguments.contains("-design-preview") { return true }
        #endif
        return model.isCreatingVisiblePreview
    }

    private var waitingTitle: String {
        if model.stagedPictureURL != nil { return "Preparing your picture…" }
        if model.currentSavedWallpaperEntry == nil && model.selectedPreviewHour == nil { return "Making your first preview…" }
        return "Making a preview for \(model.hourLabel(displayedHour))…"
    }

    private var promptHeading: some View {
        HStack(spacing: 6) {
            CreationStepHeading(number: 2, title: "Your idea")
            Button { showingPromptHelp.toggle() } label: {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About your idea")
            .help(model.imageCopy.ideaHelp)
            .popover(isPresented: $showingPromptHelp) {
                Text(model.imageCopy.ideaHelp)
                    .padding(16).frame(width: 270)
            }
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $promptDraft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: compactWorkspace ? 84 : 102)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(promptFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1) }
                .focused($promptFocused)
                .onExitCommand {
                    if model.isBrowsingSavedVariations { model.backToLivePreview(); return }
                    model.cancelPromptUpdate()
                    promptDraft = promptAtEditStart
                    editingPrompt = false
                    promptFocused = false
                }
                .onChange(of: promptFocused) { _, focused in
                    if focused {
                        editingPrompt = true; promptAtEditStart = promptDraft
                    } else { commitPrompt() }
                }
                .onChange(of: promptDraft) { _, draft in
                    if promptFocused && model.stagedPictureURL == nil && !isCropping {
                        model.schedulePromptUpdate(draft: draft)
                    }
                }
                .onAppear {
                    if !hasLoadedInstructions {
                        promptDraft = PromptRenderer.editableText(model.settings.promptTemplate)
                        hasLoadedInstructions = true
                    }
                }
                .onChange(of: model.settings.promptTemplate) { _, prompt in
                    if !promptFocused && model.stagedPictureURL == nil { promptDraft = PromptRenderer.editableText(prompt) }
                }
                .accessibilityLabel("Your idea")
                .accessibilityHint("Describe how your picture should change. When you stop typing, a preview is created using \(model.imageCreditName). \(AppCopy.usePictureAndIdeaAsWallpaper) starts automatic updates.")
                .dropDestination(for: URL.self) { urls, _ in
                    guard !isCropping, model.stagedPictureURL == nil, let file = urls.first else { return false }
                    if UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true {
                        commitPrompt(generatesDraft: false)
                        model.chooseWorkspacePicture(file, prompt: promptDraft)
                        return true
                    }
                    guard PromptFileReader.isSupported(file) else { return false }
                    commitPrompt(generatesDraft: false)
                    model.addPromptFile(file)
                    promptDraft = PromptRenderer.editableText(model.settings.promptTemplate)
                    return true
                }
            Text(model.imageCopy.ideaPreviewNotice)
                .font(.caption).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmationBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { footerStatus }
            if isCropping {
                HStack {
                    Button("Reset") { cropDraft = PictureCrop(imageSize: cropImageSize, targetAspectRatio: displayAspectRatio) }.disabled(savingCrop)
                    Spacer()
                    Button("Cancel", role: .cancel) { model.presentation = nil }
                        .keyboardShortcut(.cancelAction).disabled(savingCrop)
                    Button(savingCrop ? "Saving…" : "Done") { finishCrop() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(cropDraft == nil || savingCrop)
                        .help(model.imageCopy.cropDoneNotice(hasChanges: cropHasChanges))
                }
            } else {
                HStack { Spacer(); wallpaperDecision.fixedSize(horizontal: true, vertical: false) }
                .disabled(model.stagedPictureURL != nil && model.stagedPictureError == nil)
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder private var wallpaperDecision: some View {
        if model.isBrowsingSavedVariations {
            Button("Back to Live") { model.backToLivePreview() }.buttonStyle(.borderedProminent)
        } else if let error = model.stagedPictureError {
            Button("Cancel", role: .cancel) { model.cancelStagedPicture() }
            Button("Try Again") {
                if let url = model.stagedPictureURL { model.chooseWorkspacePicture(url, prompt: promptDraft) }
            }.buttonStyle(.borderedProminent).help(error)
        } else if let recovery = model.recovery, model.activity == .failed && !model.isGenerating {
            Button(recoveryTitle(recovery)) { recover(recovery) }.buttonStyle(.borderedProminent)
        } else if hasPicture && !model.hasImageConnection {
            Button("Add API Key…") { SettingsWindowController.show(model: model, pane: .imageAI) }.buttonStyle(.borderedProminent)
        } else if hasPicture { useWallpaperButton }
    }

    @ViewBuilder private var footerStatus: some View {
        if isCropping {
            if let cropError { Text(cropError).foregroundStyle(.red).lineLimit(2) }
            else {
                Text(model.imageCopy.cropDoneNotice(hasChanges: cropHasChanges))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.isBrowsingSavedVariations {
            Text("Browsing saved variations").font(.callout).foregroundStyle(.secondary)
        } else if let warning = model.sourceWarning {
            Text(warning).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button { model.dismissSourceWarning() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).accessibilityLabel("Dismiss warning")
        } else if model.activity == .failed {
            Text(model.detail.isEmpty ? model.status : model.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        } else if model.isMakingCurrentWallpaper || model.isAdoptingWallpaper {
            ProgressView().controlSize(.small)
            Text("Making your wallpaper…").font(.callout).foregroundStyle(.secondary)
        } else if let notice = model.previewGenerationNotice {
            Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button("Change Limit…") { SettingsWindowController.show(model: model, pane: .wallpapers) }.buttonStyle(.borderless).font(.caption)
        }
        if !isCropping, let title = model.queueCancellationTitle {
            Button(title) { model.cancelQueue() }.buttonStyle(.borderless).font(.caption)
        }
    }

    @ViewBuilder private var useWallpaperButton: some View {
        if model.isCurrentRecipeAdopted && !promptHasChanges {
            wallpaperConfirmationButton.buttonStyle(.bordered)
        } else {
            wallpaperConfirmationButton.buttonStyle(.borderedProminent)
        }
    }

    private var wallpaperConfirmationButton: some View {
        Button(AppCopy.usePictureAndIdeaAsWallpaper) {
            commitPrompt(force: true, generatesDraft: false)
            promptFocused = false
            model.closeWallpaperWindow()
            Task { await model.adoptDisplayedPictureAsWallpaper() }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canConfirmWallpaper)
        .help(wallpaperActionHelp)
        .accessibilityHint(wallpaperActionHelp)
    }

    private var wallpaperActionHelp: String {
        model.isCurrentRecipeAdopted && !promptHasChanges
            ? "This picture and idea are already your wallpaper. Returns to the current time without creating another image."
            : "Creates a full-quality wallpaper now and keeps it changing with the time and weather. Uses \(model.imageCreditName)."
    }

    private var cropHasChanges: Bool {
        guard let cropDraft, let cropAtStart else { return false }
        return !cropDraft.matchesFraming(cropAtStart)
    }

    private var cropZoom: some View {
        HStack(spacing: 10) {
            Button { adjustCropZoom(by: 1 / 1.15) } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless).accessibilityLabel("Zoom out")
            Slider(value: Binding(get: {
                cropDraft?.controls(imageSize: cropImageSize, targetAspectRatio: displayAspectRatio).zoom ?? 1
            }, set: { zoom in
                guard let cropDraft else { return }
                let current = cropDraft.controls(imageSize: cropImageSize, targetAspectRatio: displayAspectRatio).zoom
                self.cropDraft = cropDraft.scaled(by: current / zoom)
            }), in: 1...4) { Text("Zoom") }.labelsHidden().accessibilityLabel("Picture zoom")
            Button { adjustCropZoom(by: 1.15) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).accessibilityLabel("Zoom in")
        }
    }

    private func adjustCropZoom(by factor: CGFloat) {
        guard let cropDraft else { return }
        let zoom = cropDraft.controls(imageSize: cropImageSize, targetAspectRatio: displayAspectRatio).zoom
        let target = min(4, max(1, zoom * factor))
        self.cropDraft = cropDraft.scaled(by: zoom / target)
    }

    private func finishCrop() {
        guard !savingCrop, let cropDraft else { return }
        guard cropHasChanges else { model.presentation = nil; return }
        savingCrop = true
        Task {
            do { try await model.completeCrop(cropDraft, displayAspectRatio: displayAspectRatio) }
            catch { cropError = error.localizedDescription }
            savingCrop = false
        }
    }

    @ToolbarContentBuilder private var mainToolbar: some ToolbarContent {
        if model.onboardingComplete {
            ToolbarItem(placement: .automatic) {
                Button { model.openSavedWallpapers() } label: {
                    Image(systemName: "photo.stack")
                }
                    .accessibilityLabel("Previous pictures")
                    .disabled(isCropping || model.stagedPictureURL != nil)
                    .help("Previous original pictures and their ideas")
            }
        }
    }

    private func choosePicture() {
        commitPrompt(generatesDraft: false)
        model.presentation = .picture
    }

    private func timeSlider(now: Date) -> some View {
        Slider(value: Binding(get: { sliderHour }, set: { value in
            sliderHour = value
            let hour = SliderInteractionPolicy.clampedHour(value)
            selectHour(hour)
            if !draggingTime { model.endScrubbingPreview(hour: hour) }
        }), in: 0...23, step: 1, onEditingChanged: { editing in
            draggingTime = editing
            if editing { model.beginScrubbingPreview() }
            else { model.endScrubbingPreview(hour: SliderInteractionPolicy.clampedHour(sliderHour)) }
        }) { Text("Preview the day") }
        .labelsHidden()
        .focused($timelineFocused)
        .overlay(alignment: .topLeading) {
            if draggingTime || timelineFocused {
                GeometryReader { geometry in
                    Text(model.hourLabel(SliderInteractionPolicy.clampedHour(sliderHour)))
                        .font(.caption.monospacedDigit()).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.regularMaterial, in: .rect(cornerRadius: 6))
                        .fixedSize()
                        .position(x: 8 + (geometry.size.width - 16) * sliderHour / 23, y: -12)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 4) {
            GeometryReader { geometry in
                ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                    Text(model.hourLabel(hour)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: 60, alignment: hour == 0 ? .leading : hour == 23 ? .trailing : .center)
                        .offset(x: hour == 0 ? 22 : hour == 23 ? -22 : 0)
                        .position(x: 8 + (geometry.size.width - 16) * Double(hour) / 23, y: 8)
                }
            }.frame(height: 18).accessibilityHidden(true)
        }
        .accessibilityValue(sliderAccessibilityValue)
        .help(model.imageCopy.previewTimeHelp)
        .accessibilityHint(model.imageCopy.previewTimeHelp)
    }

    private var sliderAccessibilityValue: String {
        if model.isBrowsingSavedVariations {
            let hour = model.selectedPreviewHour ?? Calendar.current.component(.hour, from: .now)
            return "\(model.hourLabel(hour)), live preview time. Change it to return to live preview."
        }
        let presentation = model.previewPresentation
        let state: String
        if presentation.state == .onDesktop,
           model.currentSavedWallpaperEntry?.hour != displayedHour {
            state = "showing the existing desktop image"
        } else {
            switch presentation.state {
            case .creating: state = "creating"
            case .preparing: state = "preparing"
            case .queued: state = "queued"
            case .stale: state = "saved image, awaiting an updated preview"
            case .ready: state = "preview ready"
            case .onDesktop: state = "showing the desktop image"
            case .original: state = "showing the original picture"
            case .missing: state = "no preview yet"
            }
        }
        return "\(model.hourLabel(displayedHour)), \(model.selectedPreviewHour == nil ? "Now, " : "")\(state)"
    }

    private var previewAccessibilityLabel: String {
        model.selectedSavedWallpaper == nil ? "Picture preview" : "Saved variation"
    }

    private func selectHour(_ hour: Int) {
        if hour == Calendar.current.component(.hour, from: .now) { model.backToNow() }
        else { model.setPreviewHour(hour) }
    }

    private func stepHour(_ direction: Int) {
        if model.isBrowsingSavedVariations {
            model.browseSavedVariation(direction: direction)
            return
        }
        let next = min(23, max(0, displayedHour + direction))
        sliderHour = Double(next)
        selectHour(next)
        model.endScrubbingPreview(hour: next)
    }

    private func commitPrompt(force: Bool = false, generatesDraft: Bool = true) {
        guard model.stagedPictureURL == nil else { return }
        let edited = editingPrompt && promptDraft != promptAtEditStart
        guard edited || (force && promptHasChanges) else { editingPrompt = promptFocused; return }
        editingPrompt = promptFocused
        model.savePrompt(promptDraft, generatesDraft: generatesDraft && !isCropping && model.presentation == nil)
        promptAtEditStart = promptDraft
        if promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptDraft = PromptRenderer.editableText(model.settings.promptTemplate)
        }
    }

    private var promptHasChanges: Bool {
        !promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                != PromptRenderer.editableText(model.settings.promptTemplate).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedHour: Int {
        if model.isBrowsingSavedVariations, let saved = model.selectedSavedWallpaper { return saved.entry.hour }
        return model.selectedPreviewHour ?? Calendar.current.component(.hour, from: .now)
    }

    private func presentation(_ value: MainPresentation) -> Binding<Bool> {
        Binding(get: { model.presentation == value }, set: { shown in
            if shown { model.presentation = value }
            else if model.presentation == value { model.presentation = nil }
        })
    }

    private func recoveryTitle(_ recovery: WallpaperRecovery) -> String {
        if recovery == .apiKey && !model.hasImageConnection { return "Add API Key…" }
        if recovery == .weather { return "Allow Location…" }
        if recovery == .billing { return "Check Provider Billing…" }
        return recovery.title
    }

    private func recover(_ recovery: WallpaperRecovery) {
        commitPrompt()
        switch recovery {
        case .image: model.presentation = .picture
        case .retry: model.retryUpdate()
        case .weather: model.requestLocalWeatherAccess()
        case .apiKey: SettingsWindowController.show(model: model, pane: .imageAI)
        case .billing:
            if let url = model.imageProviderDescriptor?.billingURL { NSWorkspace.shared.open(url) }
            else { SettingsWindowController.show(model: model, pane: .imageAI) }
                }
        NSApp.activate()
    }
}
