import Foundation

/// Counts installations with a random app-local token, never hardware or account identity.
@MainActor
final class InstallationReporter {
    static let shared = InstallationReporter()
    static let endpoint = URL(string: "https://getdaydreaming.com/api/install-reports")!
    static let enabledKey = "installationReports.isEnabled"
    static let tokenKey = "installationReports.token"
    static let successDateKey = "installationReports.lastSuccessAt"
    static let successVersionKey = "installationReports.lastSuccessVersion"
    static let successBuildKey = "installationReports.lastSuccessBuild"
    static let attemptDateKey = "installationReports.lastAttemptAt"
    static let attemptVersionKey = "installationReports.lastAttemptVersion"
    static let attemptBuildKey = "installationReports.lastAttemptBuild"
    static let reportInterval: TimeInterval = 86_400
    static let retryInterval: TimeInterval = 3_600

    typealias Transport = @Sendable (URLRequest) async throws -> Int
    enum Outcome: Equatable, Sendable { case disabled, notDue, reported, failed }

    struct Runtime {
        let bundleID: String?
        let isDebug: Bool
        let isRunningTests: Bool
        var allowsReports: Bool {
            bundleID == AppRuntime.productionBundleID && !isDebug && !isRunningTests
        }
        static var current: Self {
            #if DEBUG
            let isDebug = true
            #else
            let isDebug = false
            #endif
            return Self(bundleID: Bundle.main.bundleIdentifier, isDebug: isDebug,
                        isRunningTests: AppRuntime.isRunningTests)
        }
    }

    struct Metadata {
        let appVersion: String
        let appBuild: String
        let macOSVersion: String
        let architecture: String

        static var current: Self {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            #if arch(arm64)
            let architecture = "arm64"
            #elseif arch(x86_64)
            let architecture = "x86_64"
            #else
            let architecture = "unknown"
            #endif
            return Self(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
                        appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                        macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                        architecture: architecture)
        }
    }

    private struct Payload: Encodable {
        let token: String
        let appVersion: String
        let appBuild: String
        let macOSVersion: String
        let architecture: String
        let reportedAt: Date
        let schemaVersion = 1
        enum CodingKeys: String, CodingKey {
            case token, architecture
            case appVersion = "app_version"
            case appBuild = "app_build"
            case macOSVersion = "macos_version"
            case reportedAt = "reported_at"
            case schemaVersion = "schema_version"
        }
    }

    private let defaults: UserDefaults
    private let runtime: Runtime
    private let metadata: Metadata
    private let now: @MainActor () -> Date
    private let transport: Transport
    private var inFlight: Task<Outcome, Never>?

    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, runtime: .current, metadata: .current, transport: Self.send)
    }

    /// Explicit transport injection makes release policy testable without opening a connection.
    init(defaults: UserDefaults, runtime: Runtime, metadata: Metadata,
         now: @escaping @MainActor () -> Date = { Date() }, transport: @escaping Transport) {
        self.defaults = defaults
        self.runtime = runtime
        self.metadata = metadata
        self.now = now
        self.transport = transport
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { inFlight?.cancel() }
        }
    }

    /// One bounded attempt per check. The app can recheck on launch, wake and its daily timer.
    func reportIfDue() async -> Outcome {
        guard runtime.allowsReports, isEnabled else {
            inFlight?.cancel()
            return .disabled
        }
        if let inFlight { return await inFlight.value }
        let date = now()
        let sameSuccessfulBuild = matches(versionKey: Self.successVersionKey, buildKey: Self.successBuildKey)
        if sameSuccessfulBuild, let success = defaults.object(forKey: Self.successDateKey) as? Date,
           date.timeIntervalSince(success) < Self.reportInterval { return .notDue }
        if matches(versionKey: Self.attemptVersionKey, buildKey: Self.attemptBuildKey),
           let attempt = defaults.object(forKey: Self.attemptDateKey) as? Date,
           date.timeIntervalSince(attempt) < Self.retryInterval { return .notDue }

        let task = Task { [self] in
            do {
                try Task.checkCancellation()
                guard isEnabled else { return Outcome.disabled }
                let request = try request(at: date)
                defaults.set(date, forKey: Self.attemptDateKey)
                defaults.set(metadata.appVersion, forKey: Self.attemptVersionKey)
                defaults.set(metadata.appBuild, forKey: Self.attemptBuildKey)
                let status = try await transport(request)
                try Task.checkCancellation()
                guard isEnabled else { return Outcome.disabled }
                guard (200..<300).contains(status) else { return Outcome.failed }
                defaults.set(now(), forKey: Self.successDateKey)
                defaults.set(metadata.appVersion, forKey: Self.successVersionKey)
                defaults.set(metadata.appBuild, forKey: Self.successBuildKey)
                return Outcome.reported
            } catch { return isEnabled ? Outcome.failed : Outcome.disabled }
        }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }

    func cancelPendingReport() { inFlight?.cancel() }

    private func matches(versionKey: String, buildKey: String) -> Bool {
        defaults.string(forKey: versionKey) == metadata.appVersion
            && defaults.string(forKey: buildKey) == metadata.appBuild
    }

    private func request(at date: Date) throws -> URLRequest {
        let token: String
        if let stored = defaults.string(forKey: Self.tokenKey), let uuid = UUID(uuidString: stored) {
            token = uuid.uuidString
        } else {
            token = UUID().uuidString
            defaults.set(token, forKey: Self.tokenKey)
        }
        let payload = Payload(token: token, appVersion: metadata.appVersion, appBuild: metadata.appBuild,
                              macOSVersion: metadata.macOSVersion, architecture: metadata.architecture,
                              reportedAt: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Daydreaming/\(metadata.appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(payload)
        return request
    }

    nonisolated private static func send(_ request: URLRequest) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return response.statusCode
    }
}
