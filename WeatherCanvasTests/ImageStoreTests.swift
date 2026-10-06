import XCTest
@testable import Daydreaming

final class ImageStoreTests: XCTestCase {
    func testBackgroundImportPreservesOriginalAndCreatesUpload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WeatherCanvas/Resources/YosemiteValley.jpg")
        let bytes = try Data(contentsOf: source)
        let imported = try await ImageStore.importImageInBackground(from: source, storageRoot: root)
        XCTAssertEqual(try Data(contentsOf: imported.originalURL), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.uploadURL.path))
        XCTAssertFalse(imported.digest.isEmpty)
    }

    func testCancelledImportDoesNotStartFileWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = AsyncStream<Void>.makeStream()
        let operation = Task {
            for await _ in gate.stream { break }
            return try await ImageStore.importImageInBackground(from: root.appendingPathComponent("missing.jpg"), storageRoot: root)
        }
        operation.cancel()
        gate.continuation.finish()
        do {
            _ = try await operation.value
            XCTFail("A cancelled import must not run")
        } catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
