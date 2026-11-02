import Domain
import Foundation

/// LWW 合并本地与远端记录：同 id 取 `updatedAt` 新者；结果按打卡时间倒序。
public func mergeRecords(local: [CheckIn], remote: [CheckIn]) -> [CheckIn] {
    var byID: [CheckIn.ID: CheckIn] = [:]
    for record in local + remote {
        if let existing = byID[record.id] {
            if record.updatedAt > existing.updatedAt {
                byID[record.id] = record
            }
        } else {
            byID[record.id] = record
        }
    }
    return byID.values.sorted { $0.date > $1.date }
}
