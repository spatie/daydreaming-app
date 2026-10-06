import Security
import XCTest
@testable import Daydreaming

final class KeychainStoreTests: XCTestCase {
    private let production = KeychainNamespace(bundleID: "be.spatie.daydreaming")

    func testLegacyModeCopiesThePreviousServiceWithoutDeletingUntilSaved() throws {
        let backend = MemoryKeychain()
        let previous = MemoryKeychain.Item(service: "be.spatie.weathercanvas.openai", storage: .legacy)
        backend.items[previous] = "fixture-old"
        let store = APIKeyStore(namespace: production, backend: backend, storage: .legacy)
        XCTAssertEqual(try store.read(), "fixture-old")
        XCTAssertEqual(backend.items[.init(service: production.service, storage: .legacy)], "fixture-old")
        XCTAssertNil(backend.items[previous])
    }

    func testLegacyModePreservesPreviousKeyIfCopyFails() throws {
        let backend = MemoryKeychain()
        let previous = MemoryKeychain.Item(service: "be.spatie.weathercanvas.openai", storage: .legacy)
        backend.items[previous] = "fixture-old"
        backend.failSave = true
        let store = APIKeyStore(namespace: production, backend: backend, storage: .legacy)
        XCTAssertEqual(try store.read(), "fixture-old")
        XCTAssertEqual(try store.read(), "fixture-old")
        XCTAssertEqual(backend.items[previous], "fixture-old")
        XCTAssertEqual(backend.operations.filter { $0.hasPrefix("save:") }.count, 1)
        XCTAssertFalse(backend.operations.contains { $0.hasPrefix("remove:") })
    }

    func testPreviewAndUnidentifiedBuildsNeverCallTheBackend() throws {
        for identifier in ["be.spatie.daydreaming.preview", "be.spatie.daydreaming.preview.round4", nil] {
            let backend = MemoryKeychain()
            let namespace = KeychainNamespace(bundleID: identifier)
            let store = APIKeyStore(namespace: namespace, backend: backend)
            XCTAssertNil(try store.read())
            XCTAssertThrowsError(try store.save("fixture-key"))
            XCTAssertThrowsError(try store.remove())
            XCTAssertTrue(backend.operations.isEmpty)
            XCTAssertNil(namespace.previousService)
        }
        let isolated = KeychainNamespace(bundleID: "be.spatie.daydreaming.preview.round4")
        XCTAssertEqual(isolated.service, "be.spatie.daydreaming.preview.round4.openai")
        XCTAssertEqual(production.service, "be.spatie.daydreaming.openai")
    }

