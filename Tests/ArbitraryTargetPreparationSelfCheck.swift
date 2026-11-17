import Foundation

enum PreparationFixtureError: Error { case failed(String), offline }

final class PreparationCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var denied = Set<String>()
    func operation(_ targets: [String], _ force: Bool) throws -> [String: String] {
        lock.lock(); recorded.append(targets); let denied = self.denied; lock.unlock()
        try Task.checkCancellation()
        return Dictionary(uniqueKeysWithValues: targets.filter { !denied.contains($0) }.map {
            ($0, "/fixture/" + $0)
        })
    }
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
}

@main
struct ArbitraryTargetPreparationSelfCheck {
    @MainActor
    static func main() async throws {
        var checks = 0
        func require(_ value: Bool, _ detail: String) throws {
            guard value else { throw PreparationFixtureError.failed(detail) }
            checks += 1
        }
        let custom = "com.example.Editor", other = "Com.Example-App.Reader"
        let calls = PreparationCalls(), progress = ContainerScanProgress()
        let preparation = IOS27ContainerPreparation(progress: progress, operation: { try calls.operation($0, $1) })
        var loads = 0
        preparation.configureTargetLoader { loads += 1; return [custom] }
        await preparation.prepareIfNeeded()
        try require(preparation.state == .ready, "custom-only device could not enter preparation")
        try require(calls.calls == [[custom]], "preparation searched hardcoded legacy applications")
        try require(loads == 1, "authenticated catalog was not fetched once")
        try require(IOS27ContainerSession.path(for: custom) == "/fixture/" + custom, "custom root not published")
        try require(IOS27ContainerSession.path(for: "com.dts.freefireth") == nil, "unrequested game root published")
        preparation.enterApplication()
        try require(preparation.didContinue, "verified custom preparation could not continue")
        preparation.configureTargetLoader { loads += 1; return [other] }
        await preparation.prepareIfNeeded()
        try require(loads == 1 && calls.calls == [[custom]], "repeated setup discarded ready roots")
        try await preparation.prepareAdditionalTargets(bundleIDs: [other])
        try require(calls.calls == [[custom], [other]], "new catalog target skipped lazy verification")
        try require(IOS27ContainerSession.path(for: custom) != nil && IOS27ContainerSession.path(for: other) != nil,
                    "lazy target replaced another verified root")

        let emptyCalls = PreparationCalls()
        let empty = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try emptyCalls.operation($0, $1) })
        empty.configureTargetLoader { [] }
        await empty.prepareIfNeeded()
        try require(empty.state == .ready && emptyCalls.calls.isEmpty, "empty authenticated catalog dispatched native work")
        try require(IOS27ContainerSession.path(for: custom) == nil, "empty catalog retained a previous preparation's roots")
        empty.enterApplication()
        try require(empty.didContinue, "empty catalog prevented the user from entering the app")
        try await empty.prepareAdditionalTargets(bundleIDs: [custom])
        try require(emptyCalls.calls == [[custom]], "later catalog target bypassed lazy preparation")

        let retryCalls = PreparationCalls()
        let retry = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try retryCalls.operation($0, $1) })
        var attempt = 0
        retry.configureTargetLoader {
            attempt += 1
            if attempt == 1 { throw PreparationFixtureError.offline }
            return [custom]
        }
        await retry.prepareIfNeeded()
        try require(retry.state == .failed && !retry.didContinue && retryCalls.calls.isEmpty,
                    "failed catalog was accepted as an empty catalog")
        await retry.prepareIfNeeded()
        try require(retry.state == .ready && attempt == 2 && retryCalls.calls == [[custom]],
                    "catalog retry did not fetch and prepare the custom target")

        let staleCalls = PreparationCalls()
        let stale = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try staleCalls.operation($0, $1) })
        var pending: CheckedContinuation<[String], Error>?
        stale.configureTargetLoader { try await withCheckedThrowingContinuation { pending = $0 } }
        let operation = Task { await stale.prepareIfNeeded() }
        while pending == nil { await Task.yield() }
        stale.reset()
        pending!.resume(returning: [custom])
        await operation.value
        try require(stale.state == .idle && !stale.didContinue && staleCalls.calls.isEmpty,
                    "late catalog completion after logout started native work")
        try require(IOS27ContainerSession.path(for: custom) == nil, "late catalog completion published an old root")

        let cancelledCalls = PreparationCalls()
        let cancelled = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try cancelledCalls.operation($0, $1) })
        var cancelledLoader: CheckedContinuation<[String], Error>?
        cancelled.configureTargetLoader { try await withCheckedThrowingContinuation { cancelledLoader = $0 } }
        let cancelledOperation = Task { await cancelled.prepareIfNeeded() }
        while cancelledLoader == nil { await Task.yield() }
        cancelled.cancel()
        try require(cancelled.state == .failed && !cancelled.didContinue && cancelledCalls.calls.isEmpty,
                    "cancel while fetching catalog did not stop preparation immediately")
        cancelled.configureTargetLoader { [other] }
        await cancelled.prepareIfNeeded()
        try require(cancelled.state == .failed && cancelledCalls.calls.isEmpty,
                    "automatic view task restarted a cancelled preparation")
        await cancelled.prepareIfNeeded(force: true)
        try require(cancelled.state == .ready && cancelledCalls.calls == [[other]],
                    "explicit retry after cancelling catalog did not prepare new targets")
        cancelledLoader!.resume(returning: [custom])
        await cancelledOperation.value
        try require(cancelled.state == .ready && IOS27ContainerSession.path(for: other) != nil
                    && IOS27ContainerSession.path(for: custom) == nil,
                    "cancelled catalog completion replaced the successful retry")

        let idleCalls = PreparationCalls()
        let idle = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try idleCalls.operation($0, $1) })
        var idleLoads = 0
        idle.configureTargetLoader { idleLoads += 1; return [custom] }
        idle.cancel()
        await idle.prepareIfNeeded()
        try require(idle.state == .failed && idleLoads == 0 && idleCalls.calls.isEmpty,
                    "cancel before delayed view startup was ignored")
        await idle.prepareIfNeeded(force: true)
        try require(idle.state == .ready && idleLoads == 1 && idleCalls.calls == [[custom]],
                    "explicit retry did not clear an idle cancellation")

        let malformedCalls = PreparationCalls()
        let malformed = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try malformedCalls.operation($0, $1) })
        malformed.configureTargetLoader { ["com..invalid"] }
        await malformed.prepareIfNeeded()
        try require(malformed.state == .failed && malformedCalls.calls.isEmpty,
                    "malformed catalog target reached native preparation")

        let deniedCalls = PreparationCalls(); deniedCalls.denied = [custom]
        let denied = IOS27ContainerPreparation(progress: ContainerScanProgress(), operation: { try deniedCalls.operation($0, $1) })
        denied.configureTargetLoader { [custom] }
        await denied.prepareIfNeeded()
        try require(denied.state == .ready, "verified environment could not enter preparation")
        denied.enterApplication()
        try require(denied.didContinue, "verified environment could not continue to app")
        do {
            try await denied.prepareAdditionalTargets(bundleIDs: [custom])
            try require(false, "denied target succeeded during patch preparation")
        } catch WorseQueryError.containerDiscoveryFailed {}
        print("[PASS] \(checks) production authenticated catalog/preparation checks with isolated native boundaries")
    }
}
