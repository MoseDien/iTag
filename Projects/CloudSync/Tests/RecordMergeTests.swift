import Domain
import XCTest

@testable import CloudSync

final class RecordMergeTests: XCTestCase {
    func testLastWriteWins() {
        let base = Date(timeIntervalSince1970: 1_000)
        let local = CheckIn(
            latitude: 0, longitude: 0, date: base,
            note: "本地旧", updatedAt: base
        )
        // 同 id、远端 updatedAt 更新 → 远端胜
        let remoteNew = CheckIn(
            id: local.id,
            latitude: 0, longitude: 0, date: base,
            note: "云端新", updatedAt: base.addingTimeInterval(60)
        )

        XCTAssertEqual(mergeRecords(local: [local], remote: [remoteNew]).first?.note, "云端新")
        XCTAssertEqual(mergeRecords(local: [remoteNew], remote: [local]).first?.note, "云端新")
    }

    func testRemoteOnlyAndLocalOnlyAreKept() {
        let base = Date(timeIntervalSince1970: 1_000)
        let localOnly = CheckIn(latitude: 1, longitude: 1, date: base)
        let remoteOnly = CheckIn(latitude: 2, longitude: 2, date: base.addingTimeInterval(10))

        let merged = mergeRecords(local: [localOnly], remote: [remoteOnly])
        XCTAssertEqual(Set(merged.map(\.id)), [localOnly.id, remoteOnly.id])
        // 按打卡时间倒序
        XCTAssertEqual(merged.first?.id, remoteOnly.id)
    }

    func testEmptyInputs() {
        let base = Date(timeIntervalSince1970: 1_000)
        let record = CheckIn(latitude: 0, longitude: 0, date: base)
        XCTAssertTrue(mergeRecords(local: [], remote: []).isEmpty)
        XCTAssertEqual(mergeRecords(local: [record], remote: []).count, 1)
    }
}
