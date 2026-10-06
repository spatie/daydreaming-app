import XCTest
@testable import Daydreaming

@MainActor
final class InstallationReporterTests: XCTestCase {
    func testDebugTestsPreviewAndUnknownBundlesNeverSendOrCreateIdentity() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let transport = RecordingTransport()
        let runtimes: [InstallationReporter.Runtime] = [
            .init(bundleID: AppRuntime.productionBundleID, isDebug: true, isRunningTests: false),
            .init(bundleID: AppRuntime.productionBundleID, isDebug: false, isRunningTests: true),
            .init(bundleID: AppRuntime.productionBundleID + ".preview.review", isDebug: false, isRunningTests: false),
            .init(bundleID: "local.scratch.daydreaming", isDebug: false, isRunningTests: false),
            .init(bundleID: nil, isDebug: false, isRunningTests: false)
        ]
        for runtime in runtimes {
            let reporter = fixture.reporter(transport, runtime: runtime)
            let outcome = await reporter.reportIfDue()
            XCTAssertEqual(outcome, .disabled)
        }
        // The real runtime remains disabled even if this test target were a production bundle.
        let reporter = InstallationReporter(defaults: fixture.defaults)
        let outcome = await reporter.reportIfDue()
        XCTAssertEqual(outcome, .disabled)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(fixture.defaults.persistentDomain(forName: fixture.suite)?.isEmpty ?? true)
    }

    func testOptOutPreventsTransportAndIdentityCreation() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let transport = RecordingTransport()
        let reporter = fixture.reporter(transport)
        reporter.isEnabled = false
        let outcome = await reporter.reportIfDue()
        XCTAssertEqual(outcome, .disabled)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.tokenKey))
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.attemptDateKey))
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.successDateKey))
        XCTAssertFalse(fixture.reporter(transport).isEnabled)
    }

    func testFirstReportContainsOnlyContractFieldsAndSuccessfulTimestamp() async throws {
        let fixture = Fixture()
        defer { fixture.clear() }
        let transport = RecordingTransport(statuses: [201])
        let reporter = fixture.reporter(transport)
        let outcome = await reporter.reportIfDue()
        XCTAssertEqual(outcome, .reported)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://getdaydreaming.com/api/install-reports")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Daydreaming/1.2.3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["token", "app_version", "app_build", "macos_version", "architecture", "reported_at", "schema_version"])
        let token = try XCTUnwrap(json["token"] as? String)
        XCTAssertNotNil(UUID(uuidString: token))
        XCTAssertEqual(token, fixture.defaults.string(forKey: InstallationReporter.tokenKey))
        XCTAssertEqual(json["app_version"] as? String, "1.2.3")
        XCTAssertEqual(json["app_build"] as? String, "42")
        XCTAssertEqual(json["macos_version"] as? String, "26.0.1")
        XCTAssertEqual(json["architecture"] as? String, "arm64")
        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertEqual(json["reported_at"] as? String, "2026-10-06T12:00:00Z")
        XCTAssertEqual(fixture.defaults.object(forKey: InstallationReporter.successDateKey) as? Date, fixture.date)
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.successVersionKey), "1.2.3")
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.successBuildKey), "42")
    }

    func testSuccessfulDailyLimitAndIdentitySurviveReporterRecreation() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let transport = RecordingTransport()
        let first = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(first, .reported)
        let token = fixture.defaults.string(forKey: InstallationReporter.tokenKey)
        fixture.date += InstallationReporter.reportInterval - 1
        let early = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(early, .notDue)
        fixture.date += 1
        let daily = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(daily, .reported)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.tokenKey), token)
    }

    func testFailedHTTPAndThrownRequestNeverMarkSuccessAndRetryIsBounded() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let transport = RecordingTransport(statuses: [503, nil, 204])
        let failed = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(failed, .failed)
        let token = fixture.defaults.string(forKey: InstallationReporter.tokenKey)
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.successDateKey))
        fixture.date += InstallationReporter.retryInterval - 1
        let early = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(early, .notDue)
        fixture.date += 1
        let thrown = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(thrown, .failed)
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.successDateKey))
        fixture.date += InstallationReporter.retryInterval
        let recovered = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(recovered, .reported)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.tokenKey), token)
        XCTAssertEqual(fixture.defaults.object(forKey: InstallationReporter.successDateKey) as? Date, fixture.date)
    }

    func testBuildAndVersionChangesReportImmediatelyWithoutDiscardingPriorSuccess() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let transport = RecordingTransport(statuses: [200, 503, 200])
        let initial = await fixture.reporter(transport).reportIfDue()
        XCTAssertEqual(initial, .reported)
        let changedBuild = await fixture.reporter(transport, version: "1.2.3", build: "43").reportIfDue()
        XCTAssertEqual(changedBuild, .failed)
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.successBuildKey), "42")
        let changedVersion = await fixture.reporter(transport, version: "1.2.4", build: "43").reportIfDue()
        XCTAssertEqual(changedVersion, .reported)
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.successVersionKey), "1.2.4")
        XCTAssertEqual(fixture.defaults.string(forKey: InstallationReporter.successBuildKey), "43")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testConcurrentChecksShareOneInFlightRequest() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let started = expectation(description: "request started")
        let transport = RecordingTransport(gated: true, started: started)
        let reporter = fixture.reporter(transport)
        let first = Task { await reporter.reportIfDue() }
        let startedResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(startedResult, .completed)
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.successDateKey))
        let secondStarted = expectation(description: "second check started")
        let second = Task {
            secondStarted.fulfill()
            return await reporter.reportIfDue()
        }
        let secondStartedResult = await XCTWaiter.fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertEqual(secondStartedResult, .completed)
        fixture.date += 15
        await transport.release()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .reported)
        XCTAssertEqual(secondResult, .reported)
        XCTAssertEqual(fixture.defaults.object(forKey: InstallationReporter.successDateKey) as? Date, fixture.date)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testOptOutDuringRequestCannotPersistSuccess() async {
        let fixture = Fixture()
        defer { fixture.clear() }
        let started = expectation(description: "request started")
        let transport = RecordingTransport(gated: true, started: started)
        let reporter = fixture.reporter(transport)
        let attempt = Task { await reporter.reportIfDue() }
        let startedResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(startedResult, .completed)
        reporter.isEnabled = false
        await transport.release()
        let outcome = await attempt.value
        XCTAssertEqual(outcome, .disabled)
        XCTAssertNil(fixture.defaults.object(forKey: InstallationReporter.successDateKey))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
}

