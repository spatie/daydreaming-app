import XCTest
@testable import Daydreaming

@MainActor
final class PromptSubmissionTests: XCTestCase {
    func testValidationKeepsMessageAndCreditWithinContract() {
        XCTAssertNotNil(PromptSubmission.validationError(prompt: " \n", name: "", email: ""))
        XCTAssertNotNil(PromptSubmission.validationError(prompt: String(repeating: "x", count: 5_001), name: "", email: ""))
        XCTAssertNotNil(PromptSubmission.validationError(prompt: "Feature", name: "person@example.com", email: ""))
        XCTAssertNotNil(PromptSubmission.validationError(prompt: "Feature", name: "", email: "bad-address"))
        XCTAssertNil(PromptSubmission.validationError(prompt: "Feature", name: "@Freek", email: "freek@example.com"))
        XCTAssertEqual(PromptSubmission.normalizedName(" @Freek "), "Freek")
    }

    func testRequestContainsOnlyFormAndVersionAndReturnsReceipt() async throws {
        let recorder = Recorder()
        let client = PromptSubmissionClient(transport: { try await recorder.send($0) })
        let submission = PromptSubmission(submissionID: UUID(), prompt: "Please add a shuffle mode.", name: nil,
                                          email: nil, appVersion: "0.1.0", appBuild: "10")
        let receipt = try await client.submit(submission)
        XCTAssertEqual(receipt, "DREAM-123")
        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://getdaydreaming.com/api/prompt-submissions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Daydreaming/0.1.0")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["submission_id", "prompt", "app_version", "app_build"])
        XCTAssertEqual(json["submission_id"] as? String, submission.submissionID.uuidString)
        XCTAssertEqual(json["prompt"] as? String, submission.prompt)
    }

    func testDefaultTransportIsDisabledInTests() async {
        do {
            _ = try await PromptSubmissionClient().submit(.init(submissionID: UUID(), prompt: "Feature", name: nil, email: nil, appVersion: "1", appBuild: "1"))
            XCTFail("Test copies must not submit to production")
        } catch { XCTAssertTrue(error is PromptSubmissionError) }
    }

    func testFailurePreservesDraftAndRetryUsesSameSubmissionID() async throws {
        let recorder = Recorder(statuses: [503, 200])
        let draft = PromptSubmissionDraft(client: .init(transport: { try await recorder.send($0) }), version: "1", build: "2")
        draft.prompt = " Feature request \n"
        draft.name = "@Freek"
        draft.email = "freek@example.com"
        draft.submit()
        draft.submit()
        try await settled(draft)
        XCTAssertEqual(draft.prompt, " Feature request \n")
        XCTAssertNotNil(draft.error)
        draft.closed()
        draft.submit()
        try await settled(draft)
        XCTAssertEqual(draft.reference, "DREAM-123")
        XCTAssertEqual(draft.prompt, "")
        XCTAssertEqual(draft.name, "@Freek")
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        let payload = try JSONDecoder().decode(PromptSubmission.self, from: XCTUnwrap(requests[0].httpBody))
        XCTAssertEqual(payload.prompt, "Feature request")
        XCTAssertEqual(payload.name, "Freek")
    }

    func testEditedRetryGetsNewIDAndValidationMakesNoRequest() async throws {
        let recorder = Recorder(statuses: [503, 201])
        let draft = PromptSubmissionDraft(client: .init(transport: { try await recorder.send($0) }))
        draft.submit()
        let emptyRequests = await recorder.requests
        XCTAssertTrue(emptyRequests.isEmpty)
        draft.prompt = "First request"
        draft.submit()
        try await settled(draft)
        draft.prompt = "Second request"
        draft.submit()
        try await settled(draft)
        let requests = await recorder.requests
        let first = try JSONDecoder().decode(PromptSubmission.self, from: XCTUnwrap(requests[0].httpBody))
        let second = try JSONDecoder().decode(PromptSubmission.self, from: XCTUnwrap(requests[1].httpBody))
        XCTAssertNotEqual(first.submissionID, second.submissionID)
    }

    func testClosingCancelsRequestAndDoesNotEraseDraft() async throws {
        let draft = PromptSubmissionDraft(client: .init(transport: { _ in
            try await Task.sleep(for: .seconds(30))
            throw URLError(.cancelled)
        }))
        draft.prompt = "Keep my draft"
        draft.submit()
        await Task.yield()
        draft.closed()
        XCTAssertFalse(draft.isSending)
        XCTAssertEqual(draft.prompt, "Keep my draft")
        XCTAssertNotNil(draft.error)
        XCTAssertNil(draft.reference)
    }

    func testInvalidResponseCannotClaimSuccess() async {
        for (status, body) in [(302, "{}"), (200, "{}"), (201, "{\"reference\":\"<script>\"}")] {
            let client = PromptSubmissionClient(transport: { request in
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do {
                _ = try await client.submit(.init(submissionID: UUID(), prompt: "Feature", name: nil, email: nil, appVersion: "1", appBuild: "1"))
                XCTFail("Invalid response must fail")
            } catch { XCTAssertTrue(error is PromptSubmissionError) }
        }
    }

    private func settled(_ draft: PromptSubmissionDraft) async throws {
        for _ in 0..<100 where draft.isSending { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(draft.isSending)
    }

    private actor Recorder {
        private(set) var requests: [URLRequest] = []
        private var statuses: [Int]
        init(statuses: [Int] = [201]) { self.statuses = statuses }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            let status = statuses.count > 1 ? statuses.removeFirst() : statuses[0]
            return (Data("{\"reference\":\"DREAM-123\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
