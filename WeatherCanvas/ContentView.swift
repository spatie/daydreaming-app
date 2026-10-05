import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false
    @State private var setupStep = 0
    @State private var keyDraft = ""
    @State private var promptDraft = ""
    @State private var intervalDraft: UpdateInterval = .twiceDaily
    @State private var previewOriginal = false

    var body: some View {
        Group {
            if model.onboardingComplete {
                dashboard
            } else {
                setup
            }
        }
        .frame(minWidth: 890, minHeight: 570)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                model.importImage(url)
                previewOriginal = false
            }
        }
        .onAppear {
            promptDraft = model.settings.promptTemplate
            intervalDraft = model.settings.interval
        }
        .onChange(of: model.settings.promptTemplate) { oldValue, newValue in
            if promptDraft == oldValue {
                promptDraft = newValue
            }
        }
        .onChange(of: model.settings.interval) { oldValue, newValue in
            if intervalDraft == oldValue { intervalDraft = newValue }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 38, height: 38)
                Text("Daydreaming")
                    .font(.headline)
                Spacer()
                Text("\(setupStep + 1) of 3")
                    .foregroundStyle(.secondary)
            }
            .padding(28)

            Divider()

            HStack(spacing: 36) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                    if let url = model.sourceImageURL, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    } else {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 76, weight: .ultraLight))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 18) {
                    setupStepContent
                    Spacer(minLength: 0)
                    if !model.detail.isEmpty && model.status == "Something went wrong" {
                        Label(model.detail, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .frame(width: 330, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)

            Divider()

            HStack {
                if setupStep > 0 {
                    Button("Back") { setupStep -= 1 }
                }
                Spacer()
                Button(setupStep == 2 ? "Start updating" : "Continue") {
                    if setupStep == 2 {
                        model.settings.interval = intervalDraft
                        model.finishOnboarding()
                    } else {
                        setupStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(setupStep == 0 && model.sourceImageURL == nil || setupStep == 1 && !model.hasSavedKey)
            }
            .padding(22)
        }
    }

    @ViewBuilder
    private var setupStepContent: some View {
        switch setupStep {
        case 0:
            Text("Choose your base image")
                .font(.largeTitle.weight(.semibold))
            Text("Pick a photo, illustration, or wallpaper. Daydreaming keeps the original and makes new versions from it.")
                .foregroundStyle(.secondary)
            Button(model.sourceImageURL == nil ? "Choose image" : "Change image") {
                showingImporter = true
            }
            Text(model.sourceImageURL?.lastPathComponent ?? "JPEG, PNG, HEIC, and other image formats")
                .font(.caption)
                .foregroundStyle(.secondary)

        case 1:
            Text("Connect image generation")
                .font(.largeTitle.weight(.semibold))
            Text("Use your own OpenAI API key. The key stays in Keychain, and your image goes directly to OpenAI when a new version is needed.")
                .foregroundStyle(.secondary)
            SecureField("OpenAI API key", text: $keyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(model.hasSavedKey ? "Replace key" : "Save key") {
                    if model.saveKey(keyDraft) { keyDraft = "" }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.hasSavedKey {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                .font(.caption)

        default:
            Text("Make it automatic")
                .font(.largeTitle.weight(.semibold))
            Text("Your wallpaper will change with the time and weather. You can change the schedule and prompt later.")
                .foregroundStyle(.secondary)
            Picker("Weather", selection: $model.settings.weatherChoice) {
                ForEach(WeatherChoice.allCases) { choice in Text(choice.title).tag(choice) }
            }
            Picker("Update", selection: $intervalDraft) {
                ForEach(model.availableIntervals) { interval in Text(interval.title).tag(interval) }
            }
            if !model.hasProLicense {
                Text("The free plan creates up to two new images a day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Text("Automatic weather shares your approximate location with MET Norway. New images use your OpenAI API credit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daydreaming")
                        .font(.title2.weight(.semibold))
                    Text("A living wallpaper made from your image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 20, height: 20)
                }
                .labelStyle(.iconOnly)
                .help("Settings")
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 19)

            Divider()

            HStack(spacing: 24) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 22) {
                    statusPanel

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base image")
                            .font(.headline)
                        HStack {
                            Text(model.sourceImageURL?.lastPathComponent ?? "No image selected")
                                .lineLimit(1)
                            Spacer()
                            Button("Change") { showingImporter = true }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should change?")
                            .font(.headline)
                        TextEditor(text: $promptDraft)
                            .frame(height: 88)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text("Local time and weather are added automatically. Use {{date}} if you want today's date too.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button("Save prompt") {
                                model.settings.promptTemplate = promptDraft
                            }
                            .disabled(
                                promptDraft == model.settings.promptTemplate ||
                                promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }

                    HStack {
                        Picker("Update", selection: $intervalDraft) {
                        ForEach(model.availableIntervals) { interval in Text(interval.title).tag(interval) }
                        }
                        if intervalDraft != model.settings.interval {
                            Button("Apply") { model.settings.interval = intervalDraft }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack {
                        Button(model.settings.automaticUpdates ? "Pause" : "Start automatic") {
                            model.settings.automaticUpdates ? model.stopAutomatic() : model.startAutomatic()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Generate now") { model.generateNow() }
                            .disabled(model.isGenerating)
                    }
                }
                .frame(width: 315, alignment: .leading)
            }
            .padding(24)
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(nsColor: .underPageBackgroundColor))

            if let url = previewOriginal ? model.sourceImageURL : model.displayedImageURL,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
                    .accessibilityLabel(previewOriginal ? "Base image" : "Current wallpaper")
            }

            VStack {
                if model.isGenerating {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.status)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 11))
                    .padding(22)
                }
                Spacer()
                HStack {
                    Picker("Preview", selection: $previewOriginal) {
                        Text("Current").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 175)
                    .glassEffect()
                    Spacer()
                }
                .padding(22)
            }
        }
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            if model.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            } else if model.status == "Something went wrong" {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: model.settings.automaticUpdates ? "checkmark.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(model.settings.automaticUpdates ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status)
                    .font(.headline)
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}
