import Foundation
import Observation

@MainActor
@Observable
final class ItineraryViewModel: DemoModeProviding {
    private(set) var days: [ItineraryDayGroup] = []
    private(set) var nodes: [ItineraryNodeItem] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var validationErrors: [ItineraryFormFieldKey: String] = [:]

    var selectedDayIndex: Int = 1

    let tripId: String
    private var trip: Trip
    private let itineraryService: ItineraryService
    private let routeProvider: any TripRouteProviding
    private let savedPlaceService: SavedPlaceService?
    private(set) var matchingSavedPlaceCount = 0
    private(set) var matchingSavedPlaces: [SavedPlace] = []
    private(set) var isLoadingMatchingPlaces = false
    private(set) var matchingSavedPlacesErrorMessage: String?
    private var matchingSavedPlacesGeneration = 0
    /// Demo Journey read-only guard.
    var isDemoMode = false

    var groupedNodes: [ItineraryDayGroup] {
        days
    }

    var selectedDayGroup: ItineraryDayGroup? {
        days.first { $0.dayIndex == selectedDayIndex } ?? days.first
    }

    var tripDays: Int {
        if let totalDays = trip.totalDays, totalDays > 0 {
            return totalDays
        }

        guard
            let startDate = TripDateFormatting.date(from: trip.startDate),
            let endDate = TripDateFormatting.date(from: trip.endDate),
            let dayCount = TracciDateContext.inclusiveDayCount(start: startDate, end: endDate)
        else {
            return max(days.count, 1)
        }

        return dayCount
    }

    var hasAnyNodes: Bool {
        !nodes.isEmpty
    }

    var tripTitle: String {
        let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        return trip.destination?.name ?? ""
    }

    var placeSearchContext: PlaceSearchContext {
        PlaceSearchContext(
            name: trip.destination?.name,
            cityName: trip.destination?.cityName,
            country: trip.destination?.country,
            latitude: trip.destination?.latitude,
            longitude: trip.destination?.longitude
        )
    }

    init(
        tripId: String,
        trip: Trip,
        itineraryService: ItineraryService,
        savedPlaceService: SavedPlaceService? = nil,
        routeProvider: any TripRouteProviding
    ) {
        self.tripId = tripId
        self.trip = trip
        self.itineraryService = itineraryService
        self.savedPlaceService = savedPlaceService
        self.routeProvider = routeProvider
        selectedDayIndex = Self.defaultSelectedDayIndex(for: trip)
    }

    var savedPlaceServiceForPicker: SavedPlaceService? { savedPlaceService }

