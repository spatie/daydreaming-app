import ImageIO
import XCTest
@testable import Daydreaming

final class CodexHandoffTests: XCTestCase {
    func testExportKeepsSourceAndOnlySharesNormalizedPictureAndInstructions() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WeatherCanvas/Resources/YosemiteValley.jpg")
        let originalBytes = try Data(contentsOf: source)
        let prepared = try CodexHandoff.export(.init(sourceURL: source, instructions: "Rain at 18:00"), to: parent)
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: prepared.folderURL.path)),
                       Set(["reference.png", "instructions.txt"]))
        let exported = try XCTUnwrap(CGImageSourceCreateWithURL(prepared.pictureURL as CFURL, nil))
        let input = try ImageStore.orientedImage(from: source, maximumPixelSize: 8_192)
        let output = try XCTUnwrap(CGImageSourceCreateImageAtIndex(exported, 0, nil))
        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(exported, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let text = try String(contentsOf: prepared.instructionsURL, encoding: .utf8)
        XCTAssertTrue(text.contains("Rain at 18:00"))
        XCTAssertTrue(text.contains("reference.png"))
        XCTAssertEqual(URLComponents(url: prepared.chatURL, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "prompt" })?.value, text)
    }

    func testChatPrefillsExactlyAndDoesNotAddAutoSendOrRemoteParameters() throws {
        let folder = URL(fileURLWithPath: "/tmp/Pictures & Ideas/雪")
        let prompt = "Rain & snow?\n#image + 100% café"
        let url = try CodexHandoff.chatURL(folder: folder, prompt: prompt)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "new")
        XCTAssertEqual(components.queryItems, [.init(name: "path", value: folder.path), .init(name: "prompt", value: prompt)])
        XCTAssertNil(url.fragment)
    }

    func testMissingPictureLeavesNoPartialExport() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        XCTAssertThrowsError(try CodexHandoff.export(.init(sourceURL: parent.appendingPathComponent("missing.jpg"), instructions: "Rain"), to: parent))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    func testExportUsesApprovedCropInsteadOfUncroppedOriginal() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WeatherCanvas/Resources/YosemiteValley.jpg")
        let cropped = try ImageStore.cropImage(from: source,
            crop: PictureCrop(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), storageRoot: parent)
        let prepared = try CodexHandoff.export(.init(sourceURL: cropped.originalURL, instructions: "Evening"), to: parent)
        let expected = try ImageStore.orientedImage(from: cropped.originalURL, maximumPixelSize: 8_192)
        let output = try ImageStore.orientedImage(from: prepared.pictureURL, maximumPixelSize: 8_192)
        XCTAssertEqual(output.width, expected.width)
        XCTAssertEqual(output.height, expected.height)
        let original = try ImageStore.orientedImage(from: source, maximumPixelSize: 8_192)
        XCTAssertLessThan(output.width, original.width)
        XCTAssertLessThan(output.height, original.height)
    }
}
