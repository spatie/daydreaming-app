import Foundation

enum AppRuntime {
    static let productionBundleID = "be.spatie.daydreaming"

    static func isPreview(bundleID: String?) -> Bool {
        bundleID?.hasPrefix(productionBundleID + ".preview") == true
    }

    static var isPreview: Bool { isPreview(bundleID: Bundle.main.bundleIdentifier) }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
}

struct KeychainNamespace {
    let service: String
    let previousService: String?
    let allowsAccess: Bool

    init(bundleID: String?, providerID: String = "openai") {
        let identifier = bundleID ?? "be.spatie.daydreaming.unidentified"
        service = identifier + "." + providerID
        previousService = identifier == AppRuntime.productionBundleID && providerID == "openai" ? "be.spatie.weathercanvas.openai" : nil
        allowsAccess = bundleID != nil && !AppRuntime.isPreview(bundleID: bundleID)
    }
}
