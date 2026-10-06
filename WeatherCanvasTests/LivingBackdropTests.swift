import CoreGraphics
import XCTest
@testable import Daydreaming

final class LivingBackdropTests: XCTestCase {
    func testWindowInertiaIsBoundedAndSettlesWithoutMovingThePicture() {
        var inertia = LogoWindowInertia()
        inertia.moved(to: CGPoint(x: 100, y: 100), at: 10)
        XCTAssertEqual(inertia.offset(at: 10), .zero)
        inertia.moved(to: CGPoint(x: 10_000, y: -10_000), at: 10.1)
        XCTAssertEqual(inertia.offset(at: 10.1), CGSize(width: -12, height: -12))
        let settled = inertia.offset(at: 11.1)
        XCTAssertLessThan(abs(settled.width), 1)
        XCTAssertLessThan(abs(settled.height), 1)
        XCTAssertEqual(inertia.offset(at: 13.1), .zero)
    }

    func testMotionRequiresAnActiveVisibleViewAndEveryAccessibilityPermission() {
        func allowed(requested: Bool = true, visible: Bool = true, active: Bool = true,
                     motion: Bool = false, power: Bool = false, transparency: Bool = false,
                     contrast: Bool = false) -> Bool {
            LivingBackdropPolicy.animates(requested: requested, visible: visible, sceneActive: active,
                                          reduceMotion: motion, lowPower: power,
                                          reduceTransparency: transparency, increasedContrast: contrast)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(requested: false))
        XCTAssertFalse(allowed(visible: false))
        XCTAssertFalse(allowed(active: false))
        XCTAssertFalse(allowed(motion: true))
        XCTAssertFalse(allowed(power: true))
        XCTAssertFalse(allowed(transparency: true))
        XCTAssertFalse(allowed(contrast: true))
    }

    func testPalettePreservesPictureHueWithGentlerSaturation() throws {
        let image = try solidImage(red: 1, green: 0, blue: 0, alpha: 1)
        let palette = LivingBackdropPalette.sample(image)
        XCTAssertEqual(palette.colors.count, 3)
        for color in palette.colors {
            XCTAssertEqual(color.red, 0.58 + 0.2126 * 0.42, accuracy: 0.002)
            XCTAssertEqual(color.green, 0.2126 * 0.42, accuracy: 0.002)
            XCTAssertEqual(color.blue, color.green, accuracy: 0.002)
        }
    }

    func testTransparentPictureUsesWarmFallback() throws {
        let image = try solidImage(red: 0, green: 0, blue: 0, alpha: 0)
        XCTAssertEqual(LivingBackdropPalette.sample(image), .warm)
    }

    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8,
                                            bitsPerComponent: 8, bytesPerRow: 32, space: space,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }
}
