import Foundation

enum ExploitSupportPolicy {
    enum Provider { case legacy3105, worseQuery, airLift, unsupported }
    static var currentAccessProvider: Provider = .airLift
}
enum AirLiftError: Error { case executionFailed(String), socketConnectionFailed(String) }
enum FixtureError: Error { case containerUnavailable }
func log(_ message: String) {}

// ACTUAL_FFI_TYPES

final class NativeBoundary: @unchecked Sendable {
    static let shared = NativeBoundary()
    private let lock = NSLock()
    private var calls = 0
    func hit() { lock.lock(); calls += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
}

@MainActor final class AirLiftTunnelManager {
    static let shared = AirLiftTunnelManager()
    var activePeerAddress = "10.7.0.1"
    var isOperational = true
    nonisolated static func remoteXPCHostCandidates() -> [String] { [] }
}
@MainActor final class AirTrafficProtocolClient {
    static let shared = AirTrafficProtocolClient()
    var isBusy = false
    var probes = 0
    var delay: UInt64 = 0
    func verifyPairingWithDevice() async -> (isValid: Bool, isRevoked: Bool, message: String) {
        probes += 1
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return (true, false, "fixture pairing")
    }
}
@MainActor final class StorageEngineCoordinator {
    static let shared = StorageEngineCoordinator()
    var isAirTrafficEngineLinked = true
}
@MainActor final class AirLiftPairingManager {
    static let shared = AirLiftPairingManager()
    enum Status { case ready, verified }
    var status: Status = .ready
}

@MainActor final class NativeHarness {
    fileprivate let ffiWorkState = FFIWorkState()
    let ffiExecutionQueue = DispatchQueue(label: "fixture-native")
    let primaryHost = "10.7.0.1"
    var busy = false
    var finished = false
    var stage: URL?
    func invalidate() { ffiWorkState.invalidate() }
    nonisolated static func configureTargetHosts(_ hosts: [String]) throws { NativeBoundary.shared.hit() }
    // ACTUAL_PROVIDER_GUARD
    // ACTUAL_RUN_BLOCKING
    func call() async throws -> Int { try await runBlocking(name: "fixture", timeout: 0.01) { 3 } }
    func write(until release: DispatchSemaphore, started: NativeBoundary) async throws {
        busy = true
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: path)
        stage = path
        defer { try? FileManager.default.removeItem(at: path); busy = false; finished = true }
        let value: Int = try await runBlocking(name: "fixture-write", timeout: 0.01) {
            started.hit()
            release.wait()
            precondition(FileManager.default.fileExists(atPath: path.path), "payload removed before native completion")
            return 17
        }
        precondition(value == 17)
    }
}

@MainActor final class HealthHarness {
    enum EngineHealthState {
        case idle, checking, healthy(String), error(String)
        var isHealthy: Bool { if case .healthy = self { return true }; return false }
    }
    fileprivate let ffiWorkState = FFIWorkState()
    var isBusy = false
    var engineHealthState: EngineHealthState = .idle
    var lastHealthCheckDate: Date?
    var resolveFails = false
    var delay: UInt64 = 0
    var probes = 0
    func activePairingPath() throws -> String { "fixture-pairing" }
    func verifyPairingWithDevice() async -> (Bool, Bool, String) {
        probes += 1
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return (true, false, "fixture pairing")
    }
    func resolveAppContainer(bundleID: String) async throws -> String {
        if resolveFails { throw FixtureError.containerUnavailable }
        return "/fixture/container"
    }
    // ACTUAL_HEALTH
}

#if os(Linux)
extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() {}
}
#endif

@MainActor final class PairingHarness {
    enum PairingStatus {
        case missing, ready, verified, verifying, revoked, waitingSettings
        var isPaired: Bool { self == .ready || self == .verified }
    }
    enum PairingError: Error { case busy }
    var status: PairingStatus = .ready
    var isVerifyingPairing = false
    var verificationGeneration: UInt64 = 0
    var pairingGeneration: UInt64 = 5
    var pairingThreadActive = true
    var pairingPIN = ""
    var pairingFilePath: String?
    var showAlert = false
    var statusReads = 0, backups = 0, notifications = 0
    let pairingFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    func checkPairingStatus() { statusReads += 1 }
    func notify(message: String) { notifications += 1 }
    func backupPairingDataToKeychain(_ data: Data) { backups += 1 }
    static func isSupportedPairingRecord(_ record: [String: Any]) -> Bool { record["fixture"] as? Bool == true }
    // ACTUAL_PAIR_VERIFY
    // ACTUAL_PAIR_CANCEL
    // ACTUAL_PAIR_IMPORT
    // ACTUAL_PAIR_PIN
}

