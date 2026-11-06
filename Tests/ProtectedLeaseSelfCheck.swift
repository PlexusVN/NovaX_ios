import Foundation

@main struct ProtectedLeaseSelfCheck {
    static func require(_ value: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try value() else { throw NSError(domain: label, code: 1) }
        print("[PASS] lease: \(label)")
    }
    static func main() throws {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expires = formatter.string(from: Date().addingTimeInterval(130))
        var lease = ProtectedReleaseLease()
        try require(lease.needsRenewal(now: 1_000), "a new session needs a lease")
        try lease.recordVerifiedResponse(expiresAt: expires, ttl: 120, requestStartedAt: 1_000,
                                        receivedAt: 1_001, expectedGeneration: lease.generation)
        try require(!lease.needsRenewal(now: 1_001), "server TTL anchors cache despite ten seconds of clock skew")
        try require(lease.needsRenewal(now: 1_060), "renew before the next request can exhaust the remaining budget")
        try require(lease.needsRenewal(now: 999), "a reset monotonic clock cannot extend the cache")
        let oldGeneration = lease.generation
        lease.invalidate()
        try require(lease.needsRenewal(now: 1_001), "foreground/logout invalidation discards cache")
        var staleRejected = false
        do {
            try lease.recordVerifiedResponse(expiresAt: expires, ttl: 120, requestStartedAt: 1_000,
                                            receivedAt: 1_001, expectedGeneration: oldGeneration)
        } catch ProtectedReleaseLeaseError.staleGeneration { staleRejected = true }
        try require(staleRejected, "an old foreground response cannot recache authorization")

        // The old once-per-download cache sees 61 seconds at operation start,
        // then resolve/grant each take 20 seconds and content can arrive too late.
        // The real request policy refreshes between these actual protocol steps.
        var clock: TimeInterval = 1_059
        var simulated = ProtectedReleaseLease()
        try simulated.recordVerifiedResponse(expiresAt: expires, ttl: 120, requestStartedAt: 1_000,
                                            receivedAt: 1_000, expectedGeneration: simulated.generation)
        var sequence: [String] = []; var serverExpires: TimeInterval = 1_120
        func send(_ path: String, latency: TimeInterval) throws {
            if ProtectedReleaseLease.required(for: path) && simulated.needsRenewal(now: clock) {
                let began = clock; clock += 2
                try simulated.recordVerifiedResponse(expiresAt: expires, ttl: 120, requestStartedAt: began,
                                                    receivedAt: clock, expectedGeneration: simulated.generation)
                serverExpires = began + 120
                sequence.append("integrity-v2")
            }
            try require(clock < serverExpires, "next protocol request has live server authorization: " + path)
            sequence.append(path); clock += latency
            try require(clock < serverExpires, "request reaches the server before authorization expires: " + path)
        }
        try send("/api/v2/artifacts/resolve", latency: 20)
        try send("/api/v2/artifacts/id/grants", latency: 20)
        try send("/api/v2/artifacts/id/content", latency: 25)
        try require(sequence == ["/api/v2/artifacts/resolve", "integrity-v2", "/api/v2/artifacts/id/grants", "/api/v2/artifacts/id/content"],
                    "slow resolve refreshes before grant without replaying content")
        for path in ["/api/v2/artifacts/sync", "/api/v2/artifacts/resolve", "/api/v2/artifacts/id/grants", "/api/v2/artifacts/id/content"] {
            try require(ProtectedReleaseLease.required(for: path), "all protected request stages require a lease")
        }
        for path in ["/api/v2/security/integrity-v2", "/api/v2/novax/session/open", "/api/v2/novax/session/renew", "/api/v2/novax/logout"] {
            try require(!ProtectedReleaseLease.required(for: path), "renewal/bootstrap cannot recursively request another lease")
        }
        for ttl in [0, -1, 120.5, 121, TimeInterval.infinity, TimeInterval.nan] {
            var policy = ProtectedReleaseLease(); var denied = false
            do { try policy.recordVerifiedResponse(expiresAt: expires, ttl: ttl, requestStartedAt: 100, receivedAt: 101, expectedGeneration: 0) }
            catch { denied = true }
            try require(denied, "invalid signed TTL cannot populate authorization")
        }
        var late = ProtectedReleaseLease(); var lateDenied = false
        do { try late.recordVerifiedResponse(expiresAt: expires, ttl: 120, requestStartedAt: 100, receivedAt: 161, expectedGeneration: 0) }
        catch ProtectedReleaseLeaseError.insufficientTime { lateDenied = true }
        try require(lateDenied && late.needsRenewal(now: 161), "a slow response with no usable budget fails closed")
        var invalid = ProtectedReleaseLease(); var malformedDenied = false
        do { try invalid.recordVerifiedResponse(expiresAt: "not a date", ttl: 120, requestStartedAt: 100, receivedAt: 101, expectedGeneration: 0) }
        catch ProtectedReleaseLeaseError.invalidResponse { malformedDenied = true }
        try require(malformedDenied, "malformed signed expiry is rejected")
    }
}
