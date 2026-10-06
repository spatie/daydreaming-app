import CryptoKit
import Foundation

/// Non-secret connection settings. Credentials live in the driver's own Keychain namespace.
struct ImageProviderConfiguration: Codable, Equatable, Sendable {
    var driverID = "openai"
    var baseURL = ""
    var model = ""
    var previewModel = ""

    static let openAI = Self()

    var credentialID: String {
        if driverID == "openai" { return "openai" }
        return driverID + "." + Self.digest(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    /// Omit the original driver's fingerprint to preserve all existing cache keys.
    var cacheIdentity: String? {
        if self == .openAI { return nil }
        return [driverID, credentialID, model, previewModel].joined(separator: "\u{0}")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ImageDriverDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let requiresEndpoint: Bool
    let manageKeysURL: URL?
    let billingURL: URL?

    static let openAI = Self(id: "openai", name: "OpenAI", requiresEndpoint: false,
                             manageKeysURL: URL(string: "https://platform.openai.com/api-keys"),
                             billingURL: URL(string: "https://platform.openai.com/settings/organization/billing/overview"))
    static let compatible = Self(id: "compatible", name: "Other image API", requiresEndpoint: true,
                                manageKeysURL: nil, billingURL: nil)

    var creditName: String { name == "OpenAI" ? "OpenAI credit" : "your image provider's credit" }
}

/// The app owns timing, budgeting and application. Drivers own authentication and image editing.
struct ImageGenerationRequest: Sendable {
    let sourceURL: URL
    let prompt: String
    let size: String
    let renderProfile: GenerationRenderProfile
    let settings: CanvasSettings
}

protocol ImageGenerationDriver: Sendable {
    var descriptor: ImageDriverDescriptor { get }
    func validate(_ configuration: ImageProviderConfiguration) throws
    func edit(_ request: ImageGenerationRequest, credential: String,
              willSend: @escaping @MainActor () async throws -> Void,
              didReject: @escaping @MainActor (Int) -> Void) async throws -> Data
}

struct ImageDriverRegistry: Sendable {
    private let drivers: [String: any ImageGenerationDriver]

    init(drivers: [any ImageGenerationDriver] = [OpenAIImageDriver(), CompatibleImageDriver()]) {
        precondition(Set(drivers.map { $0.descriptor.id }).count == drivers.count)
        self.drivers = Dictionary(uniqueKeysWithValues: drivers.map { ($0.descriptor.id, $0) })
    }

    var descriptors: [ImageDriverDescriptor] { drivers.values.map(\.descriptor).sorted { $0.id > $1.id } }

    func driver(for configuration: ImageProviderConfiguration) throws -> any ImageGenerationDriver {
        guard let driver = drivers[configuration.driverID] else { throw ImageDriverError.unavailable }
        try driver.validate(configuration)
        return driver
    }

    func descriptor(for configuration: ImageProviderConfiguration) -> ImageDriverDescriptor? {
        drivers[configuration.driverID]?.descriptor
    }
}

struct OpenAIImageDriver: ImageGenerationDriver {
    let descriptor = ImageDriverDescriptor.openAI
    private let client: OpenAIImageClient
    init(client: OpenAIImageClient = .init()) { self.client = client }

    func validate(_ configuration: ImageProviderConfiguration) throws {
        guard configuration == .openAI else { throw ImageDriverError.invalidConfiguration }
    }

    func edit(_ request: ImageGenerationRequest, credential: String,
              willSend: @escaping @MainActor () async throws -> Void,
              didReject: @escaping @MainActor (Int) -> Void) async throws -> Data {
        try await client.edit(sourceURL: request.sourceURL, prompt: request.prompt, apiKey: credential,
                              model: request.renderProfile.model(for: request.settings),
                              quality: request.renderProfile.quality(for: request.settings), size: request.size,
                              willSend: willSend, didReject: didReject)
    }
}

/// A service implementing the OpenAI Images edit contract can be connected without changing the app.
struct CompatibleImageDriver: ImageGenerationDriver {
    let descriptor = ImageDriverDescriptor.compatible
    private let client: OpenAIImageClient
    init(client: OpenAIImageClient = .init()) { self.client = client }

    func validate(_ configuration: ImageProviderConfiguration) throws {
        _ = try Self.endpoint(for: configuration)
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImageDriverError.modelRequired
        }
    }

    static func endpoint(for configuration: ImageProviderConfiguration) throws -> URL {
        guard configuration.driverID == "compatible",
              let components = URLComponents(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              let url = components.url else { throw ImageDriverError.invalidEndpoint }
        return url.appendingPathComponent("images/edits")
    }

    func edit(_ request: ImageGenerationRequest, credential: String,
              willSend: @escaping @MainActor () async throws -> Void,
              didReject: @escaping @MainActor (Int) -> Void) async throws -> Data {
        let configuration = request.settings.imageProvider
        try validate(configuration)
        let model = request.renderProfile == .quickPreview && !configuration.previewModel.isEmpty
            ? configuration.previewModel : configuration.model
        return try await client.edit(sourceURL: request.sourceURL, prompt: request.prompt, apiKey: credential,
                                     modelName: model, quality: request.renderProfile.quality(for: request.settings),
                                     size: request.size, endpoint: Self.endpoint(for: configuration),
                                     providerName: descriptor.name, willSend: willSend, didReject: didReject)
    }
}

enum ImageDriverError: LocalizedError {
    case unavailable, invalidConfiguration, invalidEndpoint, modelRequired
    case credentialRequired(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "This image provider is unavailable in this build. Choose another in Settings."
        case .invalidConfiguration: "Choose a valid image connection in Settings."
        case .invalidEndpoint: "Enter an HTTPS API base URL without credentials, a query or a fragment."
        case .modelRequired: "Enter the image-editing model offered by your provider."
        case .credentialRequired(let name): "Add your \(name) API key in Settings."
        }
    }
}
