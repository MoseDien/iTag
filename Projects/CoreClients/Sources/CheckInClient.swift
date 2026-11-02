import ComposableArchitecture
import DependenciesMacros
import Domain
import Foundation

/// 打卡持久化依赖（Documents/checkins.json，全量读写）。
@DependencyClient
public struct CheckInClient: Sendable {
    public var load: @Sendable () async throws -> [CheckIn]
    public var append: @Sendable (_ checkIn: CheckIn) async throws -> Void
    /// 同 id 替换、无则追加（覆盖式打卡使用，actor 内原子完成）。
    public var upsert: @Sendable (_ checkIn: CheckIn) async throws -> Void
    public var saveAll: @Sendable (_ checkIns: [CheckIn]) async throws -> Void
}

// MARK: - Live

/// actor 保证读-改-写串行化；`fileURL == nil` 时为纯内存实现（供 Preview）。
private actor CheckInStore {
    private let fileURL: URL?
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()
    private var cache: [CheckIn]?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [CheckIn] {
        if let cache { return cache }
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty
        else {
            cache = []
            return []
        }
        let items = try decoder.decode([CheckIn].self, from: data)
        cache = items
        return items
    }

    func append(_ checkIn: CheckIn) throws -> [CheckIn] {
        var items = try load()
        items.append(checkIn)
        try persist(items)
        return items
    }

    func upsert(_ checkIn: CheckIn) throws -> [CheckIn] {
        var items = try load()
        if let index = items.firstIndex(where: { $0.id == checkIn.id }) {
            items[index] = checkIn
        } else {
            items.append(checkIn)
        }
        try persist(items)
        return items
    }

    func saveAll(_ checkIns: [CheckIn]) throws {
        try persist(checkIns)
    }

    private func persist(_ checkIns: [CheckIn]) throws {
        cache = checkIns
        if let fileURL {
            let data = try encoder.encode(checkIns)
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}

extension CheckInClient: DependencyKey {
    public static let testValue = CheckInClient()

    public static let liveValue: CheckInClient = {
        let documents = try! FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let store = CheckInStore(fileURL: documents.appendingPathComponent("checkins.json"))
        return CheckInClient(
            load: { try await store.load() },
            append: { checkIn in _ = try await store.append(checkIn) },
            upsert: { checkIn in _ = try await store.upsert(checkIn) },
            saveAll: { checkIns in try await store.saveAll(checkIns) }
        )
    }()

    public static let previewValue: CheckInClient = {
        let store = CheckInStore(fileURL: nil)
        return CheckInClient(
            load: {
                _ = try await store.append(
                    CheckIn(
                        latitude: 39.9042, longitude: 116.4074,
                        date: .now.addingTimeInterval(-3_600),
                        placeName: "北京市朝阳区", note: "上午的咖啡"
                    )
                )
                return try await store.load()
            },
            append: { checkIn in _ = try await store.append(checkIn) },
            upsert: { checkIn in _ = try await store.upsert(checkIn) },
            saveAll: { checkIns in try await store.saveAll(checkIns) }
        )
    }()
}

public extension DependencyValues {
    var checkInClient: CheckInClient {
        get { self[CheckInClient.self] }
        set { self[CheckInClient.self] = newValue }
    }
}
