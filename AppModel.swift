import SwiftUI
import AppKit
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var preferences = Preferences()
    @Published var products: [Product] = []
    @Published var stores: [Store] = []
    @Published var nodes: [Node] = []
    @Published var logs: [LogEntry] = []
    @Published var running = false
    @Published var querying = false
    @Published var busyProxy = false
    @Published var currentNode = "未启用代理"
    @Published var proxyMessage = "导入订阅，让Austin使用专用查询线路"
    @Published var nextCheck: Date? = nil
    @Published var rounds = 0
    @Published var page = "监控台"
    @Published var error: String? = nil
    @Published var showAdd = false
    @Published var demo = false
    let browser = QueryBrowser(); let proxy = ProxyEngine()
    var loop: Task<Void, Never>?
    var lastRotation = Date.distantPast
    var lastAlert: [UUID: Date] = [:]
    var caffeinate: Process?
    let config = Paths.root.appendingPathComponent("settings.json")
    var inStockCount: Int { preferences.monitors.filter { $0.inStock && $0.status == "有货" }.count }
    var cityCount: Int { Set(preferences.monitors.map { $0.store.city }).count }
    var eligibleNodes: [Node] {
        nodes.filter { !preferences.excludedNodes.contains($0.name) && (preferences.nodeFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(preferences.nodeFilter)) }
    }
    init() {
        if let data = try? Data(contentsOf: config), let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = saved
            // Persist selections, never advertise last launch's stock as current.
            for i in preferences.monitors.indices { preferences.monitors[i].status = "待查询"; preferences.monitors[i].inStock = false; preferences.monitors[i].detail = "重新查询后更新库存" }
        }
        products = loadResource("products", as: [Product].self) ?? []
        stores = loadResource("stores", as: [Store].self) ?? []
        // Existing monitor selections retain their identity and settings.
        for i in preferences.monitors.indices {
            preferences.monitors[i].product.name = preferences.monitors[i].product.name.replacingOccurrences(of: "iPhone duo", with: "iPhone Duo")
            preferences.monitors[i].product.family = preferences.monitors[i].product.family.replacingOccurrences(of: "iPhone duo", with: "iPhone Duo")
        }
        log("Austin准备好了。添加想要的 iPhone 和门店，开始蹲守。")
    }
    func persist() {
        do { try JSONEncoder().encode(preferences).write(to: config, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path) }
        catch { self.error = "配置保存失败：\(error.localizedDescription)" }
    }
    func log(_ message: String, warning: Bool = false) {
        logs.insert(LogEntry(text: message, warning: warning), at: 0)
        if logs.count > 500 { logs.removeLast(logs.count - 500) }
    }
    func add(products chosen: Set<String>, stores selected: Set<String>) {
        stop()
        for p in products where chosen.contains(p.id) {
            for s in stores where selected.contains(s.id) {
                if !preferences.monitors.contains(where: { $0.product.id == p.id && $0.store.id == s.id }) { preferences.monitors.append(Monitor(product: p, store: s)) }
            }
        }
        persist(); log("监控列表已更新，共 \(preferences.monitors.count) 项。")
    }
    func remove(_ id: UUID) { stop(); preferences.monitors.removeAll { $0.id == id }; persist() }
    func start() {
        guard !running else { return }
        guard !preferences.monitors.isEmpty else { showAdd = true; return }
        guard !demo else { error = "当前为界面演示，请先退出演示再开始真实监控"; return }
        running = true
        if preferences.preventSleep {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate"); p.arguments = ["-i", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]; try? p.run(); caffeinate = p
        }
        loop = Task {
            defer { querying = false; nextCheck = nil; running = false; browser.stop(); caffeinate?.terminate(); caffeinate = nil; loop = nil }
            do {
                while !Task.isCancelled {
                    querying = true; nextCheck = nil
                    if preferences.proxy {
                        if !proxy.isRunning { try await setupProxy(); try await rotate(reason: "首次选择线路", coolCurrent: false) }
                        if currentNode == "未启用代理" || currentNode.isEmpty || !eligibleNodes.contains(where: { $0.name == currentNode && $0.available }) {
                            if !eligibleNodes.contains(where: \.available), let earliest = eligibleNodes.compactMap(\.coolingUntil).min() {
                                querying = false; nextCheck = earliest
                                log("所有可选节点暂时不可用，等待冷却结束。", warning: true)
                                try await Task.sleep(nanoseconds: UInt64(max(1, earliest.timeIntervalSinceNow)) * 1_000_000_000)
                                querying = true; nextCheck = nil
                            }
                            try await rotate(reason: "选择可用线路", coolCurrent: false)
                        }
                        if preferences.timedRotation && Date().timeIntervalSince(lastRotation) >= Double(preferences.rotateMinutes * 60) { try await rotate(reason: "定时轮换", coolCurrent: false) }
                    }
                    try await browser.start(proxy: preferences.proxy ? "http://127.0.0.1:\(proxy.port)" : nil)
                    rounds += 1; log("第 \(rounds) 轮查询开始 · \(preferences.proxy ? currentNode : "系统网络")")
                    var hit = false; var blocked = false; var connectionFailed = false
                    let groups = Dictionary(grouping: preferences.monitors, by: { $0.store.id })
                    for key in groups.keys.sorted() {
                        let group = groups[key]!
                        let parts = Array(Set(group.map { $0.product.part })).sorted()
                        for offset in stride(from: 0, to: parts.count, by: 20) {
                            try Task.checkCancellation()
                            let batch = Array(parts[offset..<min(offset+20, parts.count)])
                            do {
                                let (status, data) = try await browser.fetch(store: key, parts: batch)
                                if [403, 429, 541].contains(status) {
                                    markUnknown("网站暂时拒绝查询（HTTP \(status)）")
                                    log("网站暂时拒绝本轮查询（HTTP \(status)），停止本轮请求并等待。", warning: true)
                                    blocked = true; break
                                }
                                guard status == 200 else { throw AppError.message(status == 0 ? "网络请求失败或超时" : "Apple 返回 HTTP \(status)") }
                                let result = try PickupParser.parse(data, store: key, parts: batch)
                                for i in preferences.monitors.indices where preferences.monitors[i].store.id == key && batch.contains(preferences.monitors[i].product.part) {
                                    let old = preferences.monitors[i].inStock
                                    let id = preferences.monitors[i].id
                                    let value = result[preferences.monitors[i].product.part] ?? ("未确认", "未返回该型号")
                                    preferences.monitors[i].status = value.0; preferences.monitors[i].detail = value.1; preferences.monitors[i].checked = Date(); preferences.monitors[i].inStock = value.0 == "有货"
                                    if value.0 == "有货" {
                                        hit = true
                                        if !old || (preferences.repeatAlert && Date().timeIntervalSince(lastAlert[id] ?? .distantPast) >= 300) {
                                            lastAlert[id] = Date(); await notify(preferences.monitors[i])
                                        }
                                    }
                                }
                            } catch is CancellationError { throw CancellationError() }
                            catch {
                                if Task.isCancelled { throw CancellationError() }
                                markUnknown(error.localizedDescription, store: key, parts: batch)
                                log("\(group.first?.store.name ?? key)：\(error.localizedDescription)", warning: true)
                                if error is URLError { browser.stop(); connectionFailed = true; break }
                            }
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                        if blocked || connectionFailed { break }
                    }
                    persist()
                    if hit && preferences.pauseOnHit { log("蹲到有货，已按设置暂停。"); break }
                    if blocked || connectionFailed {
                        browser.stop()
                        if preferences.proxy {
                            do { try await rotate(reason: "网站拒绝当前线路", coolCurrent: true) }
                            catch { log(error.localizedDescription, warning: true) }
                        }
                    } else if preferences.proxy, let index = nodes.firstIndex(where: { $0.name == currentNode }) { nodes[index].failures = 0 }
                    querying = false
                    // No unbounded rapid retry: all failures wait at least the configured round interval.
                    var wait = max(15, preferences.interval)
                    if blocked { wait = max(wait, 60) }
                    if preferences.proxy && !eligibleNodes.contains(where: \.available), let earliest = eligibleNodes.compactMap(\.coolingUntil).min() { wait = max(wait, Int(earliest.timeIntervalSinceNow) + 1) }
                    nextCheck = Date().addingTimeInterval(Double(wait))
                    log("第 \(rounds) 轮结束 · \(wait) 秒后继续")
                    try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { log(error.localizedDescription, warning: true); self.error = error.localizedDescription } }
        }
    }
    func stop() {
        // running stays true until cancellation unwinds, preventing two query loops.
        loop?.cancel(); browser.stop()
        if loop == nil { running = false; querying = false; nextCheck = nil }
        if let p = caffeinate, p.isRunning { p.terminate() }; caffeinate = nil
    }
    func markUnknown(_ detail: String, store: String? = nil, parts: [String]? = nil) {
        for i in preferences.monitors.indices where (store == nil || preferences.monitors[i].store.id == store) && (parts == nil || parts!.contains(preferences.monitors[i].product.part)) {
            // Keep the last positive flag for alert de-duplication, but status is always unknown on failure.
            preferences.monitors[i].status = "未确认"; preferences.monitors[i].detail = detail; preferences.monitors[i].checked = Date()
        }
    }
    func setupProxy() async throws {
        busyProxy = true; defer { busyProxy = false }
        let oldNodes = nodes
        let loaded = try await proxy.start(subscriptions: preferences.subscriptions)
        nodes = loaded.map { n in oldNodes.first(where: { $0.name == n.name }) ?? n }
        currentNode = ""; proxyMessage = "订阅已加载，共 \(nodes.count) 个节点"
        log(proxyMessage)
    }
    func rotate(reason: String, coolCurrent: Bool) async throws {
        if coolCurrent, let index = nodes.firstIndex(where: { $0.name == currentNode }) {
            nodes[index].failures += 1
            let minutes = [5,10,20,30][min(nodes[index].failures-1, 3)]
            nodes[index].coolingUntil = Date().addingTimeInterval(Double(minutes * 60))
            log("\(currentNode) 进入 \(minutes) 分钟冷却", warning: true)
        }
        let eligible = eligibleNodes
        let start = eligible.firstIndex(where: { $0.name == currentNode }).map { $0 + 1 } ?? 0
        let ordered = eligible.isEmpty ? [] : Array(eligible.dropFirst(start)) + Array(eligible.prefix(start))
        for node in ordered where node.available {
            try Task.checkCancellation()
            do {
                let delay = try await proxy.delay(node.name)
                try await proxy.select(node.name)
                if let i = nodes.firstIndex(where: { $0.name == node.name }) { nodes[i].delay = delay }
                browser.stop() // Close all owned old HTTP connections, then re-establish shop session.
                currentNode = node.name; lastRotation = Date(); log("已切换到 \(node.name) · \(reason)"); return
            } catch {
                if let i = nodes.firstIndex(where: { $0.name == node.name }) { nodes[i].coolingUntil = Date().addingTimeInterval(60); nodes[i].delay = -1 }
            }
        }
        throw AppError.message("没有可用节点：请检查订阅、筛选条件，或等待节点冷却结束")
    }
    func refreshProxy() {
        guard !running, !busyProxy else { return }
        Task { do { try await setupProxy(); try await rotate(reason: "更新订阅", coolCurrent: false) } catch { self.proxyMessage = error.localizedDescription; self.error = error.localizedDescription; self.log(error.localizedDescription, warning: true) } }
    }
    func addSubscription(name: String, url: String) -> Bool {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), parsed.scheme == "https", parsed.host != nil else { error = "请输入有效的 HTTPS 订阅地址"; return false }
        let sub = Subscription(name: name.isEmpty ? "我的订阅" : name)
        guard Vault.set("subscription-\(sub.id.uuidString)", parsed.absoluteString) else { error = "无法把订阅凭证保存到钥匙串"; return false }
        preferences.subscriptions.append(sub); persist(); return true
    }
    func deleteSubscription(_ id: UUID) { Vault.set("subscription-\(id.uuidString)", ""); preferences.subscriptions.removeAll { $0.id == id }; persist() }
    func installCore() {
        guard !busyProxy, !running else { return }; busyProxy = true; proxyMessage = "正在从官方发布下载并校验代理组件…"
        Task { defer { busyProxy = false }; do { try await proxy.download(); proxyMessage = "代理组件已安装，添加订阅后点击加载节点"; log(proxyMessage) } catch { proxyMessage = error.localizedDescription; self.error = error.localizedDescription } }
    }
    func importCore() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.message = "选择已解压的 mihomo macOS 可执行文件"
        if panel.runModal() == .OK, let url = panel.url { do { try proxy.install(url); proxyMessage = "代理组件已导入"; objectWillChange.send() } catch { self.error = error.localizedDescription } }
    }
    func openProduct(_ product: Product) {
        var c = URLComponents(string: "https://www.apple.com.cn/shop/product/\(product.part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
        c.queryItems = []; if let u = c.url { NSWorkspace.shared.open(u) }
    }
    func notify(_ monitor: Monitor) async {
        let text = "\(monitor.store.city) · \(monitor.store.name)\n\(monitor.product.name)\n\(monitor.detail)"
        log("蹲到了！\(text.replacingOccurrences(of: "\n", with: " · "))")
        if preferences.sound { NSSound(named: "Glass")?.play() }
        if preferences.notification {
            let center = UNUserNotificationCenter.current()
            if (try? await center.requestAuthorization(options: [.alert, .sound])) == true {
                let content = UNMutableNotificationContent(); content.title = "Austin蹲到了 · iPhone 有货"; content.body = text; content.sound = .default
                content.userInfo = ["part": monitor.product.part]
                try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } else { log("Mac 通知未获授权，请在系统通知设置中允许AustinHelpU。", warning: true) }
        }
        if preferences.bark { await sendBark(title: "Austin蹲到了 · iPhone 有货", body: text) }
    }
    func sendBark(title: String, body: String) async {
        let address = Vault.get("bark")
        guard let url = URL(string: address), url.scheme == "https", !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else { log("Bark 地址缺失或格式错误", warning: true); return }
        do {
            var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 15; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["title": title, "body": body, "group": "AustinHelpU"])
            let (data, r) = try await URLSession.shared.data(for: req)
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (r as? HTTPURLResponse)?.statusCode == 200, payload?["code"] as? Int == 200 else { throw AppError.message("推送服务未确认成功") }
            log("Bark 推送已送出，请确认手机实际收到。")
        } catch { log("Bark 推送失败，请检查地址和网络", warning: true) }
    }
    func testAlert() {
        Task {
            if preferences.sound { NSSound(named: "Glass")?.play() }
            if preferences.notification {
                let center = UNUserNotificationCenter.current()
                if (try? await center.requestAuthorization(options: [.alert, .sound])) == true {
                    let c = UNMutableNotificationContent(); c.title = "AustinHelpU · 提醒测试"; c.body = "这是测试消息，不代表商品有货。"; c.sound = .default
                    try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
                } else { log("通知权限未开启，请在系统设置中允许通知。", warning: true) }
            }
            if preferences.bark { await sendBark(title: "AustinHelpU · 提醒测试", body: "这是测试消息，不代表商品有货。") }
            log("已执行提醒测试；请确认声音和通知是否收到。")
        }
    }
    func toggleDemo() {
        guard !running else { return }
        demo.toggle()
        log(demo ? "已进入界面演示：演示结果不会请求 Apple、发送提醒或保存。" : "已退出演示，真实结果需开始监控后查询。")
    }
    var displayedMonitors: [Monitor] {
        if !demo { return preferences.monitors }
        guard let p = products.first(where: { $0.family.contains("18 Pro") }), !stores.isEmpty else { return [] }
        return stores.filter { $0.city == "北京" }.prefix(4).enumerated().map { i, s in var m = Monitor(product: p, store: s); m.status = i == 1 ? "有货" : "无货"; m.detail = i == 1 ? "演示：今天可取货" : "演示：目前无法到店取货"; m.checked = Date(); m.inStock = i == 1; return m }
    }
    func exportLogs() {
        let p = NSSavePanel(); p.nameFieldStringValue = "AustinHelpU-日志.txt"
        if p.runModal() == .OK, let url = p.url { try? logs.reversed().map { "\($0.date.formatted()) \($0.text)" }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
    }
    func shutdown() { stop(); proxy.stop() }
}
