import Foundation
import Observation
import CoreLocation
import os
#if canImport(WeatherKit) && TRACCI_ENABLE_WEATHERKIT
import WeatherKit
#endif

enum TripWeatherCardState: Equatable {
    case idle
    case loading
    case available(TripWeatherDisplay)
    case unavailable(title: String, message: String, systemImage: String)
    case failed(message: String)
}

struct TripWeatherDisplay: Equatable {
    let locationName: String
    let dateRange: String?
    let summary: String
    let tempRange: String?
    let tip: String?
    let updatedAt: String?
    let items: [TripWeatherDisplayItem]
    let appleAttribution: AppleWeatherAttribution?
}

struct AppleWeatherAttribution: Equatable {
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
    let legalPageURL: URL
}

struct TripWeatherDisplayItem: Identifiable, Equatable {
    var id: String { date }

    let date: String
    let weekday: String?
    let weather: String
    let tempMin: Double?
    let tempMax: Double?
    let icon: String
    let pop: Double?
    let tip: String?

    var sfSymbolName: String {
        switch icon {
        case "sunny": "sun.max.fill"
        case "cloudy": "cloud.fill"
        case "overcast": "smoke.fill"
        case "thunderstorm": "cloud.bolt.rain.fill"
        case "light_rain": "cloud.drizzle.fill"
        case "moderate_rain", "heavy_rain": "cloud.rain.fill"
        case "snow": "cloud.snow.fill"
        case "fog": "cloud.fog.fill"
        default: "cloud.sun.fill"
        }
    }

    var compactTemperatureText: String? {
        switch (tempMin, tempMax) {
        case let (min?, max?):
            "\(Int(min.rounded()))° / \(Int(max.rounded()))°"
        case let (min?, nil):
            "\(Int(min.rounded()))°"
        case let (nil, max?):
            "\(Int(max.rounded()))°"
        default:
            nil
        }
    }
}

struct TripDayExecutionSnapshot: Equatable {
    static let refreshInterval: Duration = .seconds(30)

    enum Focus: Equatable {
        case next
        case current
        case finished
    }

    let focus: Focus
    let currentNode: ItineraryNodeItem?
    let focusNode: ItineraryNodeItem?
    let followingNodes: [ItineraryNodeItem]
    let minutesUntilFocus: Int?
    let focusDurationMinutes: Int?

    static func make(nodes: [ItineraryNodeItem], now: Date) -> TripDayExecutionSnapshot? {
        guard let nowMinutes = ItineraryTimeFormatting.minutes(from: now) else { return nil }

        let timedNodes = nodes.compactMap { node -> TimedNode? in
            guard let start = ItineraryTimeFormatting.minutes(from: node.startTime) else { return nil }
            return TimedNode(
                node: node,
                start: start,
                end: ItineraryTimeFormatting.minutes(from: node.endTime)
            )
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let lhsOrder = lhs.node.sortOrder ?? .max
            let rhsOrder = rhs.node.sortOrder ?? .max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.node.id < rhs.node.id
        }

        guard !timedNodes.isEmpty else { return nil }

        let current = timedNodes.enumerated().reversed().first { index, timedNode in
            guard timedNode.start <= nowMinutes else { return false }
            let nextStart = timedNodes.indices.contains(index + 1) ? timedNodes[index + 1].start : nil
            let effectiveEnd = timedNode.end ?? nextStart ?? (24 * 60 - 1)
            return nowMinutes <= effectiveEnd
        }?.element

        let next = timedNodes.first { $0.start > nowMinutes }

        if let next {
            let following = timedNodes
                .drop { $0.node.id != next.node.id }
                .dropFirst()
                .prefix(2)
                .map(\.node)
            return TripDayExecutionSnapshot(
                focus: .next,
                currentNode: current?.node,
                focusNode: next.node,
                followingNodes: following,
                minutesUntilFocus: max(next.start - nowMinutes, 0),
                focusDurationMinutes: duration(of: next)
            )
        }

        if let current {
            return TripDayExecutionSnapshot(
                focus: .current,
                currentNode: current.node,
                focusNode: current.node,
                followingNodes: [],
                minutesUntilFocus: nil,
                focusDurationMinutes: duration(of: current)
            )
        }

        return TripDayExecutionSnapshot(
            focus: .finished,
            currentNode: nil,
            focusNode: nil,
            followingNodes: [],
            minutesUntilFocus: nil,
            focusDurationMinutes: nil
        )
    }

