import CryptoKit
import XCTest
@testable import Daydreaming

final class LicenseManagerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidProLicense() throws {
        let key = Curve25519.Signing.PrivateKey()
        let manager = LicenseManager(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString())
        let license = payload(issuedAt: 1_799_999_900, expiresAt: nil)

        XCTAssertEqual(try manager.verify(token(for: license, signedBy: key), now: now), license)
    }

    func testTamperedPayloadIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let manager = LicenseManager(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString())
        let original = token(for: payload(issuedAt: 1_799_999_900, expiresAt: nil), signedBy: key)
        let parts = original.split(separator: ".")
        let changedFirstCharacter = parts[1].first == "A" ? "B" : "A"
        let tampered = "DDL1.\(changedFirstCharacter)\(parts[1].dropFirst()).\(parts[2])"

        XCTAssertThrowsError(try manager.verify(tampered, now: now)) { error in
            XCTAssertEqual(error as? LicenseValidationError, .invalidSignature)
        }
    }

    func testExpiredLicenseIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let manager = LicenseManager(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString())
        let license = payload(issuedAt: 1_799_999_000, expiresAt: 1_800_000_000)

        XCTAssertThrowsError(try manager.verify(token(for: license, signedBy: key), now: now)) { error in
            XCTAssertEqual(error as? LicenseValidationError, .expired)
        }
    }

    func testLicenseForAnotherProductIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let manager = LicenseManager(publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString())
        let license = LicensePayload(
            version: 1,
            product: "be.spatie.anotherapp",
            id: UUID().uuidString,
            tier: "pro",
            issuedAt: 1_799_999_900,
            expiresAt: nil
        )

        XCTAssertThrowsError(try manager.verify(token(for: license, signedBy: key), now: now)) { error in
            XCTAssertEqual(error as? LicenseValidationError, .invalidPayload)
        }
    }

    private func payload(issuedAt: Int64, expiresAt: Int64?) -> LicensePayload {
        LicensePayload(
            version: 1,
            product: "be.spatie.daydreaming",
            id: UUID().uuidString,
            tier: "pro",
            issuedAt: issuedAt,
            expiresAt: expiresAt
        )
    }

    private func token(for payload: LicensePayload, signedBy key: Curve25519.Signing.PrivateKey) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(payload)
        let signature = try! key.signature(for: data)
        return "DDL1.\(base64URL(data)).\(base64URL(signature))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
