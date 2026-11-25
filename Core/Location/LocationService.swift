import CoreLocation
import Foundation
import MapKit
import TracciNetworking

struct PlaceSearchContext: Equatable {
    let name: String?
    let cityName: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?

    var isActive: Bool {
        normalizedExpectedPlace != nil || coordinate != nil
    }

    var displayName: String? {
        [cityName, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var searchRegion: MKCoordinateRegion? {
        guard let coordinate else { return nil }
        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 0.9)
        )
    }

    func scopedKeyword(_ keyword: String) -> String {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard coordinate == nil, let displayName else { return trimmed }
        guard !normalized(trimmed).contains(normalized(displayName)) else { return trimmed }
        return "\(trimmed) \(displayName)"
    }

    func matches(_ mapItem: MKMapItem) -> Bool {
        guard isActive else { return true }

        let placemark = mapItem.placemark
        if let country,
           let placemarkCountry = placemark.country,
           !normalized(placemarkCountry).isEmpty,
           normalized(placemarkCountry) != normalized(country) {
            return false
        }

        if let expected = normalizedExpectedPlace {
            let candidates = [
                placemark.locality,
                placemark.subAdministrativeArea,
                placemark.administrativeArea,
                placemark.title
            ]
            .compactMap { $0 }
            .map(normalized)
            .filter { !$0.isEmpty }

            if candidates.contains(where: { $0.contains(expected) || expected.contains($0) }) {
                return true
            }

            if let coordinate {
                let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let target = CLLocation(
                    latitude: placemark.coordinate.latitude,
                    longitude: placemark.coordinate.longitude
                )
                return origin.distance(from: target) <= 150_000
            }

            return false
        }

        return true
    }

    private var normalizedExpectedPlace: String? {
        [cityName, name]
            .compactMap { $0 }
            .map(normalized)
            .first { !$0.isEmpty }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "市", with: "")
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "区", with: "")
            .replacingOccurrences(of: "县", with: "")
            .replacingOccurrences(of: "特别行政", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension PlaceSearchContext {
    static let unscoped = PlaceSearchContext(
        name: nil,
        cityName: nil,
        country: nil,
        latitude: nil,
        longitude: nil
    )
}

// MARK: - Models

struct POIItem: Decodable, Identifiable, Equatable {
    let poiId: String
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let provinceName: String?
    let cityName: String?
    let districtName: String?
    let adcode: String?
    let cityCode: String?
    let typeCode: String?
    let typeName: String?
    let source: String?

    var id: String { poiId }

    /// Amap returns GCJ-02 coordinates. Stored as-is for backend consistency.
    var journalLocation: JournalLocation {
        JournalLocation(
            poiId: poiId,
            name: name,
            provider: source,
            providerPlaceId: poiId,
            country: nil,
            address: address,
            latitude: latitude,
            longitude: longitude,
            adcode: adcode,
            cityCode: cityCode,
            provinceName: provinceName,
            cityName: cityName,
            districtName: districtName
        )
    }
}

struct POISearchResponse: Decodable {
    let items: [POIItem]
    let page: Int
    let size: Int
    let hasMore: Bool
    let source: String?
}

// MARK: - Service

struct LocationService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func searchPOI(keyword: String, city: String? = nil, page: Int = 1, size: Int = 10) async throws -> POISearchResponse {
        var queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(min(size, 20))"),
            URLQueryItem(name: "clientPlatform", value: "IOS")
        ]

        if let city, !city.isEmpty {
            queryItems.append(URLQueryItem(name: "city", value: city))
        }

        return try await apiClient.request(
            APIEndpoint(
                path: "locations/poi/search",
                queryItems: queryItems
            ),
            as: POISearchResponse.self
        )
    }
}
