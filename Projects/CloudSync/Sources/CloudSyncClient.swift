import ComposableArchitecture
import DependenciesMacros
import Domain
import Foundation

/// 云同步状态（历史页导航栏指示）。
public enum SyncStatus: Equatable, Sendable {
    case syncing
    case ok
    case failed
    /// 无 iCloud 权限/未登录/未配置，自动降级为纯本地模式。
    case disabled
}

public enum CloudSyncAccountStatus: Equatable, Sendable {
    case available
    case unavailable
}

/// iCloud（CloudKit 私有库）同步依赖。
///
/// 数据模型：一条打卡 = 一条 `CheckIn` CKRecord（照片以 `CKAsset` 附加）；
/// 合并策略为 LWW（`CheckIn.updatedAt` 新者胜）；本地删除以墓碑记录，
/// 在下次同步时对云端清算。
@DependencyClient
public struct CloudSyncClient: Sendable {
    /// iCloud 账号与权限是否可用。
    public var accountStatus: @Sendable () async throws -> CloudSyncAccountStatus
    /// 双向同步：推送本地全量（含照片资产）与删除墓碑，拉取并合并云端记录，返回合并结果。
    public var sync: @Sendable (_ local: [CheckIn]) async throws -> [CheckIn]
    /// 本地删除记录时登记墓碑（下次同步时删除云端对应记录）。
    public var markDeleted: @Sendable (_ id: CheckIn.ID) async throws -> Void
}

// MARK: - 墓碑（本地 UserDefaults 存储）

enum TombstoneStore {
    private static let key = "itag.cloudsync.tombstones"

    static func add(_ id: UUID) {
        var ids = all
        ids.insert(id)
        UserDefaults.standard.set(Array(ids.map(\.uuidString)), forKey: key)
    }

    static var all: Set<UUID> {
        Set(
            (UserDefaults.standard.stringArray(forKey: key) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    /// 与远端墓碑合并后回写。
    static func union(_ ids: Set<UUID>) {
        var merged = all
        merged.formUnion(ids)
        UserDefaults.standard.set(Array(merged.map(\.uuidString)), forKey: key)
    }
}

extension CloudSyncClient: DependencyKey {
    public static let testValue = CloudSyncClient()

    public static let previewValue = CloudSyncClient(
        accountStatus: { .unavailable },
        sync: { local in local },
        markDeleted: { _ in }
    )

    public static let liveValue = CloudSyncClient(
        accountStatus: {
            try await CloudKitSyncEngine.accountStatus()
        },
        sync: { local in
            try await CloudKitSyncEngine.sync(local)
        },
        markDeleted: { id in
            TombstoneStore.add(id)
        }
    )
}

public extension DependencyValues {
    var cloudSyncClient: CloudSyncClient {
        get { self[CloudSyncClient.self] }
        set { self[CloudSyncClient.self] = newValue }
    }
}
