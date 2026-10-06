import XCTest
@testable import Daydreaming

final class PromptFilesTests: XCTestCase {
    func testQuotedPathsSupportSpacesAndExpandHome() {
        let paths = LocalPromptFileDetector.paths(in: #"Use "/Users/example/My Notes/mood.txt" and '~/Documents/Ideas today.md'."#)
        XCTAssertEqual(paths, ["/Users/example/My Notes/mood.txt", LocalPromptFileDetector.userHomeDirectory + "/Documents/Ideas today.md"])
    }

    func testURLPathSegmentsAreNotLocalFiles() {
        let prompt = #"See https://example.com/Users/example/mood.txt and file:///tmp/another.txt or www.example.com/tmp/test.txt. Also use /tmp/local.txt."#
        XCTAssertEqual(LocalPromptFileDetector.paths(in: prompt), ["/tmp/local.txt"])
        XCTAssertTrue(LocalPromptFileDetector.paths(in: "scene/reference.txt and ~/not-a-url.txt").contains(LocalPromptFileDetector.userHomeDirectory + "/not-a-url.txt"))
    }

    func testPathsAreDistinctNormalizedAndLimitedToThree() {
        let prompt = "/tmp/notes/../first.txt /tmp/first.txt /tmp/second.json /tmp/third.html /tmp/fourth.md"
        XCTAssertEqual(LocalPromptFileDetector.paths(in: prompt), ["/tmp/first.txt", "/tmp/second.json", "/tmp/third.html"])
        XCTAssertEqual(LocalPromptFileDetector.allPaths(in: prompt), ["/tmp/first.txt", "/tmp/second.json", "/tmp/third.html", "/tmp/fourth.md"])
    }

    func testRelativePathsAndNullBytesAreNotAuthorizedPaths() {
        XCTAssertNil(LocalPromptFileDetector.normalizedPath("Documents/notes.txt"))
        XCTAssertNil(LocalPromptFileDetector.normalizedPath("/tmp/notes\0.txt"))
    }

    func testTildeExpansionUsesInjectedUserHomeAndPreservesAbsolutePaths() {
        XCTAssertEqual(LocalPromptFileDetector.normalizedPath("~/Documents/Ideas today.md", homeDirectory: "/Users/fictional"),
                       "/Users/fictional/Documents/Ideas today.md")
        XCTAssertEqual(LocalPromptFileDetector.normalizedPath("/tmp/notes.txt", homeDirectory: "/Users/fictional"),
                       "/tmp/notes.txt")
    }

    func testUnsupportedUnquotedTokensDoNotUseTheFileAllowance() {
        XCTAssertEqual(LocalPromptFileDetector.paths(in: "/imagine /r/earthporn /tmp/one.txt /tmp/two.md /tmp/three.json"),
                       ["/tmp/one.txt", "/tmp/two.md", "/tmp/three.json"])
    }

    func testOutboundPromptRedactsPathsAndKeepsWebsiteURLsAndPunctuation() {
        let prompt = #"Use "/Users/fictional/My Notes/notes.md", ~/Desktop/ideas.txt. See https://example.com/path/file.txt."#
        let redacted = LocalPromptFileDetector.redactingPaths(in: prompt)
        XCTAssertEqual(redacted, "Use [file: notes.md], [file: ideas.txt]. See https://example.com/path/file.txt.")
        XCTAssertTrue(prompt.contains("/Users/fictional"))
    }

    func testPrivacyRedactionIncludesUnsupportedFilesExtensionlessPathsAndFileURLs() {
        let prompt = #"Use /Users/fictional/secrets.pdf, ~/Desktop/private and file:///Users/fictional/private.json. Also 'file:///Users/fictional/My%20Notes/private.md' and https://example.com/path/file.txt."#
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt),
                       "Use [file: secrets.pdf], [file: private] and [file: private.json]. Also [file: private.md] and https://example.com/path/file.txt.")
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: prompt).isEmpty)
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: "Use /Users/fictional/private and https://example.com/news.json"),
                       "Use [file: private] and https://example.com/news.json")
    }

    func testSlashCommandsWebRoutesHTMLAndFractionsKeepTheirMeaning() {
        let prompt = "/imagine a valley from /r/EarthPorn /s (/docs/page) </br> and/or 24/7"
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt), prompt)
        XCTAssertTrue(LocalPromptFileDetector.allPathLikePaths(in: prompt).isEmpty)
    }

    func testUnquotedRealPathsWithSpacesAreRedactedThroughTheFilename() {
        let prompt = "Use /Users/fictional/My private folder/notes.txt and /Volumes/Personal Data/secrets.pdf. Keep it gentle."
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt), "Use [file: notes.txt] and [file: secrets.pdf]. Keep it gentle.")
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: prompt).isEmpty)
        XCTAssertEqual(LocalPromptFileDetector.allPathLikePaths(in: prompt),
                       ["/Users/fictional/My private folder/notes.txt", "/Volumes/Personal Data/secrets.pdf"])
    }

    func testProseAfterADirectoryDoesNotInventAReadableFile() {
        let examples = [
            ("/Users/fictional/Desktop is messy, e.g. icons", "[file: Desktop] is messy, e.g. icons"),
            ("/Users/fictional/Notes/plan and also3.5stars", "[file: plan] and also3.5stars"),
            ("/Users/fictional/Desktop has notes, see readme.md", "[file: Desktop] has notes, see readme.md"),
        ]
        for (prompt, expected) in examples {
            XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt), expected)
            XCTAssertTrue(LocalPromptFileDetector.allPaths(in: prompt).isEmpty)
        }
    }

    func testReviewerDirectoryProseFixturesKeepTextAndNeverBecomeReadableFiles() {
        let fixtures = [
            ("Use /Users/fictional/Pictures/moodboard folder and www.pinterest.com boards",
             "Use [file: moodboard] folder and www.pinterest.com boards"),
            ("/Users/fictional/Notes/plan and also 3.5 stars", "[file: plan] and also 3.5 stars"),
            ("/Users/fictional/Desktop has notes, see readme.md for details",
             "[file: Desktop] has notes, see readme.md for details"),
        ]
        for (prompt, expected) in fixtures {
            let redacted = LocalPromptFileDetector.redactingPaths(in: prompt)
            XCTAssertEqual(redacted, expected)
            XCTAssertFalse(redacted.contains("fictional"))
            XCTAssertFalse(redacted.contains("/Users/"))
            XCTAssertTrue(LocalPromptFileDetector.allPaths(in: prompt).isEmpty)
        }
    }

    func testWebsiteAfterADirectoryDoesNotPreventPrefixRedaction() {
        let prompt = "/Users/fictional/Desktop has photos from www.pinterest.com and https://example.com/notes.md"
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt),
                       "[file: Desktop] has photos from www.pinterest.com and https://example.com/notes.md")
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: prompt).isEmpty)
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: "at/Users/fictional/Desktop use soft light"),
                       "at[file: Desktop] use soft light")
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: #"Use "/Users/fictional/www.pinterest.com/notes.txt""#),
                       "Use [file: notes.txt]")
    }

    func testGluedRedactionIsLimitedToPrivateUserAndVolumeRoots() {
        let ordinary = "go/home/now role/var/value keep/private/example example.com/Users/guide"
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: ordinary), ordinary)
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: ordinary).isEmpty)
        let privateRoots = "at/Users/fictional/Desktop and on/Volumes/Personal/notes.md"
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: privateRoots), "at[file: Desktop] and on[file: notes.md]")
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: privateRoots).isEmpty)
    }

    func testParenthesizedFolderTailDoesNotAuthorizeAnUnrelatedAbsoluteFile() {
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: "/My Notes (old)/plan.md").isEmpty)
        XCTAssertEqual(LocalPromptFileDetector.allPaths(in: #""/My Notes (old)/plan.md""#), ["/My Notes (old)/plan.md"])
    }

    func testIndependentPrivatePathsKeepTheirConnectingProse() {
        let prompt = "at/Users/fictional/Desktop and on/Volumes/Drive/notes.md"
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt),
                       "at[file: Desktop] and on[file: notes.md]")
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: prompt).isEmpty)
    }

    func testManyPathsAndLongProsePreserveExactRedactionOutputs() {
        let prompt = (0..<500).map { "/tmp/reference\($0).txt" }.joined(separator: " ")
        let expected = (0..<500).map { "[file: reference\($0).txt]" }.joined(separator: " ")
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: prompt), expected)
        XCTAssertEqual(LocalPromptFileDetector.allPaths(in: prompt).count, 500)
        let longProse = String(repeating: "quiet ", count: 500)
        let directoryPrompt = "/Users/fictional/Folder " + longProse + "and https://example.com/notes.md"
        XCTAssertEqual(LocalPromptFileDetector.redactingPaths(in: directoryPrompt),
                       "[file: Folder] " + longProse + "and https://example.com/notes.md")
        XCTAssertTrue(LocalPromptFileDetector.allPaths(in: directoryPrompt).isEmpty)
    }

    func testUnsupportedQuotedReferencesRemainAvailableWithoutUsingReadAllowance() {
        let prompt = #"Use "/tmp/one.pdf" '/tmp/two.png' "/tmp/three.csv" '/tmp/four.bin' and /tmp/readable.md"#
        XCTAssertEqual(LocalPromptFileDetector.quotedPaths(in: prompt), ["/tmp/one.pdf", "/tmp/two.png", "/tmp/three.csv", "/tmp/four.bin"])
        XCTAssertEqual(LocalPromptFileDetector.allPaths(in: prompt), ["/tmp/readable.md"])
    }

    func testCompletedGrantsAreMergedOnlyForCurrentPromptReferences() {
        let grants = ["/tmp/old.txt": Data("old".utf8), "/tmp/current.md": Data("current".utf8)]
        XCTAssertEqual(LocalPromptFileDetector.referencedBookmarks(grants, in: "Use /tmp/current.md"),
                       ["/tmp/current.md": Data("current".utf8)])
    }

    func testLegacyReconnectionUsesNameOnlyWhenTheOldBookmarkCannotResolve() throws {
        let picked = URL(fileURLWithPath: "/tmp/reconnected/notes.txt")
        let unresolved = LegacyPromptFileReference(name: "notes.txt", bookmark: Data("invalid".utf8))
        XCTAssertEqual(PromptFileReader.uniqueLegacyReconnectionMatch(in: [unresolved], url: picked, bookmarks: FakePromptFileBookmarks()), unresolved)
        let resolved = LegacyPromptFileReference(name: "notes.txt", bookmark: try FakePromptFileBookmarks().make(url: URL(fileURLWithPath: "/tmp/other/notes.txt")))
        XCTAssertNil(PromptFileReader.uniqueLegacyReconnectionMatch(in: [resolved], url: picked, bookmarks: FakePromptFileBookmarks()))
        var settings = CanvasSettings()
        settings.unresolvedPromptFiles = [unresolved]
        settings.forgetUnresolvedPromptFiles()
        XCTAssertTrue(settings.unresolvedPromptFiles.isEmpty)
    }

    func testLegacyFilenameFallbackRequiresOneUnresolvedEntry() {
        let picked = URL(fileURLWithPath: "/tmp/reconnected/notes.txt")
        let first = LegacyPromptFileReference(name: "notes.txt", bookmark: Data("first invalid".utf8))
        let second = LegacyPromptFileReference(name: "notes.txt", bookmark: Data("second invalid".utf8))
        XCTAssertEqual(PromptFileReader.uniqueLegacyReconnectionMatch(in: [first], url: picked, bookmarks: FakePromptFileBookmarks()), first)
        XCTAssertNil(PromptFileReader.uniqueLegacyReconnectionMatch(in: [first, second], url: picked, bookmarks: FakePromptFileBookmarks()))
    }

    func testRefreshedBookmarkIsReturnedWithReadText() async throws {
        let backend = RefreshingPromptFileBookmarks()
        let reader = PromptFileReader(bookmarks: backend, loader: { _, _ in Data("Fresh text".utf8) })
        let result = try await reader.readResult(path: "/tmp/notes.txt", bookmark: Data("stale".utf8))
        XCTAssertEqual(result.text, "Fresh text")
        XCTAssertEqual(result.refreshedBookmark, Data("refreshed".utf8))
    }

    func testLegacyRetryPreservesFailuresAndMatchesFullPathRatherThanFilename() {
        let backend = RefreshingPromptFileBookmarks()
        var settings = CanvasSettings()
        settings.promptTemplate = "Use /other/notes.txt"
        settings.unresolvedPromptFiles = [LegacyPromptFileReference(name: "notes.txt", bookmark: Data("stale".utf8))]
        settings.retryUnresolvedPromptFiles(bookmarks: backend)
        XCTAssertTrue(settings.unresolvedPromptFiles.isEmpty)
        XCTAssertTrue(settings.promptTemplate.contains("\"/tmp/notes.txt\""))
        XCTAssertEqual(settings.promptFileBookmarks["/tmp/notes.txt"], Data("refreshed".utf8))
        settings.unresolvedPromptFiles = [LegacyPromptFileReference(name: "missing.txt", bookmark: Data("invalid".utf8))]
        settings.retryUnresolvedPromptFiles(bookmarks: FakePromptFileBookmarks())
        XCTAssertEqual(settings.unresolvedPromptFiles.count, 1)
    }

    func testFakeBookmarkRoundTripAndMigrationPath() throws {
        let backend = FakePromptFileBookmarks()
        let url = URL(fileURLWithPath: "/tmp/My Notes.txt")
        let bookmark = try backend.make(url: url)
        XCTAssertEqual(try backend.resolve(data: bookmark), url)
        XCTAssertEqual(try PromptFileReader.resolvedPath(bookmark: bookmark, bookmarks: backend), url.path)
        XCTAssertThrowsError(try backend.resolve(data: Data("not a bookmark".utf8)))
    }

    func testTextReadingUsesGrantedURLAndCollapsesWhitespace() async throws {
        let backend = FakePromptFileBookmarks()
        let url = URL(fileURLWithPath: "/tmp/current.txt")
        let bookmark = try backend.make(url: url)
        let reader = PromptFileReader(bookmarks: backend) { receivedURL, maximumBytes in
            XCTAssertEqual(receivedURL, url)
            XCTAssertEqual(maximumBytes, 256_000)
            return Data("  Soft\n rain\t and a\nquiet sky  ".utf8)
        }
        let text = try await reader.read(path: "/tmp/current.txt", bookmark: bookmark)
        XCTAssertEqual(text, "Soft rain and a quiet sky")
    }

    func testHTMLUsesMainContentAndJSONKeepsItsText() async throws {
        let backend = FakePromptFileBookmarks()
        let html = URL(fileURLWithPath: "/tmp/page.html")
        let reader = PromptFileReader(bookmarks: backend) { _, _ in
            Data("<body><nav>Skip</nav><main>Rain <strong>tomorrow</strong></main><footer>Skip</footer><script>Skip</script></body>".utf8)
        }
        let text = try await reader.read(path: html.path, bookmark: backend.make(url: html))
        XCTAssertEqual(text, "Rain tomorrow")
        let json = URL(fileURLWithPath: "/tmp/mood.json")
        let jsonReader = PromptFileReader(bookmarks: backend) { _, _ in Data("{\n \"mood\": \"calm\"\n}".utf8) }
        let jsonText = try await jsonReader.read(path: json.path, bookmark: backend.make(url: json))
        XCTAssertEqual(jsonText, #"{ "mood": "calm" }"#)
    }

    func testFilesHaveByteAndCharacterLimits() async throws {
        let backend = FakePromptFileBookmarks()
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        let bookmark = try backend.make(url: url)
        let reader = PromptFileReader(bookmarks: backend) { _, _ in Data(String(repeating: "x", count: 2_500).utf8) }
        let text = try await reader.read(path: url.path, bookmark: bookmark)
        XCTAssertEqual(text.count, 2_400)
        let oversized = PromptFileReader(bookmarks: backend) { _, _ in Data(repeating: 65, count: 256_001) }
        do {
            _ = try await oversized.read(path: url.path, bookmark: bookmark)
            XCTFail("Expected byte limit rejection")
        } catch {
            XCTAssertEqual(error as? PromptFileError, .fileTooLarge)
        }
    }

    func testUnsupportedFilesAndInvalidUTF8AreRejected() async throws {
        let backend = FakePromptFileBookmarks()
        let binary = URL(fileURLWithPath: "/tmp/secret.db")
        let reader = PromptFileReader(bookmarks: backend) { _, _ in
            XCTFail("Unsupported files must not be loaded")
            return Data()
        }
        do {
            _ = try await reader.read(path: binary.path, bookmark: backend.make(url: binary))
            XCTFail("Expected unsupported extension rejection")
        } catch {
            XCTAssertEqual(error as? PromptFileError, .unsupportedFile)
        }
        let text = URL(fileURLWithPath: "/tmp/notes.txt")
        let invalidUTF8 = PromptFileReader(bookmarks: backend) { _, _ in Data([0xff, 0xfe]) }
        do {
            _ = try await invalidUTF8.read(path: text.path, bookmark: backend.make(url: text))
            XCTFail("Expected UTF-8 rejection")
        } catch {
            XCTAssertEqual(error as? PromptFileError, .invalidTextEncoding)
        }
    }
}

