import CoreLocation
import Foundation

/// Hero 地图所需的轻量数据容器，由 TripDetailView 在 day 切换时计算。
struct TripHeroMapData: Equatable {

    struct HeroMapAnnotation: Equatable, Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let timeText: String?
        let index: Int // 1-based pin 编号
        /// 所属天（1-based）；单日模式为 0，不参与按天着色。
        var dayIndex: Int = 0

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
                && lhs.index == rhs.index
                && lhs.dayIndex == rhs.dayIndex
        }
    }

    /// 全旅程总览的按天路线段：同日内相邻节点依次相连。
    /// 各天之间**不连线**——不虚构跨天的移动轨迹。
    struct DayRouteSegment: Equatable {
        let dayIndex: Int
        let coordinates: [CLLocationCoordinate2D]

        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.dayIndex == rhs.dayIndex,
                  lhs.coordinates.count == rhs.coordinates.count
            else { return false }
            for (l, r) in zip(lhs.coordinates, rhs.coordinates)
            where l.latitude != r.latitude || l.longitude != r.longitude {
                return false
            }
            return true
        }
    }

    /// 全旅程总览节点过多时的降级阈值：仅保留每天起点，避免地图拥挤。
    static let fullTripAnnotationCap = 20
    /// 全旅程总览允许请求真实道路路径的最大段数；超过则全部直线占位
    /// （MKDirections 逐段请求，成本与耗时随段数线性增长）。
    static let fullTripRealRouteMaxSegments = 6

    var annotationNodes: [HeroMapAnnotation]
    var destinationCoordinate: CLLocationCoordinate2D?
    var destinationName: String?
    /// 非空即全旅程总览模式：按 dayIndex 分色绘制每日路线。
    var daySegments: [DayRouteSegment] = []
    /// 是否全旅程总览。由数据侧按 scope 显式设置，**不能**用 daySegments
    /// 是否为空推断——每天只有 1 个坐标节点时 segments 为空但仍属总览。
    var isFullTripOverview: Bool = false
    /// 全旅程总览的总天数：色板阶梯按真实天数定位，不受「某天无节点」压缩。
    var fullTripDayCount: Int = 0

    /// 有节点坐标 OR 有目的地坐标时 toggle 可见。
    var isMapAvailable: Bool {
        !annotationNodes.isEmpty || destinationCoordinate != nil
    }

    static let empty = TripHeroMapData(
        annotationNodes: [],
        destinationCoordinate: nil,
        destinationName: nil
    )

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.annotationNodes == rhs.annotationNodes
            && lhs.destinationCoordinate?.latitude == rhs.destinationCoordinate?.latitude
            && lhs.destinationCoordinate?.longitude == rhs.destinationCoordinate?.longitude
            && lhs.daySegments == rhs.daySegments
            && lhs.isFullTripOverview == rhs.isFullTripOverview
            && lhs.fullTripDayCount == rhs.fullTripDayCount
    }
}
