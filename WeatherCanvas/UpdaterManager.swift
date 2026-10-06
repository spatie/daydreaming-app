import AppKit
import Combine
import Sparkle

struct UpdaterPolicy {
    static let feedURL = "https://getdaydreaming.com/appcast.xml"

    static func allowsUpdates(bundleID: String?, channel: String?, feed: String?, publicKey: String?,
                              isDebug: Bool, isRunningTests: Bool) -> Bool {
        guard !isDebug, !isRunningTests, bundleID == AppRuntime.productionBundleID,
              channel == "release", feed == feedURL,
              let publicKey, let key = Data(base64Encoded: publicKey), key.count == 32 else { return false }
        return true
    }
}

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdaterManager()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isEnabled = false
    @Published private(set) var automaticallyChecks = false
    private(set) var isPresentingUpdateUI = false
    var onPresentationChanged: (() -> Void)?
    var beforeInstallation: (() -> Void)?
    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    private var imageWorkObservation: AnyCancellable?
    private var imageRequestInFlight = false
    private var deferredInstallation: (() -> Void)?

    override init() {
        super.init()
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        guard UpdaterPolicy.allowsUpdates(bundleID: Bundle.main.bundleIdentifier,
                                          channel: info["DaydreamingBuildChannel"] as? String,
                                          feed: info["SUFeedURL"] as? String,
                                          publicKey: info["SUPublicEDKey"] as? String,
                                          isDebug: isDebug, isRunningTests: AppRuntime.isRunningTests) else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        guard let updater = controller?.updater else { return }
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] value in
            MainActor.assumeIsolated { self?.canCheckForUpdates = value && self?.imageRequestInFlight != true }
        }.store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).sink { [weak self] value in
            MainActor.assumeIsolated { self?.automaticallyChecks = value }
        }.store(in: &observations)
        isEnabled = true
    }

    func start() {
        guard let updater = controller?.updater else { return }
        do { try updater.start() }
        catch { isEnabled = false; canCheckForUpdates = false }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, !imageRequestInFlight else { return }
        setPresenting(true)
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        guard isEnabled else { return }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func observeImageWork(_ publisher: Published<Bool>.Publisher) {
        imageWorkObservation = publisher.sink { [weak self] value in
            MainActor.assumeIsolated { self?.setImageRequestInFlight(value) }
        }
    }

    func setImageRequestInFlight(_ inFlight: Bool) {
        imageRequestInFlight = inFlight
        canCheckForUpdates = !inFlight && controller?.updater.canCheckForUpdates == true
        if !inFlight, let installation = deferredInstallation {
            deferredInstallation = nil
            beforeInstallation?()
            installation()
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if imageRequestInFlight {
            throw NSError(domain: "be.spatie.daydreaming.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Finish the current wallpaper before updating Daydreaming."])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard imageRequestInFlight else {
            beforeInstallation?()
            return false
        }
        deferredInstallation = installHandler
        return true
    }

    func standardUserDriverWillShowModalAlert() { setPresenting(true) }
    func standardUserDriverDidShowModalAlert() { setPresenting(false) }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { setPresenting(true) }
    }
    func standardUserDriverWillFinishUpdateSession() { setPresenting(false) }

    private func setPresenting(_ value: Bool) {
        isPresentingUpdateUI = value
        onPresentationChanged?()
    }
}
