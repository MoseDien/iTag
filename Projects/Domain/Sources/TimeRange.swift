import Foundation

/// 历史地图的时间范围。
public enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case quarter
    case year

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "最近一周"
        case .month: "最近一个月"
        case .quarter: "最近一个季度"
        case .year: "最近一年"
        }
    }

    /// 范围起点对应的日历分量。
    var dateComponents: DateComponents {
        switch self {
        case .week: DateComponents(day: -7)
        case .month: DateComponents(month: -1)
        case .quarter: DateComponents(month: -3)
        case .year: DateComponents(year: -1)
        }
    }

    /// 该范围的起始日期（含边界：`date >= startDate` 视为在范围内）。
    public func startDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: dateComponents, to: now) ?? now
    }
}

/// 按天分组的结果（供列表使用）。
public struct CheckInDayGroup: Equatable, Sendable, Identifiable {
    /// 组内任一时间（用首条记录的时间即可，展示时只取日期部分）。
    public let day: Date
    public var items: [CheckIn]

    public var id: Date { day }
}

public extension [CheckIn] {
    /// 返回 `date >= range.startDate` 的记录，按时间倒序。
    func inRange(_ range: TimeRange, now: Date = .now, calendar: Calendar = .current) -> [CheckIn] {
        let start = range.startDate(now: now, calendar: calendar)
        return filter { $0.date >= start }
            .sorted { $0.date > $1.date }
    }

    /// 按天分组：天倒序，天内按时间倒序。
    func groupedByDay(calendar: Calendar = .current) -> [CheckInDayGroup] {
        let ordered = sorted { $0.date > $1.date }
        var groups: [CheckInDayGroup] = []
        for item in ordered {
            if let last = groups.last, calendar.isDate(last.day, inSameDayAs: item.date) {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(CheckInDayGroup(day: item.date, items: [item]))
            }
        }
        return groups
    }
}
