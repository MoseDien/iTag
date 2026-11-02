import CloudSync
import ComposableArchitecture
import CoreClients
import Domain
import XCTest

@testable import FeatureHistory

final class HistoryFeatureTests: XCTestCase {
    /// 供 @Sendable 闭包记录调用结果的容器（测试内部串行使用）。
    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    private func makeOlder() -> CheckIn {
        CheckIn(
            latitude: 39.9, longitude: 116.4,
            date: Date(timeIntervalSince1970: 1_000),
            placeName: "A", note: ""
        )
    }

    private func makeNewer() -> CheckIn {
        CheckIn(
            latitude: 31.2, longitude: 121.5,
            date: Date(timeIntervalSince1970: 2_000),
            placeName: "B", note: ""
        )
    }

    @MainActor
    func testOnTaskLoadsRecordsSortedDesc() async {
        let older = makeOlder()
        let newer = makeNewer()
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.checkInClient = CheckInClient(
                load: { [older, newer] },  // 故意乱序
                append: { _ in },
                upsert: { _ in },
                saveAll: { _ in }
            )
        }

        await store.send(.onTask) {
            $0.isLoading = true
        }
        await store.receive(\.recordsLoaded) {
            $0.isLoading = false
            $0.records = IdentifiedArray(uniqueElements: [newer, older])
        }
    }

    @MainActor
    func testRecordAddedInsertsAtFront() async {
        let older = makeOlder()
        let newer = makeNewer()
        let store = TestStore(
            initialState: HistoryFeature.State(
                records: IdentifiedArray(uniqueElements: [older])
            )
        ) {
            HistoryFeature()
        }

        await store.send(.recordAdded(newer)) {
            $0.records = IdentifiedArray(uniqueElements: [newer, older])
        }
    }

    @MainActor
    func testDeleteCheckInSavesRemaining() async {
        let older = makeOlder()
        let newer = makeNewer()
        let saved = Box<[CheckIn]>()
        let store = TestStore(
            initialState: HistoryFeature.State(
                records: IdentifiedArray(uniqueElements: [older, newer])
            )
        ) {
            HistoryFeature()
        } withDependencies: {
            $0.checkInClient = CheckInClient(
                load: { [] },
                append: { _ in },
                upsert: { _ in },
                saveAll: { checkIns in
                    saved.value = checkIns
                }
            )
            $0.cloudSyncClient = CloudSyncClient(
                accountStatus: { .unavailable },
                sync: { local in local },
                markDeleted: { _ in }
            )
        }

        await store.send(.deleteCheckIn(id: newer.id)) {
            $0.records = IdentifiedArray(uniqueElements: [older])
        }
        XCTAssertEqual(saved.value?.map(\.id), [older.id])
    }

    @MainActor
    func testEditRecordSavesAndUpdates() async {
        let older = makeOlder()
        let newer = makeNewer()
        var updated = newer
        updated.note = "改过备注"
        let saved = Box<[CheckIn]>()
        let store = TestStore(
            initialState: HistoryFeature.State(
                records: IdentifiedArray(uniqueElements: [older, newer])
            )
        ) {
            HistoryFeature()
        } withDependencies: {
            $0.checkInClient = CheckInClient(
                load: { [] },
                append: { _ in },
                upsert: { _ in },
                saveAll: { checkIns in
                    saved.value = checkIns
                }
            )
            $0.dismiss = DismissEffect {}
        }

        // 点击记录进入编辑
        await store.send(.editTapped(newer.id)) {
            $0.editing = CheckInDetailFeature.State(checkIn: newer)
        }
        // 子级完成保存 → 记录更新 + 落盘 + 关闭编辑
        await store.send(.editing(.presented(.delegate(.saved(updated, []))))) {
            $0.editing = nil
            $0.records[id: updated.id] = updated
        }
        // records 保持原顺序 [older, newer→updated]
        XCTAssertEqual(saved.value?.map(\.note), [older.note, updated.note])
    }

    @MainActor
    func testRecordUpsertedMovesToFrontAndReplaces() async {
        let older = makeOlder()
        let newer = makeNewer()
        var updated = newer
        updated.note = "覆盖后的备注"
        let store = TestStore(
            initialState: HistoryFeature.State(
                records: IdentifiedArray(uniqueElements: [older, newer])
            )
        ) {
            HistoryFeature()
        }

        // 已有 id → 移到队首并替换
        await store.send(.recordUpserted(updated)) {
            $0.records = IdentifiedArray(uniqueElements: [updated, older])
        }

        // 未知 id → 视作新增插入队首
        let fresh = makeOlder()
        await store.send(.recordUpserted(fresh)) {
            $0.records = IdentifiedArray(uniqueElements: [fresh, updated, older])
        }
    }

    @MainActor
    func testLoadFailedShowsAlert() async {
        struct LoadError: Error {}
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.checkInClient = CheckInClient(
                load: { throw LoadError() },
                append: { _ in },
                upsert: { _ in },
                saveAll: { _ in }
            )
        }

        await store.send(.onTask) {
            $0.isLoading = true
        }
        await store.receive(\.loadFailed) {
            $0.isLoading = false
            $0.alert = AlertState {
                TextState("加载失败")
            } actions: {
                ButtonState(action: .send(.retryTapped)) {
                    TextState("重试")
                }
                ButtonState(role: .cancel) {
                    TextState("取消")
                }
            } message: {
                TextState("读取打卡记录出错，请重试。")
            }
        }
    }
}
