import Foundation

enum OperationCheckError: Error { case failed(String) }

@main
struct ProtectedOperationSelfCheck {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw OperationCheckError.failed(message) }
    }

    static func main() throws {
        var lease = ProtectedLeasePolicy()
        try lease.accept(ttl: 120, requestStarted: 1000, now: 1002)
        try require(lease.permitsTransfer(now: 1002), "fresh monotonic lease")
        try require(!lease.permitsTransfer(now: 1104), "16 seconds must trigger renewal")
        try require(!lease.permitsTransfer(now: 1045), "75-second boundary triggers renewal")
        lease.clear()
        try require(!lease.permitsTransfer(now: 1002), "logout clears lease")
        for ttl in [0.0, -1, 126, Double.infinity, Double.nan] {
            do {
                try lease.accept(ttl: ttl, requestStarted: 0, now: 0)
                throw OperationCheckError.failed("accepted invalid TTL")
            } catch ProtectedOperationError.invalidLease {}
        }
        do {
            try lease.accept(ttl: 120, requestStarted: 1000, now: 1050)
            throw OperationCheckError.failed("accepted excessively delayed lease")
        } catch ProtectedOperationError.invalidLease {}
        for attempt in 0..<ProtectedArtifactRetryPolicy.maximumRetries {
            try require(ProtectedArtifactRetryPolicy.delay(attempt: attempt, serverSeconds: 2) != nil,
                        "bounded retry available")
        }
        try require(ProtectedArtifactRetryPolicy.delay(attempt: 5, serverSeconds: 2) == nil, "retry bound")
        try require(ProtectedArtifactRetryPolicy.delay(attempt: 0, serverSeconds: 999) == nil, "reject untrusted delay")

        // Simulate a native canary/writer whose completion outlives Swift work.
        let entered = DispatchSemaphore(value: 0), finish = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { done.signal() }
            try? ReleaseCommitBarrier.withCommit {
                entered.signal()
                _ = finish.wait(timeout: .now() + 5)
            }
        }
        try require(entered.wait(timeout: .now() + 5) == .success, "native commit started")
        ReleaseCommitBarrier.blockNewCommits()
        try require(ReleaseCommitBarrier.activeWriterCount == 1, "lockdown preserves native commit")
        do {
            try ReleaseCommitBarrier.withCommit { throw OperationCheckError.failed("must not execute") }
            throw OperationCheckError.failed("admitted commit after lockdown")
        } catch ProtectedOperationError.commitsBlocked {}
        finish.signal()
        try require(done.wait(timeout: .now() + 5) == .success, "native commit finishes")
        try require(ReleaseCommitBarrier.activeWriterCount == 0, "commit drains")
        print("Protected lease, bounded retry and native commit checks passed")
    }
}