private struct FakePromptFileBookmarks: PromptFileBookmarkBackend {
    func make(url: URL) throws -> Data {
        Data(url.absoluteString.utf8)
    }

    func resolve(data: Data) throws -> URL {
        guard let text = String(data: data, encoding: .utf8),
              let url = URL(string: text), url.isFileURL else { throw PromptFileError.accessDenied }
        return url
    }
}

extension PromptFilesTests {
    @MainActor
    func testRestoredDeclinedPermissionLedgerDoesNotAskAgain() async {
        var attempts = Set<String>()
        let firstChoices = FakePromptFileChoices([nil])
        let firstAuthorization = PromptFileAuthorization(
            bookmarkBackend: FakePromptFileBookmarks(),
            onAttempt: { attempts.insert($0) },
            chooser: { path in firstChoices.choose(path) }
        )
        let declined = await firstAuthorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertTrue(declined.bookmarks.isEmpty)
        XCTAssertEqual(attempts, ["/tmp/requested.txt"])

        let restoredChoices = FakePromptFileChoices([URL(fileURLWithPath: "/tmp/requested.txt")])
        let restoredAuthorization = PromptFileAuthorization(
            bookmarkBackend: FakePromptFileBookmarks(),
            initialAttempts: attempts,
            chooser: { path in restoredChoices.choose(path) }
        )
        let restored = await restoredAuthorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertTrue(restored.bookmarks.isEmpty)
        XCTAssertEqual(restored.warnings.count, 1)
        XCTAssertTrue(restoredChoices.requestedPaths.isEmpty)
    }

