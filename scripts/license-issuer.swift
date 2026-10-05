#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

private struct LicensePayload: Codable {
    let version: Int
    let product: String
    let id: String
    let tier: String
    let issuedAt: Int64
    let expiresAt: Int64?
}

private enum IssuerError: LocalizedError {
    case usage
    case existingKey
    case missingKey
    case invalidKey
    case keyMismatch
    case invalidDate
    case existingOutput

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: swift scripts/license-issuer.swift init | public-key | issue --output FILE [--id UUID] [--expires YYYY-MM-DD] [--private-key FILE]"
        case .existingKey: "The signing key already exists. Keep and back up that key."
        case .missingKey: "The signing key is missing. Run init first."
        case .invalidKey: "The signing key could not be read."
        case .keyMismatch: "The signing key does not match the public key bundled in Daydreaming."
        case .invalidDate: "Use a valid expiry date in YYYY-MM-DD format."
        case .existingOutput: "The output file already exists. Choose a new path."
        }
    }
}

private let defaultKeyPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Daydreaming Licensing/issuer.key")
private let bundledPublicKeyBase64 = "a6Z11QFiV+kaiKf+RTGuSAI8javeK6lUxU/5tqFfotA="

private func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

private func keyPath(in arguments: [String]) -> URL {
    guard let value = option("--private-key", in: arguments) else { return defaultKeyPath }
    return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
}

private func loadKey(at url: URL) throws -> Curve25519.Signing.PrivateKey {
    guard FileManager.default.fileExists(atPath: url.path) else { throw IssuerError.missingKey }
    let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: text),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        throw IssuerError.invalidKey
    }
    return key
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func expiryTimestamp(_ string: String) throws -> Int64 {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let day = formatter.date(from: string), formatter.string(from: day) == string,
          let nextDay = formatter.calendar.date(byAdding: .day, value: 1, to: day) else {
        throw IssuerError.invalidDate
    }
    return Int64(nextDay.timeIntervalSince1970)
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw IssuerError.usage }
    let url = keyPath(in: arguments)

    switch command {
    case "init":
        guard !FileManager.default.fileExists(atPath: url.path) else { throw IssuerError.existingKey }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let key = Curve25519.Signing.PrivateKey()
        let value = Data((key.rawRepresentation.base64EncodedString() + "\n").utf8)
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw IssuerError.existingKey }
        defer { close(descriptor) }
        try value.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = write(descriptor, base.advanced(by: written), bytes.count - written)
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                written += count
            }
        }
        print("Signing key saved at \(url.path)")
        print("Public key: \(key.publicKey.rawRepresentation.base64EncodedString())")
    case "public-key":
        print(try loadKey(at: url).publicKey.rawRepresentation.base64EncodedString())
    case "issue":
        guard let output = option("--output", in: arguments) else { throw IssuerError.usage }
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { throw IssuerError.existingOutput }
        let id = option("--id", in: arguments) ?? UUID().uuidString
        guard UUID(uuidString: id) != nil else { throw IssuerError.usage }
        let expiresAt = try option("--expires", in: arguments).map(expiryTimestamp)
        let payload = LicensePayload(
            version: 1,
            product: "be.spatie.daydreaming",
            id: id,
            tier: "pro",
            issuedAt: Int64(Date.now.timeIntervalSince1970),
            expiresAt: expiresAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let key = try loadKey(at: url)
        guard key.publicKey.rawRepresentation.base64EncodedString() == bundledPublicKeyBase64 else {
            throw IssuerError.keyMismatch
        }
        let signature = try key.signature(for: data)
        let token = "DDL1.\(base64URL(data)).\(base64URL(signature))\n"
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(token.utf8).write(to: outputURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
        print("License \(id) saved at \(outputURL.path)")
    default:
        throw IssuerError.usage
    }
}

do {
    try run()
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
