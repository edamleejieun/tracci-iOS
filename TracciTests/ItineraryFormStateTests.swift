import Foundation
import XCTest
@testable import Tracci

/// Phase 0 表征：`ItineraryNodeFormState` 构造 / 回填 / location mutation。
/// 纯模型，无网络。
@MainActor
final class ItineraryFormStateTests: XCTestCase {

    // MARK: - .create 默认值

    func testCreateDefaults() {
        let form = ItineraryNodeFormState.create(defaultDayIndex: 3)
        XCTAssertEqual(form.dayIndex, 3)
        XCTAssertEqual(form.title, "")
        XCTAssertEqual(form.type, .other)
        XCTAssertEqual(form.locationName, "")
        XCTAssertNil(form.selectedLocation)
        XCTAssertEqual(form.startTime, "")
        XCTAssertEqual(form.endTime, "")
        XCTAssertEqual(form.note, "")
        XCTAssertNil(form.transportMode)
        XCTAssertEqual(form.flightNo, "")
        XCTAssertEqual(form.hotelCheckInTime, "")
        XCTAssertNil(form.savedPlaceId)
    }

    // MARK: - .from(node:) 回填

    func testFrom_hotelCheckInTimePrefersDetailsThenNodeStartTime() {
        // details.checkInTime 优先
        let withDetails = ItineraryFixtures.makeNodeItem(
            type: "hotel",
            startTime: "08:00",
            detailsJSON: #"{"checkInTime":"14:00","checkOutTime":"11:00"}"#
        )
        let fromDetails = ItineraryNodeFormState.from(node: withDetails)
        XCTAssertEqual(fromDetails.hotelCheckInTime, "14:00")
        XCTAssertEqual(fromDetails.hotelCheckOutTime, "11:00")
        // 酒店 endTime 强制空
        XCTAssertEqual(fromDetails.endTime, "")

        // 无 details → 回落节点 startTime
        let noDetails = ItineraryFixtures.makeNodeItem(type: "hotel", startTime: "13:00")
        let fallback = ItineraryNodeFormState.from(node: noDetails)
        XCTAssertEqual(fallback.hotelCheckInTime, "13:00")
    }

    func testFrom_transportDefaultsModeToFlight() {
        let node = ItineraryFixtures.makeNodeItem(type: "transport")
        let form = ItineraryNodeFormState.from(node: node)
        XCTAssertEqual(form.transportMode, .flight)
    }

    func testFrom_transportPreservesExistingMode() {
        let node = ItineraryFixtures.makeNodeItem(type: "transport", detailsJSON: #"{"mode":"hsr"}"#)
        let form = ItineraryNodeFormState.from(node: node)
        XCTAssertEqual(form.transportMode, .hsr)
    }

    func testFrom_savedPlaceIdRestoredAsNil() {
        // DTO 不含 savedPlaceId；回填后亦为 nil。
        let node = ItineraryFixtures.makeNodeItem(id: "node-1", title: "某地")
        let form = ItineraryNodeFormState.from(node: node)
        XCTAssertNil(form.savedPlaceId)
        XCTAssertEqual(form.title, "某地")
        XCTAssertEqual(form.dayIndex, 1)
    }

    // MARK: - location mutation 方法

    func testUseSelectedLocation_clearsSavedPlaceId() {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.savedPlaceId = "saved-1"
        let location = ItineraryLocation(name: "选中地")
        form.useSelectedLocation(location, fallbackName: "兜底")
        XCTAssertNil(form.savedPlaceId)
        XCTAssertNotNil(form.selectedLocation)
        XCTAssertEqual(form.locationName, "选中地")
    }

    func testUseManualLocation_clearsSavedPlaceIdAndSelectedLocation() {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.savedPlaceId = "saved-1"
        form.useManualLocation("手写")
        XCTAssertNil(form.savedPlaceId)
        XCTAssertNil(form.selectedLocation)
        XCTAssertEqual(form.locationName, "手写")
    }

    func testUpdateLocationText_clearsSavedPlaceIdAndSelectedLocation() {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.savedPlaceId = "saved-1"
        form.selectedLocation = ItineraryLocation(name: "旧值")
        form.updateLocationText("新文本")
        XCTAssertNil(form.savedPlaceId)
        XCTAssertNil(form.selectedLocation)
        XCTAssertEqual(form.locationName, "新文本")
    }

    func testCreateViewModelInheritsDayAndProgressesFromPlaceFirst() {
        let model = ItineraryNodeCreateViewModel(defaultDayIndex: 3)
        XCTAssertEqual(model.form.dayIndex, 3)
        XCTAssertFalse(model.hasLocation)
        XCTAssertFalse(model.isDirty)

        model.useManualLocation("南锣鼓巷")

        XCTAssertTrue(model.hasLocation)
        XCTAssertTrue(model.isDirty)
        XCTAssertEqual(model.form.locationName, "南锣鼓巷")
        XCTAssertEqual(model.form.type, .other)
    }

    func testCreateViewModelSavedPlacePreservesIdentityAndSuggestsType() {
        let model = ItineraryNodeCreateViewModel(defaultDayIndex: 2)
        let savedPlace = ItineraryFixtures.savedPlace(
            id: "saved-hotel",
            name: "溪畔酒店",
            category: .hotel
        )

        model.selectSavedPlace(savedPlace)

        XCTAssertEqual(model.form.dayIndex, 2)
        XCTAssertEqual(model.form.savedPlaceId, "saved-hotel")
        XCTAssertEqual(model.form.locationName, "溪畔酒店")
        XCTAssertEqual(model.form.selectedLocation?.address, "溪畔酒店地址")
        XCTAssertEqual(model.form.type, .hotel)
    }

    func testDisplayAddressPrefersLocationSnapshotOverTopLevelAddress() {
        let fromLocation = ItineraryFixtures.makeNodeItem(
            title: "",
            address: nil,
            locationJSON: #"{"name":"山东博物馆","address":"济南市历下区经十一路118号"}"#
        )
        XCTAssertEqual(fromLocation.displayAddress, "济南市历下区经十一路118号")
        XCTAssertEqual(fromLocation.displayTitle, "山东博物馆")

        let fromNode = ItineraryFixtures.makeNodeItem(
            address: "顶层地址",
            locationJSON: #"{"name":"趵突泉"}"#
        )
        XCTAssertEqual(fromNode.displayAddress, "顶层地址")

        let locationWins = ItineraryFixtures.makeNodeItem(
            address: "旧顶层地址",
            locationJSON: #"{"name":"趵突泉","address":"趵突泉南路1号"}"#
        )
        XCTAssertEqual(locationWins.displayAddress, "趵突泉南路1号")
    }

    func testCreateViewModelTypeChangeKeepsAdvancedCapabilitiesReachable() {
        let model = ItineraryNodeCreateViewModel(defaultDayIndex: 1)
        model.useManualLocation("首都机场")

        model.changeType(.transport)
        XCTAssertEqual(model.form.transportMode, .flight)
        XCTAssertEqual(model.form.title, "")

        model.changeType(.hotel)
        XCTAssertEqual(model.form.endTime, "")
    }

    // MARK: - Phase 4 time picker behavior

    func testApplyingStartTimeRestoresAutomaticOneHourEndTime() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        let start = try XCTUnwrap(ItineraryTimeFormatting.date(fromTime: "09:30"))

        form.applyTime(start, for: .start)

        XCTAssertEqual(form.startTime, "09:30")
        XCTAssertEqual(form.endTime, "10:30")
    }

