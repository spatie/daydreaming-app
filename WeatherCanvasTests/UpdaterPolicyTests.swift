import XCTest
import Sparkle
@testable import Daydreaming

final class UpdaterPolicyTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()

    func testOnlyProductionReleaseWithValidConfigurationCanUpdate() {
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(bundle: "be.spatie.daydreaming.preview.release"))
        XCTAssertFalse(allowed(bundle: nil))
        XCTAssertFalse(allowed(channel: "local"))
        XCTAssertFalse(allowed(feed: "http://getdaydreaming.com/appcast.xml"))
        XCTAssertFalse(allowed(feed: "https://example.com/appcast.xml"))
        XCTAssertFalse(allowed(publicKey: ""))
        XCTAssertFalse(allowed(publicKey: "$(DAYDREAMING_SPARKLE_PUBLIC_KEY)"))
        XCTAssertFalse(allowed(publicKey: Data(repeating: 1, count: 31).base64EncodedString()))
        XCTAssertFalse(allowed(debug: true))
        XCTAssertFalse(allowed(tests: true))
    }

    @MainActor
    func testHostedTestsNeverCreateOrStartAnUpdater() {
        let manager = UpdaterManager()
        manager.start()
        manager.checkForUpdates()
        manager.setAutomaticallyChecks(true)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.canCheckForUpdates)
        XCTAssertFalse(manager.automaticallyChecks)
        XCTAssertFalse(manager.isPresentingUpdateUI)
    }

    @MainActor
    func testUpdateMenuRemainsAvailableAfterDismissingTheWindow() {
        let manager = UpdaterManager()
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let item = SUAppcastItem.empty()
        XCTAssertFalse(manager.isUpdateAvailable)
        manager.updater(controller.updater, didFindValidUpdate: item)
        XCTAssertTrue(manager.isUpdateAvailable)
        manager.standardUserDriverWillFinishUpdateSession()
        XCTAssertTrue(manager.isUpdateAvailable)
        manager.updater(controller.updater, willInstallUpdate: item)
        XCTAssertFalse(manager.isUpdateAvailable)
    }

    @MainActor
    func testNoValidUpdateClearsTheMenuAndDoesNotStartAnUpdate() {
        let manager = UpdaterManager()
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        manager.updater(controller.updater, didFindValidUpdate: SUAppcastItem.empty())
        manager.updaterDidNotFindUpdate(controller.updater, error: NSError(domain: "test", code: 0))
        XCTAssertFalse(manager.isUpdateAvailable)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.canCheckForUpdates)
    }

    private func allowed(bundle: String? = AppRuntime.productionBundleID, channel: String = "release",
                         feed: String = UpdaterPolicy.feedURL, publicKey: String? = nil,
                         debug: Bool = false, tests: Bool = false) -> Bool {
        UpdaterPolicy.allowsUpdates(bundleID: bundle, channel: channel, feed: feed,
                                   publicKey: publicKey ?? key, isDebug: debug, isRunningTests: tests)
    }
}
