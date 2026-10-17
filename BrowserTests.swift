import Foundation

// Optional integration check: ./test.command --browser
// Launches an isolated Chrome / Edge profile and uses about:blank; no Apple requests.
@main struct BrowserTests {
    @MainActor static func main() async throws {
        let browser = QueryBrowser()
        defer { browser.stop() }
        try await browser.start(proxy: nil, pageURL: "about:blank")
        let answer = try await browser.evaluate("21 * 2")
        guard answer as? Int == 42 else { throw AppError.message("浏览器执行结果错误") }
        for _ in 0..<5 {
            guard try await browser.evaluate("'Austin连接正常'") as? String == "Austin连接正常" else { throw AppError.message("连续通信失败") }
        }
        browser.stop()
        try await browser.start(proxy: nil, pageURL: "about:blank")
        guard try await browser.evaluate("6 * 7") as? Int == 42 else { throw AppError.message("重连失败") }
        print("PASS: 真实浏览器连接、连续文本消息、中文响应、停止后重连")
    }
}
