import XCTest
@testable import Tracci

final class BrandTokensTests: XCTestCase {
    func testWordmarkTrackingUsesRatio() {
        let size: CGFloat = 22
        XCTAssertEqual(BrandTokens.wordmarkTracking(for: size), size * 0.12, accuracy: 0.001)
    }

    func testWatermarkOpacityMatchesStyle() {
        XCTAssertEqual(BrandTokens.watermarkOpacity(isDark: true), 0.16, accuracy: 0.001)
        XCTAssertEqual(BrandTokens.watermarkOpacity(isDark: false), 0.70, accuracy: 0.001)
    }

    func testExportWatermarkLogoHeightScalesWithCanvas() {
        XCTAssertEqual(BrandTokens.exportWatermarkLogoHeight(canvasWidth: 1080), 75.6, accuracy: 0.001)
    }

    func testBrandInkHexIsCanonical() {
        XCTAssertEqual(BrandTokens.inkHex, 0x18181B)
    }

    func testPrimaryLockupHeightIncludesSloganWhenEnabled() {
        let withoutSlogan = BrandTokens.primaryLockupHeight(showsSlogan: false)
        let withSlogan = BrandTokens.primaryLockupHeight(showsSlogan: true)
        XCTAssertGreaterThan(withSlogan, withoutSlogan)
        XCTAssertEqual(
            withSlogan,
            BrandTokens.primaryLogoHeight
                + BrandTokens.primaryStackSpacing
                + BrandTokens.primaryWordmarkSize
                + BrandTokens.primarySloganSpacing
                + BrandTokens.sloganLineHeight,
            accuracy: 0.001
        )
    }
}