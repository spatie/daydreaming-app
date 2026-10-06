import Foundation
import LocalAuthentication
import Security

enum KeychainStorage: Hashable {
    case dataProtection, legacy
}

protocol KeychainBackend {
    func read(service: String, storage: KeychainStorage) throws -> String?
    func save(_ key: String, service: String, storage: KeychainStorage) throws
    func remove(service: String, storage: KeychainStorage) throws
}

final class KeychainMigrationState {
    var attempted = false
    var failed = false
    private(set) var removed: Bool
    private let persistRemoval: ((Bool) -> Void)?

    init(removed: Bool = false, persistRemoval: ((Bool) -> Void)? = nil) {
        self.removed = removed
        self.persistRemoval = persistRemoval
    }

    func markRemoved() {
        removed = true
        persistRemoval?(true)
    }

    func markSaved() {
        removed = false
        attempted = false
        failed = false
        persistRemoval?(false)
    }
}

/// Migration can be tested without Security APIs or the person's keychain.
struct APIKeyStore {
    let namespace: KeychainNamespace
    let backend: any KeychainBackend
    var storage: KeychainStorage = .dataProtection
    var migration = KeychainMigrationState()

    func read() throws -> String? {
        guard namespace.allowsAccess else { return nil }
        if storage == .legacy { return try readLegacy() }
        if let key = try backend.read(service: namespace.service, storage: .dataProtection) { return key }
        guard !migration.removed else { return nil }
        if migration.attempted {
            if migration.failed { throw KeychainError.legacyUnavailable }
            return nil
        }
        migration.attempted = true
        var failed = false
        for service in legacyServices {
            let key: String?
            do { key = try backend.read(service: service, storage: .legacy) }
            catch { failed = true; continue }
            guard let key else { continue }
            // Never delete the only copy if the new keychain rejects the write.
            do { try backend.save(key, service: namespace.service, storage: .dataProtection) }
            catch { migration.failed = true; throw error }
            // Failed cleanup leaves both copies safe; future reads use the new one.
            try? backend.remove(service: service, storage: .legacy)
            return key
        }
        migration.failed = failed
        if failed { throw KeychainError.legacyUnavailable }
        return nil
    }

    func save(_ key: String) throws {
        guard namespace.allowsAccess else { throw KeychainError.previewUnavailable }
        try backend.save(key, service: namespace.service, storage: storage)
        migration.markSaved()
    }

    func remove() throws {
        guard namespace.allowsAccess else { throw KeychainError.previewUnavailable }
        if storage == .dataProtection {
            try backend.remove(service: namespace.service, storage: .dataProtection)
            // Persist before legacy cleanup, so an inaccessible copy cannot return on relaunch.
            migration.markRemoved()
            for service in legacyServices { try? backend.remove(service: service, storage: .legacy) }
        } else {
            for service in legacyServices { try backend.remove(service: service, storage: .legacy) }
        }
    }

    private func readLegacy() throws -> String? {
        var failed = false
        for service in legacyServices {
            do {
                if let key = try backend.read(service: service, storage: .legacy) {
                    if service != namespace.service && !migration.attempted {
                        migration.attempted = true
                        do {
                            try backend.save(key, service: namespace.service, storage: .legacy)
                            try? backend.remove(service: service, storage: .legacy)
                        } catch {
                            // Keep the readable original if a different signature owns the current item.
                        }
                    }
                    return key
                }
            } catch { failed = true }
        }
        if failed { throw KeychainError.legacyUnavailable }
        return nil
    }

    private var legacyServices: [String] {
        [namespace.service] + (namespace.previousService.map { [$0] } ?? [])
    }
}

@MainActor
enum KeychainStore {
    private static var providerStores: [String: APIKeyStore] = [:]
    private static let store: APIKeyStore = {
        let namespace = KeychainNamespace(bundleID: Bundle.main.bundleIdentifier)
        // The restricted entitlement stays opt-in until a provisioning profile is available.
        let enabled = Bundle.main.object(forInfoDictionaryKey: "KeychainUsesDataProtection") as? String == "YES"
        let marker = "legacyAPIKeyRemoved"
        let migration = namespace.allowsAccess
            ? KeychainMigrationState(removed: UserDefaults.standard.bool(forKey: marker),
                                     persistRemoval: { UserDefaults.standard.set($0, forKey: marker) })
            : KeychainMigrationState()
        return APIKeyStore(namespace: namespace, backend: SecurityKeychainBackend(),
                           storage: enabled ? .dataProtection : .legacy, migration: migration)
    }()

