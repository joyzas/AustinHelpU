import Foundation

struct Node: Identifiable {
    var id: String { name }; var name: String; var delay: Int? = nil
    var failures = 0; var coolingUntil: Date? = nil
    func isAvailable(at date: Date) -> Bool { coolingUntil.map { $0 <= date } ?? true }
    var available: Bool { isAvailable(at: Date()) }
}

enum NodeRotationError: Error {
    case coolingUntil(Date)
}

enum NodeRotation {
    // Start after the current node and wrap around, including a recovered current node last.
    static func candidates(_ nodes: [Node], after current: String, at date: Date = Date()) -> [Node] {
        let start = nodes.firstIndex(where: { $0.name == current }).map { $0 + 1 } ?? 0
        return (Array(nodes.dropFirst(start)) + Array(nodes.prefix(start))).filter { $0.isAvailable(at: date) }
    }

    // Only temporary node exhaustion is retryable. Configuration errors still surface normally.
    @MainActor static func selectWhenReady(
        attempt: () async throws -> Void,
        onWait: (Date) -> Void,
        sleep: (Date) async throws -> Void = sleepUntil
    ) async throws {
        while true {
            try Task.checkCancellation()
            do {
                try await attempt()
                try Task.checkCancellation()
                return
            } catch NodeRotationError.coolingUntil(let deadline) {
                try Task.checkCancellation()
                onWait(deadline)
                try await sleep(deadline)
            }
        }
    }

    static func sleepUntil(_ deadline: Date) async throws {
        // Keep the fractional second; waking early must never terminate monitoring.
        let seconds = max(1, deadline.timeIntervalSinceNow)
        try await Task.sleep(nanoseconds: UInt64(ceil(seconds * 1_000_000_000)))
    }
}
