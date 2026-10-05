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

    static func selectedFile(_ url: URL, selector: String? = nil) throws -> ContextSource {
        guard url.isFileURL else { throw ContextSourceError.unsupportedFile }
        guard ["txt", "html", "htm", "json"].contains(url.pathExtension.lowercased()) else {
            throw ContextSourceError.unsupportedFile
        }
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return .localFile(name: url.lastPathComponent, bookmark: bookmark, selector: selector)
    }

    static func selectedWebPage(_ url: URL, selector: String) throws -> ContextSource {
        guard Self.isAllowedHTTPSURL(url) else { throw ContextSourceError.invalidWebsiteURL }
        guard !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextSourceError.selectorRequired
        }
        return .webPage(url: url, selector: selector)
    }

    static func isAllowedHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && !(url.host ?? "").isEmpty
            && url.user == nil
            && url.password == nil
    }

    private static func safeName(_ value: String) -> String {
        String(value.prefix(100))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
    }
}

enum ContextSourceError: LocalizedError, Sendable {
    case unsupportedFile
    case staleBookmark
    case fileAccessDenied
    case fileTooLarge
    case invalidTextEncoding
    case invalidWebsiteURL
    case selectorRequired
    case selectorNotFound(String)
    case emptySelection
    case invalidSelector(String)
    case websiteNotHTML
    case websiteFailed(Int)
    case tooManySources
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a text, HTML, or JSON file."
        case .staleBookmark: "This file has moved. Choose it again to restore access."
        case .fileAccessDenied: "The app cannot read this file. Choose it again to grant access."
        case .fileTooLarge: "This file is too large. The limit is 256 KB."
        case .invalidTextEncoding: "This source must contain UTF-8 text."
        case .invalidWebsiteURL: "Enter an HTTPS page URL without a username or password."
        case .selectorRequired: "Enter a CSS selector for the page element to read."
        case let .selectorNotFound(selector): "No page element matches ‘\(selector)’."
        case .emptySelection: "The selected element has no readable text."
        case let .invalidSelector(selector): "The CSS selector ‘\(selector)’ is invalid."
        case .websiteNotHTML: "The URL did not return an HTML page."
        case let .websiteFailed(status): "The page returned HTTP \(status)."
        case .tooManySources: "Use at most five context sources."
        case .responseTooLarge: "This page is too large. The limit is 256 KB."
        }
    }
}

struct ContextEntryPreview: Equatable, Sendable, Identifiable {
    let source: ContextSource
    let extractedText: String
    var wasTruncated = false

    var id: String { source.id }
    var displayName: String { source.displayName }
}

struct ContextPreview: Equatable, Sendable {
    let entries: [ContextEntryPreview]
    let promptText: String

    static let empty = ContextPreview(entries: [], promptText: "")
}
