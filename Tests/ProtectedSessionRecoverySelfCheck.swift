import Foundation

private enum SessionCheckError: Error { case failed(String) }
@main struct ProtectedSessionRecoverySelfCheck {
    static var checks=0
    static func require(_ value:@autoclosure () -> Bool,_ label:String) throws {
        guard value() else { throw SessionCheckError.failed(label) }; checks += 1
    }
    @MainActor static func main() async throws {
        do {
            let flow=SessionRecoveryHarness()
            try await flow.run()
            try require(flow.opens==1 && flow.probes==0 && flow.clears==0,"healthy bootstrap unchanged")
        }
        do {
            let flow=SessionRecoveryHarness();flow.controller.pending=true
            try await flow.run()
            try require(flow.controller.events == ["pending","recover","open"],"durable candidate precedes old bootstrap")
            try require(flow.replacements==0,"lost response retries exact pending keys without a second ticket")
        }
        for code in ["session_expired","session_required","device_key_invalid","device_signature_invalid"] {
            let flow=SessionRecoveryHarness();flow.failures=[ProtectedDownloadError.rejected(code),nil]
            try await flow.run()
            try require(flow.opens==2 && flow.probes==0 && flow.replacements==0,"same-key retry succeeds: "+code)
        }
        for code in ["device_already_enrolled","device_recovery_required","device_key_revoked","device_revoked"] {
            let denied=SessionRecoveryHarness();denied.failures=[ProtectedDownloadError.rejected(code)]
            do { try await denied.run();throw SessionCheckError.failed("missing ticket accepted") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(denied.probes==1 && denied.replacements==0,"revocation only permits a ticket probe: "+code)
            let approved=SessionRecoveryHarness();approved.authorized=true;approved.failures=[ProtectedDownloadError.rejected(code),nil]
            try await approved.run()
            try require(approved.opens==2 && approved.probes==1 && approved.replacements==1,"authorized replacement once: "+code)
        }
        for error in [DeviceIdentityError.identityMissing,DeviceIdentityError.invalidIdentity] {
            let flow=SessionRecoveryHarness();flow.authorized=true;flow.failures=[error,nil]
            try await flow.run()
            try require(flow.probes==1 && flow.replacements==1,"missing identity reaches ticketed recovery")
        }
        for error:Error in [DeviceIdentityError.keychain(-25308),DeviceIdentityError.keychain(-34018),
            DeviceIdentityError.ambiguousIdentity,URLError(.timedOut),CancellationError(),ProtectedDownloadError.invalidResponse,
            ProtectedDownloadError.rejected("key_banned"),ProtectedDownloadError.rejected("key_revoked"),
            ProtectedDownloadError.rejected("key_expired"),ProtectedDownloadError.rejected("hwid_mismatch"),
            ProtectedDownloadError.rejected("device_quarantined"),ProtectedDownloadError.rejected("license_policy_banned"),
            ProtectedDownloadError.rejected("replay_detected")] {
            let flow=SessionRecoveryHarness();flow.authorized=true;flow.failures=[error]
            do { try await flow.run();throw SessionCheckError.failed("ineligible failure ignored") }
            catch is SessionCheckError { throw SessionCheckError.failed("ineligible failure ignored") }
            catch {}
            try require(flow.opens==1 && flow.probes==0 && flow.replacements==0,"network, storage and policy failures preserve identity")
        }
        do {
            let flow=SessionRecoveryHarness();flow.authorized=true
            flow.failures=[ProtectedDownloadError.rejected("device_key_invalid"),ProtectedDownloadError.rejected("device_key_invalid"),nil]
            try await flow.run()
            try require(flow.opens==3 && flow.probes==1,"same-key retry and recovery are both bounded")
        }
        do {
            let flow=SessionRecoveryHarness();flow.authorized=true
            flow.failures=[ProtectedDownloadError.rejected("device_already_enrolled"),ProtectedDownloadError.rejected("device_key_revoked")]
            do { try await flow.run();throw SessionCheckError.failed("recursive recovery") }
            catch ProtectedDownloadError.rejected("device_key_revoked") {}
            try require(flow.opens==2 && flow.probes==1,"failed replacement never recursively recovers")
        }
        do {
            let flow=SessionRecoveryHarness();flow.authorized=true
            flow.failures=[ProtectedDownloadError.rejected("device_already_enrolled")]
            flow.afterOpen={flow.contextEpoch += 1}
            do { try await flow.run();throw SessionCheckError.failed("stale context recovered") }
            catch is CancellationError {}
            try require(flow.probes==0 && flow.replacements==0,"cancelled context cannot ask for recovery")
        }
        do {
            let flow=SessionRecoveryHarness();flow.controller.pending=true
            flow.recoveryFailure=URLError(.networkConnectionLost)
            do { try await flow.run();throw SessionCheckError.failed("pending failure ignored") }
            catch is URLError {}
            try require(flow.opens==0 && flow.probes==1 && flow.controller.pending,"pending failure never falls back to old identity")
        }
        for code in ["device_key_revoked","device_revoked","device_recovery_required"] {
            let flow=SessionRecoveryHarness();flow.cachedSession=true;flow.authorized=true
            flow.catalogFailures=[ProtectedDownloadError.rejected(code),nil]
            flow.failures=[ProtectedDownloadError.rejected("device_already_enrolled"),nil]
            try await flow.catalog()
            try require(flow.catalogs==2 && flow.probes==1 && flow.opens==2,"admin reset with cached session recovers inside the same catalog operation")
            try require(!flow.controller.events.contains("cached"),"revoked cached session cannot skip fresh bootstrap")
        }
        do {
            let flow=SessionRecoveryHarness();flow.authorized=true
            flow.catalogFailures=[ProtectedDownloadError.rejected("session_expired"),ProtectedDownloadError.rejected("device_key_revoked")]
            do { try await flow.catalog();throw SessionCheckError.failed("catalog retry loop") }
            catch ProtectedDownloadError.rejected("device_key_revoked") {}
            try require(flow.catalogs==2,"catalog retries at most once")
        }
        for error:Error in [URLError(.timedOut),ProtectedDownloadError.rejected("device_quarantined"),ProtectedDownloadError.rejected("key_banned")] {
            let flow=SessionRecoveryHarness();flow.authorized=true;flow.catalogFailures=[error]
            do { try await flow.catalog();throw SessionCheckError.failed("ineligible catalog failure retried") }
            catch is SessionCheckError { throw SessionCheckError.failed("ineligible catalog failure retried") }
            catch {}
            try require(flow.catalogs==1 && flow.probes==0 && flow.opens==0,"catalog policy and network failures do not reenroll")
        }
        print("Production session recovery orchestration: \(checks) checks passed")
    }
}
