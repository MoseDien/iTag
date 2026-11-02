import ComposableArchitecture
import FeatureCheckIn
import FeatureHistory

/// 根 feature：组合打卡页与历史页，转发跨页事件。
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
    }

    public init() {}

    // MARK: Reducer

    public var body: some ReducerOf<Self> {
        Scope(state: \.checkIn, action: \.checkIn) {
            CheckInFeature()
        }
        Scope(state: \.history, action: \.history) {
            HistoryFeature()
        }
        Reduce { _, action in
            switch action {
            // 打卡成功（新增）→ 历史页即时插入该记录
            case let .checkIn(.delegate(.didCheckIn(checkIn))):
                return .send(.history(.recordAdded(checkIn)))
            // 打卡成功（时间窗内覆盖）→ 历史页同步更新该记录
            case let .checkIn(.delegate(.didUpdateCheckIn(checkIn))):
                return .send(.history(.recordUpserted(checkIn)))
            case .checkIn:
                return .none
            case .history:
                return .none
            }
        }
    }
}
