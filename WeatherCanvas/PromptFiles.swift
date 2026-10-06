import Foundation
import Darwin

enum LocalPromptFileDetector {
    static let maximumFiles = 3
    private static let rootNames = "Users|Volumes|private|tmp|var|etc|opt|Library|System|Applications|home|usr|bin|sbin|dev|mnt|root"
    private static let rootExpression = try? NSRegularExpression(pattern: #"(?:~/|/(?:"# + rootNames + #")/)"#, options: .caseInsensitive)
    private static let urlExpression = try? NSRegularExpression(pattern: #"(?<![/~])\b(?:[A-Za-z][A-Za-z0-9+.-]*://|www\.)[^\s\"'<>]+|(?<![\w./~])(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}/[^\s\"'<>]*"#)
    private static let readExpression = try? NSRegularExpression(pattern: #"\"((?:/|~/)[^\"\r\n]+)\"|'((?:/|~/)[^'\r\n]+)'|(?<![\w./~)])((?:~/|/)[^\s\"'<>]+)"#)
    static let userHomeDirectory: String = {
        var bufferSize = 16_384
        while bufferSize <= 1_048_576 {
            var record = passwd()
            var resolved: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: bufferSize)
            var status: Int32 = 0
            let home: String? = buffer.withUnsafeMutableBufferPointer { storage in
                guard let baseAddress = storage.baseAddress else { return nil }
                status = getpwuid_r(getuid(), &record, baseAddress, storage.count, &resolved)
                guard status == 0, let resolved, let directory = resolved.pointee.pw_dir else { return nil }
                return String(cString: directory)
            }
            if let home, home.hasPrefix("/") { return home }
            guard status == ERANGE else { break }
            bufferSize *= 2
        }
        return NSHomeDirectory()
    }()

    static func paths(in prompt: String) -> [String] {
        Array(allPaths(in: prompt).prefix(maximumFiles))
    }

    static func allPaths(in prompt: String) -> [String] {
        var seen = Set<String>()
        return references(in: prompt).compactMap { reference in
            guard PromptFileReader.isSupported(URL(fileURLWithPath: reference.path)),
                  seen.insert(reference.path).inserted else { return nil }
            return reference.path
        }
    }

    static func allPathLikePaths(in prompt: String) -> [String] {
        distinctPaths(privacyReferences(in: prompt))
    }

    static func quotedPaths(in prompt: String) -> [String] {
        distinctPaths(references(in: prompt).filter(\.quoted))
    }

    private static func distinctPaths(_ references: [Reference]) -> [String] {
        var seen = Set<String>()
        return references.compactMap { seen.insert($0.path).inserted ? $0.path : nil }
    }

    static func redactingPaths(in prompt: String) -> String {
        let redacted = NSMutableString(string: prompt)
        for reference in (privacyReferences(in: prompt) + fileURLReferences(in: prompt)).sorted(by: { $0.range.location > $1.range.location }) {
            redacted.replaceCharacters(in: reference.range,
                                       with: "[file: \(URL(fileURLWithPath: reference.path).lastPathComponent)]")
        }
        return redacted as String
    }

    static func referencedBookmarks(_ bookmarks: [String: Data], in prompt: String) -> [String: Data] {
        let paths = Set(allPaths(in: prompt))
        return bookmarks.filter { paths.contains($0.key) }
    }

    private struct Reference {
        let range: NSRange
        let path: String
        let quoted: Bool
        let isPathLike: Bool
    }

    /// Space-tolerant matches protect privacy only. They never authorize reading a guessed file.
    private static func privacyReferences(in prompt: String) -> [Reference] {
        var candidates = references(in: prompt).filter(\.isPathLike)
        let otherRoots = rootNames.split(separator: "|").filter { $0 != "Users" && $0 != "Volumes" }.joined(separator: "|")
        let prefix = #"(?:/(?:Users|Volumes)/|(?<![\w./~])(?:~/|/(?:"# + otherRoots + #")/))"#
        let extensions = PromptFileReader.supportedExtensions.joined(separator: "|")
        let patterns = [
            prefix + #"[^\r\n\"'<>.,;:!?)}\]]{0,255}?\.(?:"# + extensions + #")(?=$|[\s.,;:!?)}\]])"#,
            // Also protect unsupported filenames when the interior space is in a folder component.
            prefix + #"(?=[^\r\n\"'<>.,;:!?)}\]]{0,255}\s[^/\r\n\"'<>.,;:!?)}\]]{1,255}/)[^\r\n\"'<>.,;:!?)}\]]{0,255}?\.[A-Za-z0-9]{1,10}(?=$|[\s.,;:!?)}\]])"#,
            prefix + #"[^\s\"'<>]+"#,
        ]
        let scanRange = NSRange(prompt.startIndex..., in: prompt)
        let urlRanges = urlExpression?.matches(in: prompt, range: scanRange).map(\.range) ?? []
        for (patternIndex, pattern) in patterns.enumerated() {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in expression.matches(in: prompt, range: scanRange) {
                // Separate paths joined by prose must use their individual privacy matches.
                if patternIndex < 2, (rootExpression?.numberOfMatches(in: prompt, range: match.range) ?? 0) > 1 { continue }
                var end = NSMaxRange(match.range)
                var belongsToURL = false
                for urlRange in urlRanges where NSIntersectionRange(urlRange, match.range).length > 0 {
                    if urlRange.location <= match.range.location { belongsToURL = true; break }
                    end = min(end, urlRange.location)
                }
                guard !belongsToURL, let swiftRange = Range(NSRange(location: match.range.location, length: end - match.range.location), in: prompt) else { continue }
                var candidate = String(prompt[swiftRange])
                while let last = candidate.last, last.isWhitespace || ".,;:!?)]}".contains(last) { candidate.removeLast() }
                guard let path = normalizedPath(candidate) else { continue }
                candidates.append(Reference(range: NSRange(location: match.range.location, length: (candidate as NSString).length),
                                            path: path, quoted: false, isPathLike: true))
            }
        }
        let ordered = candidates.sorted {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
        var selected: [Reference] = []
        var selectedEnd = 0
        for candidate in ordered where candidate.range.location >= selectedEnd {
            selected.append(candidate)
            selectedEnd = NSMaxRange(candidate.range)
        }
        return selected
    }

    private static func fileURLReferences(in prompt: String) -> [Reference] {
        let pattern = #"\"(file://[^\"\r\n]+)\"|'(file://[^'\r\n]+)'|(?<![\w])file://[^\s\"'<>]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return expression.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)).compactMap { match in
            let capture = (1...2).first { match.range(at: $0).location != NSNotFound }
            let range = capture.map { match.range(at: $0) } ?? match.range
            guard let swiftRange = Range(range, in: prompt) else { return nil }
            var candidate = String(prompt[swiftRange])
            if capture == nil {
                while let last = candidate.last, ".,;:!?)]}".contains(last) { candidate.removeLast() }
            }
            guard let url = URL(string: candidate), url.isFileURL, !url.path.isEmpty else { return nil }
            let replacementRange = capture == nil
                ? NSRange(location: match.range.location, length: (candidate as NSString).length) : match.range
            return Reference(range: replacementRange, path: url.path, quoted: capture != nil, isPathLike: true)
        }
    }

    private static func references(in prompt: String) -> [Reference] {
        guard let urls = urlExpression, let paths = readExpression else { return [] }
        let range = NSRange(prompt.startIndex..., in: prompt)
        let urlRanges = urls.matches(in: prompt, range: range).map(\.range)
        var result: [Reference] = []
        for match in paths.matches(in: prompt, range: range) {
            guard !urlRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
            guard let capture = (1...3).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            guard let matchedRange = Range(match.range(at: capture), in: prompt) else { continue }
            var candidate = String(prompt[matchedRange])
            if capture >= 3 {
                while let last = candidate.last, ".,;:!?)]}".contains(last) { candidate.removeLast() }
            }
            guard let path = normalizedPath(candidate) else { continue }
            let replacementRange = capture >= 3
                ? NSRange(location: match.range.location, length: (candidate as NSString).length)
                : match.range
            let hasFileExtension = !URL(fileURLWithPath: candidate).pathExtension.isEmpty
            let startsAtFileRoot = candidate.hasPrefix("~/") || rootNames.split(separator: "|").contains { candidate.hasPrefix("/" + $0 + "/") }
            result.append(Reference(range: replacementRange, path: path, quoted: capture <= 2,
                                    isPathLike: capture <= 2 || hasFileExtension || startsAtFileRoot))
        }
        return result
    }

    static func normalizedPath(_ path: String, homeDirectory: String? = nil) -> String? {
        guard path.hasPrefix("/") || path.hasPrefix("~/"), !path.contains("\0") else { return nil }
        let expanded = path.hasPrefix("~/")
            ? (homeDirectory ?? userHomeDirectory) + "/" + path.dropFirst(2)
            : path
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}

protocol PromptFileBookmarkBackend: Sendable {
    func make(url: URL) throws -> Data
    func resolve(data: Data) throws -> URL
    func resolveForReading(data: Data) throws -> PromptFileBookmarkResolution
}

struct PromptFileBookmarkResolution: Sendable {
    let url: URL
    let refreshedBookmark: Data?
}

extension PromptFileBookmarkBackend {
    func resolveForReading(data: Data) throws -> PromptFileBookmarkResolution {
        PromptFileBookmarkResolution(url: try resolve(data: data), refreshedBookmark: nil)
    }
}

struct SecurityScopedPromptFileBookmarks: PromptFileBookmarkBackend {
    func make(url: URL) throws -> Data {
        guard url.isFileURL, PromptFileReader.isSupported(url) else { throw PromptFileError.unsupportedFile }
        return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                    includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(data: Data) throws -> URL {
        try resolveForReading(data: data).url
    }

    func resolveForReading(data: Data) throws -> PromptFileBookmarkResolution {
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            throw PromptFileError.accessDenied
        }
        guard url.isFileURL else { throw PromptFileError.unsupportedFile }
        guard stale else { return PromptFileBookmarkResolution(url: url, refreshedBookmark: nil) }
        guard url.startAccessingSecurityScopedResource() else { throw PromptFileError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return PromptFileBookmarkResolution(url: url, refreshedBookmark: try make(url: url))
    }
}

struct PromptFileReader: Sendable {
    static let maximumBodyBytes = 256_000
    static let maximumCharacters = 2_400
    static let supportedExtensions = ["txt", "md", "markdown", "json", "html", "htm"]
    typealias Loader = @Sendable (URL, Int) async throws -> Data

    private let bookmarks: any PromptFileBookmarkBackend
    private let loader: Loader

    init(bookmarks: any PromptFileBookmarkBackend = SecurityScopedPromptFileBookmarks(),
         loader: @escaping Loader = PromptFileReader.loadSecurityScopedFile) {
        self.bookmarks = bookmarks
        self.loader = loader
    }

    static func isSupported(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Resolves a previously granted file without displaying a permission panel.
    static func resolvedPath(bookmark: Data,
                             bookmarks: any PromptFileBookmarkBackend = SecurityScopedPromptFileBookmarks()) throws -> String {
        let url = try bookmarks.resolve(data: bookmark)
        guard isSupported(url) else { throw PromptFileError.unsupportedFile }
        return url.standardizedFileURL.path
    }

    static func uniqueLegacyReconnectionMatch(in references: [LegacyPromptFileReference], url: URL,
                                             bookmarks: any PromptFileBookmarkBackend = SecurityScopedPromptFileBookmarks()) -> LegacyPromptFileReference? {
        let exact = references.filter { reference in
            guard let previous = try? bookmarks.resolve(data: reference.bookmark) else { return false }
            return previous.standardizedFileURL == url.standardizedFileURL
                || previous.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL
        }
        if exact.count == 1 { return exact.first }
        guard exact.isEmpty else { return nil }
        let sameName = references.filter { $0.name == url.lastPathComponent }
        guard sameName.count == 1, let reference = sameName.first,
              (try? bookmarks.resolve(data: reference.bookmark)) == nil else { return nil }
        return reference
    }

    func read(path: String, bookmark: Data) async throws -> String {
        try await readResult(path: path, bookmark: bookmark).text
    }

    func readResult(path: String, bookmark: Data) async throws -> PromptFileReadResult {
        guard let normalized = LocalPromptFileDetector.normalizedPath(path),
              Self.isSupported(URL(fileURLWithPath: normalized)) else { throw PromptFileError.unsupportedFile }
        let resolution = try bookmarks.resolveForReading(data: bookmark)
        let url = resolution.url
        guard Self.isSupported(url) else { throw PromptFileError.unsupportedFile }
        let data = try await loader(url, Self.maximumBodyBytes)
        guard data.count <= Self.maximumBodyBytes else { throw PromptFileError.fileTooLarge }
        guard let content = String(data: data, encoding: .utf8) else { throw PromptFileError.invalidTextEncoding }
        let text: String
        if ["html", "htm"].contains(url.pathExtension.lowercased()) {
            text = try PromptContextReader.extractText(data: data, mimeType: "text/html", url: url)
        } else {
            text = content
        }
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { throw PromptFileError.emptyFile }
        return PromptFileReadResult(text: String(collapsed.prefix(Self.maximumCharacters)),
                                    refreshedBookmark: resolution.refreshedBookmark)
    }

    private static func loadSecurityScopedFile(_ url: URL, maximumBytes: Int) async throws -> Data {
        try await Task.detached(priority: .utility) {
            guard url.startAccessingSecurityScopedResource() else { throw PromptFileError.accessDenied }
            defer { url.stopAccessingSecurityScopedResource() }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw PromptFileError.unsupportedFile }
            if let size = values.fileSize, size > maximumBytes { throw PromptFileError.fileTooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while let chunk = try handle.read(upToCount: min(64_000, maximumBytes - data.count + 1)), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= maximumBytes else { throw PromptFileError.fileTooLarge }
                try Task.checkCancellation()
            }
            return data
        }.value
    }
}

struct PromptFileReadResult: Sendable {
    let text: String
    let refreshedBookmark: Data?
}

extension CanvasSettings {
    mutating func forgetUnresolvedPromptFiles() {
        unresolvedPromptFiles.removeAll()
    }

    mutating func retryUnresolvedPromptFiles(bookmarks: any PromptFileBookmarkBackend = SecurityScopedPromptFileBookmarks()) {
        let originalPrompt = promptTemplate
        var unresolved: [LegacyPromptFileReference] = []
        var knownPaths = Set(LocalPromptFileDetector.allPaths(in: promptTemplate))
        for reference in unresolvedPromptFiles {
            guard let resolution = try? bookmarks.resolveForReading(data: reference.bookmark),
                  PromptFileReader.isSupported(resolution.url) else {
                unresolved.append(reference)
                continue
            }
            let path = resolution.url.standardizedFileURL.path
            promptFileBookmarks[path] = resolution.refreshedBookmark ?? reference.bookmark
            if knownPaths.insert(path).inserted { promptTemplate += "\n\"" + path + "\"" }
        }
        unresolvedPromptFiles = unresolved
        if originalPrompt != promptTemplate {
            legacyCustomPrompt = promptTemplate
            extraInstructions = promptTemplate
        }
    }
}

enum PromptFileError: LocalizedError, Sendable, Equatable {
    case unsupportedFile, accessDenied, staleBookmark, fileTooLarge, invalidTextEncoding, emptyFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a text, Markdown, HTML or JSON file."
        case .accessDenied: "Choose this file again to allow Daydreaming to read it."
        case .staleBookmark: "This file has changed location. Choose it again."
        case .fileTooLarge: "Choose a file smaller than 256 KB."
        case .invalidTextEncoding: "This file needs to contain UTF-8 text."
        case .emptyFile: "This file has no readable text."
        }
    }
}
