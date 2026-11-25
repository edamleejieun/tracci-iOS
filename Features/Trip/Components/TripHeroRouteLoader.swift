import MapKit

/// Hero 地图所需的真实道路路线数据。地图 View 只负责把这些坐标渲染为 overlay。
struct TripHeroLoadedRoute {
    let passedCoordinates: [CLLocationCoordinate2D]
    let upcomingCoordinates: [CLLocationCoordinate2D]
}

struct TripHeroLoadedDayRoute {
    let dayIndex: Int
    let coordinates: [CLLocationCoordinate2D]
}

/// 将逐段路线请求和失败降级收口在地图渲染层之外。
struct TripHeroRouteLoader: Sendable {
    private let routeProvider: any TripRouteProviding

    init(routeProvider: any TripRouteProviding) {
        self.routeProvider = routeProvider
    }

    /// 单日路线允许局部失败；失败段按原有行为退化为两点直线。
    func loadRoute(
        coordinates: [CLLocationCoordinate2D],
        passedIndex: Int?
    ) async -> TripHeroLoadedRoute? {
        guard coordinates.count > 1 else { return nil }

        var segmentRoutes: [[CLLocationCoordinate2D]] = []
        for index in 0..<(coordinates.count - 1) {
            if Task.isCancelled { return nil }

            let from = coordinates[index]
            let to = coordinates[index + 1]
            do {
                let route = try await routeProvider.route(
                    from: from,
                    to: to,
                    transportType: .walking
                )
                segmentRoutes.append(route)
            } catch {
                segmentRoutes.append([from, to])
            }
        }

        guard !Task.isCancelled else { return nil }

        if let passedIndex, passedIndex > 0 {
            return TripHeroLoadedRoute(
                passedCoordinates: Self.join(segmentRoutes.prefix(min(passedIndex, segmentRoutes.count))),
                upcomingCoordinates: Self.join(segmentRoutes.dropFirst(min(passedIndex, segmentRoutes.count)))
            )
        }

        return TripHeroLoadedRoute(
            passedCoordinates: Self.join(segmentRoutes),
            upcomingCoordinates: []
        )
    }

    /// 全旅程路线以天为原子：任一段失败时保留该天已有直线占位，且不连接跨天路线。
    func loadFullTripRoutes(
        daySegments: [TripHeroMapData.DayRouteSegment],
        onRouteLoaded: @MainActor (TripHeroLoadedDayRoute) -> Void
    ) async {
        for segment in daySegments {
            if Task.isCancelled { return }
            guard segment.coordinates.count > 1 else { continue }

            var routes: [[CLLocationCoordinate2D]] = []
            var failed = false
            for index in 0..<(segment.coordinates.count - 1) {
                if Task.isCancelled { return }
                do {
                    let route = try await routeProvider.route(
                        from: segment.coordinates[index],
                        to: segment.coordinates[index + 1],
                        transportType: .walking
                    )
                    routes.append(route)
                } catch {
                    failed = true
                    break
                }
            }

            guard !Task.isCancelled else { return }
            guard !failed else { continue }

            let coordinates = Self.join(routes)
            guard coordinates.count > 1 else { continue }
            await onRouteLoaded(
                TripHeroLoadedDayRoute(dayIndex: segment.dayIndex, coordinates: coordinates)
            )
        }
    }

    private static func join<S: Sequence>(_ routes: S) -> [CLLocationCoordinate2D]
    where S.Element == [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        for route in routes {
            if coordinates.isEmpty {
                coordinates.append(contentsOf: route)
            } else {
                coordinates.append(contentsOf: route.dropFirst())
            }
        }
        return coordinates
    }
}