    private struct TimedNode {
        let node: ItineraryNodeItem
        let start: Int
        let end: Int?
    }

    private static func duration(of timedNode: TimedNode) -> Int? {
        guard let end = timedNode.end, end >= timedNode.start else { return nil }
        return end - timedNode.start
    }
}

@MainActor
@Observable
final class TripDetailViewModel {
    private(set) var trip: Trip
    private(set) var isLoadingDetail = false
    private(set) var weatherState: TripWeatherCardState = .idle
    private(set) var errorMessage: String?
    var selectedTab: TripDetailTab = .itinerary

    // Collaboration
    private(set) var currentUserAccess: TripAccessContext?
    private(set) var members: [TripMemberResp] = []
    private(set) var invitationErrorMessage: String?

    /// Live trip vs read-only Demo Bundle. Never pass Demo IDs to live services.
    /// Mutable only for Demo scene switching within the same Bundle.
    private(set) var journeyContext: JourneyContext

    let itineraryViewModel: ItineraryViewModel
    let journalViewModel: JournalViewModel
    let expenseViewModel: ExpenseViewModel
    let insightViewModel: TripInsightViewModel

    private let tripService: TripService
    private let collaborationService: CollaborationService
    private var didBootstrapDemo = false
    private let logger = Logger(subsystem: "com.tracci.app", category: "TripDetail")

    var isDemo: Bool { journeyContext.isDemo }

    /// Current Demo scene kind when in Demo context.
    var demoSceneKind: DemoJourneySceneKind? {
        journeyContext.demoSceneKind
    }

    /// Demo scene members (empty for live trips).
    private(set) var demoMembers: [TripMemberResp] = []
    /// Demo AA settlement (nil for live trips).
    private(set) var demoSettlement: ExpenseSettlement?

    /// Whether Demo settlement has something worth opening (total, balances, or transfers).
    var demoSettlementHasContent: Bool {
        guard let settlement = demoSettlement else { return false }
        if !settlement.suggestedTransfers.isEmpty { return true }
        if settlement.totalGroupAmountDecimal > 0 { return true }
        return settlement.members.contains { !$0.isZeroBalance }
    }
    /// Demo activity logs (empty for live trips).
    private(set) var demoActivityLogs: [ActivityLogResp] = []
    /// Demo trip summary for memory-style read surfaces (nil for live trips).
    private(set) var demoSummary: TripSummaryResponse?
    /// Demo export assets for optional local preview only (nil for live trips).
    private(set) var demoExportAssets: ExportAssetsResponse?
    private(set) var demoItineraryExportAssets: ItineraryExportAssetsResponse?

