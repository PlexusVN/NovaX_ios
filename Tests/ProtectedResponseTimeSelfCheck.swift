import Foundation

enum TimeCheckFailure: Error { case failed(String) }

@main
struct ProtectedResponseTimeSelfCheck {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TimeCheckFailure.failed(message) }
        checks += 1
    }
    static func main() throws {
        let date = ProtectedResponseTime.httpDate("Tue, 17 Nov 2026 05:20:41 GMT")!
        let start: TimeInterval = 100
        let receipt: TimeInterval = 100.4
        let anchor = ProtectedResponseTime(serverDate: date, requestStartedAt: start, receivedAt: receipt)!
        let now = anchor.verificationDate(at: 100.6)!
        try check(abs(now.timeIntervalSince(date) - 1.6) < 0.001, "full RTT and precision margin required")
        // The device wall clock is deliberately absent from the verified sample.
        // Ahead/behind clocks and a later wall-clock edit cannot change its TTL.
        for offset: TimeInterval in [-86400, -60, -1, 0, 1, 60, 86400] {
            let deviceDate = date.addingTimeInterval(offset)
            _ = deviceDate
            try check(anchor.verificationDate(at: 100.6) == now, "wall clock changed trusted response time")
        }
        let issued = Int64(date.timeIntervalSince1970)
        let expiry = issued + 60
        try check(issued <= Int64(now.timeIntervalSince1970), "fresh grant incorrectly appears future")
        try check(Int64(now.timeIntervalSince1970) < expiry, "fresh grant should remain valid")
        let expired = anchor.verificationDate(at: receipt + 60)!
        try check(Int64(expired.timeIntervalSince1970) >= expiry, "clock correction extended absolute expiry")
        let slow = ProtectedResponseTime(serverDate: date, requestStartedAt: 10, receivedAt: 75)!
        try check(Int64(slow.verificationDate(at: 75)!.timeIntervalSince1970) >= expiry,
                  "slow response must not restart grant TTL on receipt")
        try check(anchor.verificationDate(at: receipt - 0.01) == nil, "backward uptime accepted")
        try check(anchor.verificationDate(at: receipt + 301) == nil, "stale anchor accepted")
        try check(anchor.verificationDate(at: .infinity) == nil, "nonfinite uptime accepted")
        try check(ProtectedResponseTime(serverDate: date, requestStartedAt: 2, receivedAt: 1) == nil, "negative RTT accepted")
        try check(ProtectedResponseTime(serverDate: date, requestStartedAt: 1, receivedAt: 182) == nil, "unbounded RTT accepted")
        try check(ProtectedResponseTime(serverDate: date, requestStartedAt: .nan, receivedAt: 1) == nil, "NaN request accepted")
        try check(ProtectedResponseTime(serverDate: Date(timeIntervalSince1970: .infinity),
              requestStartedAt: 1, receivedAt: 2) == nil, "invalid server date accepted")
        for invalid: String? in [nil, "", "not a date", String(repeating: "x", count: 65)] {
            try check(ProtectedResponseTime.httpDate(invalid) == nil, "invalid HTTP date accepted")
        }
        print("[PASS] \(checks) production trusted-response time checks; local clock independent, absolute expiry retained")
    }
}
