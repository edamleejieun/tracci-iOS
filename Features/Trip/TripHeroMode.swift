import Foundation

/// Hero 区显示模式：封面图 / 地图。
enum TripHeroMode: String, CaseIterable, Identifiable {
    case cover
    case map

    var id: String { rawValue }

    /// 切换到该模式时显示的图标。
    var icon: String {
        switch self {
        case .cover: return "photo.fill"
        case .map: return "map.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cover: return "显示封面"
        case .map: return "显示地图"
        }
    }
}

/// Hero 地图镜头语义。节点选中与地图镜头分开建模，避免”取消选中”被误解为”恢复总览”。
enum TripHeroMapViewport: Equatable {
    /// 显示当前 Day 的完整路线与全部有效节点。
    case routeOverview
    /// 由时间线卡片或地图 marker 发起的节点聚焦。
    case focusedNode(String)
    /// 用户正在自由平移或缩放地图；不主动改写镜头。
    case userExploring
}

/// Hero 地图伸缩吸附点（browse 内小地图遗留；大地图沉浸用 `MapExplorePhase`）。
enum MapExpansionSnapPoint: Equatable {
    case compact
    case expanded

    /// expanded 相对 compact 的高度增量。
    static let expandedBonus: CGFloat = 160
}

/// 大地图沉浸 Surface 的呈现阶段。
/// browse 与 mapExplore 叠层常驻；用 progress + phase 做分层转场，避免硬切销毁 MKMapView。
enum MapExplorePhase: Equatable {
    /// 完全收起（browse 可交互）。
    case dismissed
    /// 进入动画中。
    case presenting
    /// 沉浸态可交互。
    case presented
    /// 退出动画中。
    case dismissing

    var isMapSurfaceActive: Bool {
        switch self {
        case .dismissed: false
        case .presenting, .presented, .dismissing: true
        }
    }

    var isInteractive: Bool {
        self == .presented
    }

    var isTransitioning: Bool {
        self == .presenting || self == .dismissing
    }
}
