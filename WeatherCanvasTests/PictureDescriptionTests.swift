import AppKit
import XCTest
@testable import Daydreaming

final class PictureDescriptionTests: XCTestCase {
    func testDescriptionsUseImageContentAndUncertainResultsStayNeutral() {
        XCTAssertEqual(PictureDescription.make(from: [
            .init(identifier: "cliff", confidence: 0.67),
            .init(identifier: "sky", confidence: 0.87)
        ]), "Mountain landscape")
        XCTAssertEqual(PictureDescription.make(from: [
            .init(identifier: "road", confidence: 0.44),
            .init(identifier: "apartment", confidence: 0.24),
            .init(identifier: "sunset_sunrise", confidence: 0.67)
        ]), "City view in golden light")
        XCTAssertEqual(PictureDescription.make(from: [.init(identifier: "mountain", confidence: 0.1)]), "Your picture")
    }

    func testSameFilenameWithDifferentDigestsNeverSharesADescription() async {
        let classifier = Counter()
        let store = PictureDescriptionStore(cacheURL: nil, classify: { await classifier.classify($0) })
        let url = URL(fileURLWithPath: "/temporary/photo.jpg")
        let first = await store.description(for: url, digest: "first-image")
        let second = await store.description(for: url, digest: "second-image")
        let reused = await store.description(for: URL(fileURLWithPath: "/different/photo.jpg"), digest: "first-image")
        XCTAssertEqual(first, "Picture 1")
        XCTAssertEqual(second, "Picture 2")
        XCTAssertEqual(reused, first)
        let count = await classifier.count
        XCTAssertEqual(count, 2)
    }

    func testConcurrentRequestsShareAnalysisAndPersistAcrossLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("captions.json")
        let classifier = Counter()
        let store = PictureDescriptionStore(cacheURL: cache, classify: { await classifier.classify($0) })
        let url = URL(fileURLWithPath: "/temporary/photo.jpg")
        async let first = store.description(for: url, digest: "original-image")
        async let second = store.description(for: url, digest: "original-image")
        let pair = await (first, second)
        XCTAssertEqual(pair.0, pair.1)
        let restored = PictureDescriptionStore(cacheURL: cache, classify: { await classifier.classify($0) })
        let saved = await restored.description(for: url, digest: "original-image")
        XCTAssertEqual(saved, pair.0)
        let count = await classifier.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testDecorativeNativeObserversNeverInterceptButtonClicks() {
        let views: [NSView] = [WindowViewport.ViewportView(), PreviewSavedVariationScrolling.WheelView()]
        for view in views {
            view.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
            XCTAssertNil(view.hitTest(NSPoint(x: 250, y: 250)))
        }
    }

    private actor Counter {
        var count = 0
        func classify(_ url: URL) async -> String {
            count += 1
            let description = "Picture \(count)"
            await Task.yield()
            return description
        }
    }
}
