// Compile with the extracted ACTUAL recovery policy and error declarations.
// No network, Keychain, production credentials or authorization mutations.
import Foundation

private enum RecoveryCheckError: Error { case failed(String) }

@main struct ProtectedRecoverySelfCheck {
    static var count = 0
    static func require(_ value: @autoclosure () -> Bool, _ label: String) throws {
        guard value() else { throw RecoveryCheckError.failed(label) }
        count += 1
    }
    static func main() throws {
        let binding = String(repeating: "a", count: 64)
        let base: [String: Any] = ["success": true, "license_binding": binding,
            "challenge_id": UUID().uuidString.lowercased(),
            "challenge": Data(repeating: 9, count: 32).base64EncodedString(),
            "key_id": 7, "recovery_authorized": true]
        func parsed(_ value: [String: Any], expected: Int? = 7) -> ProtectedRecoveryChallenge? {
            ProtectedRecoveryChallenge(value, licenseBinding: binding, expectedKeyID: expected)
        }
        try require(parsed(base)?.recoveryAuthorized == true, "matching signed authorization is usable")
        try require(parsed(base, expected: nil)?.keyID == 7, "first known server ID remains positive and signed")
        var changed = base; changed["recovery_authorized"] = false
        try require(parsed(changed)?.recoveryAuthorized == false, "false ticket never becomes fresh authorization")
        let invalid: [(String, Any)] = [
            ("success", false), ("license_binding", String(repeating: "b", count: 64)),
            ("key_id", 8), ("key_id", 0), ("challenge_id", "not-a-uuid"),
            ("challenge", "invalid"), ("challenge", Data(repeating: 9, count: 31).base64EncodedString()),
            ("challenge", Data(repeating: 9, count: 33).base64EncodedString()),
            ("recovery_authorized", "true")
        ]
        for (field, value) in invalid {
            changed = base; changed[field] = value
            try require(parsed(changed) == nil, "reject malformed or differently scoped " + field)
        }
        for field in ["success", "license_binding", "key_id", "challenge_id", "challenge", "recovery_authorized"] {
            changed = base; changed.removeValue(forKey: field)
            try require(parsed(changed) == nil, "missing " + field + " fails closed")
        }
        for code in ["device_key_invalid", "device_recovery_required", "device_already_enrolled", "device_key_revoked", "device_revoked"] {
            try require(ProtectedRecoveryChallenge.permitsAttempt(after: ProtectedDownloadError.rejected(code)), "eligible signed " + code)
        }
        for code in ["HTTP_401", "HTTP_503", "session_expired", "key_banned", "key_revoked", "license_policy_banned",
            "device_quarantined", "device_jailbreak_quarantined", "release_policy_unavailable",
            "app_integrity_rejected", "timestamp_invalid", "replay_detected", "device_signature_invalid"] {
            try require(!ProtectedRecoveryChallenge.permitsAttempt(after: ProtectedDownloadError.rejected(code)), "ineligible " + code)
        }
        try require(ProtectedRecoveryChallenge.permitsAttempt(after: DeviceIdentityError.identityMissing), "missing material needs server ticket")
        try require(ProtectedRecoveryChallenge.permitsAttempt(after: DeviceIdentityError.invalidIdentity), "corrupt material needs server ticket")
        try require(!ProtectedRecoveryChallenge.permitsAttempt(after: DeviceIdentityError.keychain(-25308)), "locked Keychain never rotates identity")
        try require(!ProtectedRecoveryChallenge.permitsAttempt(after: DeviceIdentityError.ambiguousIdentity), "ambiguous identity remains fail closed")
        try require(!ProtectedRecoveryChallenge.permitsAttempt(after: URLError(.timedOut)), "network failure never rotates identity")
        try require(!ProtectedRecoveryChallenge.permitsAttempt(after: CancellationError()), "cancelled context never rotates identity")
        try require(!ProtectedRecoveryChallenge.permitsAttempt(after: ProtectedDownloadError.invalidResponse), "unverified response never rotates identity")
        print("Protected recovery contract self-check: \(count) checks passed")
    }
}
