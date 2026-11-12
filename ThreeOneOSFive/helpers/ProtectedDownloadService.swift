import Foundation
import CryptoKit
import Combine

enum ProtectedDownloadError: LocalizedError {
    case rejected(String)
    case quarantined(until: Date?, retryAfterSeconds: Int?)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .quarantined(let until, let retryAfterSeconds):
            if let until {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "vi_VN")
                formatter.dateFormat = "HH:mm dd/MM/yyyy ZZZZ"
                return "Thiết bị đang tạm hạn chế tải đến \(formatter.string(from: until)). Hãy thử lại sau thời điểm này."
            }
            if let seconds = retryAfterSeconds {
                return "Thiết bị đang tạm hạn chế tải. Máy chủ yêu cầu thử lại sau \(seconds) giây."
            }
            return "Thiết bị đang tạm hạn chế tải. Hãy thử lại sau hoặc liên hệ hỗ trợ nếu cần kiểm tra."
        case .rejected(let code):
            switch code {
            case "license_context_mismatch":
                return "Phiên thiết bị không khớp với key đang đăng nhập. Hãy đăng nhập lại đúng key hoặc liên hệ hỗ trợ."
            case "license_policy_banned", "key_policy_banned":
                return "Máy chủ đã khóa quyền sử dụng của key theo chính sách bảo vệ. Hãy liên hệ hỗ trợ để được kiểm tra."
            case "key_banned":
                return "Key đã bị khóa. Hãy liên hệ hỗ trợ để được kiểm tra."
            case "key_revoked", "device_key_revoked":
                return "Quyền sử dụng đã bị máy chủ thu hồi. Hãy liên hệ hỗ trợ để khôi phục quyền hợp lệ."
            case "session_expired", "session_required":
                return "Phiên tải bảo mật không còn hiệu lực. Hãy đăng nhập lại rồi thử lại."
            case "timestamp_invalid":
                return "Thời gian trên thiết bị chưa khớp máy chủ. Hãy bật Ngày & giờ tự động rồi thử lại."
            case "replay_detected":
                return "Yêu cầu tải không còn hợp lệ. Hãy thử lại để tạo yêu cầu mới."
            case "device_recovery_required", "device_already_enrolled":
                return "Bản cài đặt này cần được cấp lại quyền thiết bị. Hãy nhờ quản trị viên cấp lại quyền cho thiết bị này, sau đó thử tải lại danh sách chức năng. Mã hỗ trợ: \(code)."
            case "device_key_invalid", "device_signature_invalid", "device_proof_missing", "hwid_mismatch":
                return "Máy chủ chưa xác minh được định danh thiết bị. Hãy thử tải lại; nếu vẫn lỗi, gửi hỗ trợ mã: \(code)."
            case "recipient_upgrade_required", "recipient_enrollment_required", "device_environment_upgrade_required", "protocol_required":
                return "Bản cài đặt chưa đáp ứng giao thức bảo mật hiện tại. Hãy cài đúng bản ứng dụng mới nhất được cung cấp."
            case "download_server_update_required":
                return "Máy chủ chưa hỗ trợ luồng tải ổn định của bản Astra này. Hãy cập nhật server rồi thử lại. Mã: download_server_update_required."
            case "app_integrity_rejected", "integrity_report_invalid", "release_upgrade_required":
                return "Máy chủ chưa chấp nhận bản ứng dụng này. Hãy dùng đúng IPA được cung cấp và liên hệ hỗ trợ nếu vẫn lỗi."
            case "device_environment_rejected", "device_jailbreak_quarantined":
                return "Máy chủ đang hạn chế quyền thiết bị theo chính sách bảo mật. Hãy liên hệ hỗ trợ để kiểm tra."
            case "enforcement_unavailable", "release_policy_unavailable", "security_v2_unavailable", "backend_unavailable",
                 "protected_download_unavailable", "protected_downloads_not_configured":
                return "Dịch vụ kiểm tra bảo mật đang tạm gián đoạn. Hãy thử lại sau."
            case "lease_connection_too_slow":
                return "Kết nối mất quá nhiều thời gian để xác minh. Hãy kiểm tra mạng rồi thử lại."
            case "release_verification_required", "device_environment_verification_required":
                return "Phiên xác minh bảo mật đã hết hạn. Hãy thử lại."
            default:
                // Verified protocol codes are bounded by fromPinnedPayload.
                // Locally generated HTTP_<status> fallbacks are not server policy.
                if code.range(of: #"^[a-z0-9_]{1,80}$"#, options: .regularExpression) != nil {
                    return "Máy chủ chưa thể cấp quyền tải bảo mật. Hãy liên hệ hỗ trợ với mã: \(code)."
                }
                return "Máy chủ chưa thể cấp quyền tải bảo mật. Hãy thử lại hoặc liên hệ hỗ trợ."
            }
        case .invalidResponse: return "Phản hồi tải bảo mật không hợp lệ."
        }
    }

    /// Only call after SecureAPIClient authenticates the exact HTTPS origin
    /// with system trust AND a pinned certificate. Local reports are not policy.
    static func fromPinnedPayload(_ object: [String: Any], statusCode: Int) -> ProtectedDownloadError? {
        guard object["success"] as? Bool == false,
              let code = object["code"] as? String,
              code.range(of: #"^[a-z0-9_]{1,80}$"#, options: .regularExpression) != nil else { return nil }
        guard code == "device_quarantined" else { return .rejected(code) }
        guard statusCode == 423 else { return .invalidResponse }
        var until: Date?
        if let timestamp = object["quarantine_until"] as? String, timestamp.utf8.count <= 64 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            until = formatter.date(from: timestamp)
            if until == nil {
                formatter.formatOptions = [.withInternetDateTime]
                until = formatter.date(from: timestamp)
            }
        }
        let seconds = object["retry_after_seconds"] as? Int
        let validSeconds = seconds.flatMap { (1...604_800).contains($0) ? $0 : nil }
        return .quarantined(until: until, retryAfterSeconds: validSeconds)
    }
}

