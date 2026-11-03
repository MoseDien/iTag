import ComposableArchitecture
import CoreClients
import Domain
import Foundation
import UIKit

/// 打卡页：定位 → 展示地名 →（可选备注）→ 一键打卡入库。
@Reducer
public struct CheckInFeature {
    // MARK: State

    @ObservableState
    public struct State: Equatable {
        /// 当前定位（nil = 尚未定位成功）。
        public var location: Location?
        /// 用户在地图上拖动选中的位置（地图中心；nil = 未选，用定位）。
        public var mapCenter: Location?
        /// 反地理编码得到的地名（对应打卡目标点）。
        public var placeName: String?
        /// 备注（可选，输入框默认隐藏，用户点击"添加备注"后显示）。
        public var note = ""
        /// 备注输入框是否可见。
        public var noteFieldVisible = false
        /// 已选择待打卡的照片文件 ID（上限见 CheckInPolicy.photoLimit）。
        public var pendingPhotoIDs: [String] = []
        /// 定位/打卡进行中。
        public var isWorking = false
        /// 最近一次成功打卡。
        public var lastCheckIn: CheckIn?
        @Presents public var alert: AlertState<Action.Alert>?

        /// 本次打卡的目标点：优先地图选点，其次当前定位。
        public var target: Location? {
            mapCenter ?? location
        }

        public init(
            location: Location? = nil,
            mapCenter: Location? = nil,
            placeName: String? = nil,
            note: String = "",
            noteFieldVisible: Bool = false,
            pendingPhotoIDs: [String] = [],
            isWorking: Bool = false,
            lastCheckIn: CheckIn? = nil
        ) {
            self.location = location
            self.mapCenter = mapCenter
            self.placeName = placeName
            self.note = note
            self.noteFieldVisible = noteFieldVisible
            self.pendingPhotoIDs = pendingPhotoIDs
            self.isWorking = isWorking
            self.lastCheckIn = lastCheckIn
        }
    }

    // MARK: Action

    public enum Action: BindableAction {
        case onTask
        case locationResponse(Result<Location, LocationError>)
        case placeNameResponse(String?)
        /// 地图拖动结束，中心点即所选位置。
        case mapCenterChanged(Location)
        /// 选择器已保存照片文件，登记到待打卡列表。
        case photoAdded(String)
        /// 移除一张待打卡照片（文件随之删除）。
        case photoRemoved(String)
        /// 切换备注输入框可见性。
        case noteFieldTapped
        case binding(BindingAction<State>)
        case checkInTapped
        /// 重复检测结果（nil = 无冲突，直接保存）。
        case duplicateCheckResponse(CheckIn?)
        case saveResponse(Result<CheckIn, SaveError>)
        case alert(PresentationAction<Action.Alert>)
        case delegate(Delegate)

        public enum Alert: Equatable {
            case openSettingsTapped
        }

        public enum Delegate: Equatable, Sendable {
            /// 新增了一条打卡记录。
            case didCheckIn(CheckIn)
            /// 覆盖更新了时间窗内的重复打卡。
            case didUpdateCheckIn(CheckIn)
        }

        public enum SaveError: Error, Equatable {
            case failed
        }

        /// 反地理编码 effect 的取消标识：新请求自动取消旧请求，避免乱序地名。
        struct GeocodeID: Hashable {}
    }

    // MARK: Dependencies

    @Dependency(LocationClient.self) private var locationClient
    @Dependency(GeocodingClient.self) private var geocodingClient
    @Dependency(CheckInClient.self) private var checkInClient
    @Dependency(\.date) private var date
    @Dependency(\.uuid) private var uuid
    @Dependency(\.openURL) private var openURL

    public init() {}

    // MARK: Reducer

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onTask:
                state.isWorking = true
                return requestLocation()

            case let .locationResponse(.success(location)):
                state.isWorking = false
                state.location = location
                return geocodeEffect(latitude: location.latitude, longitude: location.longitude)

            case let .mapCenterChanged(center):
                state.mapCenter = center
                return geocodeEffect(latitude: center.latitude, longitude: center.longitude)

            case let .photoAdded(id):
                guard state.pendingPhotoIDs.count < CheckInPolicy.photoLimit else { return .none }
                state.pendingPhotoIDs.append(id)
                return .none

            case .noteFieldTapped:
                state.noteFieldVisible.toggle()
                return .none

            case let .photoRemoved(id):
                state.pendingPhotoIDs.removeAll { $0 == id }
                PhotoStore.delete(id)  // 不存在时静默忽略
                return .none

