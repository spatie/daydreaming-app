import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyDraft = ""
    @State private var licenseDraft = ""
    @State private var customMinutesDraft = 60
    @State private var webAddress = ""
    @State private var webSelector = ""
    @State private var showingSourceImporter = false
    @State private var sourceError: String?
    @State private var isCheckingSource = false
    @State private var pendingSource: ContextSource?
    @State private var pendingPreview: ContextPreview = .empty

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }

            generationSettings
                .tabItem { Label("Generation", systemImage: "sparkles") }

            sourcesSettings
                .tabItem { Label("Sources", systemImage: "text.page") }

            connectionSettings
                .tabItem { Label("Account", systemImage: "key.horizontal") }
        }
        .frame(width: 590, height: 470)
        .onAppear { customMinutesDraft = model.settings.customMinutes }
        .fileImporter(
            isPresented: $showingSourceImporter,
            allowedContentTypes: [.plainText, .html, .json]
        ) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    prepareSource(try ContextSource.selectedFile(url))
                } catch {
                    sourceError = error.localizedDescription
                }
            }
        }
        .sheet(item: $pendingSource) { source in
            sourceConfirmation(source)
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Background") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Show menu bar icon", isOn: $model.showMenuBar)
                Text("If you hide the icon, open Daydreaming again to return to this window. The app has no Dock icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Weather") {
                Picker("Condition", selection: $model.settings.weatherChoice) {
                    ForEach(WeatherChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Text("Automatic weather uses your approximate location and a forecast from MET Norway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var generationSettings: some View {
        Form {
            Section("Image generation") {
                Picker("Model", selection: $model.settings.model) {
                    ForEach(ImageModel.allCases) { imageModel in
                        Text(imageModel.title).tag(imageModel)
                    }
                }
                Picker("Quality", selection: $model.settings.quality) {
                    ForEach(ImageQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                Toggle("Reuse matching images", isOn: $model.settings.reuseMatchingImages)
            }

            Section("Schedule") {
                if model.settings.interval == .custom {
                    Stepper(
                        "Every \(customMinutesDraft) minutes",
                        value: $customMinutesDraft,
                        in: 5...1_440,
                        step: 5
                    )
                    if customMinutesDraft != model.settings.customMinutes {
                        Button("Apply custom interval") {
                            model.settings.customMinutes = customMinutesDraft
                        }
                    }
                }
                if model.hasProLicense {
                    Stepper(
                        "At most \(model.settings.dailyGenerationLimit) new images per day",
                        value: $model.settings.dailyGenerationLimit,
                        in: 1...288
                    )
                } else {
                    Text("At most two new images per day")
                }
                Text("Saved images can be reused without spending API credit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                HStack {
                    Text("Generated images")
                    Spacer()
                    Text(model.cacheSizeLabel)
                        .foregroundStyle(.secondary)
                    Button("Clear") { model.clearCache() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sourcesSettings: some View {
        Form {
            Section("Optional data") {
                Text("Give the image editor text from a file or a specific element on an HTTPS page. Preview the extracted text before adding a source.")
                    .foregroundStyle(.secondary)
                Text("Reads text already present in page HTML. Website scripts are not run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.settings.contextSources) { source in
                    HStack {
                        Text(source.displayName)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") { model.removeSource(source) }
                    }
                }
                Button("Choose a text, HTML, or JSON file") {
                    showingSourceImporter = true
                }
                .disabled(model.settings.contextSources.count >= 5 || isCheckingSource)
            }

            Section("Web page element") {
                TextField("HTTPS URL", text: $webAddress)
                    .textContentType(.URL)
                TextField("CSS selector, such as #temperature", text: $webSelector)
                Button("Check page") {
                    guard let url = URL(string: webAddress.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        sourceError = ContextSourceError.invalidWebsiteURL.localizedDescription
                        return
                    }
                    do {
                        prepareSource(try ContextSource.selectedWebPage(url, selector: webSelector))
                    } catch {
                        sourceError = error.localizedDescription
                    }
                }
                .disabled(model.settings.contextSources.count >= 5 || isCheckingSource)
            }

            if isCheckingSource {
                Section { ProgressView("Reading source…") }
            }
            if let sourceError {
                Section { Text(sourceError).foregroundStyle(.red) }
            }

            if !model.contextPreview.promptText.isEmpty {
                Section("Connected data preview") {
                    ScrollView {
                        Text(model.contextPreview.promptText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    Button("Refresh preview") { model.previewSources() }
                        .disabled(model.isReadingSources)
                }
            } else if !model.settings.contextSources.isEmpty {
                Section {
                    Button("Preview connected data") { model.previewSources() }
                        .disabled(model.isReadingSources)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var connectionSettings: some View {
        Form {
            Section("OpenAI") {
                HStack {
                    SecureField("API key", text: $keyDraft)
                    Button(model.hasSavedKey ? "Replace" : "Save") {
                        if model.saveKey(keyDraft) { keyDraft = "" }
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if model.hasSavedKey {
                    HStack {
                        Label("Key saved in Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove key") { model.removeKey() }
                    }
                }
                Link("Manage API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
            }

            Section("License") {
                if let license = model.license {
                    Label("Licensed, all update intervals available", systemImage: "checkmark.seal.fill")
                    Text("License ID: \(license.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Remove license") { model.removeLicense() }
                } else {
                    Text("Free plan: up to two new images per day.")
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("License key", text: $licenseDraft)
                        Button("Activate") {
                            if model.activateLicense(licenseDraft) { licenseDraft = "" }
                        }
                        .disabled(licenseDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Section("Privacy") {
                Text("Originals and generated wallpapers stay on this Mac. Creating a version sends the source image and optional connected text directly to OpenAI.")
                    .foregroundStyle(.secondary)
            }

            if model.status == "Something went wrong" {
                Section { Text(model.detail).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func prepareSource(_ source: ContextSource) {
        sourceError = nil
        isCheckingSource = true
        Task { @MainActor in
            defer { isCheckingSource = false }
            do {
                pendingPreview = try await ContextSourceReader().readAll([source])
                pendingSource = source
            } catch {
                sourceError = error.localizedDescription
            }
        }
    }

    private func sourceConfirmation(_ source: ContextSource) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add \(source.displayName)?")
                .font(.title2.weight(.semibold))
            Text("This is what the app reads now. It checks the source again before each new image.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(pendingPreview.promptText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Cancel") { pendingSource = nil }
                Button("Add source") {
                    model.addSource(source, preview: pendingPreview)
                    pendingSource = nil
                    webAddress = ""
                    webSelector = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520, height: 390)
    }
}
