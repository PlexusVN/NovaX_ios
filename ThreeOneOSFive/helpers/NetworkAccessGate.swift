import Foundation
import Combine

enum NetworkProbeResult: Equatable, Sendable {
    case allowed
    case blocked(String)
    case unavailable(String)
}

extension Notification.Name {
    /// Only application API sessions observe this; the isolated probe does not.
    static let astraNetworkAccessInvalidated = Notification.Name("AstraNetworkAccessInvalidated")
}

enum NetworkAccessError: LocalizedError {
    case denied(String)
    case networkChanged
    var errorDescription: String? {
        switch self {
        case .denied(let detail): return detail
        case .networkChanged: return "Kết nối bảo mật đã thay đổi. Hãy kiểm tra lại trước khi tiếp tục."
        }
    }
}

/// Foundation-only state transitions use a monotonic clock, not the user clock.
/// A previously verified connection does not authorize work after its short lease.
struct NetworkAccessPolicy {
    static let pollingInterval: TimeInterval = 5
    // Permit a full bounded 10-second reprobe plus scheduling margin after the
    // next five-second poll starts; a healthy 2s mobile RTT must not cancel
    // every in-flight API request at the old six-second boundary.
    static let leaseDuration: TimeInterval = 17
    enum State: Equatable { case checking, allowed, blocked, unavailable }
    private(set) var state: State = .checking
    private(set) var generation: UInt64 = 0
    private(set) var detail: String?
    private(set) var allowedAt: TimeInterval?
    let maximumAge: TimeInterval

    init(maximumAge: TimeInterval = NetworkAccessPolicy.leaseDuration) { self.maximumAge = maximumAge }

    func isAllowed(now: TimeInterval) -> Bool {
        guard state == .allowed, let allowedAt else { return false }
        return now >= allowedAt && now - allowedAt < maximumAge
    }

    mutating func invalidate(_ state: State, detail: String? = nil) {
        generation &+= 1
        self.state = state
        self.detail = detail
        allowedAt = nil
    }

    mutating func record(_ result: NetworkProbeResult, now: TimeInterval) {
        switch result {
        case .allowed:
            state = .allowed; detail = nil; allowedAt = now
        case .blocked(let reason): invalidate(.blocked, detail: reason)
        case .unavailable(let reason): invalidate(.unavailable, detail: reason)
        }
    }

    func permits(_ expectedGeneration: UInt64, now: TimeInterval) -> Bool {
        expectedGeneration == generation && isAllowed(now: now)
    }
}

/// This gate verifies Astra's own network path. It neither enumerates installed
/// roots nor observes iOS Certificate Trust Settings switches.
@MainActor
final class NetworkAccessGate: ObservableObject {
    typealias State = NetworkAccessPolicy.State
    static let shared = NetworkAccessGate()
    @Published private(set) var state: State = .checking
    @Published private(set) var failureDetail: String?

    private var policy = NetworkAccessPolicy()
    private var active = false
    private var epoch: UInt64 = 0
    private var pending: (id: UUID, epoch: UInt64, task: Task<NetworkProbeResult, Never>)?
    private var pollingTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private let probe: @Sendable () async -> NetworkProbeResult
    private let clock: () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let automaticallyPoll: Bool

    private convenience init() {
        self.init(probe: { await NetworkSecurityGuard.shared.probeConnection() })
    }

