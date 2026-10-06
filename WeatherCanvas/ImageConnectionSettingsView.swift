import SwiftUI

struct ImageConnectionSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var configuration = ImageProviderConfiguration.openAI
    @State private var key = ""
    @State private var error: String?
    @State private var showingRemoval = false

    var body: some View {
        Section {
            if model.imageDrivers.count > 1 || model.imageProviderDescriptor == nil {
                Picker("Use", selection: Binding(
                    get: { model.settings.imageProvider.driverID },
                    set: { model.selectImageProvider($0); loadConfiguration() }
                )) {
                    ForEach(model.imageDrivers) { driver in Text(driver.name).tag(driver.id) }
                    if model.imageProviderDescriptor == nil {
                        Text("Unavailable provider").tag(model.settings.imageProvider.driverID)
                    }
                }
                .disabled(model.presentation == .crop)
            } else {
                LabeledContent("AI", value: model.imageProviderName)
            }

            if model.imageProviderDescriptor?.requiresEndpoint == true {
                TextField("API base URL", text: $configuration.baseURL, prompt: Text("https://example.com/v1"))
                    .autocorrectionDisabled()
                TextField("Image model", text: $configuration.model)
                    .autocorrectionDisabled()
                TextField("Preview model (optional)", text: $configuration.previewModel)
                    .autocorrectionDisabled()
                Text("Use an API that edits images with the OpenAI Images format. Leave preview model empty to use the same model.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if model.hasImageConnection {
                HStack {
                    Label(model.recovery == .apiKey ? "API key needs attention" : "\(model.imageProviderName) API key saved",
                          systemImage: model.recovery == .apiKey ? "exclamationmark.circle" : "checkmark.circle")
                        .help("Your API key is stored in Keychain.")
                    Spacer()
                    Button("Disconnect…") { showingRemoval = true }.disabled(model.isGenerating)
                }
            }
            if needsCredential {
                SecureField("API key", text: $key)
                    .onSubmit { connect() }
                HStack {
                    if let url = model.imageProviderDescriptor?.manageKeysURL {
                        Link("Get an API Key", destination: url)
                    }
                    Spacer()
                    Button("Connect", action: connect)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if configuration != model.settings.imageProvider {
                Button("Save Changes", action: connect)
            }
            if let message = error ?? model.keyRecoveryMessage {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
        } header: {
            Text("Image AI")
        } footer: {
            Text("One AI handles previews and automatic wallpapers. Changing AI pauses updates and keeps your current desktop. \(model.imageBillingNotice)")
                .font(.caption)
        }
        .onAppear { loadConfiguration() }
        .onChange(of: model.settings.imageProvider) { _, _ in loadConfiguration() }
        .onDisappear { key = "" }
        .alert("Disconnect \(model.imageProviderName)?", isPresented: $showingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                guard !model.isGenerating else { return }
                model.removeKey()
                key = ""
            }
        } message: {
            Text("Removes this connection's API key and pauses updates. Your wallpaper, original pictures and saved images stay on this Mac.")
        }
    }

    private var needsCredential: Bool {
        !model.hasSavedKey || configuration.credentialID != model.settings.imageProvider.credentialID
    }

    private func loadConfiguration() {
        configuration = model.settings.imageProvider
        key = ""
        error = nil
    }

    private func connect() {
        if model.saveImageConnection(configuration, key: key) { loadConfiguration() }
        else { error = model.keyRecoveryMessage ?? model.detail }
    }
}
