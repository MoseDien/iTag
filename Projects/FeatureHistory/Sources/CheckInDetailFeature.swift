import ComposableArchitecture
import CoreClients
import Domain
import Foundation

/// 编辑一条打卡记录（备注 + 照片）。纯内存编辑，保存经 delegate 交给父级落盘。
@Reducer
public struct CheckInDetailFeature {
    // MARK: State

    @ObservableState
    public struct State: Equatable {
        /// 被编辑的原始记录。
        public let original: CheckIn
        public var note: String
        public var photoIDs: [String]

        public init(checkIn: CheckIn) {
            original = checkIn
            note = checkIn.note
            photoIDs = checkIn.photoIDs
        }

        /// 是否有未保存的改动。
        public var isDirty: Bool {
            note != original.note || photoIDs != original.photoIDs
        }
    }

    // MARK: Action

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// 视图已落盘新照片，登记 ID。
        case addPhoto(String)
        /// 从记录移除一张照片（文件删除延迟到保存成功）。
        case removePhoto(String)
        case saveTapped
        case cancelTapped
        case delegate(Delegate)

        public enum Delegate: Equatable {
            /// 保存的记录 + 本次被移除的照片 ID（由父级在落盘成功后删除文件）。
            case saved(CheckIn, [String])
        }
    }

    // MARK: Dependencies

    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.date) private var date

    public init() {}

    // MARK: Reducer

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case let .addPhoto(id):
                guard state.photoIDs.count < CheckInPolicy.photoLimit else { return .none }
                state.photoIDs.append(id)
                return .none

            case let .removePhoto(id):
                state.photoIDs.removeAll { $0 == id }
                return .none

            case .saveTapped:
                let updated: CheckIn = {
                    var copy = state.original
                    copy.note = state.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    copy.photoIDs = state.photoIDs
                    copy.updatedAt = date()  // iCloud 同步的 LWW 依据
                    return copy
                }()
                let removed = state.original.photoIDs.filter { !state.photoIDs.contains($0) }
                let dismiss = dismiss
                return .run { send in
                    await send(.delegate(.saved(updated, removed)))
                    await dismiss()
                }

            case .cancelTapped:
                // 丢弃：清理本次新增（未保存）的照片文件
                let added = state.photoIDs.filter { !state.original.photoIDs.contains($0) }
                added.forEach { PhotoStore.delete($0) }
                let dismiss = dismiss
                return .run { _ in
                    await dismiss()
                }

            case .delegate:
                return .none
            }
        }
    }
}
