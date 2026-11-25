import CoreLocation
import MapKit

protocol TripRouteProviding: Sendable {
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async throws -> [CLLocationCoordinate2D]
    func clearCache() async
}

/// 路径缓存服务：按坐标对缓存 MKDirections 返回的真实路径坐标。
/// 使用 actor 保证并发安全，同一 key 不会重复发起网络请求。
actor RouteCacheService: TripRouteProviding {

    /// 内存缓存，上限 200 条路径。
    private let cache = NSCache<NSString, RouteBox>()

    /// 进行中的请求，用于去重（同一 key 只发一次 MKDirections）。
    private var inFlight: [String: Task<[CLLocationCoordinate2D], Error>] = [:]

    init() {
        cache.countLimit = 200
    }

    /// 获取两点间的真实路径坐标。缓存命中直接返回，否则调用 MKDirections。
    /// 失败时抛出错误，调用方可回退到直线。
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType = .walking
    ) async throws -> [CLLocationCoordinate2D] {
        let key = cacheKey(from: from, to: to)

        // 缓存命中
        if let box = cache.object(forKey: key as NSString) {
            return box.coordinates
        }

        // 去重：已有相同 key 的请求在飞
        if let task = inFlight[key] {
            return try await task.value
        }

        // 发起新请求
        let task = Task<[CLLocationCoordinate2D], Error> {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = transportType

            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            guard let route = response.routes.first else {
                throw RouteError.noRoute
            }

            let coordinates = route.polyline.coordinates()
            return coordinates
        }

        inFlight[key] = task

        defer { inFlight[key] = nil }

        let coordinates = try await task.value
        cache.setObject(RouteBox(coordinates: coordinates), forKey: key as NSString)
        return coordinates
    }

    /// 清除所有缓存（旅程编辑后坐标可能变化时调用）。
    func clearCache() {
        cache.removeAllObjects()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    // MARK: - Private

    private func cacheKey(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        let f = truncate(from)
        let t = truncate(to)
        return "\(f.latitude),\(f.longitude)→\(t.latitude),\(t.longitude)"
    }

    /// 截断到小数点后 5 位（约 1m 精度），避免浮点抖动导致缓存 miss。
    private func truncate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (coordinate.latitude * 100000).rounded() / 100000,
            longitude: (coordinate.longitude * 100000).rounded() / 100000
        )
    }
}

// MARK: - Support Types

/// NSCache 需要 class 类型。
private final class RouteBox: NSObject {
    let coordinates: [CLLocationCoordinate2D]
    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
    }
}

enum RouteError: Error {
    case noRoute
}

// MARK: - MKPolyline 坐标提取

extension MKPolyline {
    /// 提取 polyline 的全部坐标点。
    func coordinates() -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
