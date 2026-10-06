import Foundation

@MainActor
protocol ImageCredentialStore {
    func read(for configuration: ImageProviderConfiguration) throws -> String?
    func save(_ credential: String, for configuration: ImageProviderConfiguration) throws
    func remove(for configuration: ImageProviderConfiguration) throws
}

@MainActor
struct KeychainImageCredentials: ImageCredentialStore {
    func read(for configuration: ImageProviderConfiguration) throws -> String? { try KeychainStore.read(provider: configuration) }
    func save(_ credential: String, for configuration: ImageProviderConfiguration) throws { try KeychainStore.save(credential, provider: configuration) }
    func remove(for configuration: ImageProviderConfiguration) throws { try KeychainStore.remove(provider: configuration) }
}

/// A single request selects exactly one driver. There is no fallback to another provider or key.
@MainActor
struct ImageGenerationService {
    let registry: ImageDriverRegistry
    let credentials: any ImageCredentialStore

    init(registry: ImageDriverRegistry = .init(), credentials: any ImageCredentialStore = KeychainImageCredentials()) {
        self.registry = registry
        self.credentials = credentials
    }

    func generate(_ request: ImageGenerationRequest,
                  willSend: @escaping @MainActor () async throws -> Void,
                  didReject: @escaping @MainActor (Int) -> Void) async throws -> Data {
        let configuration = request.settings.imageProvider
        let driver = try registry.driver(for: configuration)
        guard let credential = try credentials.read(for: configuration), !credential.isEmpty else {
            throw ImageDriverError.credentialRequired(driver.descriptor.name)
        }
        try Task.checkCancellation()
        return try await driver.edit(request, credential: credential, willSend: willSend, didReject: didReject)
    }
}
