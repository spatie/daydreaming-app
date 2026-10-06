import XCTest
@testable import Daydreaming

final class PictureHistoryTests: XCTestCase {
    func testManifestPersistsEveryOriginalAndDeduplicatesWithoutDeletingCopies() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try original("first.png", in: directory)
        let second = try original("second.png", in: directory)
        let duplicate = try original("another-copy.png", in: directory)
        var history = PictureHistory(directory: directory)
        try history.record(digest: "first", name: "Forest", originalURL: first, importedAt: Date(timeIntervalSince1970: 1))
        try history.record(digest: "second", name: "Sea", originalURL: second, importedAt: Date(timeIntervalSince1970: 2))
        try history.record(digest: "first", name: "Forest again", originalURL: duplicate, importedAt: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(history.entries.map(\.digest), ["second", "first"])
        XCTAssertEqual(history.entry(for: "first")?.name, "Forest")
        XCTAssertEqual(history.entry(for: "first")?.importedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(history.entry(for: "first")?.originalURL, first.standardizedFileURL)
        XCTAssertEqual(PictureHistory(directory: directory).entries, history.entries)
        for url in [first, second, duplicate] { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testMissingOriginalMetadataSurvivesAndReselectingRepairsItsReference() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try original("first.png", in: directory)
        var history = PictureHistory(directory: directory)
        try history.record(digest: "first", name: "Forest", originalURL: first)
        try FileManager.default.removeItem(at: first)
        history = PictureHistory(directory: directory)
        XCTAssertEqual(history.entries.count, 1)
        let replacement = try original("replacement.png", in: directory)
        try history.record(digest: "first", name: "Forest", originalURL: replacement)
        XCTAssertEqual(history.entry(for: "first")?.originalURL, replacement.standardizedFileURL)
    }

    func testUnreadableManifestIsNotOverwrittenByASelection() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("picture-history.json")
        let damaged = Data("unreadable history".utf8)
        try damaged.write(to: index)
        let image = try original("picture.png", in: directory)
        var history = PictureHistory(directory: directory)
        XCTAssertThrowsError(try history.record(digest: "picture", name: "Picture", originalURL: image))
        XCTAssertEqual(try Data(contentsOf: index), damaged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    }

    func testGallerySeparatesOriginalsWithTheSamePromptAndSortsPromptsNewestFirst() {
        let forest = entry("forest", date: 1)
        let sea = entry("sea", date: 2)
        let noVariations = entry("mountain", date: 4)
        let older = variation("forest-old", digest: "forest", prompt: "Sunny", date: 10)
        let newer = variation("forest-new", digest: "forest", prompt: "Moonlit", date: 20)
        let another = variation("forest-another", digest: "forest", prompt: "Sunny", date: 11)
        let otherSource = variation("sea-same-prompt", digest: "sea", prompt: "Sunny", date: 30)
        let legacy = variation("legacy", digest: nil, prompt: nil, date: 100)
        let groups = PictureHistoryGalleryGroup.make(originals: [forest, sea, noVariations],
                                                     variations: [older, newer, another, otherSource, legacy])
        XCTAssertEqual(groups.map(\.id), ["sea", "forest", "mountain", "earlier-pictures"])
        XCTAssertEqual(groups[1].prompts.map(\.prompt), ["Moonlit", "Sunny"])
        XCTAssertEqual(groups[1].prompts[1].variations.map(\.id), ["forest-another.png", "forest-old.png"])
        XCTAssertEqual(groups[0].variations.map(\.id), ["sea-same-prompt.png"])
        XCTAssertTrue(groups[2].variations.isEmpty)
        XCTAssertEqual(groups[3].name, "Earlier Pictures")
        XCTAssertEqual(groups.flatMap(\.variations).count, 5)
    }

    func testLegacySnapshotDigestJoinsItsOriginalButUnknownLegacyRecordsStayEarlier() {
        var settings = CanvasSettings()
        settings.sourceDigest = "forest"
        let cached = variation("legacy-known", digest: nil, prompt: "Sunny", date: 3, settings: settings)
        var unavailableSettings = CanvasSettings()
        unavailableSettings.sourceDigest = "unavailable-original"
        let unknown = variation("legacy-unknown", digest: nil, prompt: nil, date: 4, settings: unavailableSettings)
        let groups = PictureHistoryGalleryGroup.make(originals: [entry("forest", date: 1)], variations: [unknown, cached])
        XCTAssertEqual(groups.map(\.id), ["forest", "earlier-pictures"])
        XCTAssertEqual(groups[0].variations.first?.id, "legacy-known.png")
    }

    func testOriginalUsesItsMostRecentIdeaAndFramingWithoutDroppingCachedVariations() {
        let older = variation("older", digest: "forest", prompt: "Warm morning", date: 1)
        var settings = CanvasSettings()
        settings.sourceCrop = PictureCrop(imageSize: CGSize(width: 1200, height: 800), targetAspectRatio: 1.6, zoom: 1.5)
        let newest = variation("newest", digest: "forest", prompt: "Evening mist", date: 3, settings: settings)
        let another = variation("another", digest: "forest", prompt: "Warm morning", date: 2)
        let group = PictureHistoryGalleryGroup.make(originals: [entry("forest", date: 0)],
                                                    variations: [newest, another, older])[0]
        XCTAssertEqual(group.original?.originalURL, URL(fileURLWithPath: "/fixtures/forest.png"))
        XCTAssertEqual(group.latestVariation?.prompt, "Evening mist")
        XCTAssertEqual(group.latestVariation?.entry.settingsSnapshot?.sourceCrop, settings.sourceCrop)
        XCTAssertEqual(Set(group.variations.map(\.id)), Set([older.id, newest.id, another.id]))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func original(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("fixture image metadata".utf8).write(to: url)
        return url
    }

    private func entry(_ digest: String, date: TimeInterval) -> PictureHistory.Entry {
        PictureHistory.Entry(digest: digest, name: digest, originalURL: URL(fileURLWithPath: "/fixtures/\(digest).png"),
                             importedAt: Date(timeIntervalSince1970: date))
    }

    private func variation(_ name: String, digest: String?, prompt: String?, date: TimeInterval,
                           settings suppliedSettings: CanvasSettings? = nil) -> SavedWallpaperItem {
        var settings = suppliedSettings
        if let prompt {
            if settings == nil { settings = CanvasSettings() }
            settings?.promptTemplate = prompt
        }
        let entry = HourWallpaperCache.Entry(pictureID: digest ?? "legacy", recipeID: "recipe", hour: 12,
                                              weather: WeatherSnapshot(label: "clear", symbol: "sun.max.fill", fetchedAt: Date(timeIntervalSince1970: date)),
                                              filename: name + ".png", createdAt: Date(timeIntervalSince1970: date),
                                              settingsSnapshot: settings, sourceDigest: digest)
        return SavedWallpaperItem(entry: entry, url: URL(fileURLWithPath: "/fixtures/\(name).png"))
    }
}
