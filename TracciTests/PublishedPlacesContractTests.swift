import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// 契约 §15.4.2「已发布地点列表」与 §15.4 地点内容块的客户端对接表征。
///
/// 钉住三件容易静默走偏的事：
/// 1. `pageSize` 上限是 **50** 而不是 saved-places 的 100 —— 契约对非法分页是**拒绝**（`42201`）不是夹紧。
/// 2. `publishedAt` 是 UTC `yyyy-MM-dd HH:mm:ss`，不是带 `Z` 的 ISO-8601。
/// 3. `cover` / `highlight` / `isSaved` / `editorialContent` 都可能整块省略（`@JsonInclude(NON_NULL)`）。
final class PublishedPlacesContractTests: XCTestCase {

    // MARK: - Query 构造

    func testQuery_encodesScopePagingAndOmitsEmptyCityName() {
        let items = PublishedPlacesQuery(
            placeScope: .destination,
            page: 1,
            pageSize: 50
        ).queryItems

        XCTAssertEqual(queryDictionary(items), [
            "placeScope": "DESTINATION",
            "page": "1",
            "pageSize": "50",
        ])
    }

    func testQuery_encodesCityNameForPOILayer() {
        let items = PublishedPlacesQuery(
            placeScope: .poi,
            cityName: "京都",
            page: 2,
            pageSize: 50
        ).queryItems

        let dictionary = queryDictionary(items)
        XCTAssertEqual(dictionary["placeScope"], "POI")
        XCTAssertEqual(dictionary["cityName"], "京都")
        XCTAssertEqual(dictionary["page"], "2")
    }

    func testQuery_trimsCityNameAndOmitsWhenBlank() {
        let trimmed = queryDictionary(
            PublishedPlacesQuery(placeScope: .poi, cityName: "  京都  ").queryItems
        )
        XCTAssertEqual(trimmed["cityName"], "京都")

        let blank = queryDictionary(
            PublishedPlacesQuery(placeScope: .poi, cityName: "   ").queryItems
        )
        XCTAssertNil(blank["cityName"], "空 cityName 不应出现在请求里，否则服务端精确匹配会取到空集")
    }

    func testQuery_clampsPageSizeToContractLimitOf50() {
        // saved-places 列表允许 100；本接口超过 50 会被服务端拒绝并返回 42201。
        let oversize = queryDictionary(
            PublishedPlacesQuery(placeScope: .destination, pageSize: 100).queryItems
        )
        XCTAssertEqual(oversize["pageSize"], "50")

        let zero = queryDictionary(
            PublishedPlacesQuery(placeScope: .destination, page: 0, pageSize: 0).queryItems
        )
        XCTAssertEqual(zero["page"], "1")
        XCTAssertEqual(zero["pageSize"], "1")
    }

    func testQuery_omitsCategoryByDefaultBecauseFilteringIsLocal() {
        // 规格 §5.2：不传 category，类别筛选在客户端本地做。
        let items = PublishedPlacesQuery(placeScope: .poi, cityName: "北京").queryItems
        XCTAssertNil(queryDictionary(items)["category"])
    }

    // MARK: - 列表项解码

    func testPublishedPlace_decodesContractSample() throws {
        let json = """
        {
          "id": "place-uuid",
          "name": "清水寺",
          "placeScope": "POI",
          "category": "ATTRACTION",
          "cityName": "京都",
          "country": "日本",
          "latitude": 34.9949,
          "longitude": 135.7850,
          "supportedUsages": ["ITINERARY_NODE"],
          "highlight": "山门到舞台这一段，值得慢慢走。",
          "publishedAt": "2026-09-01 08:00:00",
          "isSaved": false,
          "cover": {
            "id": "media-id",
            "thumbnailUrl": "https://cdn.example/qingshui-thumb.jpg",
            "altText": "清水舞台",
            "attribution": "趣溪编辑"
          }
        }
        """

        let place = try decode(PublishedPlace.self, from: json)
        XCTAssertEqual(place.id, "place-uuid")
        XCTAssertEqual(place.name, "清水寺")
        XCTAssertEqual(place.placeScope, .poi)
        XCTAssertEqual(place.category, .attraction)
        XCTAssertEqual(place.cityName, "京都")
        XCTAssertEqual(place.country, "日本")
        XCTAssertEqual(place.latitude, 34.9949)
        XCTAssertEqual(place.longitude, 135.7850)
        XCTAssertEqual(place.supportedUsages, [.itineraryNode])
        XCTAssertEqual(place.highlight, "山门到舞台这一段，值得慢慢走。")
        XCTAssertEqual(place.isSaved, false)
        XCTAssertEqual(place.isSavedLocally, false)
        XCTAssertEqual(place.cover?.displayURL, "https://cdn.example/qingshui-thumb.jpg")
        XCTAssertEqual(place.cover?.altText, "清水舞台")
    }

