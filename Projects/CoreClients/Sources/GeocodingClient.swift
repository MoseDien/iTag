import ComposableArchitecture
import CoreLocation
import DependenciesMacros
import Foundation

/// 反地理编码依赖：坐标 → 地名。
@DependencyClient
public struct GeocodingClient: Sendable {
    public var reverseGeocode: @Sendable (_ latitude: Double, _ longitude: Double) async throws -> String?
}

// MARK: - Live

extension GeocodingClient: DependencyKey {
    public static let testValue = GeocodingClient()

    public static let liveValue = GeocodingClient(
        reverseGeocode: { latitude, longitude in
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: latitude, longitude: longitude)
            )
            guard let placemark = placemarks.first else { return nil }
            // name 通常是完整街道描述；缺失时退回 市+区 拼接。
            if let name = placemark.name { return name }
            let city = [placemark.locality, placemark.subLocality]
                .compactMap(\.self)
                .joined()
            return city.isEmpty ? nil : city
        }
    )

    public static let previewValue = GeocodingClient(
        reverseGeocode: { _, _ in "北京市朝阳区" }
    )
}

public extension DependencyValues {
    var geocodingClient: GeocodingClient {
        get { self[GeocodingClient.self] }
        set { self[GeocodingClient.self] = newValue }
    }
}