    @MainActor
    func testPendingPermissionBlocksReentranceButPersistsOnlyAfterTheAnswer() async {
        var attempts = Set<String>()
        let chooser = SuspendedPromptFileChoice()
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(), onAttempt: { attempts.insert($0) }, chooser: { path in
            await chooser.choose(path)
        })
        let first = Task { await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:]) }
        while chooser.continuation == nil { await Task.yield() }
        XCTAssertTrue(attempts.isEmpty)
        let repeated = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertTrue(repeated.bookmarks.isEmpty)
        XCTAssertEqual(repeated.warnings.count, 1)
        XCTAssertEqual(chooser.requestedPaths, ["/tmp/requested.txt"])
        chooser.continuation?.resume(returning: URL(fileURLWithPath: "/tmp/requested.txt"))
        let accepted = await first.value
        XCTAssertNotNil(accepted.bookmarks["/tmp/requested.txt"])
        XCTAssertEqual(attempts, ["/tmp/requested.txt"])
    }

    @MainActor
    func testAuthorizationGrantsOnlyTheProposedFileAndPreservesExistingBookmarks() async throws {
        let backend = FakePromptFileBookmarks()
        let queue = FakePromptFileChoices([URL(fileURLWithPath: "/tmp/requested.txt")])
        let authorization = PromptFileAuthorization(bookmarkBackend: backend, chooser: { path in queue.choose(path) })
        let existing = Data("existing grant".utf8)
        let result = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: ["/tmp/previous.txt": existing])
        XCTAssertEqual(result.bookmarks["/tmp/previous.txt"], existing)
        XCTAssertEqual(try backend.resolve(data: XCTUnwrap(result.bookmarks["/tmp/requested.txt"])).path, "/tmp/requested.txt")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(queue.requestedPaths, ["/tmp/requested.txt"])
    }

    @MainActor
    func testDeclinedPermissionIsAttemptedOnlyOnceAndDoesNotGrantAnotherFile() async {
        let queue = FakePromptFileChoices([nil, URL(fileURLWithPath: "/tmp/different.txt")])
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(), chooser: { path in queue.choose(path) })
        let first = await authorization.authorizeMissing(prompt: "/tmp/declined.txt", bookmarks: [:])
        let repeated = await authorization.authorizeMissing(prompt: "/tmp/declined.txt", bookmarks: [:])
        let wrongFile = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertTrue(first.bookmarks.isEmpty)
        XCTAssertTrue(repeated.bookmarks.isEmpty)
        XCTAssertTrue(wrongFile.bookmarks.isEmpty)
        XCTAssertEqual(queue.requestedPaths, ["/tmp/declined.txt", "/tmp/requested.txt"])
        XCTAssertEqual(first.warnings.count, 1)
        XCTAssertEqual(repeated.warnings.count, 1)
        XCTAssertEqual(wrongFile.warnings.count, 1)
    }

    @MainActor
    func testExistingBookmarksUnsupportedPathsAndWebsiteLinksDoNotOpenPanels() async {
        let queue = FakePromptFileChoices([])
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(), chooser: { path in queue.choose(path) })
        let existing = Data("existing grant".utf8)
        let result = await authorization.authorizeMissing(
            prompt: #"/tmp/already.txt "/tmp/binary.db" https://example.com/tmp/website.txt"#,
            bookmarks: ["/tmp/already.txt": existing]
        )
        XCTAssertEqual(result.bookmarks["/tmp/already.txt"], existing)
        XCTAssertTrue(queue.requestedPaths.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    @MainActor
    func testAutomaticAuthorizationSkipsTheChooserAndDoesNotConsumeAnAttempt() async {
        var attempts = Set<String>()
        let queue = FakePromptFileChoices([URL(fileURLWithPath: "/tmp/requested.txt")])
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(),
                                                   onAttempt: { attempts.insert($0) }, chooser: { queue.choose($0) })
        let automatic = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:], allowInteraction: false)
        XCTAssertTrue(automatic.bookmarks.isEmpty)
        XCTAssertTrue(queue.requestedPaths.isEmpty)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertEqual(automatic.warnings, ["Create a wallpaper from Daydreaming to allow access to requested.txt."])
        let manual = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertNotNil(manual.bookmarks["/tmp/requested.txt"])
    }

    @MainActor
    func testInterruptedPermissionDoesNotPersistAnAttempt() async {
        var attempts = Set<String>()
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(),
                                                   onAttempt: { attempts.insert($0) }, chooser: { _ in
            throw CancellationError()
        })
        let result = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertTrue(result.bookmarks.isEmpty)
        XCTAssertTrue(attempts.isEmpty)
    }

    @MainActor
    func testRemovingAndReaddingAPathAllowsANewPermissionAttempt() async {
        let queue = FakePromptFileChoices([nil, URL(fileURLWithPath: "/tmp/requested.txt")])
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(), chooser: { queue.choose($0) })
        let first = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertTrue(first.bookmarks.isEmpty)
        XCTAssertEqual(authorization.retainAttempts(for: "/tmp/requested.txt"), ["/tmp/requested.txt"])
        XCTAssertTrue(authorization.retainAttempts(for: "No file reference").isEmpty)
        authorization.retainAttempts(for: "/tmp/requested.txt")
        let readded = await authorization.authorizeMissing(prompt: "/tmp/requested.txt", bookmarks: [:])
        XCTAssertNotNil(readded.bookmarks["/tmp/requested.txt"])
        XCTAssertEqual(queue.requestedPaths.count, 2)
    }

    @MainActor
    func testResolvedFileIdentityCanAcceptASymlinkWithoutMatchingItsSpelling() async {
        let chosen = URL(fileURLWithPath: "/tmp/actual.txt")
        let authorization = PromptFileAuthorization(bookmarkBackend: FakePromptFileBookmarks(),
                                                   identityMatcher: { proposed, result in
            proposed.path == "/tmp/link.txt" && result.path == "/tmp/actual.txt"
        }, chooser: { _ in chosen })
        let result = await authorization.authorizeMissing(prompt: "/tmp/link.txt", bookmarks: [:])
        XCTAssertNotNil(result.bookmarks["/tmp/link.txt"])
        XCTAssertTrue(result.warnings.isEmpty)
    }
}

private struct RefreshingPromptFileBookmarks: PromptFileBookmarkBackend {
    func make(url: URL) throws -> Data { Data("refreshed".utf8) }
    func resolve(data: Data) throws -> URL { URL(fileURLWithPath: "/tmp/notes.txt") }
    func resolveForReading(data: Data) throws -> PromptFileBookmarkResolution {
        PromptFileBookmarkResolution(url: try resolve(data: data), refreshedBookmark: Data("refreshed".utf8))
    }
}

@MainActor
private final class SuspendedPromptFileChoice {
    private(set) var requestedPaths: [String] = []
    private(set) var continuation: CheckedContinuation<URL?, Never>?

    func choose(_ path: String) async -> URL? {
        requestedPaths.append(path)
        return await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
private final class FakePromptFileChoices {
    private var choices: [URL?]
    private(set) var requestedPaths: [String] = []

    init(_ choices: [URL?]) {
        self.choices = choices
    }

    func choose(_ path: String) -> URL? {
        requestedPaths.append(path)
        return choices.isEmpty ? nil : choices.removeFirst()
    }
}
