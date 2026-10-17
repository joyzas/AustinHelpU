import Foundation
import CryptoKit
import Darwin

@MainActor final class ProxyEngine {
    var process: Process?; var port = 0; var controller = 0; var secret = UUID().uuidString
    let group = "Austin专用"
    var binary: URL { Paths.root.appendingPathComponent("mihomo") }
    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binary.path) }
    var isRunning: Bool { process?.isRunning == true }
    func stop() { if let process, process.isRunning { process.terminate() }; process = nil }
    func api(_ path: String, method: String = "GET", object: [String: Any]? = nil) async throws -> Any {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(controller)\(path)")!); request.timeoutInterval = 12; request.httpMethod = method
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let object { request.httpBody = try JSONSerialization.data(withJSONObject: object); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppError.message("代理控制接口请求失败") }
        return data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data)
    }
    func download() async throws {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")!); request.timeoutInterval = 25
        request.setValue("AustinHelpU/0.1.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let release = try JSONSerialization.jsonObject(with: data) as? [String: Any], let assets = release["assets"] as? [[String: Any]] else { throw AppError.message("无法读取官方代理组件发布信息") }
        #if arch(arm64)
        let architecture = "darwin-arm64"
        #else
        let architecture = "darwin-amd64-compatible"
        #endif
        guard let asset = assets.first(where: { let n = $0["name"] as? String ?? ""; return n.hasPrefix("mihomo-\(architecture)-v") && n.hasSuffix(".gz") }), let address = asset["browser_download_url"] as? String, let url = URL(string: address), url.host == "github.com", let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") else { throw AppError.message("官方发布未提供适配版本或 SHA-256 校验值，可手动导入 mihomo 可执行文件") }
        var downloadRequest = URLRequest(url: url); downloadRequest.timeoutInterval = 180
        let (archive, r) = try await URLSession.shared.data(for: downloadRequest)
        guard (r as? HTTPURLResponse)?.statusCode == 200, archive.count < 100_000_000 else { throw AppError.message("代理组件下载失败或文件过大") }
        let actual = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard actual == String(digest.dropFirst(7)) else { throw AppError.message("代理组件 SHA-256 校验不通过，已停止安装") }
        let gz = Paths.root.appendingPathComponent("mihomo-download.gz"); try archive.write(to: gz, options: .atomic); defer { try? FileManager.default.removeItem(at: gz) }
        let candidate = Paths.root.appendingPathComponent("mihomo-candidate")
        FileManager.default.createFile(atPath: candidate.path, contents: nil, attributes: [.posixPermissions: 0o700])
        let output = try FileHandle(forWritingTo: candidate); defer { try? output.close() }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); p.arguments = ["-dc", gz.path]; p.standardOutput = output; p.standardError = FileHandle.nullDevice; try p.run()
        while p.isRunning { try await Task.sleep(nanoseconds: 100_000_000) }
        guard p.terminationStatus == 0 else { throw AppError.message("代理组件解压失败") }
        try install(candidate)
        try? FileManager.default.removeItem(at: candidate)
    }
    func install(_ url: URL) throws {
        stop()
        let data = try Data(contentsOf: url)
        guard data.count > 1_000_000 else { throw AppError.message("所选文件不是有效的代理内核") }
        try data.write(to: binary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    }
    static func proxyBlock(_ text: String) throws -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let index = lines.firstIndex(where: { $0.hasPrefix("proxies:") }) else { throw AppError.message("订阅不是 Clash YAML 格式，请使用供应商的 Clash / mihomo 订阅链接") }
        guard lines[index].trimmingCharacters(in: .whitespaces) == "proxies:" else { throw AppError.message("首版支持标准多行 proxies 配置，请换用 Clash YAML 订阅") }
        var block: [String] = []
        for line in lines.dropFirst(index+1) {
            if let first = line.first, !first.isWhitespace, first != "-", first != "#" { break }
            block.append(line)
        }
        guard block.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("-") }) else { throw AppError.message("订阅中没有可用节点") }
        // Reject YAML anchors/tags that could reference content outside the extracted node list.
        guard !block.contains(where: { $0.contains("!!") || $0.contains("!<") || $0.contains("<<:") }) else { throw AppError.message("此订阅使用了暂不支持的 YAML 引用或标签，请提供普通 Clash 节点订阅") }
        // Prefix every extracted line so nodes are consistently nested beneath proxies.
        let nonempty = block.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let indent = nonempty.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        return block.map { "  " + String($0.dropFirst(min(indent, $0.prefix(while: { $0 == " " }).count))) }.joined(separator: "\n")
    }
    func start(subscriptions: [Subscription]) async throws -> [Node] {
        stop()
        guard isInstalled else { throw AppError.message("请先在代理设置里安装或导入 mihomo 组件") }
        let enabled = subscriptions.filter(\.enabled)
        guard !enabled.isEmpty else { throw AppError.message("请先添加并启用代理订阅") }
        var blocks: [String] = []
        for sub in enabled {
            let address = Vault.get("subscription-\(sub.id.uuidString)")
            guard let url = URL(string: address), url.scheme == "https", url.host != nil else { throw AppError.message("订阅地址缺失或无效，请重新添加 HTTPS 订阅") }
            var request = URLRequest(url: url); request.timeoutInterval = 30
            request.setValue("clash.meta", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 5_000_000, let text = String(data: data, encoding: .utf8) else { throw AppError.message("订阅“\(sub.name)”获取失败，请检查链接和网络") }
            blocks.append(try Self.proxyBlock(text))
        }
        port = try freeLocalPort(); controller = try freeLocalPort(); secret = UUID().uuidString
        while controller == port { controller = try freeLocalPort() }
        let config = """
        mixed-port: \(port)
        bind-address: 127.0.0.1
        allow-lan: false
        mode: rule
        log-level: warning
        ipv6: false
        external-controller: 127.0.0.1:\(controller)
        secret: \(jsonString(secret))
        profile:
          store-selected: false
        dns:
          enable: false
        proxies:
        \(blocks.joined(separator: "\n"))
        proxy-groups:
          - name: \(jsonString(group))
            type: select
            include-all: true
        rules:
          - MATCH,\(group)
        """
        let path = Paths.root.appendingPathComponent("proxy.yaml")
        try Data(config.utf8).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        let p = Process(); p.executableURL = binary; p.arguments = ["-d", Paths.root.path, "-f", path.path]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); process = p
        for _ in 0..<60 {
            try Task.checkCancellation()
            if !p.isRunning { throw AppError.message("代理内核退出：订阅含重复节点名、不兼容协议或无效配置，请检查订阅") }
            if let result = try? await api("/proxies") as? [String: Any], let proxies = result["proxies"] as? [String: [String: Any]], let entry = proxies[group], let names = entry["all"] as? [String] {
                let nodes = names.filter { !["DIRECT", "REJECT", "GLOBAL", group].contains($0) && !(proxies[$0]?["type"] as? String ?? "").contains("Selector") }.map { Node(name: $0) }
                guard !nodes.isEmpty else { throw AppError.message("代理启动成功，但没有可选节点") }
                return nodes
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        stop(); throw AppError.message("代理组件启动超时")
    }
    func select(_ name: String) async throws {
        let encoded = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        _ = try await api("/proxies/\(encoded)", method: "PUT", object: ["name": name])
    }
    func delay(_ name: String) async throws -> Int {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let target = "https://www.gstatic.com/generate_204".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let value = try await api("/proxies/\(escaped)/delay?timeout=4000&url=\(target)") as? [String: Any]
        guard let delay = value?["delay"] as? Int, delay > 0 else { throw AppError.message("节点连接超时") }
        return delay
    }
}
