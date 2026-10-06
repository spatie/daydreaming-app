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

    init(bundleID: String?) {
        let identifier = bundleID ?? "be.spatie.daydreaming.unidentified"
        service = identifier + ".openai"
        previousService = identifier == AppRuntime.productionBundleID ? "be.spatie.weathercanvas.openai" : nil
        allowsAccess = bundleID != nil && !AppRuntime.isPreview(bundleID: bundleID)
    }
}
