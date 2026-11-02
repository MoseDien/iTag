import CloudKit
import CoreClients
import Domain
import Foundation

/// CloudKit 私有库同步引擎。
///
/// 无 iCloud entitlements 时 `CKContainer(identifier:)` 会抛 ObjC 异常（无法 catch），
/// 因此用 Info.plist 的 `CloudSyncEnabled` 开关守门——它与 entitlements 在 Tuist 清单中
/// 同源配置：工程未配置 iCloud 能力时同步自动禁用，App 正常以纯本地模式运行。
enum CloudKitSyncEngine {
    static let containerID = "iCloud.com.belldien.itag"
    static let recordType = "CheckIn"
    static let tombstoneRecordType = "Meta"
    static let tombstoneRecordName = "tombstones"

    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CloudSyncEnabled") as? Bool ?? false
    }

    static func accountStatus() async throws -> CloudSyncAccountStatus {
        guard isEnabled else { return .unavailable }
        let status = try await CKContainer(identifier: containerID).accountStatus()
        return status == .available ? .available : .unavailable
    }

    // MARK: - 同步主流程

    static func sync(_ local: [CheckIn]) async throws -> [CheckIn] {
        guard isEnabled else { return local }
        let database = CKContainer(identifier: containerID).privateCloudDatabase

        // 1. 拉取云端全部记录（照片资产落地 PhotoStore，保持原 ID）
        let remoteRecords = try await fetchAllRecords(in: database)
        var remote: [CheckIn] = []
        var remoteUpdatedAt: [CheckIn.ID: Date] = [:]
        for record in remoteRecords {
            guard let checkIn = checkIn(from: record) else { continue }
            remote.append(checkIn)
            remoteUpdatedAt[checkIn.id] = checkIn.updatedAt
        }

        // 2. 墓碑：本地 ∪ 远端；从云端删除已墓碑记录并回写合并墓碑
        var tombstones = TombstoneStore.all
        tombstones.formUnion(try await fetchRemoteTombstones(in: database))
        remote.removeAll { tombstones.contains($0.id) }
        try await clearTombstonedRecords(from: remoteRecords, tombstones: tombstones, in: database)
        try await pushTombstones(tombstones, in: database)
        TombstoneStore.union(tombstones)

        // 3. LWW 合并
        let merged = mergeRecords(local: local, remote: remote)

        // 4. 推送本地较新/云端缺失的记录（含照片资产）
        for record in merged {
            let needsPush: Bool
            if let remoteDate = remoteUpdatedAt[record.id] {
                needsPush = record.updatedAt > remoteDate
            } else {
                needsPush = true
            }
            if needsPush {
                try await database.save(try ckRecord(from: record))
            }
        }
        return merged
    }

    // MARK: - CKRecord 映射

    private static func ckRecord(from checkIn: CheckIn) throws -> CKRecord {
        let record = CKRecord(
            recordType: recordType,
            recordID: CKRecord.ID(recordName: checkIn.id.uuidString)
        )
        record["latitude"] = checkIn.latitude
        record["longitude"] = checkIn.longitude
        record["date"] = checkIn.date
        record["updatedAt"] = checkIn.updatedAt
        record["placeName"] = checkIn.placeName
        record["note"] = checkIn.note
        record["photoIDs"] = checkIn.photoIDs
        for photoID in checkIn.photoIDs {
            if let url = PhotoStore.fileURL(for: photoID) {
                record["photo-\(photoID)"] = CKAsset(fileURL: url)
            }
        }
        return record
    }

    private static func checkIn(from record: CKRecord) -> CheckIn? {
        guard record.recordType == recordType,
              let id = UUID(uuidString: record.recordID.recordName),
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double,
              let date = record["date"] as? Date
        else { return nil }

        let photoIDs = record["photoIDs"] as? [String] ?? []
        // 本地缺失的照片从资产恢复（保持原 ID）
        for photoID in photoIDs {
            guard PhotoStore.fileURL(for: photoID) == nil,
                  let asset = record["photo-\(photoID)"] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url)
            else { continue }
            try? PhotoStore.save(data, as: photoID)
        }

        return CheckIn(
            id: id,
            latitude: latitude,
            longitude: longitude,
            date: date,
            placeName: record["placeName"] as? String,
            note: record["note"] as? String ?? "",
            photoIDs: photoIDs,
            updatedAt: record["updatedAt"] as? Date ?? date
        )
    }

    // MARK: - 墓碑记录（Meta/tombstones 单条记录存全部已删除 id）

    private static func fetchRemoteTombstones(in database: CKDatabase) async throws -> Set<UUID> {
        guard let record = try? await database.record(
            for: CKRecord.ID(recordName: tombstoneRecordName)
        ), record.recordType == tombstoneRecordType
        else { return [] }
        return Set((record["ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
    }

    private static func pushTombstones(_ tombstones: Set<UUID>, in database: CKDatabase) async throws {
        let record = CKRecord(
            recordType: tombstoneRecordType,
            recordID: CKRecord.ID(recordName: tombstoneRecordName)
        )
        record["ids"] = tombstones.map(\.uuidString)
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }

    private static func clearTombstonedRecords(
        from records: [CKRecord],
        tombstones: Set<UUID>,
        in database: CKDatabase
    ) async throws {
        let ids = records
            .map(\.recordID)
            .filter { UUID(uuidString: $0.recordName).map(tombstones.contains) ?? false }
        guard !ids.isEmpty else { return }
        _ = try await database.modifyRecords(saving: [], deleting: ids)
    }

    // MARK: - 拉取

    private static func fetchAllRecords(in database: CKDatabase) async throws -> [CKRecord] {
        var results: [CKRecord] = []
        var cursor: CKQueryCursor?
        repeat {
            let page = try await database.records(
                matching: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)),
                continuedFromCursor: cursor
            )
            results.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
            cursor = page.queryCursor
        } while cursor != nil
        return results.filter { $0.recordType == recordType }
    }
}
