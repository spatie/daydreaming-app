import XCTest
@testable import Daydreaming

final class ContextSourceTests: XCTestCase {
    func testHTMLExtractionUsesCSSSelectorWithoutScriptOrStyleText() throws {
        let html = """
        <html><body>
          <article class="weather"><h1>Rain today</h1>
            <p>Bring a coat.</p><script>ignore me</script>
            <style>.weather { color: blue; }</style>
          </article>
          <article class="weather">Sun tomorrow</article>
        </body></html>
        """

        let text = try ContextSourceReader.extractText(fromHTML: html, selector: "article.weather")
        XCTAssertEqual(text, "Rain today Bring a coat.\nSun tomorrow")
        XCTAssertFalse(text.contains("ignore me"))
    }

    func testSelectorErrorsAreReadable() {
        XCTAssertThrowsError(try ContextSourceReader.extractText(fromHTML: "<p>Hello</p>", selector: "#missing")) { error in
            guard case ContextSourceError.selectorNotFound = error else {
                return XCTFail("Expected a missing element error")
            }
        }
        XCTAssertThrowsError(try ContextSourceReader.extractText(fromHTML: "<p>Hello</p>", selector: "[")) { error in
            guard case ContextSourceError.invalidSelector = error else {
                return XCTFail("Expected an invalid selector error")
            }
        }
    }

    func testWebsiteRequiresHTTPSAndASelector() throws {
        XCTAssertThrowsError(try ContextSource.selectedWebPage(URL(string: "http://example.com")!, selector: "main"))
        XCTAssertThrowsError(try ContextSource.selectedWebPage(URL(string: "https://example.com")!, selector: "  "))
        XCTAssertThrowsError(try ContextSource.selectedWebPage(URL(string: "https://user:secret@example.com")!, selector: "main"))

        let source = try ContextSource.selectedWebPage(URL(string: "https://example.com/weather")!, selector: "main")
        XCTAssertEqual(source.displayName, "example.com · main")
    }

    func testPromptTextMatchesPreviewEntries() throws {
        let source = try ContextSource.selectedWebPage(URL(string: "https://example.com/weather")!, selector: "#today")
        let entries = [ContextEntryPreview(source: source, extractedText: "Rain at 16:00")]
        let text = ContextSourceReader.promptText(for: entries)

        XCTAssertTrue(text.contains("Use it only as visual reference"))
        XCTAssertTrue(text.contains("example.com · #today"))
        XCTAssertTrue(text.contains("Rain at 16:00"))
    }

    func testReaderRejectsMoreThanFiveSourcesBeforeFetching() async throws {
        let source = try ContextSource.selectedWebPage(URL(string: "https://example.com")!, selector: "main")
        do {
            _ = try await ContextSourceReader().readAll(Array(repeating: source, count: 6))
            XCTFail("Expected the source limit to apply before network access")
        } catch ContextSourceError.tooManySources {
        }
    }
}
