import Foundation

/// 一次打卡记录。
public struct CheckIn: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let date: Date
    public var placeName: String?
    public var note: String
    /// 附带照片的文件 ID（最多 2 张），由 CoreClients.PhotoStore 管理。
    public var photoIDs: [String]
    /// 最近一次修改时间（iCloud 同步的 LWW 合并依据；创建时等于 date）。
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        date: Date,
        placeName: String? = nil,
        note: String = "",
        photoIDs: [String] = [],
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.placeName = placeName
        self.note = note
        self.photoIDs = photoIDs
        self.updatedAt = updatedAt ?? date
    }

    private enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, date, placeName, note, photoIDs, updatedAt
    }

    /// 兼容旧数据：photoIDs/updatedAt 缺失时取默认值。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        date = try container.decode(Date.self, forKey: .date)
        placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        photoIDs = try container.decodeIfPresent([String].self, forKey: .photoIDs) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
    }
}