    func testPublishedPlace_toleratesOmittedCoverHighlightAndIsSaved() throws {
        // 契约：无图整块省略 cover、不返回占位 URL；highlight 两档派生都空则省略；
        // lat/lng 无坐标时省略。客户端必须全部走降级而不是解码失败。
        let json = """
        {
          "id": "place-nara",
          "name": "奈良",
          "placeScope": "DESTINATION",
          "category": "CITY",
          "cityName": null,
          "country": "日本",
          "supportedUsages": []
        }
        """

        let place = try decode(PublishedPlace.self, from: json)
        XCTAssertNil(place.cover)
        XCTAssertNil(place.highlight)
        XCTAssertNil(place.latitude)
        XCTAssertNil(place.longitude)
        XCTAssertNil(place.publishedAt)
        XCTAssertNil(place.isSaved)
        XCTAssertFalse(place.isSavedLocally, "isSaved 缺省按未收藏处理")
    }

    func testPublishedPlace_parsesPublishedAtAsUTCWithoutZSuffix() throws {
        let json = """
        {
          "id": "p1", "name": "北京", "placeScope": "DESTINATION", "category": "CITY",
          "publishedAt": "2026-09-01 08:00:00"
        }
        """
        let place = try decode(PublishedPlace.self, from: json)

        // 独立 oracle：同一刻的 ISO-8601 带 Z 写法。
        let expected = ISO8601DateFormatter().date(from: "2026-09-01T08:00:00Z")
        XCTAssertEqual(place.publishedDate, expected)
    }

    func testPublishedPlace_publishedDateOrderingSupportsClientSideSort() throws {
        let newer = try decode(PublishedPlace.self, from: """
        {"id":"a","name":"北京","placeScope":"DESTINATION","category":"CITY","publishedAt":"2026-09-12 08:00:00"}
        """)
        let older = try decode(PublishedPlace.self, from: """
        {"id":"b","name":"重庆","placeScope":"DESTINATION","category":"CITY","publishedAt":"2026-09-08 08:00:00"}
        """)

        // 规格 §6.5：展示顺序由客户端按 publishedAt DESC 决定，不依赖服务端 cityName ASC。
        XCTAssertGreaterThan(newer.publishedDate!, older.publishedDate!)
    }

    func testCover_displayURLFollowsContractPriority() throws {
        let allThree = try decode(PublishedPlaceCover.self, from: """
        {"id":"m1","thumbnailUrl":"thumb","previewUrl":"preview","url":"full"}
        """)
        XCTAssertEqual(allThree.displayURL, "thumb")

        let noThumb = try decode(PublishedPlaceCover.self, from: """
        {"id":"m1","previewUrl":"preview","url":"full"}
        """)
        XCTAssertEqual(noThumb.displayURL, "preview")

        let onlyFull = try decode(PublishedPlaceCover.self, from: """
        {"id":"m1","url":"full"}
        """)
        XCTAssertEqual(onlyFull.displayURL, "full")
    }

    // MARK: - 详情内容块解码

