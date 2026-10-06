import XCTest
@testable import Daydreaming

final class OpenAIImageClientTests: XCTestCase {
    @MainActor
    func testRejectedRequestRefundsOnlyAfterTheRequestWasSent() async throws {
        let source = try sourceFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let client = OpenAIImageClient(transport: { request in
            XCTAssertEqual(request.timeoutInterval, 600)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })
        let date = Date()
        var ledger = ImageGenerationLedger()
        var attempt: ImageGenerationAttempt?
        var rejectedStatus: Int?
        do {
            _ = try await client.edit(sourceURL: source, prompt: "Fixture", apiKey: "fixture-key", model: .fast,
                                      quality: .medium, size: "2560x1440", willSend: { attempt = ledger.reserve(at: date) },
                                      didReject: { status in rejectedStatus = status; if let attempt { ledger.refund(attempt) } })
            XCTFail("Expected rejection")
        } catch { }
        XCTAssertNotNil(attempt)
        XCTAssertEqual(rejectedStatus, 429)
        XCTAssertEqual(ledger.count(on: date), 0)
    }

    @MainActor
    func testTimeoutAndUnreadableSuccessResponseKeepTheirReservation() async throws {
        let source = try sourceFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let transports: [OpenAIImageClient.Transport] = [
            { _ in throw URLError(.timedOut) },
            { request in (Data("invalid JSON".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) },
        ]
        for transport in transports {
            var ledger = ImageGenerationLedger()
            let date = Date()
            let client = OpenAIImageClient(transport: transport)
            do {
                _ = try await client.edit(sourceURL: source, prompt: "Fixture", apiKey: "fixture-key", model: .fast,
                                          quality: .medium, size: "2560x1440", willSend: { _ = ledger.reserve(at: date) },
                                          didReject: { _ in XCTFail("No rejection response was received") })
                XCTFail("Expected failure")
            } catch { }
            XCTAssertEqual(ledger.count(on: date), 1)
        }
    }

    @MainActor
    func testPreparingAnUnreadableSourceNeverReservesOrSendsARequest() async {
        var reserved = false
        let client = OpenAIImageClient(transport: { _ in XCTFail("Request must not be sent"); throw URLError(.cancelled) })
        do {
            _ = try await client.edit(sourceURL: URL(fileURLWithPath: "/nonexistent/fixture-\(UUID().uuidString).jpg"),
                                      prompt: "Fixture", apiKey: "fixture-key", model: .fast, quality: .medium, size: "2560x1440",
                                      willSend: { reserved = true })
            XCTFail("Expected source error")
        } catch { }
        XCTAssertFalse(reserved)
    }

    private func sourceFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daydreaming-client-\(UUID().uuidString).jpg")
        try Data("fixture image bytes".utf8).write(to: url)
        return url
    }
}
