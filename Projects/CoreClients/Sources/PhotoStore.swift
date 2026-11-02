import Foundation
import UIKit

/// 打卡照片的文件存取（Documents/Photos/<id>.jpg），读取带内存缓存。
///
/// 照片本体不进 TCA 状态与 JSON 记录，`CheckIn.photoIDs` 只持有文件 ID；
/// 写入发生在选择器回调（视图侧），读取发生在列表/地图展示，均为轻量同步操作。
public enum PhotoStore {
    /// 保存一张照片，返回新生成的文件 ID。
    public static func save(_ data: Data) throws -> String {
        let id = UUID().uuidString
        try save(data, as: id)
        return id
    }

    /// 按指定 ID 保存照片（iCloud 下载还原时保持原 ID）。
    public static func save(_ data: Data, as id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(id), options: [.atomic])
    }

    /// 照片文件 URL（不存在返回 nil；供 CloudKit 资产上传直接引用）。
    public static func fileURL(for id: String) -> URL? {
        let url = fileURL(id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 读取照片（命中内存缓存优先）；不存在返回 nil。
    public static func image(for id: String) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL(id)),
              let image = UIImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    /// 删除照片（不存在时静默忽略）。
    public static func delete(_ id: String) {
        cache.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    private static var directory: URL {
        let documents = try! FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return documents.appendingPathComponent("Photos", isDirectory: true)
    }

    private static func fileURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    /// NSCache 本身线程安全，包一层以满足 Swift 6 对 static 属性的 Sendable 要求。
    private final class PhotoCache: NSCache<NSString, UIImage>, @unchecked Sendable {}

    private static let cache: PhotoCache = {
        let cache = PhotoCache()
        cache.countLimit = 300
        return cache
    }()
}