@MainActor final class TunnelHarness {
    enum TunnelStatus { case checking, connected, disconnected }
    enum ServiceStatus { case unavailable, checking, reachable, routeReady, unreachable }
    struct TunnelProbeResult: Sendable {
        let routeDetected: Bool, portResponsive: Bool, serviceReachable: Bool
        let activeHost: String, message: String
    }
    nonisolated static let routes = NativeBoundary()
    let peerAddress = "10.7.0.1", fallbackPeerAddress = "172.16.0.1"
    var status: TunnelStatus = .disconnected
    var serviceStatus: ServiceStatus = .unavailable
    var lastErrorMessage: String?
    var isTunnelRouteDetected = false, isPortResponsive = false, isEnabled = false
    var activePeerAddress = "10.7.0.1"
    var probeGeneration: UInt64 = 0
    var pendingProbe: Task<TunnelProbeResult, Never>?
    nonisolated static func hasTunnelRoute(to host: String) -> Bool {
        routes.hit()
        Thread.sleep(forTimeInterval: 0.02)
        return true
    }
    nonisolated static func probeTcpPort(host: String, port: UInt16, timeoutSec: Double) -> (reachable: Bool, connected: Bool) {
        (true, true)
    }
    // ACTUAL_TUNNEL_PROBE
    // ACTUAL_TUNNEL_CANCEL
}