            case let .locationResponse(.failure(error)):
                state.isWorking = false
                switch error {
                case .denied:
                    state.alert = AlertState {
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
                case .unavailable:
                    state.alert = AlertState {
                        TextState("定位失败")
                    } actions: {
                        ButtonState(role: .cancel) {
                            TextState("好")
                        }
                    } message: {
                        TextState("请检查网络与定位服务后重试。")
                    }
                }
                return .none

            case let .placeNameResponse(name):
                state.placeName = name
                return .none

            case .binding:
                return .none

            case .checkInTapped:
                guard !state.isWorking else { return .none }
                guard let target = state.target else {
                    state.isWorking = true
                    return requestLocation()
                }
                state.isWorking = true
                // 写入前做重复检测（同位置 10 分钟内）
                let load = checkInClient.load
                let checkDate = date()
                return .run { send in
                    let existing = (try? await load()) ?? []
                    await send(
                        .duplicateCheckResponse(
                            existing.duplicate(
                                of: target.latitude, target.longitude, at: checkDate
                            )
                        )
                    )
                }

            case .duplicateCheckResponse(nil):
                guard let checkIn = makeCheckIn(state) else {
                    state.isWorking = false
                    return .none
                }
                let append = checkInClient.append
                return persistEffect(
                    checkIn,
                    persist: { try await append(checkIn) },
                    then: .didCheckIn(checkIn)
                )

            case let .duplicateCheckResponse(.some(existing)):
                // 内容级去重（感知哈希）：与已有照片同一张图（即使重编码字节不同）的新照片不并入
                let existingKeys = Set(
                    existing.photoIDs.compactMap { PhotoStore.perceptualHash(for: $0) }
                )
                let newPhotoIDs = state.pendingPhotoIDs.filter { photoID in
                    guard let key = PhotoStore.perceptualHash(for: photoID) else { return true }
                    return !existingKeys.contains(key)
                }
                guard let fresh = makeCheckIn(state, photoIDs: newPhotoIDs) else {
                    state.isWorking = false
                    return .none
                }
                // 时间窗内同位置：直接覆盖原记录（保留 id，时间刷新、照片合并）
                let merged = fresh.mergedOver(existing)
                // 合并中被丢弃/去重的新照片文件随之删除
                state.pendingPhotoIDs
                    .filter { !merged.photoIDs.contains($0) }
                    .forEach { PhotoStore.delete($0) }
                let upsert = checkInClient.upsert
                return persistEffect(
                    merged,
                    persist: { try await upsert(merged) },
                    then: .didUpdateCheckIn(merged)
                )

            case let .saveResponse(.success(checkIn)):
                state.isWorking = false
                state.lastCheckIn = checkIn
                state.note = ""
                state.noteFieldVisible = false
                state.pendingPhotoIDs = []
                return .none

            case .saveResponse(.failure):
                state.isWorking = false
                state.alert = AlertState {
                    TextState("保存失败")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("好")
                    }
                } message: {
                    TextState("打卡未能写入本地，请重试。")
                }
                return .none

            case .alert(.presented(.openSettingsTapped)):
                state.alert = nil
                let openURL = openURL
                return .run { _ in
                    _ = try? await openURL(URL(string: UIApplication.openSettingsURLString)!)
                }

            case .alert:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    // MARK: Effect helpers

    /// 用当前 state 构造一条打卡记录（无目标点时返回 nil）；
    /// photoIDs 可覆盖（覆盖打卡时传内容去重后的列表）。
    private func makeCheckIn(_ state: State, photoIDs: [String]? = nil) -> CheckIn? {
        guard let target = state.target else { return nil }
        return CheckIn(
            id: uuid(),
            latitude: target.latitude,
            longitude: target.longitude,
            date: date(),
            placeName: state.placeName,
            note: state.note.trimmingCharacters(in: .whitespacesAndNewlines),
            photoIDs: photoIDs ?? state.pendingPhotoIDs
        )
    }

    /// 落盘并回发结果；成功后先收尾 saveResponse 再发 delegate（顺序稳定可测）。
    private func persistEffect(
        _ checkIn: CheckIn,
        persist: @escaping @Sendable () async throws -> Void,
        then delegateAction: Action.Delegate
    ) -> Effect<Action> {
        .run { send in
            do {
                try await persist()
                await send(.saveResponse(.success(checkIn)))
                await send(.delegate(delegateAction))
            } catch {
                await send(.saveResponse(.failure(.failed)))
            }
        }
    }

    /// 反地理编码（可取消：新的选点/定位自动作废进行中的旧请求）。
    private func geocodeEffect(latitude: Double, longitude: Double) -> Effect<Action> {
        let reverseGeocode = geocodingClient.reverseGeocode
        return .run { send in
            let name = try? await reverseGeocode(latitude, longitude)
            await send(.placeNameResponse(name))
        }
        .cancellable(id: Action.GeocodeID(), cancelInFlight: true)
    }

    private func requestLocation() -> Effect<Action> {
        let requestCurrentLocation = locationClient.requestCurrentLocation
        return .run { send in
            do {
                let location = try await requestCurrentLocation()
                await send(.locationResponse(.success(location)))
            } catch {
                await send(
                    .locationResponse(.failure((error as? LocationError) ?? .unavailable))
                )
            }
        }
    }
}
