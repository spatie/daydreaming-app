import Foundation

/// Inject only I/O. The model still runs its authorization, redaction and cancellation logic.
@MainActor
struct AppModelPromptSourceServices {
    let isActive: @MainActor () -> Bool
    let authorize: @MainActor (String, [String: Data], Bool) async -> PromptFileAuthorizationResult
    let readWebsite: @MainActor (String) async -> PromptContextResult
    let readFile: @MainActor (String, Data) async throws -> PromptFileReadResult
}