    func testMigrationCopiesBeforeDeletingAndRunsOnlyOnce() throws {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .legacy)] = "fixture-key"
        let store = APIKeyStore(namespace: production, backend: backend)
        XCTAssertEqual(try store.read(), "fixture-key")
        XCTAssertEqual(backend.operations, ["read:dataProtection:be.spatie.daydreaming.openai", "read:legacy:be.spatie.daydreaming.openai", "save:be.spatie.daydreaming.openai", "remove:legacy:be.spatie.daydreaming.openai"])
        XCTAssertNil(backend.items[.init(service: production.service, storage: .legacy)])
        backend.operations.removeAll()
        XCTAssertEqual(try store.read(), "fixture-key")
        XCTAssertEqual(backend.operations, ["read:dataProtection:be.spatie.daydreaming.openai"])
    }

    func testPreviousAppServiceMigratesOnlyForProduction() throws {
        let backend = MemoryKeychain()
        backend.items[.init(service: "be.spatie.weathercanvas.openai", storage: .legacy)] = "fixture-old-key"
        XCTAssertEqual(try APIKeyStore(namespace: production, backend: backend).read(), "fixture-old-key")
        XCTAssertNil(backend.items[.init(service: "be.spatie.weathercanvas.openai", storage: .legacy)])

        let isolated = KeychainNamespace(bundleID: "be.spatie.daydreaming.other")
        XCTAssertNil(isolated.previousService)
        backend.operations.removeAll()
        XCTAssertNil(try APIKeyStore(namespace: isolated, backend: backend).read())
        XCTAssertFalse(backend.operations.contains { $0.contains("weathercanvas") || $0.hasSuffix(":be.spatie.daydreaming.openai") })
    }

    func testFailedWritePreservesTheLegacyKey() {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .legacy)] = "fixture-key"
        backend.failSave = true
        XCTAssertThrowsError(try APIKeyStore(namespace: production, backend: backend).read())
        XCTAssertEqual(backend.items[.init(service: production.service, storage: .legacy)], "fixture-key")
        XCTAssertFalse(backend.operations.contains { $0.hasPrefix("remove:") })
    }

    func testReadFailureDoesNotFallBackOrModifyCredentials() {
        let backend = MemoryKeychain()
        backend.failRead = .dataProtection
        XCTAssertThrowsError(try APIKeyStore(namespace: production, backend: backend).read())
        XCTAssertEqual(backend.operations, ["read:dataProtection:be.spatie.daydreaming.openai"])

        backend.operations.removeAll()
        backend.failRead = .legacy
        XCTAssertThrowsError(try APIKeyStore(namespace: production, backend: backend).read())
        XCTAssertFalse(backend.operations.contains { $0.hasPrefix("save:") || $0.hasPrefix("remove:") })
    }

    func testFailedLegacyCleanupKeepsTheNewKeyUsable() throws {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .legacy)] = "fixture-key"
        backend.failRemove = .legacy
        let store = APIKeyStore(namespace: production, backend: backend)
        XCTAssertEqual(try store.read(), "fixture-key")
        backend.operations.removeAll()
        XCTAssertEqual(try store.read(), "fixture-key")
        XCTAssertEqual(backend.operations, ["read:dataProtection:be.spatie.daydreaming.openai"])
    }

    func testRemovalCannotResurrectALegacyKey() throws {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .legacy)] = "fixture-old"
        backend.items[.init(service: production.service, storage: .dataProtection)] = "fixture-new"
        let store = APIKeyStore(namespace: production, backend: backend)
        backend.failRemove = .legacy
        try store.remove()
        XCTAssertNil(backend.items[.init(service: production.service, storage: .dataProtection)])
        XCTAssertEqual(backend.items[.init(service: production.service, storage: .legacy)], "fixture-old")
        XCTAssertNil(try store.read())
        XCTAssertTrue(store.migration.removed)
    }

    func testFirstLegacyReadFailureStillMigratesPreviousKey() throws {
        let backend = MemoryKeychain()
        backend.failedReads.insert(.init(service: production.service, storage: .legacy))
        backend.items[.init(service: "be.spatie.weathercanvas.openai", storage: .legacy)] = "fixture-old"
        let store = APIKeyStore(namespace: production, backend: backend)
        XCTAssertEqual(try store.read(), "fixture-old")
        XCTAssertEqual(backend.items[.init(service: production.service, storage: .dataProtection)], "fixture-old")
    }

    func testFailedMigrationIsAttemptedOnlyOncePerLaunch() {
        let backend = MemoryKeychain()
        backend.failRead = .legacy
        let store = APIKeyStore(namespace: production, backend: backend)
        XCTAssertThrowsError(try store.read())
        backend.operations.removeAll()
        XCTAssertThrowsError(try store.read())
        XCTAssertEqual(backend.operations, ["read:dataProtection:be.spatie.daydreaming.openai"])
    }

    func testRemovedMarkerSurvivesRelaunchAndIsClearedOnlyAfterSave() throws {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .legacy)] = "fixture-old"
        backend.failRemove = .legacy
        var persistedRemoval = false
        let state = KeychainMigrationState(persistRemoval: { persistedRemoval = $0 })
        try APIKeyStore(namespace: production, backend: backend, migration: state).remove()
        XCTAssertTrue(persistedRemoval)
        let relaunched = APIKeyStore(namespace: production, backend: backend,
                                    migration: KeychainMigrationState(removed: persistedRemoval,
                                                                      persistRemoval: { persistedRemoval = $0 }))
        backend.operations.removeAll()
        XCTAssertNil(try relaunched.read())
        XCTAssertEqual(backend.operations, ["read:dataProtection:be.spatie.daydreaming.openai"])
        backend.failSave = true
        XCTAssertThrowsError(try relaunched.save("fixture-new"))
        XCTAssertTrue(persistedRemoval)
        backend.failSave = false
        try relaunched.save("fixture-new")
        XCTAssertFalse(persistedRemoval)
        XCTAssertEqual(try relaunched.read(), "fixture-new")
    }

    func testFailedDataProtectionRemovalLeavesCredentialsAndMigrationEnabled() {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .dataProtection)] = "fixture-new"
        backend.failRemove = .dataProtection
        let store = APIKeyStore(namespace: production, backend: backend)
        XCTAssertThrowsError(try store.remove())
        XCTAssertFalse(store.migration.removed)
        XCTAssertEqual(backend.operations, ["remove:dataProtection:be.spatie.daydreaming.openai"])
        XCTAssertEqual(backend.items[.init(service: production.service, storage: .dataProtection)], "fixture-new")
    }

    func testLegacyCompatibilityModeDoesNotUseRestrictedKeychain() throws {
        let backend = MemoryKeychain()
        backend.items[.init(service: production.service, storage: .legacy)] = "fixture-old"
        let store = APIKeyStore(namespace: production, backend: backend, storage: .legacy)
        XCTAssertEqual(try store.read(), "fixture-old")
        try store.save("fixture-new")
        XCTAssertEqual(try store.read(), "fixture-new")
        XCTAssertEqual(backend.items[.init(service: production.service, storage: .legacy)], "fixture-new")
        XCTAssertFalse(backend.operations.contains { $0.contains("dataProtection") })
    }

    func testSecurityBackendRejectsHostedTestAccessBeforeQuerying() {
        XCTAssertTrue(AppRuntime.isRunningTests)
        XCTAssertThrowsError(try SecurityKeychainBackend().read(service: production.service, storage: .legacy))
        XCTAssertThrowsError(try SecurityKeychainBackend().save("fixture-key", service: production.service, storage: .dataProtection))
        XCTAssertThrowsError(try SecurityKeychainBackend().remove(service: production.service, storage: .dataProtection))
    }
}

private final class MemoryKeychain: KeychainBackend {
    struct Item: Hashable { let service: String; let storage: KeychainStorage }
    var items: [Item: String] = [:]
    var operations: [String] = []
    var failSave = false
    var failRead: KeychainStorage?
    var failedReads: Set<Item> = []
    var failRemove: KeychainStorage?

    func read(service: String, storage: KeychainStorage) throws -> String? {
        operations.append("read:\(storage):\(service)")
        if failRead == storage || failedReads.contains(.init(service: service, storage: storage)) {
            throw KeychainError.status(errSecInteractionNotAllowed)
        }
        return items[.init(service: service, storage: storage)]
    }

    func save(_ key: String, service: String, storage: KeychainStorage) throws {
        operations.append("save:\(service)")
        if failSave { throw KeychainError.status(errSecMissingEntitlement) }
        items[.init(service: service, storage: storage)] = key
    }

    func remove(service: String, storage: KeychainStorage) throws {
        operations.append("remove:\(storage):\(service)")
        if failRemove == storage { throw KeychainError.status(errSecInteractionNotAllowed) }
        items.removeValue(forKey: .init(service: service, storage: storage))
    }
}
