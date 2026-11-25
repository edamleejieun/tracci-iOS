import Foundation
import Observation
import TracciNetworking

/// 地点半层（规格 §8）的 ViewModel。
///
/// 详情加载与取消收藏复用 `PlaceDetailViewModel`，不改它；本层只补探索特有的三件事：
/// 1. `40901` 按幂等成功处理——契约决策 9，`SavedPlaceErrorMessage.isAlreadySaved` 的注释就是为半层留的；
/// 2. 「加入行程」要 `savedPlaceId`（契约 §15.8），未收藏时先静默收藏，与城市页 §7.3 同一口径；
/// 3. 收藏态回写城市页列表（规格 §8.4）。
@MainActor
@Observable
final class ExplorePlaceSheetViewModel {
    let placeDetail: PlaceDetailViewModel
    private let tripProvider: (any SavedPlaceTripProviding)?
    /// 回写城市页列表的收藏态（规格 §8.4）；对端是 `@MainActor` 的 VM，所以这里显式标注隔离。
    private let onSavedStateChange: @MainActor (String, Bool) -> Void

    /// 规格 §8.3：客户端只在「有无规划中 / 进行中旅程」这一层分支。
    /// 与某旅程目的地是否匹配交服务端判（`42243`），不做第二套匹配逻辑。
    private(set) var hasActiveTrips = false
    private(set) var isSaving = false
    private(set) var isPreparingAddToTrip = false

    var toast: TracciToastMessage?
    var unsaveErrorMessage: String?

    init(
        placeId: String,
        service: any SavedPlaceServicing,
        tripProvider: (any SavedPlaceTripProviding)?,
        onSavedStateChange: @escaping @MainActor (String, Bool) -> Void = { _, _ in }
    ) {
        placeDetail = PlaceDetailViewModel(service: service, placeId: placeId)
        self.tripProvider = tripProvider
        self.onSavedStateChange = onSavedStateChange
    }

    private var service: any SavedPlaceServicing { placeDetail.service }
    var placeId: String { placeDetail.placeId }

    // MARK: Derived

    var detail: PlaceDetail? { placeDetail.detail }
    var isLoading: Bool { placeDetail.isLoading && placeDetail.detail == nil }
    var errorMessage: String? { placeDetail.errorMessage }
    /// 规格 §8.3「防重复点击」：任何写操作在途时操作栏一起进 loading 并禁用。
    var isBusy: Bool { isSaving || isPreparingAddToTrip || placeDetail.isSubmitting }

    var isSaved: Bool { detail?.userContext?.isSaved ?? false }
    var savedPlace: SavedPlace? { detail?.asSavedPlace() }
    var hasCoordinate: Bool { detail?.latitude != nil && detail?.longitude != nil }
    var mediaItems: [PlaceMedia] { detail?.media ?? [] }
    var addTitle: String { hasActiveTrips ? "加入行程" : "先创建旅程" }

    // MARK: Loading

    func load() async {
        // 旅程列表与详情互不依赖：并行发，任一失败都不该拖住另一个。
        async let trips: Void = refreshActiveTrips()
        await placeDetail.load()
        _ = await trips
    }

    // MARK: 收藏（规格 §8.3）

    func save() async {
        guard !isSaved, !isBusy else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await service.create(.existingPlace(placeId: placeId, note: nil))
            await reloadAfterSavedChange(isSaved: true)
            toast = .success("已收藏，可在「我的 → 想去的地点」看到")
        } catch {
            guard SavedPlaceErrorMessage.isAlreadySaved(error) else {
                toast = .error("收藏没成功，稍后再试")
                return
            }
            await reloadAfterSavedChange(isSaved: true)
        }
    }

    /// 确认层异步路径：成功返回 `true` 关层，失败返回 `false` 保留弹层并说明原因。
    func unsave() async -> Bool {
        guard !isBusy else { return false }
        guard detail?.userContext?.savedPlaceId != nil else {
            unsaveErrorMessage = "这条收藏已不可用，请刷新后重试"
            return false
        }
        guard await placeDetail.removePlace() else {
            unsaveErrorMessage = placeDetail.errorMessage ?? "收藏没成功，稍后再试"
            return false
        }
        unsaveErrorMessage = nil
        onSavedStateChange(placeId, false)
        return true
    }

    // MARK: 加入行程（规格 §8.3）

    /// 返回可直接交给 `SavedPlaceAddToTripSheet` 的收藏地点；拿不到就不开选择器。
    func prepareAddToTrip() async -> SavedPlace? {
        guard !isBusy else { return nil }
        if let savedPlace { return savedPlace }

        isPreparingAddToTrip = true
        defer { isPreparingAddToTrip = false }

        do {
            let created = try await service.create(.existingPlace(placeId: placeId, note: nil))
            await reloadAfterSavedChange(isSaved: true)
            toast = .info("已加入想去的地点")
            // 详情刷新成功就以详情为准（带地址与坐标）；刷不动时用 create 的返回值兜底。
            return savedPlace ?? created
        } catch {
            guard SavedPlaceErrorMessage.isAlreadySaved(error) else {
                toast = .error("收藏没成功，稍后再试")
                return nil
            }
            await placeDetail.load()
            return savedPlace
        }
    }

    /// 无旅程时第一格读「先创建旅程」：只给轻提示，POI **不**预填为目的地（规格 §8.3）。
    func promptCreateTrip() {
        toast = .info("先创建一趟旅程，再把这里加进去")
    }

    // MARK: Private

    /// 规格 §8.4：热更新半层自身 `userContext`，同时把结果回写城市页列表。
    /// 回写依据的是写接口的既成事实，不依赖随后的详情刷新是否成功。
    private func reloadAfterSavedChange(isSaved: Bool) async {
        await placeDetail.load()
        onSavedStateChange(placeId, isSaved)
    }

    private func refreshActiveTrips() async {
        guard let tripProvider else {
            hasActiveTrips = false
            return
        }
        do {
            hasActiveTrips = try await tripProvider.loadActiveTrips().isEmpty == false
        } catch {
            // 拿不到旅程列表就按「无旅程」呈现：读「先创建旅程」，点了仍能进创建表单，不是死路。
            hasActiveTrips = false
        }
    }
}