@MainActor
private final class Fixture {
    let suite = "Daydreaming.InstallationReporterTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var date = ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")!

    init() { defaults = UserDefaults(suiteName: suite)! }

    func clear() { defaults.removePersistentDomain(forName: suite) }

    func reporter(_ transport: RecordingTransport,
                  runtime: InstallationReporter.Runtime = .init(bundleID: AppRuntime.productionBundleID, isDebug: false, isRunningTests: false),
                  version: String = "1.2.3", build: String = "42") -> InstallationReporter {
        InstallationReporter(defaults: defaults, runtime: runtime,
                             metadata: .init(appVersion: version, appBuild: build, macOSVersion: "26.0.1", architecture: "arm64"),
                             now: { self.date }, transport: { try await transport.send($0) })
    }
}

private actor RecordingTransport {
    private(set) var requests: [URLRequest] = []
    private var statuses: [Int?]
    private var gated: Bool
    private let started: XCTestExpectation?
    private var continuation: CheckedContinuation<Void, Never>?

    init(statuses: [Int?] = [], gated: Bool = false, started: XCTestExpectation? = nil) {
        self.statuses = statuses
        self.gated = gated
        self.started = started
    }

    func send(_ request: URLRequest) async throws -> Int {
        requests.append(request)
        started?.fulfill()
        if gated { await withCheckedContinuation { continuation = $0 } }
        guard !statuses.isEmpty else { return 200 }
        guard let status = statuses.removeFirst() else { throw URLError(.timedOut) }
        return status
    }

    func release() {
        gated = false
        continuation?.resume()
        continuation = nil
    }
}
