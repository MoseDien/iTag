import CloudSync
import ComposableArchitecture
import CoreClients
import Domain
import Foundation

/// 历史页：打卡记录列表 + 按时间范围（周/月/季/年）的地图总览。
@Reducer
public struct HistoryFeature {
    // MARK: State

    public enum ViewMode: String, CaseIterable, Identifiable, Equatable, Sendable {
        case list
        case map

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .list: "记录"
            case .map: "地图"
            }
        }
    }

    @ObservableState
    public struct State: Equatable {
        public var records = IdentifiedArrayOf<CheckIn>()
        public var viewMode: ViewMode = .list
        /// 地图模式的时间范围（记录列表始终展示全部）。
        public var timeRange: TimeRange = .week
        public var isLoading = false
        /// iCloud 同步状态（nil = 尚未同步过；由 AppFeature 下发）。
        public var cloudStatus: SyncStatus?
        @Presents public var alert: AlertState<Action.Alert>?
        /// 正在编辑的记录（sheet 呈现）。
        @Presents public var editing: CheckInDetailFeature.State?

        public init(
            records: IdentifiedArrayOf<CheckIn> = [],
            viewMode: ViewMode = .list,
            timeRange: TimeRange = .week,
            isLoading: Bool = false
        ) {
            self.records = records
            self.viewMode = viewMode
            self.timeRange = timeRange
            self.isLoading = isLoading
        }

        /// 地图模式当前应展示的记录（最近 `timeRange` 内，倒序）。
        public var filteredForMap: [CheckIn] {
            records.elements.inRange(timeRange)
        }
    }

    // MARK: Action

    public enum Action: BindableAction {
        case onTask
        case recordsLoaded([CheckIn])
        case loadFailed
        /// 打卡页新增了一条记录（AppFeature 转发）。
        case recordAdded(CheckIn)
        /// 打卡页覆盖更新了时间窗内的重复记录（AppFeature 转发）。
        case recordUpserted(CheckIn)
        /// 点击记录行进入编辑。
        case editTapped(CheckIn.ID)
        case deleteCheckIn(id: CheckIn.ID)
        case saveAllFailed
        /// 同步状态更新（AppFeature 下发）。
        case syncStatusChanged(SyncStatus)
        case binding(BindingAction<State>)
        case alert(PresentationAction<Action.Alert>)
        case editing(PresentationAction<CheckInDetailFeature.Action>)

        public enum Alert: Equatable {
            case retryTapped
        }
    }

    // MARK: Dependencies

    @Dependency(CheckInClient.self) private var checkInClient
    @Dependency(CloudSyncClient.self) private var cloudSyncClient

    public init() {}

    // MARK: Reducer

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onTask:
                state.isLoading = true
                return reload()

            case let .recordsLoaded(records):
                state.isLoading = false
                state.records = IdentifiedArray(
                    uniqueElements: records.sorted { $0.date > $1.date }
                )
                return .none

            case .loadFailed:
                state.isLoading = false
                state.alert = AlertState {
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
                return .none

            case let .recordAdded(checkIn):
                state.records.insert(checkIn, at: 0)
                return .none

            case let .recordUpserted(checkIn):
                // date 已刷新为最新，移到队首
                state.records.remove(id: checkIn.id)
                state.records.insert(checkIn, at: 0)
                return .none

            case let .editTapped(id):
                guard let record = state.records[id: id] else { return .none }
                state.editing = CheckInDetailFeature.State(checkIn: record)
                return .none

            case let .editing(.presented(.delegate(.saved(updated, removedIDs)))):
                state.editing = nil
                guard state.records[id: updated.id] != nil else { return .none }
                state.records[id: updated.id] = updated
                let remaining = state.records.elements
                let saveAll = checkInClient.saveAll
                return .run { send in
                    do {
                        try await saveAll(remaining)
                        // 落盘成功后才删除被移除的照片文件，失败则保持原样
                        removedIDs.forEach { PhotoStore.delete($0) }
                    } catch {
                        await send(.saveAllFailed)
                    }
                }

            case .editing(.dismiss):
                // 下滑取消：清理本次新增但未保存的照片文件，防止孤儿文件
                if let editing = state.editing {
                    editing.photoIDs
                        .filter { !editing.original.photoIDs.contains($0) }
                        .forEach { PhotoStore.delete($0) }
                }
                return .none

            case .editing:
                return .none

            case let .deleteCheckIn(id):
                guard let record = state.records.remove(id: id) else { return .none }
                record.photoIDs.forEach { PhotoStore.delete($0) }  // 照片文件随之清理
                let remaining = state.records.elements
                let saveAll = checkInClient.saveAll
                let markDeleted = cloudSyncClient.markDeleted
                return .run { [remaining, id] send in
                    do {
                        // 登记删除墓碑，下次同步时从云端清算
                        try? await markDeleted(id)
                        try await saveAll(remaining)
                    } catch {
                        await send(.saveAllFailed)
                    }
                }

            case .saveAllFailed:                state.alert = AlertState {
                    TextState("删除失败")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("好")
                    }
                } message: {
                    TextState("改动未能写入本地，正在重新同步记录。")
                }
                state.isLoading = true
                return reload()

            case let .syncStatusChanged(status):
                state.cloudStatus = status
                return .none

            case .binding:
                return .none

            case .alert(.presented(.retryTapped)):
                state.alert = nil
                state.isLoading = true
                return reload()

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$editing, action: \.editing) {
            CheckInDetailFeature()
        }
    }

    // MARK: Effect helpers

    private func reload() -> Effect<Action> {
        let load = checkInClient.load
        return .run { send in
            do {
                let records = try await load()
                await send(.recordsLoaded(records))
            } catch {
                await send(.loadFailed)
            }
        }
    }
}
