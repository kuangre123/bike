import Foundation
import MapKit
import CyclingDomain

struct Destination: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: GeoCoordinate
}

/// MKLocalSearch 封装：关键词 → 候选地点（按当前区域偏置）。
@MainActor
struct DestinationSearch {
    func search(_ query: String, near center: GeoCoordinate) async -> [Destination] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.map { item in
            Destination(
                name: item.name ?? "未知地点",
                subtitle: item.placemark.title ?? "",
                coordinate: GeoCoordinate(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude))
        }
    }
}