@main struct AirLiftIsolationSelfCheck {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool) { precondition(condition()); checks += 1 }
        let originalNativeCalls = NativeBoundary.shared.count
        for provider in [ExploitSupportPolicy.Provider.legacy3105, .worseQuery, .unsupported] {
            ExploitSupportPolicy.currentAccessProvider = provider
            let native = NativeHarness()
            do { _ = try await native.call(); preconditionFailure("inactive provider reached native") } catch {}
            let pairing = PairingHarness()
            await pairing.verifyPairingWithDevice()
            check(pairing.statusReads == 0)
            check(!pairing.importPairingFile(from: URL(fileURLWithPath: "/missing-fixture")))
            check(pairing.backups == 0 && pairing.notifications == 0)
            pairing.showPIN("123456", generation: 5)
            check(pairing.pairingPIN.isEmpty)
            let health = HealthHarness()
            let result = await health.checkRealAirLiftHealth()
            check(!result.isHealthy && health.probes == 0)
        }
        check(NativeBoundary.shared.count == originalNativeCalls)

        let tunnel = TunnelHarness()
        let routeCalls = TunnelHarness.routes.count
        await tunnel.verifyLoopbackService()
        check(TunnelHarness.routes.count == routeCalls)
        ExploitSupportPolicy.currentAccessProvider = .airLift
        await tunnel.verifyLoopbackService()
        check(tunnel.isTunnelRouteDetected && tunnel.status == .connected)
        check(tunnel.serviceStatus == .reachable)
        let probing = Task { await tunnel.verifyLoopbackService() }
        try await Task.sleep(nanoseconds: 5_000_000)
        tunnel.cancelPendingChecks()
        await probing.value
        check(!tunnel.isTunnelRouteDetected && tunnel.status == .disconnected)

        ExploitSupportPolicy.currentAccessProvider = .airLift
        let active = NativeHarness()
        let result = try await active.call()
        check(result == 3)

        // Invalidation/provider changes after enqueue still block the native entry.
        for changeProvider in [false, true] {
            ExploitSupportPolicy.currentAccessProvider = .airLift
            let queued = NativeHarness()
            queued.ffiExecutionQueue.suspend()
            let before = NativeBoundary.shared.count
            let call = Task { try await queued.call() }
            try await Task.sleep(nanoseconds: 30_000_000)
            if changeProvider { ExploitSupportPolicy.currentAccessProvider = .worseQuery }
            else { queued.invalidate() }
            queued.ffiExecutionQueue.resume()
            do { _ = try await call.value; preconditionFailure("stale queued native work ran") } catch {}
            check(NativeBoundary.shared.count == before)
        }

        // A cancelled caller which has not crossed the native boundary must
        // never configure the native hosts or run FFI after its queue resumes.
        ExploitSupportPolicy.currentAccessProvider = .airLift
        let cancelledQueue = NativeHarness()
        cancelledQueue.ffiExecutionQueue.suspend()
        let beforeCancelled = NativeBoundary.shared.count
        var queuedFinished = false
        let cancelledCall = Task {
            defer { queuedFinished = true }
            return try await cancelledQueue.call()
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        check(!queuedFinished) // The diagnostic deadline cannot release ownership.
        cancelledCall.cancel()
        cancelledQueue.ffiExecutionQueue.resume()
        do { _ = try await cancelledCall.value; preconditionFailure("cancelled queued work entered native") }
        catch is CancellationError {}
        check(queuedFinished)
        check(NativeBoundary.shared.count == beforeCancelled)
        let nextQueuedResult = try await cancelledQueue.call()
        check(nextQueuedResult == 3) // A cancelled queued invocation releases its slot.

        let beforePrecancelled = NativeBoundary.shared.count
        let precancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cancelledQueue.call()
        }
        do { _ = try await precancelled.value; preconditionFailure("pre-cancelled caller entered native") }
        catch is CancellationError {}
        check(NativeBoundary.shared.count == beforePrecancelled)

        // Deadline and Task cancellation cannot return the writer or release its
        // stage/exclusive slot while the native boundary still owns the payload.
        ExploitSupportPolicy.currentAccessProvider = .airLift
        let writing = NativeHarness(), started = NativeBoundary(), release = DispatchSemaphore(value: 0)
        let write = Task { try await writing.write(until: release, started: started) }
        while started.count == 0 { try await Task.sleep(nanoseconds: 1_000_000) }
        try await Task.sleep(nanoseconds: 40_000_000)
        write.cancel()
        try await Task.sleep(nanoseconds: 10_000_000)
        check(writing.busy && !writing.finished)
        check(FileManager.default.fileExists(atPath: writing.stage!.path))
        do { _ = try await writing.call(); preconditionFailure("overlapping native work ran") } catch {}
        check(writing.busy)
        release.signal()
        try await write.value
        check(!writing.busy && writing.finished)
        check(!FileManager.default.fileExists(atPath: writing.stage!.path))
        let after = try await writing.call()
        check(after == 3)

        let health = HealthHarness()
        health.resolveFails = true
        let unavailable = await health.checkRealAirLiftHealth()
        check(!unavailable.isHealthy && !health.engineHealthState.isHealthy)
        health.resolveFails = false
        let available = await health.checkRealAirLiftHealth()
        check(available.isHealthy && health.engineHealthState.isHealthy)
        let lateHealth = HealthHarness(); lateHealth.delay = 30_000_000
        let checking = Task { await lateHealth.checkRealAirLiftHealth() }
        try await Task.sleep(nanoseconds: 5_000_000)
        lateHealth.ffiWorkState.invalidate()
        let lateResult = await checking.value
        check(!lateResult.isHealthy)

        let pairing = PairingHarness()
        AirTrafficProtocolClient.shared.delay = 30_000_000
        let verifying = Task { await pairing.verifyPairingWithDevice() }
        try await Task.sleep(nanoseconds: 5_000_000)
        pairing.cancelPendingChecks()
        await verifying.value
        check(pairing.status != .verified)
        pairing.showPIN("late", generation: 4)
        check(pairing.pairingPIN.isEmpty)
        pairing.showPIN("valid", generation: 5)
        check(pairing.pairingPIN == "valid")

        // An inactive provider must preserve the existing pairing bytes.
        let old = Data("previous pairing".utf8)
        try old.write(to: pairing.pairingFileURL)
        ExploitSupportPolicy.currentAccessProvider = .worseQuery
        check(!pairing.importPairingFile(from: URL(fileURLWithPath: "/does-not-exist")))
        let preserved = try Data(contentsOf: pairing.pairingFileURL)
        check(preserved == old)
        try FileManager.default.removeItem(at: pairing.pairingFileURL)
        print("AirLift isolation actual-body checks passed: \(checks)")
    }
}
