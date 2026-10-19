import Foundation

@main struct RotationTests {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { print("FAIL: \(name)"); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        let now = Date(timeIntervalSince1970: 1_000)
        let ready = [Node(name: "A"), Node(name: "B"), Node(name: "C")]
        check(NodeRotation.candidates(ready, after: "C", at: now).map(\.name) == ["A", "B", "C"], "最后一个节点之后回到第一个")
        check(NodeRotation.candidates(ready, after: "B", at: now).map(\.name) == ["C", "A", "B"], "轮换顺序覆盖全部节点")
        check(NodeRotation.candidates(ready, after: "missing", at: now).map(\.name) == ["A", "B", "C"], "首次选择从列表开头开始")
        let cooling = [Node(name: "A", coolingUntil: now.addingTimeInterval(10)), Node(name: "B", delay: -1, coolingUntil: now.addingTimeInterval(20))]
        check(NodeRotation.candidates(cooling, after: "B", at: now).isEmpty, "全节点冷却时不强行使用")
        check(NodeRotation.candidates(cooling, after: "B", at: now.addingTimeInterval(10)).map(\.name) == ["A"], "冷却到期自动重新进入候选列表")
        check(NodeRotation.candidates(cooling, after: "A", at: now.addingTimeInterval(20)).first?.name == "B", "测速失败节点到期后允许重新测速")

        var clock = now
        var attempts = 0
        var waits: [Date] = []
        var selected = ""
        try await NodeRotation.selectWhenReady(attempt: {
            attempts += 1
            guard let node = NodeRotation.candidates(cooling, after: "B", at: clock).first else {
                throw NodeRotationError.coolingUntil(now.addingTimeInterval(10))
            }
            // The first recovered route fails its probe and enters another cooldown.
            if attempts == 3 { throw NodeRotationError.coolingUntil(now.addingTimeInterval(20)) }
            selected = node.name
        }, onWait: { waits.append($0) }, sleep: { deadline in
            // Simulate an early wake, then a correct wake, then a failed-probe retry.
            clock = waits.count == 1 ? deadline.addingTimeInterval(-0.2) : deadline
        })
        check(attempts == 4 && waits.count == 3 && selected == "A", "提前唤醒及恢复后测速失败仍持续重试并恢复选择")

        enum ConfigurationError: Error { case noEligibleNodes }
        var invalidAttempts = 0
        do {
            try await NodeRotation.selectWhenReady(attempt: {
                invalidAttempts += 1; throw ConfigurationError.noEligibleNodes
            }, onWait: { _ in check(false, "配置错误不应等待") }, sleep: { _ in check(false, "配置错误不应重试") })
            check(false, "配置错误必须返回")
        } catch ConfigurationError.noEligibleNodes {
            check(invalidAttempts == 1, "无候选节点的配置错误直接返回")
        }

        var cancelAttempts = 0
        let task = Task { @MainActor in
            try await NodeRotation.selectWhenReady(attempt: {
                cancelAttempts += 1
                throw NodeRotationError.coolingUntil(now.addingTimeInterval(600))
            }, onWait: { _ in }, sleep: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                try await NodeRotation.sleepUntil(Date().addingTimeInterval(600))
            })
        }
        do { try await task.value; check(false, "暂停后不应恢复选择") }
        catch is CancellationError { check(cancelAttempts == 1, "冷却等待可立即取消且不继续重试") }
        print("通过 \(passed) 项节点轮换回归测试")
    }
}
