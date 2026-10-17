import Foundation
@main struct CoreTests {
    @MainActor static func main() throws {
        var passed = 0
        func check(_ yes: Bool, _ name: String) {
            guard yes else { print("FAIL: \(name)"); exit(1) }; passed += 1; print("PASS: \(name)")
        }
        let base = """
        {"body":{"stores":[{"storeNumber":"R001","partsAvailability":{"A":{"pickupDisplay":"available","pickupSearchQuote":"今天"},"B":{"pickupDisplay":"unavailable"},"C":{"pickupDisplay":"ineligible"},"D":{"pickupDisplay":"future_unknown"}}}]}}
        """
        let result = try PickupParser.parse(Data(base.utf8), store:"R001", parts:["A","B","C","D","E"])
        check(result["A"]?.0 == "有货" && result["A"]?.1 == "今天", "正确识别有货和取货日期")
        check(result["B"]?.0 == "无货", "正确识别无货")
        check(result["C"]?.0 == "不支持取货", "不支持取货不混为无货")
        check(result["D"]?.0 == "未确认" && result["E"]?.0 == "未确认", "未知状态和遗漏型号不误报无货")
        do { _ = try PickupParser.parse(Data(base.utf8), store:"MISSING",parts:["A"]); check(false,"缺失门店") } catch { check(true,"缺失门店明确失败") }
        do { _ = try PickupParser.parse(Data("<html>blocked</html>".utf8),store:"R001",parts:["A"]); check(false,"拦截页") } catch { check(true,"拦截页不会成为库存结果") }
        let nestedJSON = """
        {"body":{"content":{"pickupMessage":{"stores":[{"storeNumber":"R001","partsAvailability":{"A":{"pickupDisplay":"available"}}}]}}}}
        """
        check(try PickupParser.parse(Data(nestedJSON.utf8),store:"R001",parts:["A"])["A"]?.0 == "有货","兼容嵌套取货响应")
        let yaml = """
        mixed-port: 7890
        external-controller: 0.0.0.0:9090
        proxies:
          - name: node-one
            type: socks5
            server: example.com
            port: 443
        rules:
          - MATCH,DIRECT
        """
        let block = try ProxyEngine.proxyBlock(yaml)
        check(block.contains("node-one") && !block.contains("external-controller") && !block.contains("MATCH"),"只提取订阅节点，不导入规则和控制器")
        let flush = """
        proxies:
        - name: node-two
          type: socks5
          server: example.com
          port: 443
        """
        check(try ProxyEngine.proxyBlock(flush).hasPrefix("  - name:"),"兼容无缩进节点列表")
        do { _ = try ProxyEngine.proxyBlock("vmess://base64"); check(false,"非YAML订阅") } catch { check(true,"不兼容订阅明确报错") }
        let node = Node(name:"cooling",coolingUntil:Date().addingTimeInterval(600))
        check(!node.available && Node(name:"ready").available,"冷却节点不能参与轮换")
        let prefs = Preferences()
        let restored = try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(prefs))
        check(restored.interval == 30 && !restored.proxy,"默认配置可保存恢复")
        print("通过 \(passed) 项核心测试")
    }
}