    init(probe: @escaping @Sendable () async -> NetworkProbeResult,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
         }, automaticallyPoll: Bool = true) {
        self.probe = probe; self.clock = clock; self.sleep = sleep
        self.automaticallyPoll = automaticallyPoll
    }

    var isAllowed: Bool { active && policy.isAllowed(now: clock()) }

    var blockingMessage: String? {
        if isAllowed { return nil }
        switch state {
        case .checking: return "Đang kiểm tra kết nối bảo mật..."
        case .blocked:
            return failureDetail ?? "Kết nối chưa đáp ứng yêu cầu bảo mật. Hãy tắt proxy rồi kiểm tra lại."
        case .allowed, .unavailable:
            return failureDetail ?? "Chưa xác minh được kết nối bảo mật. Hãy kiểm tra mạng rồi thử lại."
        }
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        epoch &+= 1
        pending?.task.cancel(); pending = nil
        pollingTask?.cancel(); pollingTask = nil
        expiryTask?.cancel(); expiryTask = nil
        invalidate(active ? .checking : .unavailable,
                   detail: active ? nil : "Ứng dụng cần hoạt động để xác minh kết nối bảo mật.")
        guard active else { return }
        if automaticallyPoll {
            Task { [weak self] in await self?.checkNow() }
            pollingTask = Task { [weak self, sleep] in
                while !Task.isCancelled {
                    do { try await sleep(NetworkAccessPolicy.pollingInterval) } catch { return }
                    guard let self, self.active, !Task.isCancelled else { return }
                    // Keep a five-second cadence independent of probe latency.
                    // checkNow deduplicates these calls against the same task.
                    Task { [weak self] in await self?.checkNow() }
                }
            }
        }
    }

    func checkNow() async {
        guard active else { return }
        if !policy.isAllowed(now: clock()), state == .allowed {
            invalidate(.checking)
        }
        if pending == nil {
            let task = Task { [probe] in await probe() }
            pending = (UUID(), epoch, task)
        }
        guard let current = pending else { return }
        let result = await current.task.value
        // An old probe cannot unlock a new foreground epoch or a later failure.
        guard active, current.epoch == epoch, pending?.id == current.id else { return }
        pending = nil
        let wasAllowed = policy.isAllowed(now: clock())
        policy.record(result, now: clock())
        publish()
        if case .allowed = result {
            scheduleLeaseExpiry()
        } else {
            expiryTask?.cancel(); expiryTask = nil
            if wasAllowed { notifyInvalidation() }
        }
    }

    func requireAllowed() async throws -> UInt64 {
        try Task.checkCancellation()
        guard active else { throw NetworkAccessError.denied(blockingMessage ?? "Ứng dụng chưa hoạt động.") }
        if !policy.isAllowed(now: clock()) { await checkNow() }
        try Task.checkCancellation()
        guard isAllowed else { throw NetworkAccessError.denied(blockingMessage ?? "Chưa xác minh được kết nối.") }
        return policy.generation
    }

    func validateGeneration(_ generation: UInt64) throws {
        guard active, policy.permits(generation, now: clock()) else {
            if state == .allowed, !policy.isAllowed(now: clock()) { invalidate(.checking) }
            throw NetworkAccessError.networkChanged
        }
    }

    /// A rejected API TLS challenge revokes an allowed probe immediately. It is
    /// not a report of all trusted roots and never creates a server strike.
    func rejectPinnedConnection() {
        epoch &+= 1
        pending?.task.cancel(); pending = nil
        expiryTask?.cancel(); expiryTask = nil
        invalidate(.blocked, detail: "Không thể xác minh chứng chỉ máy chủ. Nếu đang dùng ProxyPin hoặc proxy HTTPS, hãy tắt proxy rồi kiểm tra lại.")
    }

    func recordCertificateFailure() { rejectPinnedConnection() }

    private func scheduleLeaseExpiry() {
        expiryTask?.cancel()
        guard automaticallyPoll else { return }
        let verifiedAt = policy.allowedAt
        expiryTask = Task { [weak self, sleep] in
            do { try await sleep(self?.policy.maximumAge ?? NetworkAccessPolicy.leaseDuration) } catch { return }
            guard let self, self.active, !Task.isCancelled,
                  self.policy.allowedAt == verifiedAt, !self.policy.isAllowed(now: self.clock()) else { return }
            self.invalidate(.checking)
        }
    }

    private func invalidate(_ state: State, detail: String? = nil) {
        policy.invalidate(state, detail: detail)
        publish()
        notifyInvalidation()
    }

    private func publish() { state = policy.state; failureDetail = policy.detail }
    private func notifyInvalidation() {
        NotificationCenter.default.post(name: .astraNetworkAccessInvalidated, object: nil)
    }
}
