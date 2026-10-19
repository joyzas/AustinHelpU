import Foundation
import Security

struct Product: Codable, Identifiable, Hashable {
    var id: String; var name: String; var family: String; var capacity: String; var color: String; var part: String
}
struct Store: Codable, Identifiable, Hashable {
    var id: String; var name: String; var city: String; var state: String; var address: String; var postal: String
}
struct Monitor: Codable, Identifiable {
    var id = UUID(); var product: Product; var store: Store
    var status = "待查询"; var detail = "等待第一轮查询"; var checked: Date? = nil
    var inStock = false
}
struct Subscription: Codable, Identifiable {
    var id = UUID(); var name: String; var enabled = true
}
struct Preferences: Codable {
    var monitors: [Monitor] = []
    var subscriptions: [Subscription] = []
    var interval = 30; var rotateMinutes = 5
    var proxy = false; var timedRotation = false
    var sound = true; var notification = true; var bark = false
    var pauseOnHit = false; var preventSleep = true; var repeatAlert = false
    var nodeFilter = ""; var excludedNodes: [String] = []
}
struct LogEntry: Identifiable {
    let id = UUID(); let date = Date(); var text: String; var warning = false
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let value): return value } }
}
enum Paths {
    static var root: URL {
        let path = ProcessInfo.processInfo.environment["XZ_DATA_ROOT"]
        let u = path.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("XiaozhangWatch")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return u
    }
}
enum Vault {
    static func get(_ key: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cn.xiaozhang.watch", kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    @discardableResult static func set(_ key: String, _ value: String) -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cn.xiaozhang.watch", kSecAttrAccount as String: key]
        if value.isEmpty { SecItemDelete(q as CFDictionary); return true }
        let data = Data(value.utf8)
        let result = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return true }
        var entry = q; entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }
}
func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let array = String(data: data, encoding: .utf8)!
    return String(array.dropFirst().dropLast())
}
func loadResource<T: Decodable>(_ name: String, as type: T.Type) -> T? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}
enum PickupParser {
    static func parse(_ data: Data, store: String, parts: [String]) throws -> [String: (String, String)] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let body = root["body"] as? [String: Any] else { throw AppError.message("Apple 返回结构变化：缺少 body") }
        let nested = body["content"] as? [String: Any]
        let pickup = nested?["pickupMessage"] as? [String: Any]
        guard let stores = (body["stores"] ?? pickup?["stores"]) as? [[String: Any]] else { throw AppError.message("Apple 暂未返回门店数据") }
        guard let shop = stores.first(where: { $0["storeNumber"] as? String == store }) else { throw AppError.message("响应中未包含目标门店，不能确认库存") }
        guard let statuses = shop["partsAvailability"] as? [String: [String: Any]] else { throw AppError.message("Apple 返回结构变化：缺少型号状态") }
        var result: [String: (String, String)] = [:]
        for part in parts {
            guard let p = statuses[part], let display = p["pickupDisplay"] as? String else { result[part] = ("未确认", "未返回该型号"); continue }
            let quote = p["pickupSearchQuote"] as? String ?? p["pickupQuote"] as? String ?? ""
            switch display {
            case "available": result[part] = ("有货", quote.isEmpty ? "可到店取货" : quote)
            case "unavailable": result[part] = ("无货", quote.isEmpty ? "目前无法到店取货" : quote)
            case "ineligible": result[part] = ("不支持取货", quote)
            default: result[part] = ("未确认", "Apple 状态：\(display) \(quote)")
            }
        }
        return result
    }
}
