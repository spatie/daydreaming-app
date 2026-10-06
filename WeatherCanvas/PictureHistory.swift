import Foundation

/// The originals manifest never removes picture files or generated variations.
struct PictureHistory: Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let digest: String
        let name: String
        let originalURL: URL
        let importedAt: Date
        var id: String { digest }
    }

    let directory: URL
    private(set) var entries: [Entry]
    private let unreadableIndex: Bool
    private var indexURL: URL { directory.appendingPathComponent("picture-history.json") }

    init(directory: URL) {
        self.directory = directory
        let index = directory.appendingPathComponent("picture-history.json")
        let loaded = (try? Data(contentsOf: index)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }
        unreadableIndex = loaded == nil && FileManager.default.fileExists(atPath: index.path)
        entries = loaded ?? []
        entries.sort { $0.importedAt == $1.importedAt ? $0.digest < $1.digest : $0.importedAt > $1.importedAt }
    }

    func entry(for digest: String) -> Entry? { entries.first { $0.digest == digest } }

    mutating func record(digest: String, name: String, originalURL: URL, importedAt: Date = .now) throws {
        guard !unreadableIndex else { throw PictureHistoryError.unreadableHistory }
        guard !digest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, originalURL.isFileURL,
              (try? originalURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw PictureHistoryError.invalidOriginal
        }
        let existing = entry(for: digest)
        if let existing, FileManager.default.fileExists(atPath: existing.originalURL.path) { return }
        let entry = Entry(digest: digest, name: existing?.name ?? (name.isEmpty ? originalURL.lastPathComponent : name),
                          originalURL: originalURL.standardizedFileURL, importedAt: existing?.importedAt ?? importedAt)
        var updated = entries.filter { $0.digest != digest }
        updated.append(entry)
        updated.sort { $0.importedAt == $1.importedAt ? $0.digest < $1.digest : $0.importedAt > $1.importedAt }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: indexURL, options: .atomic)
        entries = updated
    }
}

enum PictureHistoryError: LocalizedError {
    case invalidOriginal, unreadableHistory
    var errorDescription: String? {
        switch self {
        case .invalidOriginal: "The original picture could not be found."
        case .unreadableHistory: "The picture history could not be read. Your saved pictures are still on this Mac."
        }
    }
}

struct PictureHistoryGalleryGroup: Identifiable, Equatable, Sendable {
    struct PromptGroup: Identifiable, Equatable, Sendable {
        let id: String
        let prompt: String?
        let variations: [SavedWallpaperItem]
        var newestDate: Date { variations.first?.entry.createdAt ?? .distantPast }
    }

    let id: String
    let original: PictureHistory.Entry?
    let prompts: [PromptGroup]
    let newestDate: Date
    var isEarlier: Bool { id == "earlier-pictures" }
    var variations: [SavedWallpaperItem] { prompts.flatMap(\.variations) }
    var latestVariation: SavedWallpaperItem? {
        variations.max { lhs, rhs in
            lhs.entry.createdAt == rhs.entry.createdAt ? lhs.id > rhs.id : lhs.entry.createdAt < rhs.entry.createdAt
        }
    }
    var name: String {
        isEarlier ? "Earlier Pictures" : original?.name ?? variations.first?.entry.settingsSnapshot?.pictureName ?? "Picture"
    }

    static func make(originals: [PictureHistory.Entry], variations: [SavedWallpaperItem]) -> [Self] {
        var originalByDigest: [String: PictureHistory.Entry] = [:]
        for original in originals where originalByDigest[original.digest] == nil {
            originalByDigest[original.digest] = original
        }
        var variationsByDigest: [String: [SavedWallpaperItem]] = [:]
        for item in variations {
            let snapshot = item.entry.settingsSnapshot
            let recordedDigest: String = item.entry.sourceDigest ?? snapshot?.originalPictureDigest
                ?? snapshot?.sourceDigest ?? item.entry.pictureID
            let matchedDigest: String? = originalByDigest[recordedDigest] == nil ? nil : recordedDigest
            let digest: String = item.entry.sourceDigest ?? matchedDigest ?? "earlier-pictures"
            variationsByDigest[digest, default: []].append(item)
        }
        for original in originals where variationsByDigest[original.digest] == nil {
            variationsByDigest[original.digest] = []
        }

        var result: [Self] = []
        for (digest, items) in variationsByDigest {
            let original = originalByDigest[digest]
            let prompts = promptGroups(from: items)
            let newestVariation = items.map { $0.entry.createdAt }.max() ?? Date.distantPast
            let newestImport = original?.importedAt ?? Date.distantPast
            result.append(Self(id: digest, original: original, prompts: prompts,
                               newestDate: max(newestImport, newestVariation)))
        }
        result.sort { lhs, rhs in
            if lhs.isEarlier != rhs.isEarlier { return !lhs.isEarlier }
            if lhs.newestDate != rhs.newestDate { return lhs.newestDate > rhs.newestDate }
            return lhs.id < rhs.id
        }
        return result
    }

    private static func promptGroups(from items: [SavedWallpaperItem]) -> [PromptGroup] {
        var itemsByPrompt: [String: [SavedWallpaperItem]] = [:]
        for item in items {
            let prompt = item.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = prompt?.nilIfEmpty ?? "prompt-not-saved"
            itemsByPrompt[key, default: []].append(item)
        }
        var groups: [PromptGroup] = []
        for (key, items) in itemsByPrompt {
            let sorted = items.sorted { lhs, rhs in
                if lhs.entry.createdAt != rhs.entry.createdAt { return lhs.entry.createdAt > rhs.entry.createdAt }
                return lhs.id < rhs.id
            }
            groups.append(PromptGroup(id: key, prompt: sorted.first?.prompt, variations: sorted))
        }
        groups.sort { lhs, rhs in
            if lhs.newestDate != rhs.newestDate { return lhs.newestDate > rhs.newestDate }
            return lhs.id < rhs.id
        }
        return groups
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
