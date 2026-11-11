import Foundation
import Combine

enum ScanFixtureError: LocalizedError {
    case denied
    var errorDescription: String? { "fixture query denied" }
}

@main struct ContainerScanProgressSelfCheck {
    @MainActor static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor static func main() async throws {
        let model = ContainerScanProgress(historyURL: nil)
        var publishedOffMain = false
        let subscription = model.$snapshot.dropFirst().sink { _ in
            if !Thread.isMainThread { publishedOffMain = true }
        }
        defer { subscription.cancel() }
        precondition(model.snapshot.phase == .idle && !model.isPresented)
        let path = try await Task.detached {
            try model.track(bundleID: "com.fixture.game") { id in
                model.report(id, scanned: 2_000_000, total: 3_000_000, candidates: 15, grants: 12, message: "fixture real range")
                return "/fixture/game"
            }
        }.value
        await drainMainQueue()
        precondition(path == "/fixture/game" && model.snapshot.phase == .resolved)
        precondition(model.snapshot.scanned == 2_000_000 && model.snapshot.grants == 12)
        precondition(abs(model.snapshot.fraction - 2.0 / 3.0) < 0.001 && model.isPresented)
        precondition(model.shareText.contains("fixture real range"))
        model.dismiss(); await drainMainQueue()
        precondition(!model.isPresented)
        model.showHistory(); await drainMainQueue()
        precondition(model.isPresented && model.snapshot.phase == .resolved)

        do {
            _ = try await Task.detached {
                try model.track(bundleID: "com.fixture.game") { _ in throw ScanFixtureError.denied }
            }.value
            preconditionFailure("query failure was swallowed")
        } catch ScanFixtureError.denied {}
        await drainMainQueue()
        precondition(model.snapshot.phase == .failed && model.snapshot.detail == "fixture query denied")

        do {
            _ = try await Task.detached {
                try model.track(bundleID: "com.fixture.game") { id in
                    model.requestCancellation()
                    try model.checkCancellation(id)
                    preconditionFailure("cancelled discovery continued")
                }
            }.value
            preconditionFailure("cancel was swallowed")
        } catch is CancellationError {}
        await drainMainQueue()
        precondition(model.snapshot.phase == .cancelled && !model.cancelPending)

        _ = try await Task.detached {
            try model.track(bundleID: "com.fixture.game") { id in
                for index in 1...260 {
                    model.report(id, scanned: UInt64(index), total: 1_000, candidates: 0, grants: 0, message: "range \(index)")
                }
                return "/fixture/game"
            }
        }.value
        await drainMainQueue()
        precondition(model.snapshot.logs.count <= 200)
        precondition(model.snapshot.logs.contains { $0.contains("range 260") })
        precondition(!publishedOffMain, "worker published observable state off the UI thread")

        let history = FileManager.default.temporaryDirectory.appendingPathComponent("astra-scan-fixture-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: history) }
        var interrupted = ContainerScanSnapshot(id: UUID(), bundleID: "com.fixture.game", phase: .scanning)
        interrupted.scanned = 750_000; interrupted.total = 2_000_000
        interrupted.logs = ["saved real progress"]
        try JSONEncoder().encode(interrupted).write(to: history)
        let restored = ContainerScanProgress(historyURL: history)
        precondition(restored.snapshot.phase == .interrupted && !restored.isPresented)
        precondition(restored.snapshot.scanned == 750_000 && restored.snapshot.logs.contains("saved real progress"))
        try Data("corrupt history".utf8).write(to: history)
        precondition(ContainerScanProgress(historyURL: history).snapshot.phase == .idle)
        print("[PASS] production scan monitor: background reports, UI-thread publication, success/failure/cancel, bounded logs, copied history and interrupted restart without auto-scan")
    }
}
