import Foundation
import XCTest
@testable import Tracci

/// Phase 0 表征：`CreateTripRequest` / `UpdateTripRequest` 编码与 `TripFormState` 映射。
/// 纯编码，无网络。冻结「怪行为只冻结不修」（UpdateTripRequest 完全忽略 savedPlaceId）。
final class TripRequestEncodingTests: XCTestCase {

    private func encode(_ value: Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(AnyEncodable(value))
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [String: Any] ?? [:]
    }

    private func jsonString(_ value: Encodable) throws -> String {
        let data = try JSONEncoder().encode(AnyEncodable(value))
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - CreateTripRequest

    func testCreateTripRequest_trimsTitleAndFormatsDates() throws {
        let calendar = TracciDateContext.calendar
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start)
        let state = TripFormState(
            title: "  京都赏樱  ",
            destinationName: "",
            selectedDestination: nil,
            startDate: start,
            endDate: end,
            coverFileId: nil,
            coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let request = CreateTripRequest(from: state, baseCurrency: "CNY")
        let body = try encode(request)

        XCTAssertEqual(body["title"] as? String, "京都赏樱")
        XCTAssertEqual(body["baseCurrency"] as? String, "CNY")
        XCTAssertEqual(body["startDate"] as? String, TripDateFormatting.apiString(from: start))
        XCTAssertEqual(body["endDate"] as? String, TripDateFormatting.apiString(from: end))
    }

    func testCreateTripRequest_manualDestinationUsesProviderMANUAL() throws {
        let state = TripFormState(
            title: "T",
            destinationName: " 自定义地点 ",
            selectedDestination: nil,
            startDate: nil,
            endDate: nil,
            coverFileId: nil,
            coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let request = CreateTripRequest(from: state)
        let body = try encode(request)

        XCTAssertNotNil(body["destination"])
        let dest = body["destination"] as? [String: Any]
        XCTAssertEqual(dest?["name"] as? String, "自定义地点")
        XCTAssertEqual(dest?["provider"] as? String, "MANUAL")
    }

    func testCreateTripRequest_selectedDestinationBecomesStructuredInput() throws {
        let selected = TripDestination(name: "Tokyo", provider: "APPLE", providerPlaceId: "pid-1",
                                       country: "日本", latitude: 35.0, longitude: 139.0)
        let state = TripFormState(
            title: "T",
            destinationName: "",
            selectedDestination: selected,
            startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let request = CreateTripRequest(from: state)
        let body = try encode(request)

        let dest = body["destination"] as? [String: Any]
        XCTAssertEqual(dest?["name"] as? String, "Tokyo")
        XCTAssertEqual(dest?["provider"] as? String, "APPLE")
        XCTAssertEqual(dest?["providerPlaceId"] as? String, "pid-1")
    }

    func testCreateTripRequest_emptyDestinationOmitsDestinationKey() throws {
        let state = TripFormState(
            title: "T",
            destinationName: "   ",
            selectedDestination: nil,
            startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let request = CreateTripRequest(from: state)
        let body = try encode(request)

        XCTAssertNil(body["destination"])
    }

    func testCreateTripRequest_savedPlaceIdPresentNilDestination() throws {
        // selectedDestination 与 savedPlaceId 同时存在时，savedPlaceId 优先 → destination 为 nil。
        let selected = TripDestination(name: "Tokyo", provider: "APPLE")
        let state = TripFormState(
            title: "T",
            destinationName: "",
            selectedDestination: selected,
            startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
            destinationSavedPlaceId: "saved-1"
        )
        let request = CreateTripRequest(from: state)
        let body = try encode(request)

        XCTAssertNil(body["destination"])
        XCTAssertEqual(body["destinationSavedPlaceId"] as? String, "saved-1")
    }

    // MARK: - UpdateTripRequest（当前零覆盖 → 冻结）

    func testUpdateTripRequest_encodesStatusChangeConfirmedFalseAndTrue() throws {
        let state = TripFormState(
            title: "T", destinationName: "Osaka", selectedDestination: nil,
            startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let noConfirm = UpdateTripRequest(from: state, statusChangeConfirmed: false)
        XCTAssertEqual(try encode(noConfirm)["statusChangeConfirmed"] as? Bool, false)

        let confirmed = UpdateTripRequest(from: state, statusChangeConfirmed: true)
        XCTAssertEqual(try encode(confirmed)["statusChangeConfirmed"] as? Bool, true)
    }

    func testUpdateTripRequest_ignoresStateSavedPlaceId_keyAbsent() throws {
        // 冻结怪行为：UpdateTripRequest 完全没有 destinationSavedPlaceId 字段，
        // 即使 state 含 savedPlaceId，body 也不应出现该 key。
        let state = TripFormState(
            title: "T",
            destinationName: "",
            selectedDestination: nil,
            startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
            destinationSavedPlaceId: "saved-ghost"
        )
        let request = UpdateTripRequest(from: state)
        let body = try encode(request)

        XCTAssertNil(body["destinationSavedPlaceId"])
    }

    func testUpdateTripRequest_destinationThreeVariants() throws {
        let manual = TripFormState(title: "T", destinationName: "手写", selectedDestination: nil,
                                   startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
                                   destinationSavedPlaceId: nil)
        let manualBody = try encode(UpdateTripRequest(from: manual))
        let dest = manualBody["destination"] as? [String: Any]
        XCTAssertEqual(dest?["provider"] as? String, "MANUAL")

        let selected = TripDestination(name: "Kyoto", provider: "APPLE")
        let withSelected = TripFormState(title: "T", destinationName: "", selectedDestination: selected,
                                         startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
                                         destinationSavedPlaceId: nil)
        let selectedBody = try encode(UpdateTripRequest(from: withSelected))
        XCTAssertEqual((selectedBody["destination"] as? [String: Any])?["provider"] as? String, "APPLE")

        let empty = TripFormState(title: "T", destinationName: "", selectedDestination: nil,
                                  startDate: nil, endDate: nil, coverFileId: nil, coverPreviewURL: nil,
                                  destinationSavedPlaceId: nil)
        XCTAssertNil(try encode(UpdateTripRequest(from: empty))["destination"])
    }

    // MARK: - TripFormState

    func testTripFormState_emptyDefaultsTodayToPlusTwo() {
        let form = TripFormState.empty
        let calendar = TracciDateContext.calendar
        let today = calendar.startOfDay(for: Date())
        let plusTwo = calendar.date(byAdding: .day, value: 2, to: today)

        XCTAssertEqual(form.title, "")
        XCTAssertEqual(form.destinationName, "")
        XCTAssertEqual(form.startDate, today)
        XCTAssertEqual(form.endDate, plusTwo)
        XCTAssertNil(form.destinationSavedPlaceId)
    }

    func testTripFormState_fromMapsFieldsAndClearsSavedPlaceId() {
        let trip = Trip(
            id: "trip-1",
            title: "既有旅程",
            startDate: "2026-09-01",
            endDate: "2026-09-05",
            status: .planning,
            totalDays: 5,
            destination: TripDestination(name: "Tokyo", provider: "APPLE"),
            coverPhoto: TripCoverPhoto(fileId: "file-1", url: nil, thumbnailUrl: nil, previewUrl: nil,
                                       exportUrl: nil, storyPortraitUrl: nil, storyCardUrl: nil,
                                       squareUrl: nil, watermarkedUrl: nil, width: nil, height: nil)
        )
        let form = TripFormState.from(trip: trip)

        XCTAssertEqual(form.title, "既有旅程")
        XCTAssertEqual(form.destinationName, "Tokyo")
        XCTAssertNotNil(form.selectedDestination)
        XCTAssertEqual(form.coverFileId, "file-1")
        // 冻结：编辑回填始终不携带 savedPlaceId。
        XCTAssertNil(form.destinationSavedPlaceId)
    }
}

/// 让非 Codable（`Encodable` 即可）的值能走 `JSONEncoder` 的包装器。
private struct AnyEncodable: Encodable {
    private let encodable: Encodable
    init(_ encodable: Encodable) { self.encodable = encodable }
    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}
