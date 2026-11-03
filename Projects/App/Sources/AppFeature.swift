import CloudSync
import ComposableArchitecture
import CoreClients
import Domain
import FeatureCheckIn
import FeatureHistory

/// 根 feature：组合打卡页与历史页，转发跨页事件，编排 iCloud 同步。
@Reducer
public struct AppFeature {
    // MARK: State

    @ObservableState
    public struct State: Equatable {
        public var checkIn = CheckInFeature.State()
        public var history = HistoryFeature.State()

        public init() {}
    }

    // MARK: Action

    public enum Action {
        case checkIn(CheckInFeature.Action)
        case history(HistoryFeature.Action)
        /// 请求一次双向同步（cancellable：新请求会替代进行中的旧请求）。
        case syncTriggered
        case syncResponse(Result<[CheckIn], SyncError>)

        public enum SyncError: Error, Equatable {
            case failed
        }

        struct SyncID: Hashable {}
    }

    // MARK: Dependencies

    @Dependency(CloudSyncClient.self) private var cloudSyncClient
    @Dependency(CheckInClient.self) private var checkInClient

    public init() {}

    // MARK: Reducer

    public var body: some ReducerOf<Self> {
        Scope(state: \.checkIn, action: \.checkIn) {
            CheckInFeature()
        }
        Scope(state: \.history, action: \.history) {
            HistoryFeature()
        }
        Reduce { state, action in
            switch action {
            // 打卡成功（新增）→ 历史页即时插入 + 触发同步
            case let .checkIn(.delegate(.didCheckIn(checkIn))):
                return .concatenate(
                    .send(.history(.recordAdded(checkIn))),
                    .send(.syncTriggered)
                )

            // 打卡成功（时间窗内覆盖）→ 历史页同步更新 + 触发同步
            case let .checkIn(.delegate(.didUpdateCheckIn(checkIn))):
                return .concatenate(
                    .send(.history(.recordUpserted(checkIn))),
                    .send(.syncTriggered)
                )

            // 启动后历史加载完成 → 触发首次同步
            case .history(.recordsLoaded):
                return .send(.syncTriggered)

            // 编辑保存 → 触发同步
            case .history(.editing(.presented(.delegate))):
                return .send(.syncTriggered)

            // 本地删除靠墓碑在下一次同步时对云端清算（无需即时触发）
            case .checkIn, .history:
                return .none

            case .syncTriggered:
                let sync = cloudSyncClient.sync
                let accountStatus = cloudSyncClient.accountStatus
                let local = state.history.records.elements
                return .run { send in
                    guard (try? await accountStatus()) == .available else {
                        await send(.history(.syncStatusChanged(.disabled)))
                        return
                    }
                    await send(.history(.syncStatusChanged(.syncing)))
                    do {
                        let merged = try await sync(local)
                        await send(.syncResponse(.success(merged)))
                    } catch {
                        await send(.syncResponse(.failure(.failed)))
                    }
                }
                .cancellable(id: Action.SyncID(), cancelInFlight: true)

            case let .syncResponse(.success(merged)):
                state.history.cloudStatus = .ok
                // 合并结果必须落盘：否则本地 JSON/照片缺一不可地依赖每次云端拉取，
                // 断网或重装后数据"消失"
                let saveAll = checkInClient.saveAll
                let persist: Effect<Action> = .run { _ in
                    try? await saveAll(merged)
                }
                if merged != state.history.records.elements {
                    return .concatenate(
                        persist,
                        .send(.history(.recordsLoaded(merged)))
                    )
                }
                return persist

            case .syncResponse(.failure):
                state.history.cloudStatus = .failed
                return .none
            }
        }
    }
}