@MainActor
private final class ProtectedAuthContext {
    weak var auth: AuthManager?
    let revision: UInt64
    let licenseKey: String
    let hwid: String
    let binding: String
    init(_ auth: AuthManager) {
        self.auth = auth; revision = auth.authenticationRevision
        licenseKey = DeviceIdentityService.canonicalLicense(auth.licenseKey)
        hwid = auth.hwid; binding = DeviceIdentityService.binding(forLicense: licenseKey)
    }
    func validate() throws {
        guard let auth, auth.authState == .verified, auth.authenticationRevision == revision,
              DeviceIdentityService.binding(forLicense: auth.licenseKey) == binding, auth.hwid == hwid else {
            throw FeaturePatchError.notAuthenticated
        }
    }
}

private struct ProtectedSessionSnapshot {
    let id: String
    let token: String
    let expiry: Date
    let identity: DeviceIdentityService
}

private struct ProtectedArtifactDescriptor {
    let artifactID: String
    let fileHash: String
    let fileSize: Int
    let version: Int64
    let manifestDigest: String
    let variant: String
    let kind: String
    let fileName: String?
}

// BEGIN RECOVERY CHALLENGE CONTRACT — compiled directly by the offline self-check.
struct ProtectedRecoveryChallenge {
    let id: String
    let value: String
    let keyID: Int
    let recoveryAuthorized: Bool

    static func permitsResume(after error: Error) -> Bool {
        if case ProtectedDownloadError.rejected("device_signature_invalid") = error { return true }
        return permitsAttempt(after: error)
    }

    static func permitsAttempt(after error: Error) -> Bool {
        switch error {
        case ProtectedDownloadError.rejected(let code):
            // Eligibility only: a fresh, scoped server ticket still decides
            // whether a replacement identity may be prepared.
            return ["device_key_invalid", "device_recovery_required", "device_already_enrolled",
                    "device_key_revoked", "device_revoked"].contains(code)
        case DeviceIdentityError.identityMissing, DeviceIdentityError.invalidIdentity:
            return true
        default:
            return false
        }
    }

    static func permitsPendingRepair(after error: Error) -> Bool {
        switch error {
        case DeviceIdentityError.identityMissing, DeviceIdentityError.invalidIdentity: return true
        default: return false
        }
    }

    init?(_ object: [String: Any], licenseBinding: String, expectedKeyID: Int?) {
        guard object["success"] as? Bool == true,
              object["license_binding"] as? String == licenseBinding,
              let id = object["challenge_id"] as? String, UUID(uuidString: id) != nil,
              let value = object["challenge"] as? String,
              let bytes = Data(base64Encoded: value), bytes.count == 32,
              bytes.base64EncodedString() == value,
              let keyID = object["key_id"] as? Int, keyID > 0,
              expectedKeyID == nil || expectedKeyID == keyID,
              let authorized = object["recovery_authorized"] as? Bool else { return nil }
        self.id = id; self.value = value; self.keyID = keyID
        recoveryAuthorized = authorized
    }
}
// END RECOVERY CHALLENGE CONTRACT

struct ProtectedCodePatchDownload {
    let data: Data
    let fileName: String
}

/// Serializes the entire signed operation, not just counter allocation. The
/// existing v2 database uses a strict monotonic counter per installation.
private actor ProtectedRequestGate {
    private var busy = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { pending.append($0) }
    }
    func release() {
        if pending.isEmpty { busy = false } else { pending.removeFirst().resume() }
    }
}

