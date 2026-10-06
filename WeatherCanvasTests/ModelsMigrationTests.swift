import XCTest
@testable import Daydreaming

final class ModelsMigrationTests: XCTestCase {
    func testOnlyExactOldIdeaDefaultsMigrateAndCustomIdeasStayIntact() throws {
        let old = "Adjust this image for the time of day and the local weather."
        for prompt in [old, old + " Add snow.", "My own scene at sunrise"] {
            let data = try JSONSerialization.data(withJSONObject: ["promptTemplate": prompt, "legacyCustomPrompt": prompt, "extraInstructions": prompt])
            let settings = try JSONDecoder().decode(CanvasSettings.self, from: data)
            XCTAssertEqual(settings.promptTemplate, prompt == old ? CanvasSettings.defaultPrompt : prompt)
            if prompt == old {
                XCTAssertNil(settings.legacyCustomPrompt)
                XCTAssertTrue(settings.extraInstructions.isEmpty)
            } else {
                XCTAssertEqual(settings.legacyCustomPrompt, prompt)
                XCTAssertEqual(settings.extraInstructions, prompt)
            }
        }
        XCTAssertEqual(CanvasSettings.defaultPrompt, "Update my picture according to the current time and weather conditions.")
    }

    func testRemovingExperimentalProviderPreservesExistingPictureAndInstructions() throws {
        let saved = Data("{\"imageProvider\":\"codex\",\"sourcePath\":\"/tmp/original.jpg\",\"promptTemplate\":\"Keep the valley warm\",\"dailyGenerationLimit\":5}".utf8)
        let settings = try JSONDecoder().decode(CanvasSettings.self, from: saved)
        XCTAssertEqual(settings.sourcePath, "/tmp/original.jpg")
        XCTAssertEqual(settings.promptTemplate, "Keep the valley warm")
        XCTAssertEqual(settings.dailyGenerationLimit, 5)
        XCTAssertEqual(settings.imageProvider, .openAI)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual((encoded["imageProvider"] as? [String: Any])?["driverID"] as? String, "openai")
    }

    func testMigrationDoesNotAppendAlreadyPresentPrivateOrBlockedHTTPSLinks() {
        let privateLink = URL(string: "https://127.0.0.1/weather")!
        let blockedLink = URL(string: "https://router.local/sky")!
        var settings = CanvasSettings()
        settings.promptTemplate = "Keep \(privateLink.absoluteString) and \(blockedLink.absoluteString) in these instructions."
        let original = settings.promptTemplate
        settings.migrateSources([.webPage(url: privateLink, selector: "main"), .webPage(url: blockedLink, selector: "article")])
        XCTAssertEqual(settings.promptTemplate, original)
        XCTAssertTrue(PromptLinkDetector.allURLs(in: original).isEmpty)
        XCTAssertEqual(PromptLinkDetector.rawURLs(in: original), [privateLink, blockedLink])
    }

    func testMigrationDeduplicatesReferencesPastTheThreeSourceReadingLimit() throws {
        let backend = MigrationTestBookmarks()
        let files = (1...4).map { URL(fileURLWithPath: "/tmp/notes\($0).txt") }
        let links = (1...4).map { URL(string: "https://example.com/page\($0)")! }
        var settings = CanvasSettings()
        settings.promptTemplate = files.map { $0.path }.joined(separator: " ") + " " + links.map(\.absoluteString).joined(separator: " ")
        let original = settings.promptTemplate
        let fourthFile = ContextSource.localFile(name: files[3].lastPathComponent, bookmark: try backend.make(url: files[3]), selector: nil)
        let fourthLink = ContextSource.webPage(url: links[3], selector: "main")
        settings.migrateSources([fourthFile, fourthFile, fourthLink, fourthLink], bookmarks: backend)
        XCTAssertEqual(settings.promptTemplate, original)
        XCTAssertEqual(LocalPromptFileDetector.allPaths(in: settings.promptTemplate).count, 4)
        XCTAssertEqual(PromptLinkDetector.allURLs(in: settings.promptTemplate).count, 4)
    }

