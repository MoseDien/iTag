import ComposableArchitecture
import Domain
import XCTest

@testable import FeatureHistory

final class CheckInDetailFeatureTests: XCTestCase {
    private func makeRecord() -> CheckIn {
        CheckIn(
            latitude: 39.9, longitude: 116.4,
            date: Date(timeIntervalSince1970: 1_000),
            placeName: "北京市朝阳区",
            note: "原备注",
            photoIDs: ["photo-a"]
        )
    }

    @MainActor
    func testEditNoteAndPhotosThenSave() async {
        let base = makeRecord()
        let store = TestStore(
            initialState: CheckInDetailFeature.State(checkIn: base)
        ) {
            CheckInDetailFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {}
            let saveTime = Date(timeIntervalSince1970: 5_000)
            $0.date = DateGenerator { saveTime }
        }

        var updated = base
        updated.note = "新备注"
        updated.photoIDs = ["photo-b", "photo-c"]

        await store.send(.binding(.set(\.note, "新备注"))) {
            $0.note = "新备注"
        }
        await store.send(.addPhoto("photo-b")) {
            $0.photoIDs = ["photo-a", "photo-b"]
        }
        // 上限 9 张，第三张正常加入
        await store.send(.addPhoto("photo-c")) {
            $0.photoIDs = ["photo-a", "photo-b", "photo-c"]
        }
        // 移除原有照片（文件删除延迟到父级落盘成功后）
        await store.send(.removePhoto("photo-a")) {
            $0.photoIDs = ["photo-b", "photo-c"]
        }
        await store.send(.saveTapped)
        await store.receive(\.delegate)
        // delegate 携带更新后的记录与被移除照片 ID（父级测试覆盖落盘）
    }

    @MainActor
    func testIsDirty() {
        let base = makeRecord()
        var state = CheckInDetailFeature.State(checkIn: base)
        XCTAssertFalse(state.isDirty)
        state.note = "改了"
        XCTAssertTrue(state.isDirty)
        state.note = base.note
        state.photoIDs = ["photo-x"]
        XCTAssertTrue(state.isDirty)
    }
}
