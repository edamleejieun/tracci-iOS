import Foundation
import Observation

// MARK: - Lightweight Trip Summary (for picker)

/// 加入行程选择器用的旅程摘要。
/// 仅包含选择器所需的字段，避免持有完整 Trip 模型。
struct SavedPlaceTripSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let status: TripStatus
    let startDate: String
    let endDate: String
    let destinationName: String?
    let coverThumbnailURL: URL?
    let totalDays: Int?
    let nodeCount: Int?

    init(trip: Trip) {
        id = trip.id
        title = trip.title
        status = trip.status
        startDate = trip.startDate
        endDate = trip.endDate
        destinationName = trip.destinationName
        coverThumbnailURL = trip.coverThumbnailURL
        totalDays = trip.totalDays
        nodeCount = trip.nodeCount
    }
}

/// 选择器用的旅程日期（仅含选择所需的字段）。
struct SavedPlaceTripDay: Identifiable, Equatable {
    let id: String
    let dayIndex: Int
    let date: String
    let nodeCount: Int

    init(day: ItineraryDay) {
        id = day.id
        dayIndex = day.dayIndex
        date = day.date
        nodeCount = day.nodes.count
    }
}

// MARK: - Errors

enum SavedPlaceAddToTripError: Error {
    case noActiveTrips
    case noDays
    case addFailed(Error)

    var message: String {
        switch self {
        case .noActiveTrips: "还没有可以添加地点的旅程"
        case .noDays: "这个旅程还没有日期"
        case .addFailed(let error): SavedPlaceErrorMessage.resolve(error)
        }
    }
}

// MARK: - Capability Protocol

/// 把收藏地点加入行程的能力抽象。
///
/// 列表页通过这个协议拉取「可加入的旅程」并执行追加节点，
/// 不直接依赖 TripService / ItineraryService，保持 SavedPlacesView
/// 与行程模块解耦；测试可用 mock 注入。
@MainActor
protocol SavedPlaceTripProviding: AnyObject {
    /// 加载可加入收藏地点的旅程（规划中 + 进行中）。
    func loadActiveTrips() async throws -> [SavedPlaceTripSummary]

    /// 加载某个旅程的日期列表。
    func loadTripDays(tripId: String) async throws -> [SavedPlaceTripDay]

    /// 把收藏地点作为节点追加到指定旅程的指定日期末尾。
    /// 返回创建后的节点 id。
    @discardableResult
    func addSavedPlace(
        _ place: SavedPlace,
        toTripId tripId: String,
        dayId: String
    ) async throws -> String
}

// MARK: - Live Implementation

/// 基于 TripService + ItineraryService 的默认实现。
///
/// 规划中（planning）与进行中（ongoing）的旅程才可加入节点；
/// 已完成（completed）与 unknown 不出现。
final class SavedPlaceTripProvider: SavedPlaceTripProviding {
    private let tripService: TripService
    private let itineraryService: ItineraryService

    init(tripService: TripService, itineraryService: ItineraryService) {
        self.tripService = tripService
        self.itineraryService = itineraryService
    }

    func loadActiveTrips() async throws -> [SavedPlaceTripSummary] {
        async let planning = tripService.listTrips(pageSize: 50, status: .planning)
        async let ongoing = tripService.listTrips(pageSize: 50, status: .ongoing)
        let planningResponse = try await planning
        let ongoingResponse = try await ongoing
        let all = planningResponse.list + ongoingResponse.list
        return all
            .sorted { $0.startDate < $1.startDate }
            .map(SavedPlaceTripSummary.init)
    }

    func loadTripDays(tripId: String) async throws -> [SavedPlaceTripDay] {
        let response = try await itineraryService.fetchItinerary(tripId: tripId)
        return response.days
            .sorted { $0.dayIndex < $1.dayIndex }
            .map(SavedPlaceTripDay.init)
    }

    func addSavedPlace(
        _ place: SavedPlace,
        toTripId tripId: String,
        dayId: String
    ) async throws -> String {
        // dayIndex 不进入 create 请求体（路径用 dayId）；仍按契约使用 1-based 默认值。
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.useSavedPlace(place)
        do {
            let created = try await itineraryService.createNode(
                tripId: tripId,
                dayId: dayId,
                request: CreateItineraryNodeRequest(from: form)
            )
            return created.id
        } catch {
            throw SavedPlaceAddToTripError.addFailed(error)
        }
    }
}