    func testLegacyWebsiteSourceMovesIntoExistingPromptWithoutItsSelector() throws {
        let original = "Keep the river calm on {{date}}."
        let website = URL(string: "https://example.com/weather")!
        let source = ContextSource.webPage(url: website, selector: "#temperature")
        let sourceJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode([source]))
        let data = try JSONSerialization.data(withJSONObject: [
            "promptTemplate": original,
            "contextSources": sourceJSON,
        ])
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: data)

        XCTAssertEqual(restored.promptTemplate, original + "\n\n" + website.absoluteString)
        XCTAssertEqual(restored.extraInstructions, restored.promptTemplate)
        XCTAssertEqual(restored.legacyCustomPrompt, restored.promptTemplate)
        XCTAssertFalse(restored.promptTemplate.contains("#temperature"))
        let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertNil(savedJSON["contextSources"])
        let reopened = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(reopened.promptTemplate, restored.promptTemplate)
    }

    func testLegacyFileMigrationKeepsPathAndGrantedBookmarkWithoutReadingTheFile() throws {
        let backend = MigrationTestBookmarks()
        let file = URL(fileURLWithPath: "/Users/example/My Notes/mood.txt")
        let bookmark = try backend.make(url: file)
        var settings = CanvasSettings()
        settings.promptTemplate = "A quiet evening."
        settings.migrateSources([.localFile(name: "mood.txt", bookmark: bookmark, selector: nil)], bookmarks: backend)

        XCTAssertEqual(settings.promptTemplate, "A quiet evening.\n\n\"/Users/example/My Notes/mood.txt\"")
        XCTAssertEqual(settings.promptFileBookmarks[file.path], bookmark)
        XCTAssertEqual(LocalPromptFileDetector.paths(in: settings.promptTemplate), [file.path])
        XCTAssertEqual(settings.legacyCustomPrompt, settings.promptTemplate)
    }

    func testMigratingAlreadyReferencedSourcesDoesNotAppendThemAgain() throws {
        let backend = MigrationTestBookmarks()
        let file = URL(fileURLWithPath: "/Users/example/notes.txt")
        let bookmark = try backend.make(url: file)
        let website = URL(string: "https://example.com/weather")!
        let sources: [ContextSource] = [
            .webPage(url: website, selector: "main"),
            .localFile(name: "notes.txt", bookmark: bookmark, selector: nil),
        ]
        var settings = CanvasSettings()
        settings.promptTemplate = "Use https://example.com/weather and \"/Users/example/notes.txt\"."
        let original = settings.promptTemplate
        settings.migrateSources(sources, bookmarks: backend)
        settings.migrateSources(sources, bookmarks: backend)

        XCTAssertEqual(settings.promptTemplate, original)
        XCTAssertEqual(settings.promptFileBookmarks[file.path], bookmark)
    }

    func testNewSettingsEncodePromptFileBookmarksWithoutLegacySourceKey() throws {
        let backend = MigrationTestBookmarks()
        let file = URL(fileURLWithPath: "/Users/example/ideas.md")
        var settings = CanvasSettings()
        settings.updateWallpaperInstructions(style: .cinematic, extraInstructions: "Use \"\(file.path)\" on {{date}}.")
        settings.promptFileBookmarks[file.path] = try backend.make(url: file)
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: data)

        XCTAssertNil(object["contextSources"])
        XCTAssertNotNil(object["promptFileBookmarks"])
        XCTAssertEqual(restored.promptFileBookmarks, settings.promptFileBookmarks)
        XCTAssertEqual(restored.promptTemplate, settings.promptTemplate)
        XCTAssertEqual(restored.extraInstructions, settings.extraInstructions)
        XCTAssertEqual(restored.style, .cinematic)
    }

    func testWebsiteMigrationDoesNotMistakeAPrefixForAnExistingReference() {
        let website = URL(string: "https://example.com/weather")!
        var settings = CanvasSettings()
        settings.promptTemplate = "Use https://example.com/weather-archive for the color palette."
        settings.migrateSources([.webPage(url: website, selector: "main")])

        XCTAssertTrue(PromptLinkDetector.urls(in: settings.promptTemplate).contains(website))
    }

    func testExistingUnquotedFileReferenceKeepsItsBookmarkWithoutDuplicatingItsPath() throws {
        let backend = MigrationTestBookmarks()
        let file = URL(fileURLWithPath: "/Users/example/notes.txt")
        let bookmark = try backend.make(url: file)
        var settings = CanvasSettings()
        settings.promptTemplate = "Use /Users/example/notes.txt for the atmosphere."
        let original = settings.promptTemplate
        settings.migrateSources([.localFile(name: "notes.txt", bookmark: bookmark, selector: nil)], bookmarks: backend)

        XCTAssertEqual(settings.promptTemplate, original)
        XCTAssertEqual(settings.promptFileBookmarks[file.path], bookmark)
    }

    func testExactHourDefaultPromptIncludesRequestedTimeAndPreservationGuard() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 22, minute: 17)))
        let rendered = PromptRenderer.renderHour(CanvasSettings.defaultPrompt, date: date, weather: "rainy")

        XCTAssertTrue(rendered.contains("The local time is " + date.formatted(date: .omitted, time: .shortened)))
        XCTAssertTrue(rendered.contains("the weather is rainy"))
        XCTAssertTrue(rendered.contains("Preserve the composition and main subjects"))
        XCTAssertTrue(rendered.contains("recognizably the same picture"))
        XCTAssertFalse(rendered.contains("around"))
    }

    func testUnresolvableLegacyBookmarkIsRetainedForReconnectionAndSurvivesSaving() throws {
        let original = "Keep the valley recognizable."
        let bookmark = Data("old granted bookmark".utf8)
        var settings = CanvasSettings()
        settings.promptTemplate = original
        settings.migrateSources([
            .localFile(name: "My weather notes.txt", bookmark: bookmark, selector: nil),
        ], bookmarks: UnresolvableMigrationBookmarks())

        XCTAssertEqual(settings.promptTemplate, original)
        XCTAssertTrue(settings.promptFileBookmarks.isEmpty)
        XCTAssertEqual(settings.unresolvedPromptFiles.count, 1)
        XCTAssertEqual(settings.unresolvedPromptFiles.first?.name, "My weather notes.txt")
        XCTAssertEqual(settings.unresolvedPromptFiles.first?.bookmark, bookmark)
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.unresolvedPromptFiles, settings.unresolvedPromptFiles)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertNil(object["contextSources"])
    }
}

private struct MigrationTestBookmarks: PromptFileBookmarkBackend {
    func make(url: URL) throws -> Data { Data(url.absoluteString.utf8) }

    func resolve(data: Data) throws -> URL {
        guard let value = String(data: data, encoding: .utf8), let url = URL(string: value), url.isFileURL else {
            throw PromptFileError.accessDenied
        }
        return url
    }
}

private struct UnresolvableMigrationBookmarks: PromptFileBookmarkBackend {
    func make(url: URL) throws -> Data { throw PromptFileError.accessDenied }
    func resolve(data: Data) throws -> URL { throw PromptFileError.staleBookmark }
}
