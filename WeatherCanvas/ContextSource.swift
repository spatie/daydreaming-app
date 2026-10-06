import CryptoKit
import Foundation

enum ContextSource: Codable, Equatable, Sendable, Identifiable {
    case localFile(name: String, bookmark: Data, selector: String?)
    case webPage(url: URL, selector: String)

    var id: String {
        let data: Data
        switch self {
        case let .localFile(_, bookmark, selector):
            data = bookmark + Data((selector ?? "").utf8)
        case let .webPage(url, selector):
            data = Data((url.absoluteString + selector).utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var displayName: String {
        switch self {
        case let .localFile(name, _, _):
            return Self.safeName(name)
        case let .webPage(url, selector):
            return "\(url.host ?? "Website") · \(Self.safeName(selector))"
        }
    }

    private static func safeName(_ value: String) -> String {
        String(value.prefix(100))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
    }
}
