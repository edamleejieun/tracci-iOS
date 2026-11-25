import Foundation
import XCTest
@testable import Tracci

/// Phase 0 表征：`CreateItineraryNodeRequest` / `UpdateItineraryNodeRequest` 编码语义。
/// 纯编码，无网络。冻结 transport 强制空 title、hotel endTime、details `{}` vs 缺省、noteOnly、emptyForClearing。
final class ItineraryMutationRequestTests: XCTestCase {

    private func encode(_ value: Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(AnyEncodable(value))
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [String: Any] ?? [:]
    }

    private func makeForm(
        type: ItineraryNodeType = .attraction,
        title: String = "节点",
        locationName: String = "地点",
        startTime: String = "09:00",
        endTime: String = "10:00",
        note: String = "",
        savedPlaceId: String? = nil,
        selectedLocation: ItineraryLocation? = nil,
        transportMode: TransportMode? = nil,
        flightNo: String = "", airline: String = "", trainNo: String = "", busNo: String = "",
        departureName: String = "", arrivalName: String = "", seatInfo: String = "",
        confirmationCode: String = "",
        hotelCheckInTime: String = "", hotelCheckOutTime: String = "", hotelCheckOutDate: String = ""
    ) -> ItineraryNodeFormState {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.type = type
        form.title = title
        form.locationName = locationName
        form.startTime = startTime
        form.endTime = endTime
        form.note = note
        form.savedPlaceId = savedPlaceId
        form.selectedLocation = selectedLocation
        form.transportMode = transportMode
        form.flightNo = flightNo
        form.airline = airline
        form.trainNo = trainNo
        form.busNo = busNo
        form.departureName = departureName
        form.arrivalName = arrivalName
        form.seatInfo = seatInfo
        form.confirmationCode = confirmationCode
        form.hotelCheckInTime = hotelCheckInTime
        form.hotelCheckOutTime = hotelCheckOutTime
        form.hotelCheckOutDate = hotelCheckOutDate
        return form
    }

    // MARK: - CreateItineraryNodeRequest

    func testCreate_manualLocationUsesProviderMANUAL() throws {
        let form = makeForm(locationName: "手写地点")
        let body = try encode(CreateItineraryNodeRequest(from: form))

        let location = body["location"] as? [String: Any]
        XCTAssertEqual(location?["name"] as? String, "手写地点")
        XCTAssertEqual(location?["provider"] as? String, "MANUAL")
    }

    func testCreate_transportForcesEmptyTitle() throws {
        let form = makeForm(type: .transport, title: "不该出现")
        let body = try encode(CreateItineraryNodeRequest(from: form))

        XCTAssertEqual(body["title"] as? String, "")
    }

    func testCreate_transportModeMatrix() throws {
        // flight：座位允许
        let flight = makeForm(type: .transport, transportMode: .flight, flightNo: "JL001",
                              seatInfo: "12A")
        let flightBody = try encode(CreateItineraryNodeRequest(from: flight))
        let flightDetails = flightBody["details"] as? [String: Any]
        XCTAssertEqual(flightDetails?["mode"] as? String, "flight")
        XCTAssertEqual(flightDetails?["seatInfo"] as? String, "12A")
        XCTAssertEqual(flightDetails?["flightNo"] as? String, "JL001")

        // hsr：座位允许，trainNo 提交
        let hsr = makeForm(type: .transport, transportMode: .hsr, trainNo: "G1")
        let hsrDetails = (try encode(CreateItineraryNodeRequest(from: hsr)))["details"] as? [String: Any]
        XCTAssertEqual(hsrDetails?["mode"] as? String, "hsr")
        XCTAssertEqual(hsrDetails?["trainNo"] as? String, "G1")

        // driving：座位被抑制
        let driving = makeForm(type: .transport, transportMode: .driving, seatInfo: "不该出现")
        let drivingDetails = (try encode(CreateItineraryNodeRequest(from: driving)))["details"] as? [String: Any]
        XCTAssertEqual(drivingDetails?["mode"] as? String, "driving")
        XCTAssertNil(drivingDetails?["seatInfo"])

        // 无 mode：details 缺失
        let noMode = makeForm(type: .transport, transportMode: nil)
        XCTAssertNil(try encode(CreateItineraryNodeRequest(from: noMode))["details"])
    }

    func testCreate_hotelCheckInAndNilEndTime() throws {
        let form = makeForm(type: .hotel, hotelCheckInTime: "15:00", hotelCheckOutDate: "2026-09-05")
        let body = try encode(CreateItineraryNodeRequest(from: form))

        XCTAssertEqual(body["startTime"] as? String, "15:00")
        XCTAssertNil(body["endTime"])
        let details = body["details"] as? [String: Any]
        XCTAssertEqual(details?["checkOutDate"] as? String, "2026-09-05")
    }

    func testCreate_hotelEmptyDetailsMissing() throws {
        // 无离店日等任何扩展 → details 不传。
        let form = makeForm(type: .hotel)
        XCTAssertNil(try encode(CreateItineraryNodeRequest(from: form))["details"])
    }

