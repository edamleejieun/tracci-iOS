import Foundation
import MapKit
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Phase 0 表征：`PlaceCategory` → `ItineraryNodeType` 推断 + `SavedPlaceClassification.infer` 中文标签矩阵。
///
/// `suggestedNodeType(for:)` 是 `ItineraryViewModel.private static`（@testable 亦不可见），
/// 故经公开 `applySavedPlace(_:to:)` 覆盖全矩阵，不改可见性——保住「仅测试 + 文档」回滚边界。
/// `TracciPlaceSearchResult(mapItem:)` 间接覆盖 private MK category displayName 扩展，
/// 冻结 MapKit category → 中文 hint → Saved Place 分类的真实链路。
@MainActor
final class CategoryMappingCharacterizationTests: XCTestCase {

    private func makeVM() -> ItineraryViewModel {
        let client = APIClient()
        let service = ItineraryService(apiClient: client)
        let trip = ItineraryFixtures.makeTrip(status: .planning)
        let routeProvider = TripRouteProviderStub()
        return ItineraryViewModel(
            tripId: trip.id,
            trip: trip,
            itineraryService: service,
            savedPlaceService: nil,
            routeProvider: routeProvider
        )
    }

    private func nodeType(for category: PlaceCategory) -> ItineraryNodeType {
        let vm = makeVM()
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        let savedPlace = ItineraryFixtures.savedPlace(name: "示例", category: category)
        vm.applySavedPlace(savedPlace, to: &form)
        return form.type
    }

    // MARK: - PlaceCategory → ItineraryNodeType 全矩阵

    func testApplySavedPlace_restaurantMapping() {
        XCTAssertEqual(nodeType(for: .restaurant), .restaurant)
    }

    func testApplySavedPlace_hotelMapping() {
        XCTAssertEqual(nodeType(for: .hotel), .hotel)
    }

    func testApplySavedPlace_transportMapping() {
        XCTAssertEqual(nodeType(for: .transport), .transport)
    }

    func testApplySavedPlace_shoppingMapping() {
        XCTAssertEqual(nodeType(for: .shopping), .shopping)
    }

    func testApplySavedPlace_attractionMapping() {
        XCTAssertEqual(nodeType(for: .attraction), .attraction)
    }

    func testApplySavedPlace_cityFallsBackToOther() {
        XCTAssertEqual(nodeType(for: .city), .other)
    }

    func testApplySavedPlace_regionFallsBackToOther() {
        XCTAssertEqual(nodeType(for: .region), .other)
    }

    func testApplySavedPlace_otherStaysOther() {
        XCTAssertEqual(nodeType(for: .other), .other)
    }

    func testApplySavedPlace_setsIdentityLocationAndType_preservesCustomTitle() {
        let vm = makeVM()
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.title = "旧标题"
        let savedPlace = ItineraryFixtures.savedPlace(id: "saved-42", name: "清水寺", category: .attraction)
        vm.applySavedPlace(savedPlace, to: &form)

        XCTAssertEqual(form.savedPlaceId, "saved-42")
        XCTAssertEqual(form.locationName, "清水寺")
        XCTAssertNotNil(form.selectedLocation)
        XCTAssertEqual(form.type, .attraction)
        XCTAssertEqual(form.title, "旧标题", "选择想去的地点不应覆盖用户已填写的自定义标题")
    }

    func testMapKitMuseumCategory_mapsThroughSearchResultToAttraction() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 39.9163, longitude: 116.3972))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "故宫博物院"
        mapItem.pointOfInterestCategory = .museum

        let result = TracciPlaceSearchResult(mapItem: mapItem, style: .scopedPlace)
        XCTAssertEqual(result.category, "博物馆")

        let classification = SavedPlaceClassification.infer(
            name: result.name,
            mapCategory: result.category,
            cityName: result.cityName,
            provinceName: result.provinceName
        )
        XCTAssertEqual(classification, .init(scope: .poi, category: .attraction))
        XCTAssertEqual(ItineraryNodeSuggestion.nodeType(for: result), .attraction)
    }

    // MARK: - SavedPlaceClassification.infer 中文标签矩阵

    func testInfer_restaurantLabels() {
        for label in ["餐厅", "咖啡", "烘焙", "酒吧", "酒庄"] {
            let c = SavedPlaceClassification.infer(name: label, mapCategory: label, cityName: nil, provinceName: nil)
            XCTAssertEqual(c.category, .restaurant, "label=\(label)")
            XCTAssertEqual(c.scope, .poi)
        }
    }

    func testInfer_hotelLabel() {
        let c = SavedPlaceClassification.infer(name: "酒店", mapCategory: "酒店", cityName: nil, provinceName: nil)
        XCTAssertEqual(c.category, .hotel)
    }

    func testInfer_shoppingLabels() {
        for label in ["商店", "市场"] {
            XCTAssertEqual(SavedPlaceClassification.infer(name: label, mapCategory: label, cityName: nil, provinceName: nil).category, .shopping)
        }
    }

    func testInfer_transportLabels() {
        for label in ["机场", "公共交通", "租车", "码头", "停车", "加油站", "充电"] {
            XCTAssertEqual(SavedPlaceClassification.infer(name: label, mapCategory: label, cityName: nil, provinceName: nil).category, .transport, "label=\(label)")
        }
    }

    func testInfer_attractionLabels() {
        // 含「博物馆」→ attraction（与方案 §4.2 裁决一致）。
        for label in ["游乐园", "水族馆", "海滩", "图书馆", "影院", "博物馆", "公园", "体育场", "剧院", "大学", "动物园"] {
            XCTAssertEqual(SavedPlaceClassification.infer(name: label, mapCategory: label, cityName: nil, provinceName: nil).category, .attraction, "label=\(label)")
        }
    }

    func testInfer_defaultIsOther() {
        let c = SavedPlaceClassification.infer(name: "未知", mapCategory: "未知分类", cityName: nil, provinceName: nil)
        XCTAssertEqual(c.category, .other)
        XCTAssertEqual(c.scope, .poi)
    }

    func testInfer_administrativeDetection() {
        // mapCategory == nil 且 name 命中 city / province → destination scope。
        let city = SavedPlaceClassification.infer(name: "京都", mapCategory: nil, cityName: "京都", provinceName: nil)
        XCTAssertEqual(city.scope, .destination)
        XCTAssertEqual(city.category, .city)

        let region = SavedPlaceClassification.infer(name: "京都府", mapCategory: nil, cityName: "京都", provinceName: "京都府")
        XCTAssertEqual(region.scope, .destination)
        XCTAssertEqual(region.category, .region)
    }
}
