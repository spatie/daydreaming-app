import CryptoKit
import Foundation
import Security

struct LicensePayload: Codable, Equatable, Sendable {
    let version: Int
    let product: String
    let id: String
    let tier: String
    let issuedAt: Int64
    let expiresAt: Int64?

    var expirationDate: Date? {
        expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

enum LicenseValidationError: LocalizedError, Equatable {
    case invalidFormat
    case invalidSignature
    case invalidPayload
    case unsupportedVersion
    case notYetValid
    case expired
    case verificationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "That license key is not in the expected format."
        case .invalidSignature: "That license key could not be verified."
        case .invalidPayload: "That license key contains invalid information."
        case .unsupportedVersion: "Update the app to use this license key."
        case .notYetValid: "That license key is not valid yet. Check your Mac's date and time."
        case .expired: "That license key has expired."
        case .verificationUnavailable: "This app cannot verify license keys."
        }
    }
}

struct LicenseManager {
    static let shared = LicenseManager()

    private static let bundledPublicKeyBase64 = "a6Z11QFiV+kaiKf+RTGuSAI8javeK6lUxU/5tqFfotA="
    private static let keychainService = "be.spatie.daydreaming.license"
    private static let keychainAccount = "pro-license-token"
    private let publicKeyBase64: String

    init(publicKeyBase64: String = bundledPublicKeyBase64) {
        self.publicKeyBase64 = publicKeyBase64
    }

    func currentLicense(now: Date = .now) throws -> LicensePayload? {
        guard let token = try readToken() else { return nil }
        do {
            return try verify(token, now: now)
        } catch is LicenseValidationError {
            return nil
        }
    }

    @discardableResult
    func activate(_ token: String, now: Date = .now) throws -> LicensePayload {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let license = try verify(normalized, now: now)
        try saveToken(normalized)
        return license
    }

    func remove() throws {
        let status = SecItemDelete(Self.keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    func verify(_ token: String, now: Date = .now) throws -> LicensePayload {
        guard token.utf8.count <= 16_384 else { throw LicenseValidationError.invalidFormat }
        let components = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "DDL1",
              let payloadData = Self.decodeBase64URL(String(components[1])),
              let signature = Self.decodeBase64URL(String(components[2])),
              signature.count == 64 else {
            throw LicenseValidationError.invalidFormat
        }

        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw LicenseValidationError.verificationUnavailable
        }
        guard publicKey.isValidSignature(signature, for: payloadData) else {
            throw LicenseValidationError.invalidSignature
        }

        guard let license = try? JSONDecoder().decode(LicensePayload.self, from: payloadData),
              license.product == "be.spatie.daydreaming",
              UUID(uuidString: license.id) != nil,
              license.tier == "pro",
              license.issuedAt > 0,
              license.expiresAt.map({ $0 > license.issuedAt }) ?? true else {
            throw LicenseValidationError.invalidPayload
        }
        guard license.version == 1 else { throw LicenseValidationError.unsupportedVersion }

        let timestamp = Int64(now.timeIntervalSince1970)
        guard license.issuedAt <= timestamp + 300 else { throw LicenseValidationError.notYetValid }
        guard license.expiresAt.map({ timestamp < $0 }) ?? true else { throw LicenseValidationError.expired }
        return license
    }

    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private func readToken() throws -> String? {
        var query = Self.keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw LicenseValidationError.invalidFormat
        }
        return token
    }

    private func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemCopyMatching(Self.keychainQuery as CFDictionary, nil)
        if status == errSecItemNotFound {
            var item = Self.keychainQuery
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
            return
        }

        guard status == errSecSuccess else { throw KeychainError.status(status) }
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(Self.keychainQuery as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        guard !text.isEmpty,
              text.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
              }) else { return nil }
        let base64 = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64 + padding)
    }
}