    /// Wall-clock used for ongoing execution strip. Demo uses Bundle `referenceDate` noon.
    var demoReferenceNow: Date? {
        guard isDemo, let raw = journeyContext.demoBundle?.referenceDate else { return nil }
        guard let day = TripDateFormatting.date(from: raw) else { return nil }
        return TracciDateContext.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    init(
        trip: Trip,
        tripService: TripService,
        itineraryService: ItineraryService,
        savedPlaceService: SavedPlaceService? = nil,
        journalService: JournalService,
        expenseService: ExpenseService,
        collaborationService: CollaborationService,
        routeProvider: any TripRouteProviding,
        initialTab: TripDetailTab = .itinerary,
        journeyContext: JourneyContext? = nil
    ) {
        self.trip = trip
        self.tripService = tripService
        self.collaborationService = collaborationService
        self.currentUserAccess = trip.access
        self.selectedTab = initialTab
        self.journeyContext = journeyContext ?? .live(tripID: trip.id)
        self.itineraryViewModel = ItineraryViewModel(
            tripId: trip.id,
            trip: trip,
            itineraryService: itineraryService,
            savedPlaceService: savedPlaceService,
            routeProvider: routeProvider
        )
        self.journalViewModel = JournalViewModel(
            tripId: trip.id,
            tripStartDate: trip.startDate,
            tripEndDate: trip.endDate,
            tripDestination: trip.destination,
            journalService: journalService
        )
        self.expenseViewModel = ExpenseViewModel(
            tripId: trip.id,
            tripStartDate: trip.startDate,
            tripEndDate: trip.endDate,
            baseCurrency: trip.baseCurrency ?? "CNY",
            expenseService: expenseService,
            collaborationService: collaborationService
        )
        self.insightViewModel = TripInsightViewModel(
            tripId: trip.id,
            tripService: tripService
        )
    }

    func loadTripDetail() async {
        if isDemo {
            await bootstrapDemoIfNeeded()
            return
        }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let detail = try await tripService.tripDetail(id: trip.id)
            trip = detail
            if let detailAccess = detail.access {
                currentUserAccess = detailAccess
            }
            itineraryViewModel.updateTrip(detail)
            journalViewModel.updateTripDates(startDate: detail.startDate, endDate: detail.endDate)
            journalViewModel.updateTripDestination(detail.destination)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadWeather() async {
        if isDemo {
            await bootstrapDemoIfNeeded()
            return
        }

        weatherState = .loading

        do {
            let response = try await tripService.tripWeather(id: trip.id)
            await applyWeather(response)
        } catch {
            weatherState = .failed(message: "暂时无法获取天气")
        }
    }

    func refreshAll() async {
        if isDemo {
            await bootstrapDemoIfNeeded(force: true)
            return
        }

        async let detailTask: Void = loadTripDetail()
        async let itineraryTask: Void = itineraryViewModel.refresh()
        async let journalTask: Void = journalViewModel.refresh()
        async let expenseTask: Void = expenseViewModel.refresh()
        async let weatherTask: Void = loadWeather()
        async let insightTask: Void = insightViewModel.refresh()
        _ = await (detailTask, itineraryTask, journalTask, expenseTask, weatherTask, insightTask)
    }

    func loadMembers() async {
        if isDemo {
            await bootstrapDemoIfNeeded()
            members = demoMembers
            return
        }
        do {
            members = try await collaborationService.listMembers(tripId: trip.id)
        } catch {
            // Group expenses and share surfaces treat members as supplementary data.
        }
    }

    func createInvitationForSharing() async -> TripInvitationResp? {
        guard !isDemo, DemoMutationGuard.allows(.invite, in: journeyContext) else {
            invitationErrorMessage = DemoReadOnlyCopy.inviteUnavailable
            return nil
        }
        invitationErrorMessage = nil
        do {
            return try await collaborationService.createInvitation(
                tripId: trip.id,
                request: CreateInvitationRequest(
                    roleToGrant: "editor",
                    expiresInHours: 72,
                    maxUses: nil
                )
            )
        } catch {
            invitationErrorMessage = "邀请生成失败，请重试"
            return nil
        }
    }

    /// Applies the active Demo scene into child ViewModels. Safe to call repeatedly.
    func bootstrapDemoIfNeeded(force: Bool = false) async {
        guard isDemo else { return }
        if didBootstrapDemo, !force { return }
        guard let scene = journeyContext.demoScene else {
            errorMessage = "示例旅程暂不可用"
            return
        }

        trip = scene.trip
        currentUserAccess = scene.trip.access
        demoMembers = scene.members
        members = scene.members
        demoSettlement = scene.expenseSettlement
        demoActivityLogs = scene.activityLogs.list
        demoSummary = scene.summary
        demoExportAssets = scene.exportAssets
        demoItineraryExportAssets = scene.itineraryExportAssets

        itineraryViewModel.updateTrip(scene.trip)
        itineraryViewModel.applyDemoPayload(
            scene.itinerary,
            preferredDayIndex: preferredDemoDayIndex(for: scene.trip)
        )
        journalViewModel.updateTripDates(startDate: scene.trip.startDate, endDate: scene.trip.endDate)
        journalViewModel.updateTripDestination(scene.trip.destination)
        journalViewModel.applyDemoEntries(scene.journals.list)
        expenseViewModel.applyDemo(
            expenses: scene.expenses.list,
            summary: scene.expenseSummary,
            settlement: scene.expenseSettlement
        )
        expenseViewModel.applyDemoMembers(scene.members)
        insightViewModel.applyDemoOverview(scene.stageOverview)
        await applyWeather(scene.weather)
        errorMessage = nil
        isLoadingDetail = false
        didBootstrapDemo = true
    }

    /// Switches among PLANNING / ONGOING / COMPLETED scenes of the same Bundle (Demo only).
    @discardableResult
    func switchDemoScene(to kind: DemoJourneySceneKind) async -> Bool {
        guard case let .demo(bundle, current) = journeyContext else { return false }
        guard current != kind else { return true }
        guard bundle.scene(kind) != nil else { return false }

        journeyContext = .demo(bundle: bundle, scene: kind)
        didBootstrapDemo = false
        await bootstrapDemoIfNeeded(force: true)
        return true
    }

    func updateTrip(_ updatedTrip: Trip) {
        guard !isDemo else {
            logger.warning("updateTrip dropped: journeyContext is demo but caller is live path")
            return
        }
        trip = updatedTrip
        if let access = updatedTrip.access {
            currentUserAccess = access
        }
        itineraryViewModel.updateTrip(updatedTrip)
        journalViewModel.updateTripDates(startDate: updatedTrip.startDate, endDate: updatedTrip.endDate)
        journalViewModel.updateTripDestination(updatedTrip.destination)
        errorMessage = nil
    }

    /// 所有权转让等场景：立即替换服务端授权快照（不必等整页刷新）。
    func applyAccess(_ access: TripAccessContext) {
        guard !isDemo else {
            logger.warning("applyAccess dropped: journeyContext is demo but caller is live path")
            return
        }
        currentUserAccess = access
    }

    func executionSnapshot(for dayIndex: Int, now: Date = Date()) -> TripDayExecutionSnapshot? {
        let clock = isDemo ? (demoReferenceNow ?? now) : now
        guard TracciDateContext.tripStatus(
            startDate: trip.startDate,
            endDate: trip.endDate,
            now: clock
        ) == .ongoing,
        let startDate = TripDateFormatting.date(from: trip.startDate),
        TracciDateContext.dayIndex(for: clock, startDate: startDate) == dayIndex,
        let day = itineraryViewModel.groupedNodes.first(where: { $0.dayIndex == dayIndex })
        else { return nil }

        return TripDayExecutionSnapshot.make(nodes: day.nodes, now: clock)
    }

    /// Day index aligned to Demo `referenceDate` within the trip window.
    private func preferredDemoDayIndex(for trip: Trip) -> Int? {
        guard let referenceNow = demoReferenceNow,
              let startDate = TripDateFormatting.date(from: trip.startDate)
        else { return nil }
        return TracciDateContext.dayIndex(for: referenceNow, startDate: startDate)
    }

    private func applyWeather(_ response: TripWeatherResponse) async {
        if response.available, !response.items.isEmpty {
            weatherState = .available(Self.display(from: response, fallbackTrip: trip))
            return
        }

        if response.status == "CLIENT_REQUIRED", response.source == "APPLE_CLIENT" {
            await loadAppleWeather(from: response)
            return
        }

        weatherState = .unavailable(
            title: Self.unavailableTitle(for: response.status),
            message: response.message ?? "临近出行时将为你更新天气。",
            systemImage: Self.unavailableIcon(for: response.status)
        )
    }

    private func loadAppleWeather(from response: TripWeatherResponse) async {
        guard
            let latitude = response.location?.latitude,
            let longitude = response.location?.longitude
        else {
            weatherState = .unavailable(
                title: "暂无目的地天气",
                message: "目的地缺少经纬度，暂时无法查询 WeatherKit。",
                systemImage: "mappin.slash"
            )
            return
        }

        #if canImport(WeatherKit) && TRACCI_ENABLE_WEATHERKIT
        do {
            let service = WeatherService.shared
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let startDate = Self.weatherStartDate(for: trip)
            let endDate = Self.weatherEndDate(startDate: startDate, trip: trip)

            async let forecastTask = service.weather(
                for: location,
                including: .daily(startDate: startDate, endDate: endDate)
            )
            async let attributionTask = service.attribution
            let (forecast, attribution) = try await (forecastTask, attributionTask)
            let items = forecast.forecast.prefix(5).map(Self.displayItem(from:))

            guard !items.isEmpty else {
                weatherState = .unavailable(
                    title: "暂无目的地天气",
                    message: "临近出行时将为你更新天气。",
                    systemImage: "clock"
                )
                return
            }

            weatherState = .available(
                TripWeatherDisplay(
                    locationName: response.locationName ?? response.location?.city ?? trip.destinationName ?? "目的地",
                    dateRange: Self.displayDateRange(from: items),
                    summary: items.first?.weather ?? "天气预报",
                    tempRange: Self.tempRange(min: items.first?.tempMin, max: items.first?.tempMax),
                    tip: Self.appleWeatherTip(for: items.first),
                    updatedAt: response.updatedAt,
                    items: items,
                    appleAttribution: AppleWeatherAttribution(
                        combinedMarkLightURL: attribution.combinedMarkLightURL,
                        combinedMarkDarkURL: attribution.combinedMarkDarkURL,
                        legalPageURL: attribution.legalPageURL
                    )
                )
            )
        } catch {
            weatherState = .failed(message: "暂时无法获取天气")
        }
        #else
        weatherState = .unavailable(
            title: "天气暂未启用",
            message: "当前构建暂未启用 WeatherKit，开通 Apple Developer Program 后即可恢复。",
            systemImage: "cloud"
        )
        #endif
    }

    private static func display(from response: TripWeatherResponse, fallbackTrip trip: Trip) -> TripWeatherDisplay {
        let items = response.items.prefix(response.forecastLimitDays ?? 5).map {
            TripWeatherDisplayItem(
                date: $0.date,
                weekday: $0.weekday,
                weather: $0.weather,
                tempMin: $0.tempMin,
                tempMax: $0.tempMax,
                icon: $0.icon ?? "unknown",
                pop: Self.normalizedPop($0.pop),
                tip: $0.tip
            )
        }

        return TripWeatherDisplay(
            locationName: response.locationName ?? trip.destinationName ?? "目的地",
            dateRange: displayDateRange(from: Array(items)),
            summary: items.first?.weather ?? "天气预报",
            tempRange: tempRange(min: items.first?.tempMin, max: items.first?.tempMax),
            tip: items.first?.tip,
            updatedAt: response.updatedAt,
            items: Array(items),
            appleAttribution: nil
        )
    }

    private static func unavailableTitle(for status: String) -> String {
        switch status {
        case "DATE_TOO_FAR": "距离出发还有一段时间"
        case "PAST_TRIP_NOT_SUPPORTED": "历史天气暂不可查看"
        case "LOCATION_MISSING": "暂无目的地天气"
        case "PROVIDER_DISABLED": "天气服务当前不可用"
        default: "暂时无法获取天气"
        }
    }

    private static func unavailableIcon(for status: String) -> String {
        switch status {
        case "DATE_TOO_FAR": "clock"
        case "PAST_TRIP_NOT_SUPPORTED": "calendar"
        case "LOCATION_MISSING": "mappin.slash"
        default: "cloud"
        }
    }

    private static func weatherStartDate(for trip: Trip) -> Date {
        let today = TracciDateContext.today()
        guard let tripStart = TripDateFormatting.date(from: trip.startDate) else {
            return today
        }
        return max(today, tripStart)
    }

    private static func weatherEndDate(startDate: Date, trip: Trip) -> Date {
        let calendar = TracciDateContext.calendar
        let fiveDaysLater = calendar.date(byAdding: .day, value: 5, to: startDate) ?? startDate
        guard let tripEnd = TripDateFormatting.date(from: trip.endDate) else {
            return fiveDaysLater
        }
        return min(fiveDaysLater, calendar.date(byAdding: .day, value: 1, to: tripEnd) ?? fiveDaysLater)
    }

    private static func displayDateRange(from items: [TripWeatherDisplayItem]) -> String? {
        guard let first = items.first?.date else { return nil }
        guard let last = items.last?.date, last != first else {
            return ItineraryTimeFormatting.displayDate(first)
        }
        return "\(ItineraryTimeFormatting.displayDate(first)) - \(ItineraryTimeFormatting.displayDate(last))"
    }

    private static func tempRange(min: Double?, max: Double?) -> String? {
        switch (min, max) {
        case let (min?, max?):
            return "\(Int(round(max)))° / \(Int(round(min)))°"
        case let (_, max?):
            return "\(Int(round(max)))°"
        case let (min?, _):
            return "\(Int(round(min)))°"
        default:
            return nil
        }
    }

    private static func appleWeatherTip(for item: TripWeatherDisplayItem?) -> String? {
        guard let item else { return nil }
        if let pop = item.pop, pop >= 0.5 {
            return "可能有降水，出门前记得带伞。"
        }
        return "天气信息已更新，适合安排当天行程。"
    }

    #if canImport(WeatherKit) && TRACCI_ENABLE_WEATHERKIT
    private static func displayItem(from day: DayWeather) -> TripWeatherDisplayItem {
        let dateString = TripDateFormatting.apiString(from: day.date)
        return TripWeatherDisplayItem(
            date: dateString,
            weekday: ItineraryTimeFormatting.weekday(dateString),
            weather: localizedWeatherText(conditionDescription: day.condition.description, symbolName: day.symbolName),
            tempMin: day.lowTemperature.converted(to: .celsius).value,
            tempMax: day.highTemperature.converted(to: .celsius).value,
            icon: weatherIconCode(from: day.symbolName),
            pop: day.precipitationChance,
            tip: nil
        )
    }
    #endif

    private static func weatherIconCode(from symbolName: String) -> String {
        if symbolName.contains("bolt") || symbolName.contains("thunderstorm") { return "thunderstorm" }
        if symbolName.contains("sun") { return "sunny" }
        if symbolName.contains("rain") || symbolName.contains("drizzle") { return "light_rain" }
        if symbolName.contains("snow") { return "snow" }
        if symbolName.contains("fog") { return "fog" }
        if symbolName.contains("cloud") { return "cloudy" }
        return "unknown"
    }

    private static func localizedWeatherText(conditionDescription: String, symbolName: String) -> String {
        let normalized = conditionDescription
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch normalized {
        case "clear":
            return "晴"
        case "mostlyclear":
            return "大部晴朗"
        case "partlycloudy":
            return "局部多云"
        case "mostlycloudy":
            return "大部多云"
        case "cloudy":
            return "多云"
        case "haze":
            return "霾"
        case "smoky":
            return "烟雾"
        case "foggy":
            return "雾"
        case "breezy":
            return "微风"
        case "windy":
            return "有风"
        case "drizzle":
            return "毛毛雨"
        case "rain":
            return "雨"
        case "heavyrain":
            return "大雨"
        case "sunshowers":
            return "太阳雨"
        case "isolatedthunderstorms", "scatteredthunderstorms", "strongstorms", "thunderstorm", "thunderstorms":
            return "雷暴"
        case "flurries":
            return "小雪"
        case "snow":
            return "雪"
        case "heavysnow":
            return "大雪"
        case "sunflurries":
            return "晴间小雪"
        case "sleet":
            return "雨夹雪"
        case "wintrymix":
            return "雨雪混合"
        case "blizzard":
            return "暴雪"
        case "blowingsnow":
            return "风雪"
        case "freezingdrizzle":
            return "冻毛毛雨"
        case "freezingrain":
            return "冻雨"
        case "hail":
            return "冰雹"
        case "hot":
            return "炎热"
        case "frigid":
            return "严寒"
        case "hurricane":
            return "飓风"
        case "tropicalstorm":
            return "热带风暴"
        default:
            return localizedWeatherText(symbolName: symbolName)
        }
    }

    private static func localizedWeatherText(symbolName: String) -> String {
        if symbolName.contains("bolt") || symbolName.contains("thunderstorm") { return "雷暴" }
        if symbolName.contains("drizzle") { return "毛毛雨" }
        if symbolName.contains("rain") { return "雨" }
        if symbolName.contains("snow") { return "雪" }
        if symbolName.contains("fog") { return "雾" }
        if symbolName.contains("cloud") { return "多云" }
        if symbolName.contains("sun") { return "晴" }
        return "天气预报"
    }

    /// Normalize precipitation probability to 0–1 range.
    /// Backend may return 0–100 (percentage) or 0–1 (fraction).
    private static func normalizedPop(_ raw: Double?) -> Double? {
        guard let raw else { return nil }
        return raw > 1 ? raw / 100 : raw
    }
}
