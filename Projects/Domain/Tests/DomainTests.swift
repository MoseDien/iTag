import XCTest

@testable import Domain

final class DomainTests: XCTestCase {
    /// 固定日历（UTC），保证断言确定性。
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-10-31 12:00:00 UTC
    var now: Date {
        let components = DateComponents(
            year: 2026, month: 10, day: 31, hour: 12, minute: 0, second: 0
        )
        return calendar.date(from: components)!
    }

    func checkIn(daysAgo: Double, id: String = UUID().uuidString) -> CheckIn {
        CheckIn(
            id: UUID(uuidString: id)!,
            latitude: 39.9,
            longitude: 116.4,
            date: now.addingTimeInterval(-daysAgo * 86_400),
            placeName: "某处",
            note: ""
        )
    }

    // MARK: - TimeRange.startDate

    func testStartDateWeek() {
        XCTAssertEqual(
            TimeRange.week.startDate(now: now, calendar: calendar),
            calendar.date(byAdding: .day, value: -7, to: now)
        )
    }

    func testStartDateMonthQuarterYear() {
        XCTAssertEqual(
            TimeRange.month.startDate(now: now, calendar: calendar),
            calendar.date(byAdding: .month, value: -1, to: now)
        )
        XCTAssertEqual(
            TimeRange.quarter.startDate(now: now, calendar: calendar),
            calendar.date(byAdding: .month, value: -3, to: now)
        )
        XCTAssertEqual(
            TimeRange.year.startDate(now: now, calendar: calendar),
            calendar.date(byAdding: .year, value: -1, to: now)
        )
    }

    func testAllCasesOrder() {
        XCTAssertEqual(TimeRange.allCases, [.week, .month, .quarter, .year])
    }

    // MARK: - [CheckIn].inRange

    func testInRangeFiltersAndSorts() {
        let records = [
            checkIn(daysAgo: 1),      // 一天前 → 一周内
            checkIn(daysAgo: 10),     // 十天前 → 超过一周，一个月内
            checkIn(daysAgo: 0.5),    // 半天前 → 一周内
            checkIn(daysAgo: 400),    // 一年多以前 → 全部排除
        ]

        let week = records.inRange(.week, now: now, calendar: calendar)
        XCTAssertEqual(week.map(\.id), [records[2].id, records[0].id])

        let month = records.inRange(.month, now: now, calendar: calendar)
        XCTAssertEqual(month.count, 3)
        XCTAssertEqual(month.first?.id, records[2].id)

        let year = records.inRange(.year, now: now, calendar: calendar)
        XCTAssertEqual(year.count, 3)

        XCTAssertTrue(records.inRange(.week, now: now, calendar: calendar).allSatisfy { $0.date >= TimeRange.week.startDate(now: now, calendar: calendar) })
    }

    func testInRangeIncludesBoundary() {
        let start = TimeRange.week.startDate(now: now, calendar: calendar)
        let boundary = CheckIn(latitude: 0, longitude: 0, date: start)
        XCTAssertEqual(
            [boundary].inRange(.week, now: now, calendar: calendar).count, 1
        )
    }

    // MARK: - Codable 兼容