    func testPlaceMedia_heroURLPrefersPreviewOverFull() throws {
        let media = try decode(PlaceMedia.self, from: """
        {"id":"m1","url":"full","thumbnailUrl":"thumb","previewUrl":"preview","width":1600,"height":1067,
         "altText":"清水舞台","attribution":"趣溪编辑"}
        """)
        XCTAssertEqual(media.heroURL, "preview")
        XCTAssertEqual(media.width, 1600)
        XCTAssertEqual(media.height, 1067)

        let noPreview = try decode(PlaceMedia.self, from: """
        {"id":"m2","url":"full"}
        """)
        XCTAssertEqual(noPreview.heroURL, "full")
    }

    func testPlaceDetail_decodesEditorialContentMetaAndMedia() throws {
        let json = """
        {
          "id": "place-id",
          "name": "蓝瓶咖啡 京都店",
          "placeScope": "POI",
          "category": "RESTAURANT",
          "address": "京都府京都市",
          "cityName": "京都",
          "country": "日本",
          "latitude": 35.0116,
          "longitude": 135.7681,
          "supportedUsages": ["ITINERARY_NODE"],
          "editorialContent": {
            "version": 3,
            "introduction": "从午门进、神武门出。",
            "highlights": ["太和殿广场", "珍宝馆"],
            "recommendedDurationMinutes": 180,
            "visitTips": ["租一台讲解器"],
            "bestVisitTime": "上午 8:30–10:30",
            "reservationTips": "需提前 7 天预约",
            "notice": "院内禁止使用无人机"
          },
          "contentMeta": {
            "aiAssisted": true,
            "label": "AI 辅助整理 · 已审核",
            "verifiedAt": "2026-08-01T00:00:00",
            "nextReviewAt": "2027-02-01T00:00:00",
            "reviewDue": false
          },
          "media": [
            {"id":"m1","url":"full","previewUrl":"preview","altText":"店面"}
          ],
          "userContext": {"isSaved": true, "savedPlaceId": "saved-1", "note": null,
                          "usageSummary": {"tripCount": 1, "lastUsedTripId": "trip-1"}}
        }
        """

        let detail = try decode(PlaceDetail.self, from: json)
        XCTAssertEqual(detail.editorialContent?.version, 3)
        XCTAssertEqual(detail.editorialContent?.introduction, "从午门进、神武门出。")
        XCTAssertEqual(detail.editorialContent?.highlights, ["太和殿广场", "珍宝馆"])
        XCTAssertEqual(detail.editorialContent?.recommendedDurationMinutes, 180)
        XCTAssertEqual(detail.editorialContent?.visitTips, ["租一台讲解器"])
        XCTAssertEqual(detail.editorialContent?.bestVisitTime, "上午 8:30–10:30")
        XCTAssertEqual(detail.editorialContent?.reservationTips, "需提前 7 天预约")
        XCTAssertEqual(detail.editorialContent?.notice, "院内禁止使用无人机")
        XCTAssertEqual(detail.contentMeta?.aiAssisted, true)
        XCTAssertEqual(detail.contentMeta?.label, "AI 辅助整理 · 已审核")
        XCTAssertEqual(detail.contentMeta?.reviewDue, false)
        XCTAssertEqual(detail.media?.count, 1)
        XCTAssertEqual(detail.media?.first?.heroURL, "preview")
        XCTAssertEqual(detail.userContext?.usageSummary?.tripCount, 1)
    }

    func testPlaceDetail_omitsContentBlocksWhenNotPublished() throws {
        // 契约 §15.4：无 PUBLISHED 内容时整块省略，不返回空壳。
        // 既有收藏/行程入口的详情就长这样，新增字段不得让它解码失败。
        let json = """
        {
          "id": "place-id", "name": "某个地点", "placeScope": "POI", "category": "OTHER",
          "supportedUsages": [], "userContext": {"isSaved": false}
        }
        """

        let detail = try decode(PlaceDetail.self, from: json)
        XCTAssertNil(detail.editorialContent)
        XCTAssertNil(detail.contentMeta)
        XCTAssertNil(detail.media)
        XCTAssertNil(detail.address)
        XCTAssertEqual(detail.userContext?.isSaved, false)
    }

