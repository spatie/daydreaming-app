import XCTest
@testable import Daydreaming

final class PromptContextReaderTests: XCTestCase {
    func testDNSLookupStopsWaitingAfterTimeoutAndAcceptsAPromptResolution() async {
        let timedOut = await PromptDNSLookup.resolve(timeout: .milliseconds(1)) {
            try? await Task.sleep(for: .milliseconds(50))
            return true
        }
        XCTAssertFalse(timedOut)
        let publicDestination = await PromptDNSLookup.resolve { true }
        XCTAssertTrue(publicDestination)
    }

    func testDetectorKeepsThreeDistinctPublicHTTPSLinks() {
        let prompt = """
        Use https://example.com/one, https://example.com/one and http://example.com/plain.
        Then https://example.org/two, https://example.net/three and https://example.edu/four.
        """
        XCTAssertEqual(PromptLinkDetector.urls(in: prompt).map(\.absoluteString), [
            "https://example.com/one", "https://example.org/two", "https://example.net/three",
        ])
    }

    func testBareFilenameDoesNotProduceABlockedLinkWarning() {
        XCTAssertFalse(PromptLinkDetector.hasBlockedLinks(in: "Use notes.txt and ideas.md for the colors."))
        XCTAssertTrue(PromptLinkDetector.hasBlockedLinks(in: "Use http://example.com/notes.txt"))
    }

    func testPrivateAndLocalAddressesCannotBecomeContextLinks() {
        let blocked = [
            "https://localhost/", "https://localhost./", "https://router.local/", "https://printer.lan/",
            "https://127.0.0.1/", "https://10.2.3.4/", "https://172.16.2.3/", "https://192.168.1.2/",
            "https://169.254.169.254/", "https://100.64.1.1/", "https://0.0.0.0/",
            "https://2130706433/", "https://0177.0.0.1/", "https://0x7f000001/",
            "https://[::1]/", "https://[fe80::1]/", "https://[fd00::1]/", "https://[::ffff:127.0.0.1]/",
            "http://example.com/", "https://user:secret@example.com/", "https://example.com:8443/",
        ]
        for value in blocked {
            XCTAssertFalse(PromptLinkDetector.isAllowed(URL(string: value)!), value)
        }
        XCTAssertTrue(PromptLinkDetector.isAllowed(URL(string: "https://8.8.8.8/")!))
        XCTAssertTrue(PromptLinkDetector.isAllowed(URL(string: "https://[2001:4860:4860::8888]/")!))
        XCTAssertTrue(PromptLinkDetector.isAllowed(URL(string: "https://[64:ff9b::808:808]/")!))
        XCTAssertFalse(PromptLinkDetector.isAllowed(URL(string: "https://[64:ff9b::7f00:1]/")!))
    }

    func testMainTextExcludesNavigationScriptsAndUnrelatedBodyContent() async throws {
        let html = """
        <html><body><header>Brand</header><nav>Links</nav>
          <p>Unrelated content outside main.</p><main><h1>Rain today</h1>
          <p>Bring    a coat.</p><script>steal secrets</script><style>color: red</style>
          <aside>Subscribe now</aside><footer>Copyright</footer></main>
          <article>Other story.</article></body></html>
        """
        let reader = PromptContextReader { url in
            Self.response(url: url, content: html, mimeType: "text/html")
        }
        let result = await reader.read(prompt: "Draw https://example.com/weather")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.promptText.contains("Rain today Bring a coat."))
        for excluded in ["Brand", "Links", "Unrelated", "steal secrets", "color: red", "Subscribe", "Copyright", "Other story"] {
            XCTAssertFalse(result.promptText.contains(excluded), excluded)
        }
    }

    func testBlockedPromptLinksNeverReachTransport() async {
        let reader = PromptContextReader { _ in
            XCTFail("A blocked address must not reach transport.")
            throw URLError(.badURL)
        }
        let result = await reader.read(prompt: "Use https://127.0.0.1/ and https://[fd00::1]/ and http://example.com/.")
        XCTAssertTrue(result.promptText.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("HTTPS"))
    }

    func testArticleAndBodyAreUsedWhenMainIsMissing() throws {
        let url = URL(string: "https://example.com/")!
        let article = try PromptContextReader.extractText(
            data: Data("<body>Outside<article>First <b>story</b></article></body>".utf8), mimeType: "text/html", url: url
        )
        XCTAssertEqual(article, "First story")
        let body = try PromptContextReader.extractText(
            data: Data("<body>Body <span>text</span><script>Ignored</script></body>".utf8), mimeType: "text/html", url: url
        )
        XCTAssertEqual(body, "Body text")
    }

    func testFailedSourceDoesNotDiscardOtherLinksOrModifyOriginalPrompt() async throws {
        let prompt = "Keep https://example.com/broken and https://example.org/weather in this instruction."
        let reader = PromptContextReader { url in
            if url.host == "example.com" { throw URLError(.timedOut) }
            return Self.response(url: url, content: "Snow tomorrow", mimeType: "text/plain")
        }
        let result = await reader.read(prompt: prompt)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("example.com"))
        XCTAssertTrue(result.promptText.contains("Snow tomorrow"))
        XCTAssertTrue(result.promptText.contains("https://example.org/weather"))
        XCTAssertEqual(prompt, "Keep https://example.com/broken and https://example.org/weather in this instruction.")
    }

    func testPrivateRedirectAndOversizedResponseProduceWarnings() async {
        let redirectReader = PromptContextReader { _ in
            Self.response(url: URL(string: "https://127.0.0.1/admin")!, content: "Private text", mimeType: "text/plain")
        }
        let redirected = await redirectReader.read(prompt: "https://example.com/")
        XCTAssertTrue(redirected.promptText.isEmpty)
        XCTAssertEqual(redirected.warnings.count, 1)

        let largeReader = PromptContextReader { url in
            Self.response(url: url, content: String(repeating: "a", count: PromptContextReader.maximumBodyBytes + 1), mimeType: "text/plain")
        }
        let oversized = await largeReader.read(prompt: "https://example.com/")
        XCTAssertTrue(oversized.promptText.isEmpty)
        XCTAssertEqual(oversized.warnings.count, 1)
    }

    func testJSONStaysTextAndEachSourceIsLimitedTo2400Characters() async {
        let json = "{\"message\":\"Add falling leaves\"}"
        let jsonReader = PromptContextReader { url in Self.response(url: url, content: json, mimeType: "application/json") }
        let result = await jsonReader.read(prompt: "https://example.com/data.json")
        XCTAssertTrue(result.promptText.contains(json))

        let longReader = PromptContextReader { url in
            Self.response(url: url, content: String(repeating: "x", count: 2_500), mimeType: "text/plain")
        }
        let long = await longReader.read(prompt: "https://example.com/story.txt")
        XCTAssertTrue(long.warnings.isEmpty)
        XCTAssertTrue(long.promptText.hasSuffix(String(repeating: "x", count: 2_400)))
        XCTAssertFalse(long.promptText.contains(String(repeating: "x", count: 2_401)))
    }

    private static func response(url: URL, content: String, mimeType: String) -> PromptContextResponse {
        PromptContextResponse(
            data: Data(content.utf8),
            response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mimeType])!
        )
    }
}
