import Foundation

/// 打卡业务的策略常量。
public enum CheckInPolicy {
    /// 判定"同一位置"的半径（米），覆盖 GPS 漂移与地图选点的正常偏差。
    public static let duplicateRadiusMeters: Double = 50
    /// 重复打卡的时间窗（秒）：窗口内同位置重复打卡自动覆盖原记录。
    public static let duplicateWindow: TimeInterval = 5 * 60
    /// 单条打卡记录的照片上限。
    public static let photoLimit = 3
}

let earthRadiusMeters = 6_371_000.0

public extension CheckIn {
    /// 与目标点之间的 Haversine 球面距离（米）。
    func distanceMeters(latitude: Double, longitude: Double) -> Double {
        func radians(_ degrees: Double) -> Double {
            degrees * .pi / 180
        }

        let lat1 = radians(self.latitude)
        let lat2 = radians(latitude)
        let dLat = radians(latitude - self.latitude)
        let dLon = radians(longitude - self.longitude)

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    /// 时间窗内重复打卡的覆盖合并：保留原 id 与坐标（同一条记录的延续）；
    /// date/note 取新值，地名新值为 nil 时保留旧值；
    /// 照片旧优先合并去重、截取至 `CheckInPolicy.photoLimit`（被丢弃的新照片文件由调用方删除）。
    func mergedOver(_ existing: CheckIn) -> CheckIn {
        CheckIn(
            id: existing.id,
            latitude: existing.latitude,
            longitude: existing.longitude,
            date: date,
            placeName: placeName ?? existing.placeName,
            note: note,
            photoIDs: Array((existing.photoIDs + photoIDs).uniqued().prefix(CheckInPolicy.photoLimit)),
            updatedAt: date
        )
    }
}

private extension Sequence where Element: Hashable {
    /// 保持首次出现顺序去重。
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

public extension [CheckIn] {
    /// 在时间窗与半径内与目标点重复的最近一条记录；无冲突返回 nil。
    ///
    /// - Parameters:
    ///   - latitude/longitude: 目标点坐标
    ///   - now: 当前时间（测试可注入）
    func duplicate(
        of latitude: Double,
        _ longitude: Double,
        at now: Date,
        radiusMeters: Double = CheckInPolicy.duplicateRadiusMeters,
        window: TimeInterval = CheckInPolicy.duplicateWindow
    ) -> CheckIn? {
        let windowStart = now.addingTimeInterval(-window)
        return filter { record in
            record.date > windowStart
                && record.distanceMeters(latitude: latitude, longitude: longitude) <= radiusMeters
        }
        .max { $0.date < $1.date }
    }
}
