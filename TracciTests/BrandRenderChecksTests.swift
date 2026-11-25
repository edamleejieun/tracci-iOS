import XCTest
@testable import Tracci

@MainActor
final class BrandRenderChecksTests: XCTestCase {
    func testRenderWatermarkAndLockupReturnsImages() {
        XCTAssertTrue(BrandRenderChecks.canRenderWatermarkAndLockup())
    }
}

final class HomeFeaturedCoverPolicyTests: XCTestCase {
    func testUserProvidedCoverCanBecomeHomeMediaHero() {
        let trip = makeTrip(fileId: "user-cover")

        XCTAssertEqual(
            trip.homeFeaturedCoverURL?.absoluteString,
            "https://example.com/preview.jpg"
        )
    }

    func testSystemProvidedCoverKeepsHomeNarrativeStage() {
        let trip = makeTrip(fileId: nil)

        XCTAssertNil(trip.homeFeaturedCoverURL)
        XCTAssertNil(trip.homeFeaturedCoverFallbackURL)
        XCTAssertEqual(
            trip.coverCardURL?.absoluteString,
            "https://example.com/thumb.jpg"
        )
        XCTAssertEqual(
            trip.coverHeroURL?.absoluteString,
            "https://example.com/preview.jpg"
        )
    }

    func testFullSizeCoverPreviewPrefersOriginalThenDerivedImages() {
        let trip = makeTrip(fileId: "user-cover")

        XCTAssertEqual(
            trip.coverFullSizeURLs.map(\.absoluteString),
            [
                "https://example.com/original.jpg",
                "https://example.com/preview.jpg",
                "https://example.com/thumb.jpg"
            ]
        )
    }

    private func makeTrip(fileId: String?) -> Trip {
        Trip(
            id: "featured-cover-policy",
            title: "厦门之旅",
            startDate: "2026-07-21",
            endDate: "2026-07-24",
            status: .ongoing,
            coverPhoto: TripCoverPhoto(
                fileId: fileId,
                url: "https://example.com/original.jpg",
                thumbnailUrl: "https://example.com/thumb.jpg",
                previewUrl: "https://example.com/preview.jpg",
                exportUrl: nil,
                storyPortraitUrl: nil,
                storyCardUrl: nil,
                squareUrl: nil,
                watermarkedUrl: nil,
                width: 1200,
                height: 800
            )
        )
    }
}