    func testApplyingStartTimePreservesValidLaterEndTime() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.endTime = "12:00"
        let start = try XCTUnwrap(ItineraryTimeFormatting.date(fromTime: "09:30"))

        form.applyTime(start, for: .start)

        XCTAssertEqual(form.startTime, "09:30")
        XCTAssertEqual(form.endTime, "12:00")
    }

    func testApplyingStartTimeRepairsEarlierEndTime() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.endTime = "08:00"
        let start = try XCTUnwrap(ItineraryTimeFormatting.date(fromTime: "09:30"))

        form.applyTime(start, for: .start)

        XCTAssertEqual(form.endTime, "10:30")
    }

    func testApplyingStartTimeFromLivePickerDatePreservesLaterEndTime() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.endTime = "18:00"

        form.applyTime(try livePickerDate(hour: 9, minute: 30), for: .start)

        XCTAssertEqual(form.startTime, "09:30")
        XCTAssertEqual(form.endTime, "18:00")
    }

    func testApplyingStartTimeFromLivePickerDateRepairsEarlierEndTime() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.endTime = "08:00"

        form.applyTime(try livePickerDate(hour: 9, minute: 30), for: .start)

        XCTAssertEqual(form.startTime, "09:30")
        XCTAssertEqual(form.endTime, "10:30")
    }

    func testHotelPickerKeepsTimelineAndDetailTimeSemantics() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.endTime = "18:00"
        let checkIn = try XCTUnwrap(ItineraryTimeFormatting.date(fromTime: "14:00"))
        let checkOut = try XCTUnwrap(ItineraryTimeFormatting.date(fromTime: "11:00"))

        form.applyTime(checkIn, for: .hotelCheckIn)
        form.applyTime(checkOut, for: .hotelCheckOut)

        XCTAssertEqual(form.hotelCheckInTime, "14:00")
        XCTAssertEqual(form.startTime, "14:00")
        XCTAssertEqual(form.hotelCheckOutTime, "11:00")
        XCTAssertEqual(form.endTime, "")
    }

    func testEndPickerDefaultsToOneHourAfterExistingStart() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.startTime = "09:30"
        let fallbackNow = try XCTUnwrap(ItineraryTimeFormatting.date(fromTime: "16:00"))

        let initialEnd = form.initialTimeDate(for: .end, now: fallbackNow)

        XCTAssertEqual(ItineraryTimeFormatting.apiTime(from: initialEnd), "10:30")
    }

    private func livePickerDate(hour: Int, minute: Int) throws -> Date {
        var components = TracciDateContext.calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try XCTUnwrap(TracciDateContext.calendar.date(from: components))
    }
}