@MainActor
final class ProtectedDownloadService: ObservableObject {
    static let shared = ProtectedDownloadService()
    @Published private(set) var accessNotice: String?
    private let gate = ProtectedRequestGate()
    private let origin = AppSecurityConfiguration.apiOrigin
    private var sessionID = ""
    private var sessionToken = ""
    private var sessionExpiry = Date.distantPast
    private var licenseDigest = ""
    private var identity: DeviceIdentityService?
    private var currentAuthContext: ProtectedAuthContext?
    private var contextEpoch: UInt64 = 0
    private var releaseLease = ProtectedReleaseLease()

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: origin + path) else { throw SecureAPIError.invalidEndpoint }
        try SecureAPIClient.validateURL(url)
        return url
    }

    private func post(_ path: String, body: [String: Any], signed: Bool,
                      purpose: String?, bearer: Bool = true,
                      identityOverride: DeviceIdentityService? = nil,
                      detachedSession: ProtectedSessionSnapshot? = nil) async throws -> (Data, String) {
        // Refresh before EACH protected request, before allocating its proof.
        // The integrity endpoint is outside this prefix, so renewal cannot recurse.
        if ProtectedReleaseLease.required(for: path) {
            guard signed, bearer, detachedSession == nil else { throw ProtectedDownloadError.invalidResponse }
            try await ensureReleaseLease()
        }
        let epoch = contextEpoch
        let authContext = currentAuthContext
        if detachedSession == nil { try authContext?.validate() }
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = path.hasSuffix("/content") ? 120 : 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("tls-pinned-v1", forHTTPHeaderField: "X-Astra-Response-Mode")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        let nonce: String
        if signed {
            guard let signingIdentity = detachedSession?.identity ?? identityOverride ?? identity,
                  let deviceID = try signingIdentity.persistedEnrollmentID() else {
                throw DeviceIdentityError.identityMissing
            }
            if bearer {
                let token = detachedSession?.token ?? sessionToken
                let id = detachedSession?.id ?? sessionID
                guard !id.isEmpty, !token.isEmpty else { throw ProtectedDownloadError.rejected("session_required") }
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            nonce = try RequestProofService.shared.signRequest(request: &request,
                sessionId: bearer ? (detachedSession?.id ?? sessionID) : "", deviceKeyId: deviceID,
                identity: signingIdentity)
        } else {
            nonce = try RequestProofService.shared.generateNonce()
            request.setValue(nonce, forHTTPHeaderField: "X-Astra-Nonce")
        }
        let (data, response) = try await SecureAPIClient.shared.data(for: request)
        if detachedSession == nil {
            guard epoch == contextEpoch else { throw CancellationError() }
            try authContext?.validate()
        }
        guard (200..<300).contains(response.statusCode) else {
            // This response came only through SecureAPIClient's system-trusted,
            // certificate-pinned connection. RSA API envelopes are no longer a
            // prerequisite; request proof/session/grant authorization stays on.
            if data.count <= 256 * 1024,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rejection = ProtectedDownloadError.fromPinnedPayload(object, statusCode: response.statusCode) {
                if case .rejected(let code) = rejection,
                   ["release_verification_required", "device_environment_verification_required", "release_upgrade_required"].contains(code),
                   detachedSession == nil { releaseLease.invalidate() }
                if detachedSession == nil,
                   response.statusCode == 401 || (object["session_revoked"] as? Bool) == true {
                    clearSession()
                }
                if case .quarantined = rejection, detachedSession == nil { clearSession() }
                throw rejection
            }
            throw ProtectedDownloadError.rejected("HTTP_\(response.statusCode)")
        }
        let payload = data
        if detachedSession == nil && purpose != nil && (path.hasPrefix("/api/v2/artifacts/") ||
            path == "/api/v2/novax/session/open" || path == "/api/v2/novax/session/renew") {
            accessNotice = nil
        }
        return (payload, nonce)
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["success"] as? Bool == true else { throw ProtectedDownloadError.invalidResponse }
        return value
    }

    private func clearSession() {
        releaseLease.invalidate()
        sessionID = ""; sessionToken = ""; sessionExpiry = .distantPast
    }

    /// Foreground/background transitions invalidate cached time. A response from
    /// an older foreground cannot repopulate this lease after that transition.
    func invalidateReleaseLease() { releaseLease.invalidate() }

    func reset() {
        contextEpoch &+= 1
        clearSession(); licenseDigest = ""; accessNotice = nil
        identity = nil; currentAuthContext = nil
    }

    /// Snapshot synchronously at the user's logout action. The queued request
    /// can revoke only this old session, never a later login's session.
    func requestLogout() {
        let snapshot = identity.map { ProtectedSessionSnapshot(id: sessionID, token: sessionToken,
            expiry: sessionExpiry, identity: $0) }
        reset()
        guard let snapshot, !snapshot.id.isEmpty, snapshot.expiry > Date() else { return }
        Task {
            await gate.acquire()
            _ = try? await post("/api/v2/novax/logout", body: [:], signed: true,
                purpose: "novax-logout-v2", detachedSession: snapshot)
            await gate.release()
        }
    }

    private func beginOperation(_ context: ProtectedAuthContext) throws {
        try context.validate()
        if context.binding != licenseDigest {
            contextEpoch &+= 1
            clearSession(); identity = nil; accessNotice = nil
            licenseDigest = context.binding
        }
        currentAuthContext = context
    }

    private func prepareIdentity(_ context: ProtectedAuthContext) async throws -> DeviceIdentityService {
        if let identity, identity.licenseBinding == context.binding { return identity }
        let selected = try DeviceIdentityService.scoped(to: context.binding)
        if try selected.persistedEnrollmentID() == nil {
            let legacy = DeviceIdentityService.shared
            if let legacyID = try legacy.persistedEnrollmentID() {
                do {
                    let (data, _) = try await post("/api/v2/device/context", body: [:], signed: true,
                        purpose: "device-context-v2", bearer: false, identityOverride: legacy)
                    let payload = try dictionary(data)
                    guard let actualBinding = payload["license_binding"] as? String,
                          let keyID = payload["key_id"] as? Int,
                          payload["device_key_id"] as? String == legacyID else {
                        throw ProtectedDownloadError.invalidResponse
                    }
                    do {
                        try legacy.migrateLegacy(to: actualBinding, expectedDeviceID: legacyID, keyID: keyID)
                    } catch DeviceIdentityError.ambiguousIdentity where actualBinding != context.binding {
                        // An unrelated legacy A archive cannot prevent a valid B
                        // identity from being used. Keep both archives intact.
                    }
                } catch ProtectedDownloadError.rejected(let code)
                    where ["key_expired", "key_invalid", "key_banned", "key_revoked", "device_revoked", "device_key_invalid", "device_key_revoked", "license_policy_banned"].contains(code) {
                    // Preserve an unusable archive. A different license gets its
                    // own fresh identity and can never inherit this old device.
                }
            }
        }
        try context.validate()
        self.identity = selected
        return selected
    }

    private func ensureSession(auth: AuthManager) async throws {
        guard let context = currentAuthContext else { throw FeaturePatchError.notAuthenticated }
        let epoch = contextEpoch
        // A previous enrollment may have committed and consumed its ticket
        // before its response arrived. Retry the durable candidate first.
        let controller = try recoveryController(context)
        let hasPending: Bool
        do { hasPending = try controller.pendingRecoveryCandidate(hwid: context.hwid) != nil }
        catch {
            guard ProtectedRecoveryChallenge.permitsPendingRepair(after: error) else { throw error }
            try await recoverInstallation(context: context, epoch: epoch)
            try await ensureCurrentSession(auth: auth)
            return
        }
        if hasPending {
            try await recoverInstallation(context: context, epoch: epoch)
            try await ensureCurrentSession(auth: auth)
            return
        }
        do {
            do {
                try await ensureCurrentSession(auth: auth)
            } catch ProtectedDownloadError.rejected(let code)
                where ["session_expired", "session_required", "device_key_invalid", "device_signature_invalid"].contains(code) {
                try requireRecoveryContext(context, epoch: epoch)
                clearSession()
                // One ordinary bootstrap retry with the SAME private keys.
                try await ensureCurrentSession(auth: auth)
            }
        } catch {
            guard ProtectedRecoveryChallenge.permitsAttempt(after: error) else { throw error }
            try requireRecoveryContext(context, epoch: epoch)
            clearSession()
            // No recursive retry: only a fresh admin-authorized ticket can
            // create a candidate. Policy/network failures never authorize it.
            try await recoverInstallation(context: context, epoch: epoch)
            try await ensureCurrentSession(auth: auth)
        }
    }

    private func recoveryController(_ context: ProtectedAuthContext) throws -> DeviceIdentityService {
        if let identity, identity.licenseBinding == context.binding {
            return try identity.recoveryController()
        }
        return try DeviceIdentityService.recoveryController(for: context.binding)
    }

    private func bootstrapEnrollment(_ context: ProtectedAuthContext, epoch: UInt64) async throws -> DeviceIdentityService {
        let selected = try await prepareIdentity(context)
        let installID = try selected.existingInstallationID() ?? selected.initialEnrollmentInstallationID() ?? UUID().uuidString.lowercased()
        let (challengeData, _) = try await post("/api/v2/device/challenge", body: [
            "key": context.licenseKey, "hwid": context.hwid, "install_id": installID
        ], signed: false, purpose: "device-challenge")
        try requireRecoveryContext(context, epoch: epoch)
        guard let challenge = ProtectedRecoveryChallenge(try dictionary(challengeData),
            licenseBinding: context.binding, expectedKeyID: nil) else {
            throw ProtectedDownloadError.invalidResponse
        }
        // A remembered enrollment cannot silently generate replacement keys.
        // New users may create keys only after the active license challenge.
        let initialPreparation = try selected.prepareInitialEnrollment(installationID: installID)
        if !initialPreparation { _ = try selected.existingResumeMaterial() }
        let signing = try selected.getOrCreateKey()
        let agreement = try selected.getOrCreateAgreementKey()
        let material = try selected.existingResumeMaterial()
        let signature = try selected.signResumeEnrollment(challengeID: challenge.id,
            challenge: challenge.value, key: context.licenseKey, hwid: context.hwid, installationID: installID)
        try selected.finishInitialEnrollmentPreparation(installationID: installID)
        let (enrolledData, _) = try await post("/api/v2/device/enroll", body: [
            "challenge_id": challenge.id, "challenge": challenge.value,
            "key": context.licenseKey, "hwid": context.hwid, "install_id": installID,
            "public_key_x963": signing.publicKeyX963Base64,
            "agreement_public_key_x963": agreement.publicKeyX963Base64,
            "assurance_level": signing.assurance.rawValue, "enrollment_revision": 2,
            "signature": signature, "canonical_enrollment": true
        ], signed: false, purpose: "device-enroll")
        try requireRecoveryContext(context, epoch: epoch)
        let enrolled = try dictionary(enrolledData)
        let fingerprint: (String) throws -> String = { value in
            guard let bytes = Data(base64Encoded: value), bytes.count == 65 else { throw ProtectedDownloadError.invalidResponse }
            return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        guard enrolled["license_binding"] as? String == context.binding,
              enrolled["key_id"] as? Int == challenge.keyID,
              enrolled["enrollment_revision"] as? Int == 2,
              let deviceID = enrolled["device_key_id"] as? String,
              let canonicalInstallID = enrolled["install_id"] as? String,
              enrolled["public_key_fingerprint"] as? String == (try fingerprint(material.signing)),
              enrolled["agreement_public_key_fingerprint"] as? String == (try fingerprint(material.agreement)) else {
            throw ProtectedDownloadError.rejected("download_server_update_required")
        }
        try selected.acceptCanonicalEnrollment(deviceKeyID: deviceID, installationID: canonicalInstallID,
            keyID: challenge.keyID, signingFingerprint: try fingerprint(material.signing),
            agreementFingerprint: try fingerprint(material.agreement))
        identity = selected
        return selected
    }

    private func recordAccessFailure(_ error: Error, context: ProtectedAuthContext) {
        guard !(error is CancellationError), currentAuthContext === context,
              (try? context.validate()) != nil else { return }
        accessNotice = error.localizedDescription
    }

    private func requireRecoveryContext(_ context: ProtectedAuthContext, epoch: UInt64) throws {
        try Task.checkCancellation()
        guard contextEpoch == epoch, currentAuthContext === context else { throw CancellationError() }
        try context.validate()
    }

    private func recoverInstallation(context: ProtectedAuthContext, epoch: UInt64) async throws {
        try requireRecoveryContext(context, epoch: epoch)
        let original = try recoveryController(context)
        guard original.licenseBinding == context.binding else { throw DeviceIdentityError.invalidIdentity }
        let pending: DeviceIdentityService?
        var replacingUnreadablePending = false
        do { pending = try original.pendingRecoveryCandidate(hwid: context.hwid) }
        catch {
            guard ProtectedRecoveryChallenge.permitsPendingRepair(after: error) else { throw error }
            pending = nil
            replacingUnreadablePending = true
        }
        let installID = try pending?.existingInstallationID() ?? UUID().uuidString.lowercased()
        let expectedKeyID = try pending?.persistedServerKeyID() ?? original.recoveryExpectedServerKeyID()
        let (data, _) = try await post("/api/v2/device/challenge", body: [
            "key": context.licenseKey, "hwid": context.hwid, "install_id": installID,
            "recover_installation": true
        ], signed: false, purpose: "device-challenge")
        try requireRecoveryContext(context, epoch: epoch)
        guard let challenge = ProtectedRecoveryChallenge(try dictionary(data),
                licenseBinding: context.binding, expectedKeyID: expectedKeyID) else {
            throw ProtectedDownloadError.invalidResponse
        }
        let candidate: DeviceIdentityService
        if let pending {
            // The durable candidate was prepared after a previously verified true
            // ticket. A lost enrollment response may have consumed that ticket;
            // only these exact keys may retry the server's idempotent enroll.
            guard try pending.existingInstallationID() == installID,
                  try pending.persistedServerKeyID() == challenge.keyID else {
                throw DeviceIdentityError.invalidIdentity
            }
            candidate = pending
        } else {
            guard challenge.recoveryAuthorized else {
                throw ProtectedDownloadError.rejected("device_recovery_required")
            }
            candidate = try original.prepareRecoveryCandidate(installationID: installID,
                keyID: challenge.keyID, hwid: context.hwid,
                replacingUnreadablePending: replacingUnreadablePending)
        }
        try requireRecoveryContext(context, epoch: epoch)
        let (signing, assurance) = try candidate.getOrCreateKey()
        let (agreement, _) = try candidate.getOrCreateAgreementKey()
        let signature = try candidate.signEnrollment(challengeId: challenge.id, challenge: challenge.value,
            key: context.licenseKey, hwid: context.hwid, installId: installID,
            publicKeyX963: signing, assurance: assurance, agreementPublicKeyX963: agreement)
        let (enrolledData, _) = try await post("/api/v2/device/enroll", body: [
            "challenge_id": challenge.id, "challenge": challenge.value,
            "key": context.licenseKey, "hwid": context.hwid, "install_id": installID,
            "public_key_x963": signing, "agreement_public_key_x963": agreement,
            "assurance_level": assurance.rawValue, "enrollment_revision": 2, "signature": signature,
            "canonical_enrollment": true
        ], signed: false, purpose: "device-enroll")
        try requireRecoveryContext(context, epoch: epoch)
        let enrolled = try dictionary(enrolledData)
        let signingBytes = Data(base64Encoded: signing)
        let agreementBytes = Data(base64Encoded: agreement)
        guard enrolled["license_binding"] as? String == context.binding,
              enrolled["key_id"] as? Int == challenge.keyID,
              enrolled["install_id"] as? String == installID,
              let deviceID = enrolled["device_key_id"] as? String, UUID(uuidString: deviceID) != nil,
              enrolled["enrollment_revision"] as? Int == 2,
              let signingBytes, signingBytes.count == 65,
              let agreementBytes, agreementBytes.count == 65,
              enrolled["public_key_fingerprint"] as? String ==
                SHA256.hash(data: signingBytes).map({ String(format: "%02x", $0) }).joined(),
              enrolled["agreement_public_key_fingerprint"] as? String ==
                SHA256.hash(data: agreementBytes).map({ String(format: "%02x", $0) }).joined() else {
            throw ProtectedDownloadError.invalidResponse
        }
        // Promotion is durable and keeps the old generation intact. No await
        // occurs between the final context check and publishing the new identity.
        try requireRecoveryContext(context, epoch: epoch)
        identity = try original.promoteRecoveryCandidate(candidate, deviceKeyID: deviceID,
            keyID: challenge.keyID, hwid: context.hwid)
        clearSession()
    }

    private func ensureCurrentSession(auth: AuthManager) async throws {
        guard let context = currentAuthContext else { throw FeaturePatchError.notAuthenticated }
        try context.validate()
        if !sessionID.isEmpty && sessionExpiry.timeIntervalSinceNow > 90 { return }
        if !sessionID.isEmpty && sessionExpiry.timeIntervalSinceNow > 0 {
            let (data, _) = try await post("/api/v2/novax/session/renew", body: [:], signed: true,
                                         purpose: "novax-session-renew-v2")
            try acceptSession(data)
            return
        }
        clearSession()
        let identity = try await bootstrapEnrollment(context, epoch: contextEpoch)
        self.identity = identity
        let (loginData, _) = try await post("/api/v2/novax/session/open", body: [
            "app_release": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "license_binding": context.binding
        ], signed: true, purpose: "novax-session-open-v2", bearer: false)
        try acceptSession(loginData)
    }

    private func acceptSession(_ data: Data) throws {
        let session = try dictionary(data)
        guard let context = currentAuthContext, let identity,
              session["license_binding"] as? String == context.binding,
              let keyID = session["key_id"] as? Int, keyID > 0 else {
            throw ProtectedDownloadError.rejected("license_context_mismatch")
        }
        try context.validate()
        try identity.persistServerKeyID(keyID)
        guard let id = session["app_session_id"] as? String, UUID(uuidString: id) != nil,
              let token = session["app_session_token"] as? String, !token.isEmpty,
              let expiryString = session["session_expires_at"] as? String else { throw ProtectedDownloadError.invalidResponse }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var expiry = expiryString.utf8.count <= 64 ? formatter.date(from: expiryString) : nil
        if expiry == nil && expiryString.utf8.count <= 64 {
            formatter.formatOptions = [.withInternetDateTime]
            expiry = formatter.date(from: expiryString)
        }
        guard let expiry, expiry > Date() else { throw ProtectedDownloadError.invalidResponse }
        sessionID = id; sessionToken = token; sessionExpiry = expiry
    }

    func sync(auth: AuthManager) async throws -> Data {
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try beginOperation(requestedContext)
            accessNotice = nil
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            let data = try await syncCatalogWithSessionRetry(auth: auth)
            await gate.release()
            return data
        } catch { recordAccessFailure(error, context: requestedContext); await gate.release(); throw error }
    }

    /// Catalog sync is read-only. A pinned-TLS expired-session rejection permits
    /// ONE fresh session/proof/nonce retry. One-use grants/content are never replayed.
    private func syncCatalogWithSessionRetry(auth: AuthManager) async throws -> Data {
        do {
            return try await post("/api/v2/artifacts/sync", body: [:], signed: true, purpose: "artifact-sync").0
        } catch {
            let expiredSession: Bool
            if case ProtectedDownloadError.rejected(let code) = error {
                expiredSession = ["session_expired", "session_required"].contains(code)
            } else { expiredSession = false }
            guard expiredSession || ProtectedRecoveryChallenge.permitsAttempt(after: error) else { throw error }
            guard let context = currentAuthContext else { throw FeaturePatchError.notAuthenticated }
            try context.validate()
            clearSession()
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            return try await post("/api/v2/artifacts/sync", body: [:], signed: true, purpose: "artifact-sync").0
        }
    }

    /// Best-effort telemetry is a device-authenticated signal, never a license
    /// credential or a client-side decision to ban the user.
    func reportSecuritySignal(auth: AuthManager, signal: String) async {
        guard auth.authState == .verified,
              signal.range(of: #"^[a-z0-9_]{1,64}$"#, options: .regularExpression) != nil else { return }
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try beginOperation(requestedContext)
            try await ensureSession(auth: auth)
            _ = try await post("/api/v2/security/report-crack", body: [
                "signal": signal,
                "app_release": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                "os_build": AppInfo.osBuild
            ], signed: true, purpose: "security-report-v2")
        } catch {
            // Offline, attestation and telemetry failures cannot revoke a key,
            // change local authentication or silently retry a legacy endpoint.
        }
        await gate.release()
    }

    func download(_ patch: PatchItem, auth: AuthManager) async throws -> Data {
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try beginOperation(requestedContext)
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            guard let artifactID = patch.artifactID,
                  let digest = patch.manifestDigest,
                  let variant = patch.artifactVariant else { throw ProtectedDownloadError.invalidResponse }
            let descriptor = ProtectedArtifactDescriptor(artifactID: artifactID,
                fileHash: patch.fileHash, fileSize: patch.fileSize, version: Int64(patch.version),
                manifestDigest: digest, variant: variant, kind: "package", fileName: nil)
            let result = try await downloadArtifact(descriptor, auth: auth)
            await gate.release()
            return result.data
        } catch { await gate.release(); throw error }
    }

    /// Resolving availability is authenticated metadata, never a HEAD request to
    /// the legacy binary endpoint. Failure never reuses a cached true value.
    func isCodePatchAvailable(variant: GamePatchVariant, kind: FeaturePatchService.CodePatchKind,
                              auth: AuthManager) async throws -> Bool {
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try beginOperation(requestedContext)
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            _ = try await resolveCodePatch(variant: variant, kind: kind)
            try requireCurrentLicense(auth)
            await gate.release()
            return true
        } catch { await gate.release(); throw error }
    }

    func downloadCodePatch(variant: GamePatchVariant, kind: FeaturePatchService.CodePatchKind,
                           auth: AuthManager) async throws -> ProtectedCodePatchDownload {
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try beginOperation(requestedContext)
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            let descriptor = try await resolveCodePatch(variant: variant, kind: kind)
            let result = try await downloadArtifact(descriptor, auth: auth)
            await gate.release()
            return result
        } catch { await gate.release(); throw error }
    }

    private func ensureReleaseLease() async throws {
        guard AppSecurityConfiguration.localIntegrityEnforced else { return }
        if !releaseLease.needsRenewal(now: ProcessInfo.processInfo.systemUptime) { return }
        // Inspect on the runtime's detached utility task, not the UI thread;
        // consume its current-epoch snapshot rather than a global stale result.
        guard await AppIntegrityRuntime.shared.verifyNow(force:true),
              let result = AppIntegrityRuntime.shared.acceptedResult,
              result.permitsProtectedOperation else { throw IntegrityError.invalid }
        let generation = releaseLease.generation
        let started = ProcessInfo.processInfo.systemUptime
        let (data,_) = try await post("/api/v2/security/integrity-v2", body:result.reportV2,
                                    signed:true,purpose:"app-integrity-v2")
        let response=try dictionary(data)
        guard response["environment_policy"] as? Int == DeviceEnvironmentResult.policy,
              let text=response["lease_expires_at"] as? String,
              let ttl=response["lease_ttl_seconds"] as? Double else { throw ProtectedDownloadError.invalidResponse }
        do {
            try releaseLease.recordVerifiedResponse(expiresAt:text,ttl:ttl,requestStartedAt:started,
                receivedAt:ProcessInfo.processInfo.systemUptime,expectedGeneration:generation)
        } catch ProtectedReleaseLeaseError.staleGeneration { throw CancellationError() }
        catch ProtectedReleaseLeaseError.insufficientTime { throw ProtectedDownloadError.rejected("lease_connection_too_slow") }
        catch { throw ProtectedDownloadError.invalidResponse }
    }

    /// One short pinned, signed report may outlive cancellation of ordinary
    /// requests. It cannot enroll an identity or open a new session after failure.
    func reportIntegrityFailure(_ result:SecurityCheckResult) async {
        guard AppSecurityConfiguration.localIntegrityEnforced else { return }
        guard result.isCompromised,let identity,!sessionID.isEmpty,!sessionToken.isEmpty,sessionExpiry > Date(),
              let deviceID=try? identity.persistedEnrollmentID(),!deviceID.isEmpty else { return }
        let id=sessionID,token=sessionToken
        await gate.acquire()
        do {
            var request=URLRequest(url:try endpoint("/api/v2/security/integrity-v2"))
            request.httpMethod="POST";request.timeoutInterval=2
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
            var body=result.reportV2
            if result.sealDigest.isEmpty { body["seal_digest"]=String(repeating:"0",count:64) }
            request.httpBody=try JSONSerialization.data(withJSONObject:body,options:[.sortedKeys,.withoutEscapingSlashes])
            _ = try RequestProofService.shared.signRequest(request:&request,sessionId:id,deviceKeyId:deviceID,identity:identity)
            let config=URLSessionConfiguration.ephemeral;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil
            config.timeoutIntervalForRequest=2;config.timeoutIntervalForResource=3
            let session=URLSession(configuration:config,delegate:CertPinningDelegate.shared,delegateQueue:nil)
            defer { session.invalidateAndCancel() }
            _ = try await session.data(for:request)
        } catch {}
        clearSession();await gate.release()
    }

    private func resolveCodePatch(variant: GamePatchVariant,
                                  kind: FeaturePatchService.CodePatchKind) async throws -> ProtectedArtifactDescriptor {
        let (data, _) = try await post("/api/v2/artifacts/resolve", body: [
            "variant": variant.rawValue, "kind": kind.rawValue
        ], signed: true, purpose: "artifact-resolve")
        let response = try dictionary(data)
        guard let artifact = response["artifact"] as? [String: Any],
              let artifactID = artifact["artifact_id"] as? String,
              let hash = artifact["file_hash"] as? String,
              let size = artifact["file_size"] as? Int,
              let version = artifact["version"] as? Int64,
              let digest = artifact["manifest_digest"] as? String,
              artifact["artifact_variant"] as? String == variant.rawValue,
              artifact["kind"] as? String == kind.rawValue,
              let fileName = artifact["file_name"] as? String,
              let manifest = artifact["signed_manifest"] else {
            throw ProtectedDownloadError.invalidResponse
        }
        let descriptor = ProtectedArtifactDescriptor(artifactID: artifactID, fileHash: hash,
            fileSize: size, version: version, manifestDigest: digest,
            variant: variant.rawValue, kind: kind.rawValue, fileName: fileName)
        let manifestData = try JSONSerialization.data(withJSONObject: manifest,
            options: [.sortedKeys, .withoutEscapingSlashes])
        let body = try ProtectedArtifactDecoder.shared.verifyManifest(manifestData)
        try validateDescriptor(descriptor, manifest: body, signedDocument: manifest)
        return descriptor
    }

    /// Caller owns the session gate. This common path applies the same device
    /// envelope policy to packages, native mods and their original restore files.
    private func downloadArtifact(_ descriptor: ProtectedArtifactDescriptor,
                                  auth: AuthManager) async throws -> ProtectedCodePatchDownload {
        guard UUID(uuidString: descriptor.artifactID) != nil,
              ["package", "mod", "original"].contains(descriptor.kind),
              AppSecurityConfiguration.protectedBundleID(forVariant: descriptor.variant) != nil,
              descriptor.variant != "capcut" || descriptor.kind == "package" else {
            throw ProtectedDownloadError.invalidResponse
        }
        let initialLicenseDigest = licenseDigest
        let (grantData, _) = try await post("/api/v2/artifacts/\(descriptor.artifactID)/grants",
            body: [:], signed: true, purpose: "artifact-grant")
        let granted = try dictionary(grantData)
        guard let grantID = granted["grant_id"] as? String, UUID(uuidString: grantID) != nil,
              granted["artifact_id"] as? String == descriptor.artifactID else {
            throw ProtectedDownloadError.invalidResponse
        }
        let (contentData, nonce) = try await post("/api/v2/artifacts/\(descriptor.artifactID)/content",
            body: ["grant_id": grantID], signed: true, purpose: nil)
        guard contentData.count <= 72 * 1024 * 1024 else { throw ProtectedDownloadError.invalidResponse }
        let content = try dictionary(contentData)
        guard let manifest = content["signed_manifest"], let grant = content["signed_grant"],
              let encoded = content["ciphertext_b64"] as? String,
              let ciphertext = Data(base64Encoded: encoded),
              let identity, let deviceID = try identity.persistedEnrollmentID() else {
            throw ProtectedDownloadError.invalidResponse
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifest,
            options: [.sortedKeys, .withoutEscapingSlashes])
        let grantDataJSON = try JSONSerialization.data(withJSONObject: grant,
            options: [.sortedKeys, .withoutEscapingSlashes])
        let manifestBody = try ProtectedArtifactDecoder.shared.verifyManifest(manifestData)
        try validateDescriptor(descriptor, manifest: manifestBody, signedDocument: manifest)
        let decoder = ProtectedArtifactDecoder(verifier: .shared, recipientIdentity: {
            guard let id = try identity.persistedEnrollmentID(),
                  let publicKey = Data(base64Encoded: try identity.getOrCreateAgreementKey().publicKeyX963Base64) else {
                throw ProtectedDownloadError.invalidResponse
            }
            return (id, publicKey)
        }, sharedSecret: { try identity.agreementSharedSecret(peerPublicKeyX963: $0) })
        try await AppIntegrityRuntime.shared.requireAllowed(force:true)
        let plaintext = try decoder.decrypt(signedManifest: manifestData,
            signedGrant: grantDataJSON, ciphertext: ciphertext, recipientID: deviceID, sessionID: sessionID,
            requestNonce: nonce, expectedArtifactID: descriptor.artifactID, expectedGrantID: grantID)
        try await AppIntegrityRuntime.shared.requireAllowed(force:true)
        try requireCurrentLicense(auth)
        guard licenseDigest == initialLicenseDigest,
              SHA256.hash(data: plaintext).map({ String(format: "%02x", $0) }).joined() == descriptor.fileHash,
              plaintext.count == descriptor.fileSize else { throw ProtectedDownloadError.invalidResponse }
        return ProtectedCodePatchDownload(data: plaintext, fileName: manifestBody.fileName)
    }

    private func validateDescriptor(_ descriptor: ProtectedArtifactDescriptor,
                                    manifest: ProtectedArtifactManifest, signedDocument: Any) throws {
        let digest = SHA256.hash(data: try ProtectedArtifactDecoder.canonicalData(signedDocument))
            .map { String(format: "%02x", $0) }.joined()
        guard manifest.artifactId == descriptor.artifactID, digest == descriptor.manifestDigest,
              manifest.kind == descriptor.kind, manifest.variant == descriptor.variant,
              manifest.releaseVersion == descriptor.version,
              manifest.plaintextSHA256 == descriptor.fileHash,
              manifest.plaintextSize == descriptor.fileSize,
              descriptor.fileName == nil || descriptor.fileName == manifest.fileName else {
            throw ProtectedDownloadError.invalidResponse
        }
    }

    private func requireCurrentLicense(_ auth: AuthManager) throws {
        guard let context = currentAuthContext, context.auth === auth,
              context.binding == licenseDigest else { throw FeaturePatchError.notAuthenticated }
        try context.validate()
    }
}
