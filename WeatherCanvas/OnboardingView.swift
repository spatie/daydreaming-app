import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showingImporter: Bool
    @State private var step = 0
    @State private var key = ""
    @State private var error: String?
    @FocusState private var keyFocused: Bool

    private let steps = ["Welcome", "Your picture", "Image creation", "Ready"]
    private var primaryTitle: String {
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
        guard !model.isImportingPicture else { return false }
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

            Divider()
            HStack(alignment: .bottom, spacing: 16) {
                if step > 0 {
                    Button("Back") { move(to: step - 1) }
                        .keyboardShortcut("[", modifiers: .command)
                }
                if step == 3 {
                    Button("Not Now") { model.finishOnboarding(createFirstWallpaper: false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if step == 3 && model.onboardingWeatherReady {
                        Text("Creates your first wallpaper now. OpenAI bills your API key for each new image.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 300)
                    }
                    Button(primaryTitle, action: advance)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
            .padding(22)
        }
        .onAppear {
            model.useLocalWeather()
            model.useBuiltInPicture(replaceCurrent: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if step == 3 { model.refreshOnboardingLocation() }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if step == 0 {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    illustration("Morning")
                    illustration("Rain")
                }
                HStack(spacing: 10) {
                    illustration("Snow")
                    illustration("Night")
                }
                Text("A preview of how your picture could change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if let url = model.sourceImageURL {
            WallpaperPreview(url: url, label: "Your chosen picture")
        } else {
            ContentUnavailableView("Choose Your Picture", systemImage: "photo.artframe")
        }
    }

    private func illustration(_ title: String) -> some View {
        VStack(spacing: 5) {
            WallpaperPreview(url: model.builtInPictureURL, label: "\(title) illustration", fillsFrame: true)
                .overlay {
                    illustrationOverlay(title)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .clipShape(.rect(cornerRadius: 12))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func illustrationOverlay(_ title: String) -> some View {
        Canvas { context, size in
            let bounds = Path(CGRect(origin: .zero, size: size))
            switch title {
            case "Morning":
                context.fill(bounds, with: .linearGradient(
                    Gradient(colors: [.orange.opacity(0.55), .yellow.opacity(0.18), .clear]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)
                ))
            case "Rain":
                for index in 0..<36 {
                    let x = CGFloat((index * 37) % 100) / 100 * size.width
                    let y = CGFloat((index * 61) % 100) / 100 * size.height
                    var streak = Path()
                    streak.move(to: CGPoint(x: x, y: y))
                    streak.addLine(to: CGPoint(x: x - 5, y: y + 15))
                    context.stroke(streak, with: .color(.white.opacity(0.6)), lineWidth: 1)
                }
            case "Snow":
                context.fill(bounds, with: .color(.white.opacity(0.28)))
                for index in 0..<44 {
                    let x = CGFloat((index * 37) % 100) / 100 * size.width
                    let y = CGFloat((index * 61) % 100) / 100 * size.height
                    let radius = CGFloat(2 + index % 3)
                    let flake = Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius))
                    context.fill(flake, with: .color(.white.opacity(0.9)))
                }
            default:
                context.fill(bounds, with: .linearGradient(
                    Gradient(colors: [.indigo.opacity(0.45), .black.opacity(0.2)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
                ))
                for index in 0..<24 {
                    let x = CGFloat((index * 37) % 100) / 100 * size.width
                    let y = CGFloat((index * 61) % 60) / 100 * size.height
                    let radius = CGFloat(1 + index % 2)
                    let star = Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius))
                    context.fill(star, with: .color(.white.opacity(0.9)))
                }
            }
        }
    }

    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case 0:
                    Text("A favorite picture. A changing day.")
                        .font(.largeTitle.weight(.semibold))
                    Text("Daydreaming keeps your favorite picture as your wallpaper and gently reimagines it through the day: at sunrise, in the rain, under snow, at night.")
                        .foregroundStyle(.secondary)
                    Text("Pick a picture. Connect OpenAI. Your local weather does the rest.")
                        .foregroundStyle(.secondary)
                    Text("New wallpapers use your own OpenAI API key. OpenAI bills you for each new image.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Text("OpenAI creates a new version of your picture for the time of day and the weather.")
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
                    SecureField("Paste your OpenAI API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFocused)
                        .accessibilityLabel("OpenAI API key")
                    Link("Get an API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    Text("Your key stays in Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("New wallpapers use OpenAI credit.")
                        .font(.caption).foregroundStyle(.secondary)

                default:
                    Text("Ready to follow the day.")
                        .font(.largeTitle.weight(.semibold))
                    Text("Your picture changes through the day, shaped by your local weather.")
                        .foregroundStyle(.secondary)
                    locationStatus
                    Text("Starts at login and updates every screen while Daydreaming is open. You can change this in Settings. Your original stays saved.")
                        .foregroundStyle(.secondary)
                    if model.onboardingWeatherReady && !canContinue, let reason = model.generationUnavailableReason {
                        Label(reason, systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
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
            Text("Local weather needs your approximate location. Daydreaming shares rounded coordinates with MET Norway. macOS will ask for permission next.")
                .font(.caption).foregroundStyle(.secondary)
        case .requesting:
            ProgressView("Waiting for location access…").controlSize(.small)
        case .allowed:
            Label("Local weather is ready", systemImage: "checkmark.circle")
                .font(.callout)
        case .denied:
            Label("Location access is off", systemImage: "location.slash")
                .font(.callout)
            Text("Allow Daydreaming in System Settings → Privacy & Security → Location Services, then return here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func advance() {
        error = nil
        if step == 3 && !model.onboardingWeatherReady {
            model.requestLocalWeatherAccess()
            return
        }
        if step == 2 && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard model.saveKey(key) else { error = model.detail; return }
            key = ""
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
