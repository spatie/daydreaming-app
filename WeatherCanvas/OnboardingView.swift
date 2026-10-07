import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showingImporter: Bool
    @State private var step = 0
    @State private var key = ""
    @State private var error: String?
    @State private var connectionTask: Task<Void, Never>?
    @FocusState private var keyFocused: Bool

    private let steps = ["Welcome", "Your picture", "Image creation", "Ready"]
    private var primaryTitle: String {
        if model.isCheckingImageConnection { return "Checking…" }
        if step == 1 && model.isBuiltInPictureChosen { return "Continue with Yosemite" }
        if step == 3 {
            if model.onboardingWeatherReady { return "Start Daydreaming" }
            switch model.onboardingLocationState {
            case .notRequested: return "Allow Location Access"
            case .denied: return "Open System Settings"
            case .requesting, .allowed: return "Start Daydreaming"
            }
        }
        return "Continue"
    }
    private var canContinue: Bool {
        guard !model.isImportingPicture, !model.isCheckingImageConnection else { return false }
        return switch step {
        case 0: true
        case 1: model.sourceImageURL != nil
        case 2: model.hasSavedKey || !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: model.onboardingWeatherReady ? model.canGenerate
            : model.onboardingLocationState == .notRequested || model.onboardingLocationState == .denied
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")

            if step == 0 {
                welcome
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    artwork.frame(minWidth: 220, minHeight: 200)
                    stepContent.frame(width: 300)
                }
                VStack(spacing: 20) {
                    artwork.frame(height: 190)
                    stepContent
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack(spacing: 16) {
                Button("Skip Setup") { connectionTask?.cancel(); model.skipOnboarding() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(model.isCheckingImageConnection)
                    .help("Open Daydreaming without creating an image. Connect your image AI later in Settings.")
                if step > 0 {
                    Button("Back") { move(to: step - 1) }
                        .disabled(model.isCheckingImageConnection)
                        .keyboardShortcut("[", modifiers: .command)
                }
                if step == 3 {
                    Button("Not Now") { model.finishOnboarding(createFirstWallpaper: false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(primaryTitle, action: advance)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
            .controlSize(.large)
            .padding(22)
        }
        .onAppear {
            model.useLocalWeather()
            model.useBuiltInPicture(replaceCurrent: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if step == 3 { model.refreshOnboardingLocation() }
        }
        .onDisappear { connectionTask?.cancel() }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Text("See your old wallpaper in a new light.")
                .font(.system(size: 32, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)
            Text("Daydreaming uses AI to match your picture to the time and local weather, then sets it as your Mac wallpaper.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 490)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    welcomeImage("WelcomeDay", label: "Day")
                    welcomeImage("WelcomeNight", label: "Night")
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(.rect(cornerRadius: 16))
            }
            .frame(maxWidth: 640, maxHeight: 280)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("The same Yosemite picture in daylight and at night. An example of how Daydreaming changes your wallpaper.")
        }
    }

    private func welcomeImage(_ resource: String, label: String) -> some View {
        GeometryReader { geometry in
            BundledCommunityImage(resource: resource, fileExtension: "jpg").scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: .capsule).padding(12)
                }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = model.sourceImageURL {
            WallpaperPreview(url: url, label: "Your chosen picture")
        } else {
            ContentUnavailableView("Choose your picture", systemImage: "photo.artframe")
        }
    }

    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case 1:
                    Text("Choose Your Picture")
                        .font(.largeTitle.weight(.semibold))
                    Text("It's most magical with a picture you love.")
                        .foregroundStyle(.secondary)
                    Button("Choose Your Own Picture…") { showingImporter = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Text("Or drop a picture into this window.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.isImportingPicture {
                        ProgressView("Opening picture…").controlSize(.small)
                    } else {
                        Label(model.sourceImageName, systemImage: "photo")
                            .font(.callout).lineLimit(2)
                    }
                    if model.isBuiltInPictureChosen {
                        Text("Yosemite Valley · NPS Photo / C. Jacoby")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Use Yosemite Valley Instead") { model.useBuiltInPicture(replaceCurrent: true) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    Text("Your original is always kept.")
                        .font(.caption).foregroundStyle(.secondary)
                case 2:
                    Text("A little imagination, powered by AI.")
                        .font(.title.weight(.semibold))
                    Text("\(model.imageProviderName) creates a new version of your picture for the time of day and the weather.")
                        .foregroundStyle(.secondary)
                    Text("“Adjust this image for the time of day and the local weather.”")
                        .font(.callout).italic()
                    if let message = model.keyRecoveryMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                    if model.hasSavedKey && key.isEmpty {
                        Label("API key saved", systemImage: "checkmark.circle")
                            .font(.callout)
                    }
                    if model.isCheckingImageConnection {
                        ProgressView("Checking API key…").controlSize(.small)
                    }
                    SecureField("Paste your \(model.imageProviderName) API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFocused)
                        .disabled(model.isCheckingImageConnection)
                        .accessibilityLabel("\(model.imageProviderName) API key")
                    if let url = model.imageProviderDescriptor?.manageKeysURL { Link("Get an API Key", destination: url) }
                    Text("Your key stays in Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("New wallpapers use \(model.imageCreditName).")
                        .font(.caption).foregroundStyle(.secondary)

                default:
                    Text("Ready to follow the day.")
                        .font(.body.weight(.semibold))
                    Text("Your wallpaper follows the time and local weather.")
                        .foregroundStyle(.secondary)
                    locationStatus
                    Text("Starts at login. Your original stays saved.")
                        .foregroundStyle(.secondary)
                    if model.onboardingWeatherReady && !canContinue, let reason = model.generationUnavailableReason {
                        Label(reason, systemImage: "info.circle")
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.red)
                } else if model.activity == .failed {
                    Text(model.detail).font(.callout).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch model.onboardingLocationState {
        case .notRequested:
            Text("Allow location access for local weather. Rounded coordinates go to MET Norway.")
                .font(.body).foregroundStyle(.secondary)
        case .requesting:
            ProgressView("Waiting for location access…").controlSize(.small)
        case .allowed:
            Label("Local weather is ready", systemImage: "checkmark.circle")
                .font(.body)
        case .denied:
            Label("Location access is off", systemImage: "location.slash")
                .font(.body)
            Text("Enable Daydreaming in System Settings → Privacy & Security → Location Services.")
                .font(.body).foregroundStyle(.secondary)
        }
    }

    private func advance() {
        error = nil
        if step == 3 && !model.onboardingWeatherReady {
            model.requestLocalWeatherAccess()
            return
        }
        if step == 2 && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !model.isCheckingImageConnection else { return }
            let requestedKey = key
            connectionTask = Task {
                guard await model.saveKey(requestedKey), !Task.isCancelled else {
                    if !Task.isCancelled { error = model.keyRecoveryMessage }
                    return
                }
                key = ""
                move(to: 3)
            }
            return
        }
        if step == 3 {
            model.finishOnboarding()
        } else {
            move(to: step + 1)
        }
    }

    private func move(to newStep: Int) {
        error = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = newStep }
        keyFocused = newStep == 2 && !model.hasSavedKey
    }
}