    /// SavedPlacePicker 顶部上下文副标，如「为 京都 · 第 2 天选择地点」。
    /// 让选择动作带上目标感；目的地缺失时退化为仅天数。
    func savedPlacePickerContextSubtitle(dayIndex: Int) -> String {
        let dayText = "第 \(dayIndex) 天"
        guard let destination = placeSearchContext.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return "为\(dayText)选择地点"
        }
        return "为 \(destination) · \(dayText) 选择地点"
    }

    func loadMatchingSavedPlaces() async {
        await loadMatchingSavedPlaces(keyword: nil, pageSize: 8)
    }

    func searchMatchingSavedPlaces(keyword: String) async {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        await loadMatchingSavedPlaces(
            keyword: normalized.isEmpty ? nil : normalized,
            pageSize: normalized.isEmpty ? 8 : 20
        )
    }

    private func loadMatchingSavedPlaces(keyword: String?, pageSize: Int) async {
        guard !isDemoMode, let savedPlaceService else { return }
        matchingSavedPlacesGeneration += 1
        let generation = matchingSavedPlacesGeneration
        isLoadingMatchingPlaces = true
        do {
            let response = try await savedPlaceService.list(
                SavedPlaceListQuery(
                    usage: .itineraryNode,
                    tripId: tripId,
                    keyword: keyword,
                    pageSize: pageSize
                )
            )
            guard generation == matchingSavedPlacesGeneration else { return }
            matchingSavedPlaceCount = response.total
            matchingSavedPlaces = response.list
            matchingSavedPlacesErrorMessage = nil
        } catch {
            guard generation == matchingSavedPlacesGeneration else { return }
            matchingSavedPlaces = []
            matchingSavedPlacesErrorMessage = SavedPlaceErrorMessage.resolve(error)
        }
        if generation == matchingSavedPlacesGeneration {
            isLoadingMatchingPlaces = false
        }
    }

    func applySavedPlace(_ savedPlace: SavedPlace, to form: inout ItineraryNodeFormState) {
        form.useSavedPlace(savedPlace)
    }

    func updateTrip(_ trip: Trip) {
        self.trip = trip
    }

    func loadNodes() async {
        guard !isDemoMode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await itineraryService.fetchItinerary(tripId: tripId)
            apply(response: response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isDemoMode else { return }
        await loadNodes()
    }

    /// Demo Journey: hydrate from Bundle without network.
    func applyDemoPayload(_ response: ItineraryResponse, preferredDayIndex: Int? = nil) {
        isDemoMode = true
        apply(response: response)
        if let preferredDayIndex, days.contains(where: { $0.dayIndex == preferredDayIndex }) {
            selectedDayIndex = preferredDayIndex
        }
        isLoading = false
        errorMessage = nil
    }

    func selectDay(_ dayIndex: Int) {
        selectedDayIndex = dayIndex
    }

    func dayId(for dayIndex: Int) -> String? {
        days.first { $0.dayIndex == dayIndex }?.dayId
    }

    func validate(form: ItineraryNodeFormState) -> Bool {
        var errors: [ItineraryFormFieldKey: String] = [:]

        // 地点必填（title 可选，空时后端以地点名称兜底）。
        if !form.hasValidLocation {
            errors[.location] = "请填写地点"
        }

        if form.dayIndex < 1 || form.dayIndex > tripDays {
            errors[.dayIndex] = "请选择有效的天数"
        }

        if !ItineraryTimeFormatting.isValidTimeFormat(form.startTime) {
            errors[.startTime] = "开始时间格式应为 HH:mm"
        }

        if !ItineraryTimeFormatting.isValidTimeFormat(form.endTime) {
            errors[.endTime] = "结束时间格式应为 HH:mm"
        }

        if !ItineraryTimeFormatting.isStartBeforeOrEqualEnd(start: form.startTime, end: form.endTime) {
            errors[.endTime] = "结束时间不能早于开始时间"
        }

        let trimmedNote = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNote.count > 500 {
            errors[.note] = "备注不能超过 500 字"
        }

        validationErrors = errors
        return errors.isEmpty
    }

    func validationMessage(for field: ItineraryFormFieldKey) -> String? {
        validationErrors[field]
    }

    /// 设置（或清除）指定字段的校验错误。用于视图层失焦即时校验。
    func setValidationError(_ message: String?, for field: ItineraryFormFieldKey) {
        validationErrors[field] = message
    }

    func createNode(form: ItineraryNodeFormState) async -> String? {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return nil
        }
        guard !isSubmitting else { return nil }

        errorMessage = nil
        guard validate(form: form) else { return nil }

        guard let dayId = dayId(for: form.dayIndex) else {
            errorMessage = "未找到对应行程天，请刷新后重试"
            return nil
        }

        isSubmitting = true
        let createdId: String?
        do {
            let created = try await itineraryService.createNode(
                tripId: tripId,
                dayId: dayId,
                request: CreateItineraryNodeRequest(from: form)
            )
            await refresh()
            await routeProvider.clearCache()
            selectedDayIndex = form.dayIndex
            createdId = created.id
        } catch {
            errorMessage = error.localizedDescription
            createdId = nil
        }
        isSubmitting = false

        // 产品：住宿默认置底。后端 nextSortOrder 仅追加；先建酒店再加点位时需把酒店重新钉到末尾。
        // 新建 hotel（含 Stay Group 投影）本身已 nextSortOrder 置底，不必再钉。
        if createdId != nil, form.type != .hotel {
            await pinHotelsToBottomIfNeeded(dayIndex: form.dayIndex)
        }
        return createdId
    }

    func updateNode(_ node: ItineraryNodeItem, form: ItineraryNodeFormState) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        errorMessage = nil
        guard validate(form: form) else { return false }

        let targetDayId: String
        if form.dayIndex != node.dayIndex, let newDayId = dayId(for: form.dayIndex) {
            targetDayId = newDayId
        } else {
            targetDayId = node.dayId
        }

        let previousDayIndex = node.dayIndex
        isSubmitting = true
        var succeeded = false
        do {
            _ = try await itineraryService.updateNode(
                tripId: tripId,
                dayId: targetDayId,
                nodeId: node.id,
                request: UpdateItineraryNodeRequest(from: form)
            )
            await refresh()
            await routeProvider.clearCache()
            selectedDayIndex = form.dayIndex
            succeeded = true
        } catch {
            errorMessage = error.localizedDescription
            succeeded = false
        }
        isSubmitting = false

        if succeeded {
            let dayIndices: Set<Int> = [form.dayIndex, previousDayIndex]
            await pinHotelsToBottomIfNeeded(dayIndices: dayIndices)
        }
        return succeeded
    }

    /// 仅修改节点备注（用于已结束旅程的节点）。后端只允许 note 变化，其余字段必须为 null。
    func updateNodeNote(_ node: ItineraryNodeItem, note: String) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await itineraryService.updateNode(
                tripId: tripId,
                dayId: node.dayId,
                nodeId: node.id,
                request: .noteOnly(note: note)
            )
            await refresh()
            await routeProvider.clearCache()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteNode(_ node: ItineraryNodeItem) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await itineraryService.deleteNode(
                tripId: tripId,
                dayId: node.dayId,
                nodeId: node.id
            )
            await refresh()
            await routeProvider.clearCache()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Same-day reorder

    /// Apply a local-only order for one day (optimistic UI during reorder mode).
    @discardableResult
    func applyLocalNodeOrder(dayIndex: Int, orderedIds: [String]) -> Bool {
        guard !isDemoMode else { return false }
        guard let dayPosition = days.firstIndex(where: { $0.dayIndex == dayIndex }) else { return false }
        let day = days[dayPosition]
        guard orderedIds.count == day.nodes.count else { return false }
        let map = Dictionary(uniqueKeysWithValues: day.nodes.map { ($0.id, $0) })
        let reordered = orderedIds.compactMap { map[$0] }
        guard reordered.count == day.nodes.count else { return false }

        days[dayPosition] = ItineraryDayGroup(
            id: day.id,
            dayId: day.dayId,
            dayIndex: day.dayIndex,
            date: day.date,
            nodes: reordered
        )
        nodes = days.flatMap(\.nodes)
        return true
    }

    /// Persist the current local order for a day via reorder API.
    func commitNodeOrder(dayIndex: Int, orderedIds: [String]) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }
        guard let day = days.first(where: { $0.dayIndex == dayIndex }) else {
            errorMessage = "未找到对应行程天"
            return false
        }
        guard orderedIds.count == day.nodes.count,
              Set(orderedIds) == Set(day.nodes.map(\.id))
        else {
            errorMessage = "排序数据不完整，请重试"
            return false
        }

        // Ensure local state matches the ids we submit.
        _ = applyLocalNodeOrder(dayIndex: dayIndex, orderedIds: orderedIds)

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await itineraryService.reorderNodes(
                tripId: tripId,
                dayId: day.dayId,
                nodeIds: orderedIds
            )
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(response: ItineraryResponse) {
        let groups = response.days
            .sorted { $0.dayIndex < $1.dayIndex }
            .map { day in
                // 稳定按 sortOrder；nil 靠后。不在此处强制酒店置底（尊重用户手动排序）。
                let items = day.nodes
                    .map {
                        ItineraryNodeItem(
                            dto: $0,
                            tripId: response.tripId,
                            dayId: day.id,
                            dayIndex: day.dayIndex
                        )
                    }
                    .sorted { lhs, rhs in
                        (lhs.sortOrder ?? .max) < (rhs.sortOrder ?? .max)
                    }

                return ItineraryDayGroup(
                    id: day.id,
                    dayId: day.id,
                    dayIndex: day.dayIndex,
                    date: day.date,
                    nodes: items
                )
            }

        days = groups
        nodes = groups.flatMap(\.nodes)

        if !groups.contains(where: { $0.dayIndex == selectedDayIndex }) {
            selectedDayIndex = groups.first?.dayIndex ?? 1
        }
    }

    // MARK: - Hotel pin-to-bottom (产品：住宿默认置底)

    /// 若当天存在「非酒店插在酒店之后」的顺序，则把所有 hotel 稳定挪到末尾并提交 reorder。
    private func pinHotelsToBottomIfNeeded(dayIndices: Set<Int>) async {
        for dayIndex in dayIndices.sorted() {
            await pinHotelsToBottomIfNeeded(dayIndex: dayIndex)
        }
    }

    private func pinHotelsToBottomIfNeeded(dayIndex: Int) async {
        guard !isDemoMode else { return }
        guard let day = days.first(where: { $0.dayIndex == dayIndex }) else { return }

        let nonHotels = day.nodes.filter { $0.type != .hotel }
        let hotels = day.nodes.filter { $0.type == .hotel }
        guard !hotels.isEmpty, !nonHotels.isEmpty else { return }

        // 已是「非酒店前缀 + 酒店后缀」则无需处理（保留酒店之间原有相对顺序）。
        let desiredIds = nonHotels.map(\.id) + hotels.map(\.id)
        guard desiredIds != day.nodes.map(\.id) else { return }

        _ = applyLocalNodeOrder(dayIndex: dayIndex, orderedIds: desiredIds)

        do {
            try await itineraryService.reorderNodes(
                tripId: tripId,
                dayId: day.dayId,
                nodeIds: desiredIds
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            await refresh()
        }
    }

    private static func defaultSelectedDayIndex(for trip: Trip) -> Int {
        guard
            trip.effectiveStatus == .ongoing,
            let startDate = TripDateFormatting.date(from: trip.startDate),
            let totalDays = trip.totalDays ?? inferredTotalDays(for: trip)
        else {
            return 1
        }

        let today = TracciDateContext.today()
        let offset = TracciDateContext.calendar.dateComponents([.day], from: startDate, to: today).day ?? 0
        return min(max(offset + 1, 1), totalDays)
    }

    private static func inferredTotalDays(for trip: Trip) -> Int? {
        guard
            let startDate = TripDateFormatting.date(from: trip.startDate),
            let endDate = TripDateFormatting.date(from: trip.endDate),
            let dayCount = TracciDateContext.inclusiveDayCount(start: startDate, end: endDate)
        else {
            return nil
        }

        return dayCount
    }
}
