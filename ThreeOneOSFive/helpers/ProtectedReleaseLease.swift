import Foundation

enum ProtectedReleaseLeaseError: Error { case invalidResponse, staleGeneration, insufficientTime }

/// Call only after verifying the response signature, purpose, nonce and session.
/// Server TTL starts no earlier than the request, so anchoring it to the request
/// start is conservative and independent of a small client/server clock offset.
struct ProtectedReleaseLease {
    static let maximumTTL: TimeInterval = 120
    static let minimumRequestBudget: TimeInterval = 60
    private(set) var generation: UInt64 = 0
    private var deadline: TimeInterval?
    private var receivedAt: TimeInterval?

    static func required(for path: String) -> Bool { path.hasPrefix("/api/v2/artifacts/") }

    func needsRenewal(now: TimeInterval) -> Bool {
        guard now.isFinite, let deadline, let receivedAt, now >= receivedAt else { return true }
        return deadline - now <= Self.minimumRequestBudget
    }

    mutating func invalidate() {
        generation &+= 1
        deadline = nil; receivedAt = nil
    }

    mutating func recordVerifiedResponse(expiresAt: String, ttl: TimeInterval,
                                        requestStartedAt: TimeInterval, receivedAt: TimeInterval,
                                        expectedGeneration: UInt64) throws {
        guard expectedGeneration == generation else { throw ProtectedReleaseLeaseError.staleGeneration }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard expiresAt.utf8.count <= 64, formatter.date(from: expiresAt) != nil,
              ttl.isFinite, ttl.rounded() == ttl, ttl > 0, ttl <= Self.maximumTTL,
              requestStartedAt.isFinite, receivedAt.isFinite, requestStartedAt >= 0,
              receivedAt >= requestStartedAt else { throw ProtectedReleaseLeaseError.invalidResponse }
        let limit = requestStartedAt + ttl
        guard limit.isFinite, limit - receivedAt > Self.minimumRequestBudget else {
            throw ProtectedReleaseLeaseError.insufficientTime
        }
        deadline = limit; self.receivedAt = receivedAt
    }
}
