import Foundation
import Darwin

func freeLocalPort() throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AppError.message("无法创建本地端口") }
    defer { close(fd) }
    var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = 0; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard bound == 0 else { throw AppError.message("无法绑定本地端口") }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
    return Int(UInt16(bigEndian: addr.sin_port))
}

@MainActor final class QueryBrowser {
    // DevTools is a loopback connection. Never send it through a system proxy.
    let localSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()
    var process: Process?; var socket: URLSessionWebSocketTask?; var serial = 0
    var activeProxy: String?; var profile: URL?
    static var executable: String? {
        ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func stop() {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }
    func start(proxy: String?, pageURL: String = "https://www.apple.com.cn/shop/buy-iphone") async throws {
        if socket != nil, process?.isRunning == true, activeProxy == proxy { return }
        stop()
        guard let path = Self.executable else { throw AppError.message("请将 Google Chrome 或 Microsoft Edge 安装到“应用程序”") }
        let port = try freeLocalPort()
        // Every process gets its own profile; an old Chrome process can never steal a restarted session.
        let dir = Paths.root.appendingPathComponent("Browser-\(UUID().uuidString)")
        profile = dir
        let p = Process(); p.executableURL = URL(fileURLWithPath: path)
        var args = ["--headless=new", "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=\(port)", "--user-data-dir=\(dir.path)", "--no-first-run", "--no-default-browser-check", "--disable-background-networking", "--disable-component-update"]
        if let proxy { args.append("--proxy-server=\(proxy)") }
        args.append("about:blank"); p.arguments = args; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); process = p; activeProxy = proxy
        var ws: String?
        for _ in 0..<50 {
            try Task.checkCancellation()
            if !p.isRunning { throw AppError.message("查询浏览器提前退出，请重启监控") }
            if let (data, _) = try? await localSession.data(from: URL(string: "http://127.0.0.1:\(port)/json/list")!), let pages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let page = pages.first(where: { $0["type"] as? String == "page" }) { ws = page["webSocketDebuggerUrl"] as? String }
            if ws != nil { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let ws, let url = URL(string: ws) else { stop(); throw AppError.message("无法连接专用查询浏览器") }
        let s = localSession.webSocketTask(with: url); s.maximumMessageSize = 8 * 1024 * 1024; s.resume(); socket = s
        do {
            _ = try await command("Page.enable", [:])
            _ = try await command("Page.navigate", ["url": pageURL])
        } catch {
            stop()
            if Task.isCancelled { throw CancellationError() }
            throw AppError.message("连接查询浏览器失败（本机 DevTools 通道）：\(error.localizedDescription)。请退出应用后重试，并确认 Chrome / Edge 可以正常启动。")
        }
        for _ in 0..<35 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if let value = try? await evaluate("document.readyState"), value as? String == "complete" { break }
        }
        // Allow the shop's own browser verification to settle.
        if pageURL.hasPrefix("https:") { try await Task.sleep(nanoseconds: 3_000_000_000) }
    }
    func command(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        guard let socket else { throw AppError.message("查询浏览器未连接") }
        serial += 1; let id = serial
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let timeout = Task { try? await Task.sleep(nanoseconds: 50_000_000_000); if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) } }
        defer { timeout.cancel() }
        // Chromium's DevTools endpoint accepts UTF-8 TEXT frames. Sending Data
        // creates a binary WebSocket frame, which can close the connection.
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        while true {
            try Task.checkCancellation()
            let message = try await socket.receive()
            let bytes: Data
            switch message { case .data(let d): bytes = d; case .string(let s): bytes = Data(s.utf8); @unknown default: continue }
            guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], json["id"] as? Int == id else { continue }
            if let error = json["error"] as? [String: Any] { throw AppError.message(error["message"] as? String ?? "浏览器命令失败") }
            return json["result"] as? [String: Any] ?? [:]
        }
    }
    func evaluate(_ expression: String) async throws -> Any {
        let result = try await command("Runtime.evaluate", ["expression": expression, "awaitPromise": true, "returnByValue": true])
        if result["exceptionDetails"] != nil { throw AppError.message("Apple 页面执行失败，请稍后再试") }
        guard let remote = result["result"] as? [String: Any], let value = remote["value"] else { throw AppError.message("浏览器没有返回查询结果") }
        return value
    }
    func fetch(store: String, parts: [String]) async throws -> (Int, Data) {
        var components = URLComponents(string: "https://www.apple.com.cn/shop/retail/pickup-message")!
        components.queryItems = [URLQueryItem(name: "pl", value: "true"), URLQueryItem(name: "mts.0", value: "regular"), URLQueryItem(name: "store", value: store)] + parts.enumerated().map { URLQueryItem(name: "parts.\($0.offset)", value: $0.element) }
        let expression = """
        (async()=>{ const abort=new AbortController(); const timer=setTimeout(()=>abort.abort(),35000); try { const r=await fetch(\(jsonString(components.url!.absoluteString)),{credentials:'same-origin',signal:abort.signal,headers:{'Accept':'application/json','X-Requested-With':'XMLHttpRequest'}}); const body=await r.text(); if(body.length>4194304) throw Error('响应过大');return {status:r.status,body}; }catch(e){return {status:0,body:String(e)};}finally{clearTimeout(timer);} })()
        """
        guard let value = try await evaluate(expression) as? [String: Any], let status = value["status"] as? Int, let body = value["body"] as? String else { throw AppError.message("Apple 响应格式异常") }
        return (status, Data(body.utf8))
    }
    func cleanProfiles() {
        stop()
        // Profiles from this app only. Never touch the user's Chrome or Edge profile.
        if let entries = try? FileManager.default.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for u in entries where u.lastPathComponent.hasPrefix("Browser-") {
                let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: u) }
            }
        }
    }
}
