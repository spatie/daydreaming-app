import Foundation

struct PromptSubmission: Codable, Equatable, Sendable {
    let submissionID: UUID
    let prompt: String
    let name: String?
    let email: String?
    let appVersion: String
    let appBuild: String

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id", prompt, name, email
        case appVersion = "app_version", appBuild = "app_build"
    }

    static func validationError(prompt: String, name: String, email: String) -> String? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Tell us what you would like Daydreaming to do." }
        if text.unicodeScalars.count > 5_000 { return "Keep your request within 5,000 characters." }
        let credit = normalizedName(name)
        if credit.unicodeScalars.count > 60 { return "Keep your name within 60 characters." }
        if !credit.isEmpty && credit.range(of: "^[\\p{L}\\p{N} ._'-]+$", options: .regularExpression) == nil {
            return "Use a name or handle for credit, rather than an email address."
        }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty && (address.unicodeScalars.count > 254 || address.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil) {
            return "Check your email address, or leave it empty."
        }
        return nil
    }

    static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "@" }))
    }
}

enum PromptSubmissionError: LocalizedError {
    case unavailable, rejected(Int), invalidReceipt
    var errorDescription: String? {
        switch self {
        case .unavailable: "Submissions are disabled in test copies of Daydreaming."
        case .rejected(429): "Too many submissions for now. Your request is kept here. Try again later."
        case .rejected(409): "This submission changed after it was sent. Reopen the form to try again."
        case .rejected: "Couldn't send your request. It is kept here so you can try again."
        case .invalidReceipt: "Couldn't confirm delivery. Try again with the same request."
        }
    }
}

struct PromptSubmissionClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    init(transport: @escaping Transport = Self.send) { self.transport = transport }

    func submit(_ submission: PromptSubmission) async throws -> String {
        var request = URLRequest(url: URL(string: "https://getdaydreaming.com/api/prompt-submissions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Daydreaming/\(submission.appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(submission)
        let (data, response) = try await transport(request)
        guard response.statusCode == 201 || response.statusCode == 200 else {
            throw PromptSubmissionError.rejected(response.statusCode)
        }
        struct Receipt: Decodable { let reference: String }
        guard data.count <= 4_096, let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              !receipt.reference.isEmpty, receipt.reference.count <= 100,
              receipt.reference.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil else {
            throw PromptSubmissionError.invalidReceipt
        }
        return receipt.reference
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !AppRuntime.isPreview, !AppRuntime.isRunningTests else { throw PromptSubmissionError.unavailable }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: SubmissionRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PromptSubmissionError.invalidReceipt }
        return (data, response)
    }
}

private final class SubmissionRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
@Observable
final class PromptSubmissionDraft {
    var prompt = ""
    var name = ""
    var email = ""
    private(set) var isSending = false
    private(set) var error: String?
    private(set) var reference: String?
    private var lastSubmission: PromptSubmission?
    private var task: Task<Void, Never>?
    private var attempt = UUID()
    private let client: PromptSubmissionClient
    private let version: String
    private let build: String

    init(client: PromptSubmissionClient = .init(), version: String? = nil, build: String? = nil) {
        self.client = client
        self.version = version ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        self.build = build ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    func submit() {
        guard !isSending else { return }
        error = PromptSubmission.validationError(prompt: prompt, name: name, email: email)
        guard error == nil else { return }
        let credit = PromptSubmission.normalizedName(name)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        var submission = PromptSubmission(submissionID: lastSubmission?.submissionID ?? UUID(),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), name: credit.isEmpty ? nil : credit,
            email: address.isEmpty ? nil : address, appVersion: version, appBuild: build)
        if let previous = lastSubmission, submission != previous {
            submission = PromptSubmission(submissionID: UUID(), prompt: submission.prompt, name: submission.name,
                                          email: submission.email, appVersion: version, appBuild: build)
        }
        lastSubmission = submission
        isSending = true
        reference = nil
        attempt = UUID()
        let currentAttempt = attempt
        task = Task {
            do {
                let receipt = try await client.submit(submission)
                guard currentAttempt == attempt, !Task.isCancelled else { return }
                reference = receipt
                prompt = ""
                lastSubmission = nil
            } catch {
                guard currentAttempt == attempt else { return }
                self.error = (error as? PromptSubmissionError)?.errorDescription
                    ?? "Couldn't send your request. It is kept here so you can try again."
            }
            isSending = false
            task = nil
        }
    }

    func closed() {
        guard isSending else { return }
        attempt = UUID()
        task?.cancel()
        task = nil
        isSending = false
        error = "Couldn't confirm delivery. Your request is kept here. Try again when you're ready."
    }

    func startAnother() { reference = nil; error = nil }
}