    func testCreate_savedPlaceIdForbidsAddressAndLocation() throws {
        let form = makeForm(locationName: "不该出现", savedPlaceId: "saved-1")
        let body = try encode(CreateItineraryNodeRequest(from: form))

        XCTAssertEqual(body["savedPlaceId"] as? String, "saved-1")
        XCTAssertNil(body["address"])
        XCTAssertNil(body["location"])
    }

    func testCreate_emptyNoteBecomesNil() throws {
        let form = makeForm(note: "   ")
        XCTAssertNil(try encode(CreateItineraryNodeRequest(from: form))["note"])
    }

    func testCreate_attractionNoDetailsKey() throws {
        let form = makeForm(type: .attraction)
        XCTAssertNil(try encode(CreateItineraryNodeRequest(from: form))["details"])
    }

    // MARK: - UpdateItineraryNodeRequest

    func testUpdate_noteAlwaysSentEmptyStringClears() throws {
        let form = makeForm(note: "   ")
        let body = try encode(UpdateItineraryNodeRequest(from: form))

        // 全量表单始终发 note；空串 = 清空。
        XCTAssertTrue(body.keys.contains("note"))
        XCTAssertEqual(body["note"] as? String, "")
    }

    func testUpdate_hotelEndTimeSentAsEmptyString() throws {
        let form = makeForm(type: .hotel, endTime: "任何旧值")
        let body = try encode(UpdateItineraryNodeRequest(from: form))

        // 显式清空 endTime 避免旧值残留。
        XCTAssertEqual(body["endTime"] as? String, "")
    }

    func testUpdate_locationClearingUsesEmptyForClearing() throws {
        // selectedLocation == nil 且 locationName 为空 → location = emptyForClearing（key 存在，name/provider null）。
        let form = makeForm(locationName: "", selectedLocation: nil)
        let body = try encode(UpdateItineraryNodeRequest(from: form))

        XCTAssertTrue(body.keys.contains("location"))
        let location = body["location"] as? [String: Any]
        XCTAssertNotNil(location)
        XCTAssertNil(location?["name"])
        XCTAssertNil(location?["provider"])
        XCTAssertNil(body["address"])
    }

    func testUpdate_fullFormNoDetailsEncodesEmptyObject() throws {
        // 结构字段有提交意图且 details 为空 → 编码 {} 以清空。
        let form = makeForm(type: .attraction, locationName: "某地")
        let body = try encode(UpdateItineraryNodeRequest(from: form))

        XCTAssertTrue(body.keys.contains("details"))
        let details = body["details"] as? [String: Any]
        XCTAssertEqual(details?.count, 0)
    }

    func testUpdate_transportDetailsEncoded() throws {
        let form = makeForm(type: .transport, transportMode: .flight, flightNo: "JL001",
                            departureName: "HND", arrivalName: "KIX", seatInfo: "12A")
        let details = (try encode(UpdateItineraryNodeRequest(from: form)))["details"] as? [String: Any]
        XCTAssertEqual(details?["mode"] as? String, "flight")
        XCTAssertEqual(details?["flightNo"] as? String, "JL001")
        XCTAssertEqual(details?["departureName"] as? String, "HND")
    }

    // MARK: - noteOnly

    func testNoteOnly_bodyOnlyHasNoteKeyAmongOptionalFields() throws {
        let request = UpdateItineraryNodeRequest.noteOnly(note: " 只看这个 ")
        let body = try encode(request)

        XCTAssertEqual(body["note"] as? String, "只看这个")
        XCTAssertNil(body["title"])
        XCTAssertNil(body["type"])
        XCTAssertNil(body["startTime"])
        XCTAssertNil(body["endTime"])
        XCTAssertNil(body["address"])
        XCTAssertNil(body["location"])
    }

    func testNoteOnly_emptyNoteSendsEmptyString() throws {
        let body = try encode(UpdateItineraryNodeRequest.noteOnly(note: "  "))
        XCTAssertEqual(body["note"] as? String, "")
    }

    func testNoteOnly_allNilMemberwiseDoesNotEncodeDetails() throws {
        // 全 nil → hasStructuralIntent == false → details 不编码（无 {}）。
        let request = UpdateItineraryNodeRequest(
            title: nil, type: nil, startTime: nil, endTime: nil,
            address: nil, location: nil, note: "", details: nil
        )
        let body = try encode(request)
        XCTAssertFalse(body.keys.contains("details"))
    }

    // MARK: - 解码兼容

    func testNodeTypeDecode_cafeToRestaurantPhotoToOther() throws {
        let cafe = try JSONDecoder().decode(ItineraryNodeType.self, from: Data("\"cafe\"".utf8))
        XCTAssertEqual(cafe, .restaurant)
        let photo = try JSONDecoder().decode(ItineraryNodeType.self, from: Data("\"photo\"".utf8))
        XCTAssertEqual(photo, .other)
        let unknown = try JSONDecoder().decode(ItineraryNodeType.self, from: Data("\"nope\"".utf8))
        XCTAssertEqual(unknown, .other)
    }
}

private struct AnyEncodable: Encodable {
    private let encodable: Encodable
    init(_ encodable: Encodable) { self.encodable = encodable }
    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}
