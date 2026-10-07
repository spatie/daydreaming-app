import SwiftUI

struct ImageConnectionSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var configuration = ImageProviderConfiguration.openAI
    @State private var key = ""
    @State private var error: String?
    @State private var showingRemoval = false
    @State private var connectionTask: Task<Void, Never>?

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
                    Label {
                        Text(connectionLabel)
                    } icon: {
                        Image(systemName: model.imageConnectionVerifiedAt != nil ? "checkmark.circle" : "key")
                            .foregroundStyle(model.imageConnectionVerifiedAt != nil ? Color.green.opacity(0.65) : Color.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .help(connectionHelp)
                    Spacer()
                    if !model.isCheckingImageConnection {
                        Button(model.imageConnectionVerifiedAt == nil ? "Check Connection" : "Check Again") {
                            connectionTask = Task { _ = await model.checkImageConnection() }
                        }
                    }
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
            if model.isCheckingImageConnection {
                ProgressView("Checking API key…").controlSize(.small)
            }
            if let message = error ?? model.keyRecoveryMessage {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
        } header: {
            Text("Image AI")
        } footer: {
            Text("Creating sends your picture and idea to \(model.imageProviderName). \(model.imageBillingNotice)")
                .font(.caption)
        }
        .disabled(model.isCheckingImageConnection)
        .onAppear { loadConfiguration() }
        .onChange(of: model.settings.imageProvider) { _, _ in loadConfiguration() }
        .onDisappear { connectionTask?.cancel(); key = "" }
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

    private var connectionLabel: String {
        if model.imageConnectionVerifiedAt != nil { return "API key verified" }
        return model.recovery == .apiKey ? "API key needs attention" : "API key saved"
    }

    private var connectionHelp: String {
        guard let date = model.imageConnectionVerifiedAt else { return "Stored in Keychain. Check Connection verifies API access without creating an image." }
        return "API authentication checked \(date.formatted(date: .abbreviated, time: .shortened)). Image permissions and available credit are checked when creating an image."
    }

    private func connect() {
        guard !model.isCheckingImageConnection else { return }
        let requestedConfiguration = configuration
        let requestedKey = key
        error = nil
        connectionTask = Task {
            if await model.saveImageConnection(requestedConfiguration, key: requestedKey) { loadConfiguration() }
            else if !Task.isCancelled { error = model.keyRecoveryMessage }
        }
    }
}
