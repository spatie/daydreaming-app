import Foundation

struct SavedWallpaperItem: Identifiable, Equatable, Sendable {
    let entry: HourWallpaperCache.Entry
    let url: URL
    var id: String { entry.filename }
    var prompt: String? { entry.settingsSnapshot?.promptTemplate }
}

struct SavedWallpaperGroup: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let prompt: String?
    let wallpapers: [SavedWallpaperItem]

    static func make(from items: [SavedWallpaperItem]) -> [Self] {
        let grouped = Dictionary(grouping: items) { item in
            let day = Calendar.current.startOfDay(for: item.entry.createdAt).timeIntervalSince1970
            return "\(day):\(item.prompt ?? item.entry.promptRecipeID ?? item.entry.recipeID)"
        }
        return grouped.map { id, entries in
            let sorted = entries.sorted { lhs, rhs in
                if lhs.entry.renderProfile != rhs.entry.renderProfile { return lhs.entry.renderProfile == .wallpaper }
                if lhs.entry.hour != rhs.entry.hour { return lhs.entry.hour < rhs.entry.hour }
                return lhs.entry.createdAt > rhs.entry.createdAt
            }
            return Self(id: id, date: Calendar.current.startOfDay(for: sorted[0].entry.createdAt),
                        prompt: sorted[0].prompt, wallpapers: sorted)
        }.sorted { lhs, rhs in lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date > rhs.date }
    }
}

/// One trackpad gesture moves through saved pictures, not through generation slots.
struct SavedVariationScrollPolicy {
    private var accumulated: CGFloat = 0
    private var lastStep: TimeInterval = -.infinity

    mutating func direction(delta: CGFloat, precise: Bool, momentum: Bool, began: Bool, timestamp: TimeInterval) -> Int? {
        if began { accumulated = 0 }
        guard !momentum, delta.isFinite, delta != 0 else { return nil }
        if !precise { return delta < 0 ? 1 : -1 }
        if accumulated.sign != delta.sign { accumulated = 0 }
        accumulated += delta
        guard abs(accumulated) >= 40, timestamp - lastStep >= 0.18 else { return nil }
        let direction = accumulated < 0 ? 1 : -1
        accumulated = 0
        lastStep = timestamp
        return direction
    }
}
