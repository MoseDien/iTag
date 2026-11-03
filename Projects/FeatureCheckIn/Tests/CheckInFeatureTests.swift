import ComposableArchitecture
import CoreClients
import Domain
import XCTest

@testable import FeatureCheckIn

final class CheckInFeatureTests: XCTestCase {
    @MainActor
    func testCheckInHappyPath() async {
        let now = Date(timeIntervalSince1970: 1_799_000_000)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let location = Location(latitude: 39.9, longitude: 116.4, timestamp: now)
        let expected = CheckIn(
            id: id,
            latitude: 39.9,
            longitude: 116.4,
            date: now,
            placeName: "北京市朝阳区",
            note: "测试备注",
            photoIDs: ["photo-1", "photo-2"]
        )

        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                requestCurrentLocation: { location }
            )
            $0.geocodingClient = GeocodingClient(
                reverseGeocode: { _, _ in "北京市朝阳区" }
            )
            $0.checkInClient = CheckInClient(
                load: { [] },
                append: { _ in },
                upsert: { _ in },
                saveAll: { _ in }
            )
            $0.date = DateGenerator { now }
            $0.uuid = UUIDGenerator { id }
        }

        await store.send(.onTask) {
            $0.isWorking = true
        }
        await store.receive(\.locationResponse) {
            $0.isWorking = false
            $0.location = location
        }
        await store.receive(\.placeNameResponse) {
            $0.placeName = "北京市朝阳区"
        }
        await store.send(.binding(.set(\.note, "测试备注"))) {
            $0.note = "测试备注"
        }
        await store.send(.photoAdded("photo-1")) {
            $0.pendingPhotoIDs = ["photo-1"]
        }
        await store.send(.photoAdded("photo-2")) {
            $0.pendingPhotoIDs = ["photo-1", "photo-2"]
        }
        await store.send(.checkInTapped) {
            $0.isWorking = true
        }
        // 无重复（load 返回空）→ 直接保存
        await store.receive(\.duplicateCheckResponse)
        await store.receive(\.saveResponse) {
            $0.isWorking = false
            $0.lastCheckIn = expected
            $0.note = ""
            $0.pendingPhotoIDs = []
        }
        await store.receive(\.delegate)
    }

    @MainActor
    func testDuplicateWithinWindowUpserts() async {
        let now = Date(timeIntervalSince1970: 1_799_000_000)
        let freshID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let location = Location(latitude: 39.9, longitude: 116.4, timestamp: now)
        // 4 分钟前在同一位置打过卡（含一张旧照片），处于 5 分钟覆盖窗口内
        let existingID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let existing = CheckIn(
            id: existingID,
            latitude: 39.9, longitude: 116.4,
            date: now.addingTimeInterval(-240),
            placeName: "北京市朝阳区",
            note: "旧备注",
            photoIDs: ["p-old"]
        )
        // 覆盖合并：保留原 id，时间刷新，备注取新，照片旧优先合并
        let expected = CheckIn(
            id: existingID,
            latitude: 39.9, longitude: 116.4,
            date: now,
            placeName: "北京市朝阳区",
            note: "新备注",
            photoIDs: ["p-old", "p-new"]
        )

        final class UpsertBox: @unchecked Sendable {
            var value: CheckIn?
        }
        let upserted = UpsertBox()

        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                requestCurrentLocation: { location }
            )
            $0.geocodingClient = GeocodingClient(
                reverseGeocode: { _, _ in "北京市朝阳区" }
            )
            $0.checkInClient = CheckInClient(
                load: { [existing] },
                append: { _ in },
                upsert: { checkIn in
                    upserted.value = checkIn
                },
                saveAll: { _ in }
            )
            $0.date = DateGenerator { now }
            $0.uuid = UUIDGenerator { freshID }
        }

        await store.send(.onTask) {
            $0.isWorking = true
        }
        await store.receive(\.locationResponse) {
            $0.isWorking = false
            $0.location = location
        }
        await store.receive(\.placeNameResponse) {
            $0.placeName = "北京市朝阳区"
        }
        await store.send(.binding(.set(\.note, "新备注"))) {
            $0.note = "新备注"
        }
        await store.send(.photoAdded("p-new")) {
            $0.pendingPhotoIDs = ["p-new"]
        }
        await store.send(.checkInTapped) {
            $0.isWorking = true
        }
        // 时间窗内同位置：不弹框，直接覆盖原记录
        await store.receive(\.duplicateCheckResponse)
        await store.receive(\.saveResponse) {
            $0.isWorking = false
            $0.lastCheckIn = expected
            $0.note = ""
            $0.pendingPhotoIDs = []
        }
        await store.receive(\.delegate)
        XCTAssertEqual(upserted.value, expected)
    }

    @MainActor
    func testDuplicatePhotoMergeByContent() async {
        let now = Date(timeIntervalSince1970: 1_799_000_000)
        let freshID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let location = Location(latitude: 39.9, longitude: 116.4, timestamp: now)

        // 同一张图（左黑右白，高对比保证 aHash 稳定）重编码为两种压缩质量——字节不同但应判定为同一张
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let source = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
            UIColor.white.setFill()
            context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        }
        let sameHigh = source.jpegData(compressionQuality: 0.9)!
        let sameLow = source.jpegData(compressionQuality: 0.2)!
        XCTAssertNotEqual(sameHigh, sameLow, "重编码后字节应不同")
        // 另一张不同的图（整体黑）
        let other = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        .jpegData(compressionQuality: 0.9)!

        try? PhotoStore.save(sameHigh, as: "p-old")
        try? PhotoStore.save(sameLow, as: "p-same")
        try? PhotoStore.save(other, as: "p-diff")
        defer {
            PhotoStore.delete("p-old")
            PhotoStore.delete("p-diff")
            // p-same 被覆盖流程判定为重复并删除
        }

        let existingID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let existing = CheckIn(
            id: existingID,
            latitude: 39.9, longitude: 116.4,
            date: now.addingTimeInterval(-240),
            placeName: "北京市朝阳区",
            photoIDs: ["p-old"]
        )
        // 同内容被去重，只并入不同内容的照片
        let expected = CheckIn(
            id: existingID,
            latitude: 39.9, longitude: 116.4,
            date: now,
            placeName: "北京市朝阳区",
            photoIDs: ["p-old", "p-diff"]
        )

        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                requestCurrentLocation: { location }
            )
            $0.geocodingClient = GeocodingClient(
                reverseGeocode: { _, _ in "北京市朝阳区" }
            )
            $0.checkInClient = CheckInClient(
                load: { [existing] },
                append: { _ in },
                upsert: { _ in },
                saveAll: { _ in }
            )
            $0.date = DateGenerator { now }
            $0.uuid = UUIDGenerator { freshID }
        }

        await store.send(.onTask) {
            $0.isWorking = true
        }
        await store.receive(\.locationResponse) {
            $0.isWorking = false
            $0.location = location
        }
        await store.receive(\.placeNameResponse) {
            $0.placeName = "北京市朝阳区"
        }
        await store.send(.photoAdded("p-same")) {
            $0.pendingPhotoIDs = ["p-same"]
        }
        await store.send(.photoAdded("p-diff")) {
            $0.pendingPhotoIDs = ["p-same", "p-diff"]
        }
        await store.send(.checkInTapped) {
            $0.isWorking = true
        }
        await store.receive(\.duplicateCheckResponse)
        await store.receive(\.saveResponse) {
            $0.isWorking = false
            $0.lastCheckIn = expected
            $0.pendingPhotoIDs = []
        }
        await store.receive(\.delegate)
        // 同内容的重复照片文件已被删除
        XCTAssertNil(PhotoStore.fileURL(for: "p-same"))
    }

    @MainActor
    func testPhotoLimitAndRemoval() async {        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        }

        var expected: [String] = []
        for index in 0..<CheckInPolicy.photoLimit {
            expected.append("photo-\(index)")
            await store.send(.photoAdded("photo-\(index)")) {
                $0.pendingPhotoIDs = expected
            }
        }
        // 超过上限时忽略
        await store.send(.photoAdded("photo-overflow"))
        // 移除第一张（文件不存在时静默忽略）
        await store.send(.photoRemoved("photo-0")) {
            $0.pendingPhotoIDs = Array(expected.dropFirst())
        }
    }

    @MainActor
    func testNoteFieldHiddenByDefault() async {
        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        }

        // 默认隐藏，点击后显示
        await store.send(.noteFieldTapped) {
            $0.noteFieldVisible = true
        }
        await store.send(.noteFieldTapped) {
            $0.noteFieldVisible = false
        }
    }

    @MainActor
    func testLocationDeniedShowsAlert() async {
        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                requestCurrentLocation: { throw LocationError.denied }
            )
        }

        await store.send(.onTask) {
            $0.isWorking = true
        }
        await store.receive(\.locationResponse) {
            $0.isWorking = false
            $0.alert = AlertState {
                TextState("无法访问定位")
            } actions: {
                ButtonState(action: .send(.openSettingsTapped)) {
                    TextState("去设置")
                }
                ButtonState(role: .cancel) {
                    TextState("稍后")
                }
            } message: {
                TextState("请在系统设置中允许 iTag 使用定位权限后重试。")
            }
        }
    }

    @MainActor
    func testMapCenterSelectionUsesCenterForCheckIn() async {
        let now = Date(timeIntervalSince1970: 1_799_000_000)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let center = Location(latitude: 31.2, longitude: 121.5, timestamp: now)
        let expected = CheckIn(
            id: id,
            latitude: 31.2,
            longitude: 121.5,
            date: now,
            placeName: "上海市黄浦区",
            note: ""
        )

        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        } withDependencies: {
            $0.geocodingClient = GeocodingClient(
                reverseGeocode: { _, _ in "上海市黄浦区" }
            )
            $0.checkInClient = CheckInClient(
                load: { [] },
                append: { _ in },
                upsert: { _ in },
                saveAll: { _ in }
            )
            $0.date = DateGenerator { now }
            $0.uuid = UUIDGenerator { id }
        }

        // 拖动地图选点 → 更新中心并反地理编码
        await store.send(.mapCenterChanged(center)) {
            $0.mapCenter = center
        }
        await store.receive(\.placeNameResponse) {
            $0.placeName = "上海市黄浦区"
        }
        // 打卡使用所选中心点（即使没有 GPS 定位）
        await store.send(.checkInTapped) {
            $0.isWorking = true
        }
        await store.receive(\.duplicateCheckResponse)
        await store.receive(\.saveResponse) {
            $0.isWorking = false
            $0.lastCheckIn = expected
        }
        await store.receive(\.delegate)
    }

    @MainActor
    func testCheckInWithoutLocationLocatesFirst() async {
        let now = Date(timeIntervalSince1970: 1_799_000_000)
        let location = Location(latitude: 31.2, longitude: 121.5, timestamp: now)

        let store = TestStore(initialState: CheckInFeature.State()) {
            CheckInFeature()
        } withDependencies: {
            $0.locationClient = LocationClient(
                requestCurrentLocation: { location }
            )
            $0.geocodingClient = GeocodingClient(
                reverseGeocode: { _, _ in nil }
            )
            $0.checkInClient = CheckInClient(
                load: { [] },
                append: { _ in },
                upsert: { _ in },
                saveAll: { _ in }
            )
        }

        // 未定位时点击打卡：先触发定位
        await store.send(.checkInTapped) {
            $0.isWorking = true
        }
        await store.receive(\.locationResponse) {
            $0.isWorking = false
            $0.location = location
        }
        await store.receive(\.placeNameResponse)
    }
}