    func testDecodeLegacyJSONWithoutPhotos() throws {
        // 旧版本数据没有 photoIDs 字段
        let legacy = """
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","latitude":39.9,"longitude":116.4,
        "date":"2026-10-31T04:00:00Z","placeName":"某处","note":"旧记录"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(CheckIn.self, from: Data(legacy.utf8))
        XCTAssertEqual(record.photoIDs, [])
        XCTAssertEqual(record.note, "旧记录")
    }

    // MARK: - 距离与重复判定

    func testDistanceMeters() {
        let tiananmen = CheckIn(latitude: 39.9087, longitude: 116.3975, date: now)
        // 同点距离为 0
        XCTAssertEqual(tiananmen.distanceMeters(latitude: 39.9087, longitude: 116.3975), 0, accuracy: 1)
        // 天安门 → 王府井 约 3.3 km
        let distance = tiananmen.distanceMeters(latitude: 39.9097, longitude: 116.4109)
        XCTAssertEqual(distance, 1_200, accuracy: 300)
        // 纬度 0.0005° ≈ 55 米
        XCTAssertEqual(
            tiananmen.distanceMeters(latitude: 39.9092, longitude: 116.3975), 55, accuracy: 10
        )
    }

    func testDuplicateHitsLatestWithinWindowAndRadius() {
        func near(_ minutesAgo: Double) -> CheckIn {
            CheckIn(latitude: 39.9, longitude: 116.4, date: now.addingTimeInterval(-minutesAgo * 60))
        }
        let closeOld = near(6)      // 窗内近处
        let closeNew = near(3)      // 窗内近处、最新 → 应命中
        let farAway = CheckIn(      // 窗内但 ~220 米外
            latitude: 39.902, longitude: 116.4,
            date: now.addingTimeInterval(-90)
        )
        let tooOld = near(14)       // 出窗

        let records = [tooOld, farAway, closeNew, closeOld]
        let hit = records.duplicate(of: 39.9, 116.4, at: now)
        XCTAssertEqual(hit?.id, closeNew.id)

        // 出窗 → nil
        XCTAssertNil([tooOld].duplicate(of: 39.9, 116.4, at: now))
        // 半径外（纬度差 ~0.002° ≈ 220 米）→ nil
        XCTAssertNil([farAway].duplicate(of: 39.9, 116.4, at: now))
        // 空记录 → nil
        XCTAssertNil([CheckIn]().duplicate(of: 39.9, 116.4, at: now))
    }

    func testMergedOver() {
        let existing = CheckIn(
            latitude: 39.9, longitude: 116.4,
            date: now.addingTimeInterval(-300),
            placeName: "旧地名",
            note: "旧备注",
            photoIDs: ["p-old"]
        )
        let fresh = CheckIn(
            latitude: 39.9001, longitude: 116.4001,  // 50 米内的新点
            date: now,
            placeName: nil,       // 新地名缺失 → 保留旧地名
            note: "新备注",
            photoIDs: ["p-new-1", "p-new-2", "p-new-3"]
        )

        let merged = fresh.mergedOver(existing)
        // id 与坐标保留原记录
        XCTAssertEqual(merged.id, existing.id)
        XCTAssertEqual(merged.latitude, existing.latitude)
        XCTAssertEqual(merged.longitude, existing.longitude)
        // date/note 取新值；地名 nil 时保留旧值
        XCTAssertEqual(merged.date, now)
        XCTAssertEqual(merged.note, "新备注")
        XCTAssertEqual(merged.placeName, "旧地名")
        // 照片旧优先合并、可超过三张
        XCTAssertEqual(merged.photoIDs, ["p-old", "p-new-1", "p-new-2", "p-new-3"])

        // 超过 photoLimit(9) 时截断（旧优先）
        var many = existing
        many.photoIDs = (0..<8).map { "p-old-\($0)" }
        var freshMany = fresh
        freshMany.photoIDs = (0..<5).map { "p-new-\($0)" }
        XCTAssertEqual(
            freshMany.mergedOver(many).photoIDs.count,
            CheckInPolicy.photoLimit
        )
    }

    // MARK: - [CheckIn].groupedByDay

    func testGroupedByDay() {
        let records = [
            checkIn(daysAgo: 0.1),     // 今天（晚）
            checkIn(daysAgo: 0.2),     // 今天（早）
            checkIn(daysAgo: 1.2),     // 昨天
            checkIn(daysAgo: 3.5),     // 三天前
        ]

        let groups = records.groupedByDay(calendar: calendar)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].items.count, 2)
        // 组内与组间均按时间倒序
        XCTAssertEqual(groups[0].items.map(\.id), [records[0].id, records[1].id])
        XCTAssertEqual(groups[1].items.first?.id, records[2].id)
        XCTAssertEqual(groups[2].items.first?.id, records[3].id)
    }
}
