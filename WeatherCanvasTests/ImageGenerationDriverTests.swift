import CryptoKit
import XCTest
@testable import Daydreaming

final class ImageGenerationDriverTests: XCTestCase {
    func testOldSettingsKeepTheOriginalProviderAndExactCacheIdentity() throws {
        let settings = try JSONDecoder().decode(CanvasSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.imageProvider, .openAI)
        XCTAssertNil(settings.imageProvider.cacheIdentity)
        let components = ["", settings.promptTemplate, settings.style.rawValue,
                          settings.model.rawValue, settings.quality.rawValue, settings.weatherChoice.rawValue]
        let oldKey = SHA256.hash(data: Data(components.joined(separator: "\u{0}").utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(HourWallpaperCache.recipeID(for: settings), oldKey)
        XCTAssertEqual(HourWallpaperCache.promptRecipeID(for: settings), oldKey)
    }

    func testProviderHostAndModelsNeverAliasCachesButSwitchingBackReusesTheOriginalKey() throws {
        var settings = CanvasSettings()
        let original = HourWallpaperCache.recipeID(for: settings)
        settings.imageProvider = custom()
        var keys = [HourWallpaperCache.recipeID(for: settings)]
        settings.imageProvider.baseURL = "https://other.example/v1"
        keys.append(HourWallpaperCache.recipeID(for: settings))
        settings.imageProvider.model = "different-model"
        keys.append(HourWallpaperCache.recipeID(for: settings))
        settings.imageProvider.previewModel = "different-preview"
        keys.append(HourWallpaperCache.recipeID(for: settings))
        XCTAssertEqual(Set(keys).count, 4)
        XCTAssertFalse(keys.contains(original))
        let decoded = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.imageProvider, settings.imageProvider)
        settings.imageProvider = .openAI
        XCTAssertEqual(HourWallpaperCache.recipeID(for: settings), original)
    }

    func testCredentialsAreScopedToProviderAndHostWithoutBorrowingOpenAIKeyMigration() {
        let openAI = KeychainNamespace(bundleID: AppRuntime.productionBundleID)
        let first = KeychainNamespace(bundleID: AppRuntime.productionBundleID, providerID: custom().credentialID)
        var other = custom()
        other.baseURL = "https://other.example/v1"
        let second = KeychainNamespace(bundleID: AppRuntime.productionBundleID, providerID: other.credentialID)
        XCTAssertNotEqual(first.service, openAI.service)
        XCTAssertNotEqual(first.service, second.service)
        XCTAssertNil(first.previousService)
        XCTAssertNotNil(openAI.previousService)
        var slash = custom()
        slash.baseURL += "/"
        XCTAssertEqual(slash.credentialID, custom().credentialID)
    }

    func testMalformedConnectionsAreRejectedBeforeCredentialsOrRequestsAreRead() throws {
        let driver = CompatibleImageDriver()
        for address in ["http://images.example/v1", "file:///tmp/images", "https://user:secret@images.example/v1",
                        "https://images.example/v1?token=secret", "https://images.example/v1#token", "not a URL"] {
            var configuration = custom()
            configuration.baseURL = address
            XCTAssertThrowsError(try driver.validate(configuration), address)
        }
        var configuration = custom()
        configuration.model = " "
        XCTAssertThrowsError(try driver.validate(configuration))
        XCTAssertEqual(try CompatibleImageDriver.endpoint(for: custom()).absoluteString, "https://images.example/v1/images/edits")
    }

    @MainActor
    func testOnlySelectedDriverAndCredentialAreUsedForOneEdit() async throws {
        let first = RecordingImageDriver(id: "first")
        let second = RecordingImageDriver(id: "second")
        let credentials = MemoryImageCredentials()
        let configuration = ImageProviderConfiguration(driverID: "second")
        credentials.keys[configuration.credentialID] = "second-fixture-key"
        let service = ImageGenerationService(registry: .init(drivers: [first, second]), credentials: credentials)
        var settings = CanvasSettings()
        settings.imageProvider = configuration
        var sent = 0
        let image = try await service.generate(request(settings: settings), willSend: { sent += 1 }, didReject: { _ in })
        XCTAssertEqual(image, Data("second result".utf8))
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(first.calls, 0)
        XCTAssertEqual(second.calls, 1)
        XCTAssertEqual(second.lastCredential, "second-fixture-key")
        XCTAssertEqual(credentials.readIDs, [configuration.credentialID])
    }

    @MainActor
    func testMissingCredentialAndUnknownDriverNeverFallbackOrReserveCredit() async {
        let driver = RecordingImageDriver(id: "first")
        let credentials = MemoryImageCredentials()
        credentials.keys["openai"] = "fixture-not-to-be-used"
        let service = ImageGenerationService(registry: .init(drivers: [driver]), credentials: credentials)
        for id in ["first", "unknown"] {
            var settings = CanvasSettings()
            settings.imageProvider = .init(driverID: id)
            do {
                _ = try await service.generate(request(settings: settings), willSend: { XCTFail("No reservation") }, didReject: { _ in })
                XCTFail("Expected connection failure")
            } catch { }
        }
        XCTAssertEqual(driver.calls, 0)
        XCTAssertEqual(credentials.readIDs, [ImageProviderConfiguration(driverID: "first").credentialID])
    }

    @MainActor
    func testCompatibleDriverEditsTheSourceUsingConfiguredPreviewModelAndOneRequest() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data("fixture-source-image".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let client = OpenAIImageClient(transport: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://images.example/v1/images/edits")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-fixture-key")
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            XCTAssertTrue(body.contains("fixture-source-image"))
            XCTAssertTrue(body.contains("edit-fast"))
            XCTAssertFalse(body.contains(ImageModel.fast.rawValue))
            XCTAssertTrue(body.contains("name=\"n\"\r\n\r\n1\r\n"))
            XCTAssertTrue(body.contains("name=\"quality\"\r\n\r\nlow\r\n"))
            let data = Data("{\"data\":[{\"b64_json\":\"aW1hZ2U=\"}]}".utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        var settings = CanvasSettings()
        settings.imageProvider = custom()
        let imageRequest = ImageGenerationRequest(sourceURL: source, prompt: "Keep this scene", size: "1024x640",
                                                  renderProfile: .quickPreview, settings: settings)
        var sent = 0
        let image = try await CompatibleImageDriver(client: client).edit(imageRequest, credential: "custom-fixture-key",
                                                                        willSend: { sent += 1 }, didReject: { _ in XCTFail() })
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(image, Data("image".utf8))
    }

    @MainActor
    func testSwitchingConnectionSavesOnlyItsCredentialAndNeverGenerates() async throws {
        let credentials = MemoryImageCredentials()
        let client = OpenAIImageClient(transport: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://images.example/v1/models")
            return (Data("{\"data\":[{\"id\":\"edit-v1\"}]}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let service = ImageGenerationService(registry: .init(drivers: [CompatibleImageDriver(client: client)]), credentials: credentials)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = connectionModel(service: service, directory: directory)
        defer { model.stopBackgroundTasks() }
        let connected = await model.saveImageConnection(custom(), key: "custom-fixture-key")
        XCTAssertTrue(connected)
        XCTAssertNotNil(model.imageConnectionVerifiedAt)
        XCTAssertEqual(model.settings.imageProvider, custom())
        XCTAssertFalse(model.settings.automaticUpdates)
        XCTAssertEqual(credentials.keys[custom().credentialID], "custom-fixture-key")
        XCTAssertNil(credentials.keys["openai"])
        XCTAssertEqual(model.generatedToday, 0)
    }

    func testCostsAndDataDisclosureFollowTheSelectedProvider() {
        let copy = ImageGenerationCopy(provider: .compatible)
        XCTAssertFalse(copy.ideaHelp.contains("OpenAI"))
        XCTAssertTrue(copy.ideaHelp.contains("Other image API"))
        XCTAssertFalse(copy.previewTimeNotice.contains("OpenAI"))
        XCTAssertFalse(copy.cropDoneNotice(hasChanges: true).contains("OpenAI"))
        XCTAssertEqual(copy.cropDoneNotice(hasChanges: false), AppCopy.cropDoneNotice(hasChanges: false))
    }

    @MainActor
    func testInvalidKeyAndOfflineVerificationKeepTheExistingConnectionAndSettings() async throws {
        for offline in [false, true] {
            let credentials = MemoryImageCredentials()
            credentials.keys["openai"] = "existing-fixture-key"
            let client = OpenAIImageClient(transport: { request in
                if offline { throw URLError(.notConnectedToInternet) }
                return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            })
            let service = ImageGenerationService(registry: .init(drivers: [OpenAIImageDriver(client: client)]), credentials: credentials)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = connectionModel(service: service, directory: directory)
            defer { model.stopBackgroundTasks() }
            let settings = model.settings
            let saved = await model.saveImageConnection(.openAI, key: "invalid-new-key")
            XCTAssertFalse(saved)
            XCTAssertEqual(credentials.keys, ["openai": "existing-fixture-key"])
            XCTAssertEqual(model.settings, settings)
            XCTAssertNil(model.imageConnectionVerifiedAt)
            XCTAssertFalse(model.isCheckingImageConnection)
            XCTAssertNotNil(model.keyRecoveryMessage)
            XCTAssertEqual(model.generatedToday, 0)
        }
    }

    @MainActor
    func testCancelledOrSupersededCheckNeverSavesTheCredential() async throws {
        for changeProvider in [false, true] {
            let gate = CredentialCheckGate()
            let credentials = MemoryImageCredentials()
            let client = OpenAIImageClient(transport: { request in
                await gate.wait()
                return (Data("{\"data\":[{\"id\":\"fixture-model\"}]}".utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            let service = ImageGenerationService(registry: .init(drivers: [OpenAIImageDriver(client: client), CompatibleImageDriver(client: client)]), credentials: credentials)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = connectionModel(service: service, directory: directory)
            defer { model.stopBackgroundTasks() }
            let task = Task { await model.saveImageConnection(.openAI, key: "candidate-key") }
            while !(await gate.started) { await Task.yield() }
            XCTAssertTrue(model.isCheckingImageConnection)
            XCTAssertTrue(credentials.keys.isEmpty)
            if changeProvider { model.selectImageProvider("compatible") }
            else { task.cancel() }
            await gate.release()
            let saved = await task.value
            XCTAssertFalse(saved)
            XCTAssertTrue(credentials.keys.isEmpty)
            XCTAssertNil(model.imageConnectionVerifiedAt)
            XCTAssertFalse(model.isCheckingImageConnection)
            XCTAssertEqual(model.settings.imageProvider.driverID, changeProvider ? "compatible" : "openai")
            XCTAssertEqual(model.generatedToday, 0)
        }
    }

    @MainActor
    func testCheckingSavedConnectionDoesNotPauseUpdatesOrCreateAnything() async throws {
        let credentials = MemoryImageCredentials()
        credentials.keys["openai"] = "saved-fixture-key"
        let client = OpenAIImageClient(transport: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let status = request.value(forHTTPHeaderField: "Authorization") == "Bearer saved-fixture-key" ? 200 : 401
            return (Data("{\"data\":[]}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let service = ImageGenerationService(registry: .init(drivers: [OpenAIImageDriver(client: client)]), credentials: credentials)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = connectionModel(service: service, directory: directory)
        defer { model.stopBackgroundTasks() }
        let settings = model.settings
        let checked = await model.checkImageConnection()
        XCTAssertTrue(checked)
        XCTAssertEqual(model.settings, settings)
        XCTAssertEqual(credentials.keys, ["openai": "saved-fixture-key"])
        XCTAssertNotNil(model.imageConnectionVerifiedAt)
        XCTAssertEqual(model.generatedToday, 0)
        credentials.keys["openai"] = "revoked-fixture-key"
        let rejected = await model.checkImageConnection()
        XCTAssertFalse(rejected)
        XCTAssertNil(model.imageConnectionVerifiedAt)
        XCTAssertEqual(model.settings, settings)
        XCTAssertEqual(credentials.keys, ["openai": "revoked-fixture-key"])
        XCTAssertEqual(model.generatedToday, 0)
    }

    @MainActor
    private func connectionModel(service: ImageGenerationService, directory: URL) -> AppModel {
        let services = AppModelHourlyServices(now: { .now }, sourceAvailable: { _ in false },
            weather: { _, date in WeatherSnapshot(label: "clear", symbol: "sun.max", fetchedAt: date) },
            readPrompt: nil, create: { _, _, _, _ in XCTFail("Connection checks cannot generate"); return Data() },
            cacheDirectory: directory, apply: { _ in XCTFail("Connection checks cannot apply") },
            loadLedger: { .init() }, saveLedger: { _ in }, loadPending: { [] }, savePending: { _ in },
            loadApplicationRetry: { nil }, saveApplicationRetry: { _ in })
        return AppModel(settings: .init(), hourlyServices: services, imageGeneration: service)
    }

    private func custom() -> ImageProviderConfiguration {
        .init(driverID: "compatible", baseURL: "https://images.example/v1", model: "edit-v1", previewModel: "edit-fast")
    }

    private func request(settings: CanvasSettings) -> ImageGenerationRequest {
        .init(sourceURL: URL(fileURLWithPath: "/fixture/image.jpg"), prompt: "Fixture", size: "1024x640",
              renderProfile: .quickPreview, settings: settings)
    }
}

@MainActor
private final class MemoryImageCredentials: ImageCredentialStore {
    var keys: [String: String] = [:]
    var readIDs: [String] = []
    func read(for configuration: ImageProviderConfiguration) -> String? {
        readIDs.append(configuration.credentialID)
        return keys[configuration.credentialID]
    }
    func save(_ credential: String, for configuration: ImageProviderConfiguration) { keys[configuration.credentialID] = credential }
    func remove(for configuration: ImageProviderConfiguration) { keys.removeValue(forKey: configuration.credentialID) }
}

private final class RecordingImageDriver: ImageGenerationDriver {
    let descriptor: ImageDriverDescriptor
    @MainActor private(set) var calls = 0
    @MainActor private(set) var lastCredential: String?
    init(id: String) {
        descriptor = .init(id: id, name: id, requiresEndpoint: false, manageKeysURL: nil, billingURL: nil)
    }
    func validate(_ configuration: ImageProviderConfiguration) throws { }
    @MainActor
    func verifyCredential(_ credential: String, configuration: ImageProviderConfiguration) async throws { }
    @MainActor
    func edit(_ request: ImageGenerationRequest, credential: String,
              willSend: @escaping @MainActor () async throws -> Void,
              didReject: @escaping @MainActor (Int) -> Void) async throws -> Data {
        try await willSend()
        calls += 1
        lastCredential = credential
        return Data("\(descriptor.id) result".utf8)
    }
}

private actor CredentialCheckGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}