    static func read() throws -> String? { try store.read() }
    static func save(_ key: String) throws { try store.save(key) }
    static func remove() throws { try store.remove() }

    static func read(provider: ImageProviderConfiguration) throws -> String? { try providerStore(provider).read() }
    static func save(_ key: String, provider: ImageProviderConfiguration) throws { try providerStore(provider).save(key) }
    static func remove(provider: ImageProviderConfiguration) throws { try providerStore(provider).remove() }

    private static func providerStore(_ provider: ImageProviderConfiguration) -> APIKeyStore {
        if provider.credentialID == "openai" { return store }
        if let existing = providerStores[provider.credentialID] { return existing }
        let namespace = KeychainNamespace(bundleID: Bundle.main.bundleIdentifier, providerID: provider.credentialID)
        let enabled = Bundle.main.object(forInfoDictionaryKey: "KeychainUsesDataProtection") as? String == "YES"
        let marker = "imageCredentialRemoved." + provider.credentialID
        let migration = namespace.allowsAccess
            ? KeychainMigrationState(removed: UserDefaults.standard.bool(forKey: marker),
                                     persistRemoval: { UserDefaults.standard.set($0, forKey: marker) })
            : KeychainMigrationState()
        let result = APIKeyStore(namespace: namespace, backend: SecurityKeychainBackend(),
                                storage: enabled ? .dataProtection : .legacy, migration: migration)
        providerStores[provider.credentialID] = result
        return result
    }
}

struct SecurityKeychainBackend: KeychainBackend {
    private static let legacyLock = NSLock()
    private let account: String

    init(account: String = "image-api-key") { self.account = account }

    func read(service: String, storage: KeychainStorage) throws -> String? {
        var query = try query(service: service, storage: storage)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return try perform(storage: storage) {
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw KeychainError.status(status) }
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        }
    }

    func save(_ key: String, service: String, storage: KeychainStorage) throws {
        let query = try query(service: service, storage: storage)
        try perform(storage: storage) {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            if storage == .dataProtection {
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem {
                let update = [kSecValueData as String: Data(key.utf8)]
                let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
                guard result == errSecSuccess else { throw KeychainError.status(result) }
            } else if status != errSecSuccess {
                throw KeychainError.status(status)
            }
        }
    }

    func remove(service: String, storage: KeychainStorage) throws {
        let query = try query(service: service, storage: storage)
        try perform(storage: storage) {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
        }
    }

    private func query(service: String, storage: KeychainStorage) throws -> [String: Any] {
        guard !AppRuntime.isPreview, !AppRuntime.isRunningTests else { throw KeychainError.previewUnavailable }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: storage == .dataProtection,
        ]
        if storage == .dataProtection {
            guard let bundleID = Bundle.main.bundleIdentifier,
                  let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
                  group.hasSuffix("." + bundleID), !group.contains("$(") else {
                throw KeychainError.missingAccessGroup
            }
            query[kSecAttrAccessGroup as String] = group
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    private func perform<T>(storage: KeychainStorage, operation: () throws -> T) throws -> T {
        guard storage == .legacy else { return try operation() }
        // File-keychain ACL dialogs do not reliably honor LocalAuthentication UI settings.
        // Serialize and restore this process-wide legacy switch even if an operation fails.
        Self.legacyLock.lock()
        defer { Self.legacyLock.unlock() }
        var allowed: DarwinBoolean = false
        let getStatus = SecKeychainGetUserInteractionAllowed(&allowed)
        guard getStatus == errSecSuccess else { throw KeychainError.status(getStatus) }
        let setStatus = SecKeychainSetUserInteractionAllowed(false)
        guard setStatus == errSecSuccess else { throw KeychainError.status(setStatus) }
        defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return try operation()
    }
}

enum KeychainError: LocalizedError {
    case previewUnavailable, missingAccessGroup, invalidData, legacyUnavailable
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .previewUnavailable: "Keychain access is unavailable in preview builds."
        case .missingAccessGroup: "This build needs a valid signing identity to save your API key."
        case .invalidData: "The saved API key could not be read. Add your key again."
        case .legacyUnavailable: "Your saved key couldn't be moved. Add it again."
        case .status(let status) where status == errSecInteractionNotAllowed:
            "Your saved key belongs to another build. Remove it in Keychain Access, then add it again."
        case .status(let status): "Keychain error \(status)."
        }
    }
}