    func testEditorialContent_toleratesPartiallyFilledBlocks() throws {
        // 编辑可以只填几项；客户端按块隐藏，不补占位文案。
        let content = try decode(PlaceEditorialContent.self, from: """
        {"version":1,"introduction":"只有介绍"}
        """)
        XCTAssertEqual(content.introduction, "只有介绍")
        XCTAssertNil(content.highlights)
        XCTAssertNil(content.recommendedDurationMinutes)
        XCTAssertNil(content.visitTips)
        XCTAssertNil(content.bestVisitTime)
        XCTAssertNil(content.reservationTips)
        XCTAssertNil(content.notice)
    }

    // MARK: - 错误码映射

    func testErrorMessage_coversPaginationRejection() {
        XCTAssertEqual(
            SavedPlaceErrorMessage.resolve(APIError.business(code: 42201, message: "invalid page")),
            "分页或筛选参数不正确"
        )
    }

    func testIsAlreadySaved_treats40901AsIdempotentSuccess() {
        // 决策 9：重复收藏不弹错误。
        XCTAssertTrue(SavedPlaceErrorMessage.isAlreadySaved(APIError.business(code: 40901, message: "already")))
        XCTAssertFalse(SavedPlaceErrorMessage.isAlreadySaved(APIError.business(code: 42243, message: "mismatch")))
        XCTAssertFalse(SavedPlaceErrorMessage.isAlreadySaved(APIError.unauthorized))
    }

    // MARK: - Path / Query 映射（经 HTTPStub）

    func testService_publishedPlaces_mapsPathQueryAndPageEnvelope() async throws {
        let stub = HTTPStub()
        stub.install()
        defer {
            stub.removeAllResponses()
            stub.resetRequestLog()
            stub.uninstall()
        }
        let service = SavedPlaceService(apiClient: stub.makeAPIClient())

        stub.stubAPISuccess(
            path: "/api/v1/places",
            dataJSON: """
            {"list":[{"id":"p1","name":"北京","placeScope":"DESTINATION","category":"CITY",
                      "country":"中国","highlight":"首都风范","publishedAt":"2026-09-12 08:00:00",
                      "isSaved":true}],
             "total":1,"page":1,"pageSize":50}
            """,
            allowPathOnlyMatch: true
        )

        let page = try await service.publishedPlaces(
            PublishedPlacesQuery(placeScope: .destination, page: 1, pageSize: 50)
        )

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.list.first?.name, "北京")
        XCTAssertEqual(page.list.first?.isSaved, true)

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/places")
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertTrue(query.contains("placeScope=DESTINATION"), query)
        XCTAssertTrue(query.contains("pageSize=50"), query)
    }

    func testService_publishedPlaces_surfacesBusinessError() async throws {
        let stub = HTTPStub()
        stub.install()
        defer {
            stub.removeAllResponses()
            stub.resetRequestLog()
            stub.uninstall()
        }
        let service = SavedPlaceService(apiClient: stub.makeAPIClient())

        stub.stubAPIBusinessError(
            path: "/api/v1/places",
            code: 42201,
            message: "pageSize 超出上限",
            allowPathOnlyMatch: true
        )

        do {
            _ = try await service.publishedPlaces(PublishedPlacesQuery(placeScope: .poi))
            XCTFail("非法分页应当抛业务错误")
        } catch {
            XCTAssertEqual(SavedPlaceErrorMessage.businessCode(error), 42201)
        }
    }

    func testService_publishedPlaces_treatsEmptyListAsSuccess() async throws {
        // 契约：空列表 code=0 且 total=0，不是错误。
        let stub = HTTPStub()
        stub.install()
        defer {
            stub.removeAllResponses()
            stub.resetRequestLog()
            stub.uninstall()
        }
        let service = SavedPlaceService(apiClient: stub.makeAPIClient())

        stub.stubAPISuccess(
            path: "/api/v1/places",
            dataJSON: #"{"list":[],"total":0,"page":1,"pageSize":50}"#,
            allowPathOnlyMatch: true
        )

        let page = try await service.publishedPlaces(PublishedPlacesQuery(placeScope: .destination))
        XCTAssertEqual(page.total, 0)
        XCTAssertTrue(page.list.isEmpty)
    }

    // MARK: - Helpers

    private func queryDictionary(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
