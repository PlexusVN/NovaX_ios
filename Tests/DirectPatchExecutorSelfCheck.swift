import Foundation

@main struct DirectPatchExecutorSelfCheck {
    @MainActor static func main() async throws {
        let value = try await DirectPatchExecutor.run(validation: {}) {
            precondition(!Thread.isMainThread)
            try DirectPatchExecutionContext.check()
            return 42
        }
        precondition(value == 42)
        for event in ["AstraNetworkAccessInvalidated", "AstraAuthenticationInvalidated"] {
            do {
                _ = try await DirectPatchExecutor.run(validation: {}) {
                    precondition(!Thread.isMainThread)
                    NotificationCenter.default.post(name: Notification.Name(event), object: nil)
                    try DirectPatchExecutionContext.check()
                    return true
                }
                preconditionFailure("revoked execution continued")
            } catch is CancellationError {}
        }
        let parent = Task {
            try await DirectPatchExecutor.run(validation: {}) {
                for _ in 0..<1000 {
                    try DirectPatchExecutionContext.check()
                    Thread.sleep(forTimeInterval: 0.002)
                }
                preconditionFailure("parent cancellation was not propagated")
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        parent.cancel()
        do { _ = try await parent.value; preconditionFailure("cancelled operation returned") }
        catch is CancellationError {}
        print("[PASS] production direct executor: native work off UI thread, network/auth revocation and parent cancellation")
    }
}
