import SwiftUI

/// 探索 Tab 内部的路由值。壳层只认这个枚举，具体页面在 `navigationDestination` 里映射。
enum ExploreNavigationRoute: Hashable {
    /// 城市页（规格 §7）。带整份种子：Hero 封面承上（§10.1），
    /// 并在城市自己的详情返回前先把标题、meta 与收藏态立起来。
    case city(ExploreCitySeed)
}

/// 探索 Tab 的导航外壳：`NavigationStack` + 路由表 + `AppTabPageHeader` 页头 + 溪线氛围底。
/// 页头与回忆/我的对齐（决策 2026-09-18），不再使用系统大标题。
///
/// Dock 显隐不在这里声明——沿用全局单一 preference 架构，由
/// `MainTabCoordinator.exploreNavigationPath` 的深度经
/// `TracciNavigationPathTabBarPolicy` 驱动。
struct ExploreRootView: View {
    @Bindable var viewModel: ExploreHomeViewModel
    /// 城市页自己发详情与地点流请求；服务由组合根经 `MainTabView` 注入（同 Home / Profile）。
    let service: any SavedPlaceServicing
    @Binding var navigationPath: NavigationPath
    var bottomTabBarContentInset: CGFloat = AppNavigationMetrics.contentInset(for: SafeAreaMetrics.bottom)
    var onRootScrollOffsetChange: (CGFloat) -> Void = { _ in }
    /// 「用这里创建旅程」的目的地只读预填（规格 §7.3），交给壳层打开创建表单。
    var onCreateTrip: ((TripCreateSeed) -> Void)?
    /// 地点半层「先创建旅程」（规格 §8.3）：POI **不**预填为目的地，所以与城市那条分开。
    var onCreateTripFromPlace: (() -> Void)?
    /// 半层「加入行程」复用 `SavedPlaceAddToTripSheet`，需要 `MainTabView` 已有的 provider。
    var tripProvider: (any SavedPlaceTripProviding)?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            exploreRoot
                .navigationDestination(for: ExploreNavigationRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    private var exploreRoot: some View {
        ExploreHomeView(
            viewModel: viewModel,
            bottomTabBarContentInset: bottomTabBarContentInset,
            onRootScrollOffsetChange: { offset in
                // 非根页面时把偏移归零：城市页有自己的紧凑逻辑，不能继承首页的滚动值。
                onRootScrollOffsetChange(navigationPath.isEmpty ? offset : 0)
            }
        )
        .toolbar(.hidden, for: .navigationBar)
        .tracciNavigationPathUIKitPopSync(path: $navigationPath)
        .tracciAtmosphere(.creek)
    }

    @ViewBuilder
    private func destination(for route: ExploreNavigationRoute) -> some View {
        switch route {
        case let .city(seed):
            ExploreCityView(
                seed: seed,
                service: service,
                tripProvider: tripProvider,
                onBack: popCityPage,
                onInteractivePopFinished: popCityPage,
                onCreateTrip: onCreateTrip,
                onCreateTripFromPlace: onCreateTripFromPlace
            )
        }
    }

    /// 城市页隐藏了系统返回键（会连带关掉侧滑），所以浮层按钮与自建侧滑都走这里改路径。
    private func popCityPage() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }
}
