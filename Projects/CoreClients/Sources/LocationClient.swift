import ComposableArchitecture
import CoreLocation
import DependenciesMacros
import Foundation

/// Sendable 的位置快照（避免 CLLocation 跨隔离边界）。
public struct Location: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

public enum LocationError: Error, Equatable {
    /// 用户拒绝或系统限制了定位权限。
    case denied
    /// 定位不可用或失败。
    case unavailable
}

/// 定位依赖：一次性获取当前位置（含权限请求流程）。
@DependencyClient
public struct LocationClient: Sendable {
    public var requestCurrentLocation: @Sendable () async throws -> Location
}

// MARK: - Live

/// 一次性定位的 delegate。
///
/// 注意：不能把这个类标成 `@MainActor`——隔离类型对非隔离 @objc 协议
/// （CLLocationManagerDelegate）的实现不会生成静态 ObjC 方法入口，
/// `CLLocationManager.requestLocation()` 在运行时用 `respondsToSelector:`
/// 校验 delegate 时会失败并抛 NSInternalInconsistencyException。
/// 线程安全靠约定保证：manager 创建于主线程，delegate 回调同样派发在主线程，
/// 因此下面的 continuation 存储实际只在主线程读写。
private final class OneShotLocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<Location, any Error>?

    // MARK: - CLLocationManagerDelegate（回调派发在创建 manager 的主线程上）

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        guard let location = locations.max(by: { $0.timestamp < $1.timestamp }) else {
            continuation.resume(throwing: LocationError.unavailable)
            return
        }
        continuation.resume(
            returning: Location(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: LocationError.unavailable)
    }

    /// 在主线程上完成创建与请求编排（CLLocationManager 要求其创建线程带 runloop）。
    @MainActor
    static func currentLocation() async throws -> Location {
        let oneShot = OneShotLocationManager()
        oneShot.manager.delegate = oneShot

        var status = oneShot.manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                // 闭包同步立即执行（仍在主线程），先挂 continuation 再触发系统弹窗，
                // 顺序得以保证（回调走主 runloop，必晚于此处）。
                oneShot.authorizationContinuation = continuation
                oneShot.manager.requestWhenInUseAuthorization()
            }
        }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            throw LocationError.denied
        }

        return try await withCheckedThrowingContinuation { continuation in
            oneShot.locationContinuation = continuation
            oneShot.manager.requestLocation()
        }
    }
}

extension LocationClient: DependencyKey {
    public static let testValue = LocationClient()

    public static let liveValue = LocationClient(
        requestCurrentLocation: {
            try await OneShotLocationManager.currentLocation()
        }
    )

    public static let previewValue = LocationClient(
        requestCurrentLocation: {
            Location(latitude: 39.9042, longitude: 116.4074, timestamp: .now)
        }
    )
}

public extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
