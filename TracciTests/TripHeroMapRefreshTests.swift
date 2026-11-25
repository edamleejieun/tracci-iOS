import CoreLocation
import XCTest
@testable import Tracci

final class TripHeroMapRefreshTests: XCTestCase {

    func testRenderContentKeyChangesWhenLaterRouteCoordinateMoves() {
        let annotations = [
            TripHeroMapData.HeroMapAnnotation(
                id: "day-1-start",
                coordinate: coordinate(31.20, 121.40),
                title: "起点",
                timeText: "09:00",
                index: 1,
                dayIndex: 1
            )
        ]
        let originalSegment = TripHeroMapData.DayRouteSegment(
            dayIndex: 1,
            coordinates: [
                coordinate(31.20, 121.40),
                coordinate(31.21, 121.41),
                coordinate(31.22, 121.42),
                coordinate(31.23, 121.43)
            ]
        )
        let movedSegment = TripHeroMapData.DayRouteSegment(
            dayIndex: 1,
            coordinates: [
                coordinate(31.20, 121.40),
                coordinate(31.21, 121.41),
                coordinate(31.22, 121.42),
                coordinate(32.00, 122.00)
            ]
        )

        let originalKey = makeKey(annotations: annotations, segments: [originalSegment])
        let movedKey = makeKey(annotations: annotations, segments: [movedSegment])

        XCTAssertNotEqual(originalKey, movedKey)
    }

    func testRenderContentKeyChangesBetweenDayAndFullTripScope() {
        let annotations = [
            TripHeroMapData.HeroMapAnnotation(
                id: "only-node",
                coordinate: coordinate(31.20, 121.40),
                title: "节点",
                timeText: nil,
                index: 1
            )
        ]

        let dayKey = makeKey(annotations: annotations, segments: [], isFullTrip: false)
        let fullTripKey = makeKey(annotations: annotations, segments: [], isFullTrip: true)

        XCTAssertNotEqual(dayKey, fullTripKey)
    }

    func testDayRoutePolylineMetadataRoundTripsThroughStandardPolylineTitle() {
        let polyline = DayRoutePolylineMetadata.makePolyline(
            coordinates: [coordinate(31.20, 121.40), coordinate(31.21, 121.41)],
            dayIndex: 2,
            dayCount: 5,
            layer: .line
        )

        XCTAssertEqual(
            DayRoutePolylineMetadata(title: polyline.title),
            DayRoutePolylineMetadata(dayIndex: 2, dayCount: 5, layer: .line)
        )
    }

    func testDayRoutePolylineMetadataDoesNotConsumeSingleDayRouteTitles() {
        XCTAssertNil(DayRoutePolylineMetadata(title: TripDayRouteLayer.line.rawValue))
        XCTAssertNil(DayRoutePolylineMetadata(title: "\(TripDayRouteLayer.line.rawValue).upcoming"))
    }

    private func makeKey(
        annotations: [TripHeroMapData.HeroMapAnnotation],
        segments: [TripHeroMapData.DayRouteSegment],
        isFullTrip: Bool = true
    ) -> String {
        TripHeroMapView.makeRenderContentKey(
            annotations: annotations,
            destinationCoordinate: nil,
            daySegments: segments,
            isFullTripOverview: isFullTrip,
            fullTripDayCount: 2,
            tripStatus: .completed
        )
    }

    private func coordinate(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
