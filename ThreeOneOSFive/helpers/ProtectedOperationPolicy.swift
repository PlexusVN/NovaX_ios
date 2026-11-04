import Foundation

/// Expiration uses monotonic time. The user's clock and timezone cannot extend
/// a lease or incorrectly reject one when the device clock is a little behind.
struct ProtectedLeasePolicy {
    static let minimumTransferValidity: TimeInterval = 75
    private(set) var validUntil: TimeInterval = 0

    mutating func clear() { validUntil = 0 }

    mutating func accept(ttl: TimeInterval, requestStarted: TimeInterval,
                         now: TimeInterval) throws {
        guard ttl.isFinite, ttl > 0, ttl <= 125,
              requestStarted.isFinite, now.isFinite, now >= requestStarted,
              ttl - (now - requestStarted) > Self.minimumTransferValidity else {
            throw ProtectedOperationError.invalidLease
        }
        // Subtract the entire roundtrip, including time spent waiting for the
        // server. Never grant a fresh full TTL on receipt of a delayed response.
        validUntil = requestStarted + ttl
    }

    func permitsTransfer(now: TimeInterval) -> Bool {
        now.isFinite && validUntil - now > Self.minimumTransferValidity
    }
}

enum ProtectedOperationError: Error { case invalidLease, commitsBlocked }

enum ProtectedArtifactRetryPolicy {
    static let maximumRetries = 5
    static func delay(attempt: Int, serverSeconds: Int) -> TimeInterval? {
        guard (0..<maximumRetries).contains(attempt), (1...10).contains(serverSeconds) else { return nil }
        return min(10, max(Double(serverSeconds), pow(2, Double(attempt))))
    }
}

/// A native writer keeps its lease until it actually returns, even if its
/// Swift timeout fires first. Lockdown never interrupts an admitted commit.
enum ReleaseCommitBarrier {
    private static let lock = NSLock()
    private static var blocked = false
    private static var writers = 0

    static var activeWriterCount: Int {
        lock.lock(); defer { lock.unlock() }
        return writers
    }

    static func blockNewCommits() { lock.lock(); blocked = true; lock.unlock() }

    static func requireAllowed() throws {
        lock.lock(); defer { lock.unlock() }
        if blocked { throw ProtectedOperationError.commitsBlocked }
    }

    static func withCommit<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        if blocked { lock.unlock(); throw ProtectedOperationError.commitsBlocked }
        writers += 1
        lock.unlock()
        defer { lock.lock(); writers -= 1; lock.unlock() }
        return try operation()
    }
}
