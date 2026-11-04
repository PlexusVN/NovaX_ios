import Foundation
import CryptoKit
import Combine

enum ProtectedDownloadError: LocalizedError {
    case rejected(String)
    case quarantined(until: Date?, retryAfterSeconds: Int?)
    case retryable(after: Int)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .retryable: return "Máy chủ đang bận. Đang chờ cấp quyền tải, vui lòng giữ ứng dụng mở."
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
            case "enforcement_unavailable":
                return "Dịch vụ kiểm tra bảo mật đang tạm gián đoạn. Hãy thử lại sau."
            case "release_verification_required", "app_integrity_rejected", "client_integrity_failed":
                return "Chưa thể xác minh bản cài đặt này. Hãy dùng bản phát hành chính thức hoặc liên hệ admin kiểm tra cấu hình phát hành. Đây không phải thông báo khóa HWID."
            case "enrollment_authorization_required", "device_recovery_required", "device_already_enrolled":
                return "Định danh cài đặt đã thay đổi. Hãy nhờ admin Reset HWID của key, sau đó đăng nhập lại. Pairing trên máy vẫn được giữ nguyên."
            default:
                return "Máy chủ chưa thể cấp quyền tải bảo mật. Hãy thử lại hoặc liên hệ hỗ trợ."
            }
        case .invalidResponse: return "Phản hồi tải bảo mật không hợp lệ."
        }
    }

    /// Only call with a nonce-bound, signature-verified response. No policy is
    /// inferred from unsigned JSON or from a local detector's report.
    static func fromVerifiedPayload(_ object: [String: Any], statusCode: Int) -> ProtectedDownloadError? {
        guard object["success"] as? Bool == false,
              let code = object["code"] as? String,
              code.range(of: #"^[a-z0-9_]{1,80}$"#, options: .regularExpression) != nil else { return nil }
        if code == "transfer_busy", statusCode == 429,
           let seconds = object["retry_after_seconds"] as? Int, (1...10).contains(seconds) {
            return .retryable(after: seconds)
        }
        guard code == "device_quarantined" || code == "device_jailbreak_quarantined" else {
            return .rejected(code)
        }
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
    private let origin = Obf.s([
        207, 211, 211, 215, 212, 157, 136, 136, 221, 222,
        201, 200, 223, 137, 196, 203, 206, 196, 204
    ], 0xA7)
    private var sessionID = ""
    private var sessionToken = ""
    private var sessionExpiry = Date.distantPast
    private var licenseDigest = ""
    private var identity: DeviceIdentityService?
    private var currentAuthContext: ProtectedAuthContext?
    private var contextEpoch: UInt64 = 0
    private var releaseLease = ProtectedLeasePolicy()
    private var releaseLeaseSubject = ""

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: origin + path) else { throw SecureAPIError.invalidEndpoint }
        try SecureAPIClient.validateURL(url)
        return url
    }

    private func post(_ path: String, body: [String: Any], signed: Bool,
                      purpose: String?, bearer: Bool = true,
                      identityOverride: DeviceIdentityService? = nil,
                      detachedSession: ProtectedSessionSnapshot? = nil) async throws -> (Data, String) {
        let epoch = contextEpoch
        let retryStarted = ProcessInfo.processInfo.systemUptime
        var retries = 0
        var recoveredLease = false
        while true {
            do {
                return try await sendPost(path, body: body, signed: signed, purpose: purpose,
                    bearer: bearer, identityOverride: identityOverride, detachedSession: detachedSession)
            } catch ProtectedDownloadError.retryable(let seconds) where path.hasPrefix("/api/v2/artifacts/") {
                guard let delay = ProtectedArtifactRetryPolicy.delay(attempt: retries, serverSeconds: seconds),
                      epoch == contextEpoch,
                      ProcessInfo.processInfo.systemUptime - retryStarted + delay < 60 else {
                    throw ProtectedDownloadError.retryable(after: seconds)
                }
                retries += 1
                try await Task.sleep(nanoseconds: UInt64((delay + Double.random(in: 0...0.5)) * 1_000_000_000))
                guard epoch == contextEpoch else { throw CancellationError() }
                try currentAuthContext?.validate()
                try await ensureReleaseLease()
                // sendPost allocates a NEW nonce/counter for every retry.
            } catch ProtectedDownloadError.rejected("release_verification_required")
                where path.hasPrefix("/api/v2/artifacts/") && !recoveredLease {
                guard epoch == contextEpoch else { throw CancellationError() }
                recoveredLease = true
                releaseLease.clear()
                try await ensureReleaseLease()
            }
        }
    }

    private func sendPost(_ path: String, body: [String: Any], signed: Bool,
                          purpose: String?, bearer: Bool,
                          identityOverride: DeviceIdentityService?,
                          detachedSession: ProtectedSessionSnapshot?) async throws -> (Data, String) {
        let epoch = contextEpoch
        let authContext = currentAuthContext
        if detachedSession == nil { try authContext?.validate() }
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = path.hasSuffix("/content") ? 120 : 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            // Never retry through legacy endpoints or accept unsigned error data
            // as policy. A fresh user retry can safely obtain a new grant.
            if response.statusCode == 401 && detachedSession == nil { clearSession() }
            // Artifact failures use a separate signed purpose. Only an exact
            // request nonce and a verified purpose can influence retry/recovery.
            let errorPurposes = ["security-enforcement-v2"] + (path.hasPrefix("/api/v2/artifacts/")
                ? ["artifact-error"] : purpose.map { [$0] } ?? [])
            for errorPurpose in errorPurposes {
                if let verified = try? ServerSignatureVerifier.shared.verifiedPayload(in: data,
                        expectedNonce: nonce, expectedPurpose: errorPurpose),
                   let object = try? JSONSerialization.jsonObject(with: verified) as? [String: Any],
                   let rejection = ProtectedDownloadError.fromVerifiedPayload(object, statusCode: response.statusCode) {
                    if object["session_revoked"] as? Bool == true, detachedSession == nil { clearSession() }
                    if detachedSession == nil { accessNotice = rejection.errorDescription }
                    if case .quarantined = rejection, detachedSession == nil {
                        // Keep the license and persistent device identities. A
                        // later retry opens a fresh server-authorized session.
                        clearSession()
                    }
                    throw rejection
                }
            }
            throw ProtectedDownloadError.rejected("HTTP_\(response.statusCode)")
        }
        let payload: Data
        if let purpose {
            payload = try ServerSignatureVerifier.shared.verifiedPayload(in: data,
                expectedNonce: nonce, expectedPurpose: purpose)
        } else { payload = data } // content's two signed documents are checked by the decoder
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
        releaseLease.clear()
        releaseLeaseSubject = ""
        sessionID = ""; sessionToken = ""; sessionExpiry = .distantPast
    }

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

    private func beginOperation(_ context: ProtectedAuthContext,
                                allowIntegrityIncident: Bool = false) async throws {
        try context.validate()
        if !allowIntegrityIncident {
            let (runtime, executable) = await Task.detached(priority: .utility) {
                (AntiTamper.checkAtLaunch(), BinaryIntegrity.evaluate())
            }.value
            let release = await ReleaseIntegrityRuntime.verify()
            try context.validate()
            guard !runtime.isCompromised, !executable.isCompromised, !release.requiresLocalBlock else {
                ReleaseCommitBarrier.blockNewCommits()
                AntiTamper.reportCrackAndLockMachine(
                    reason: "Protected operation rejected by local integrity gate",
                    details: [:]
                )
                throw ProtectedDownloadError.rejected("client_integrity_failed")
            }
        }
        if context.binding != licenseDigest {
            contextEpoch &+= 1
            clearSession(); identity = nil; accessNotice = nil
            licenseDigest = context.binding
        }
        currentAuthContext = context
    }

    private func prepareIdentity(_ context: ProtectedAuthContext) async throws -> DeviceIdentityService {
        if let identity, identity.licenseBinding == context.binding {
            let pending = try identity.hasPendingAuthorizedRecovery
            if !pending { return identity }
        }
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
                    where ["key_expired", "key_invalid", "key_banned", "key_revoked", "device_revoked", "device_key_invalid", "device_key_revoked", "license_policy_banned", "HTTP_401", "HTTP_403"].contains(code) {
                    // Preserve an unusable archive. A different license gets its
                    // own fresh identity and can never inherit this old device.
                }
            }
        }
        try context.validate()
        let pendingRecovery = try selected.hasPendingAuthorizedRecovery
        let hasEnrollment = try selected.persistedEnrollmentID() != nil
        if pendingRecovery || hasEnrollment {
            do {
                if pendingRecovery { throw DeviceIdentityError.identityMissing }
                _ = try selected.getOrCreateKey()
            }
            catch {
                // A changed signing identity can leave metadata readable while
                // the Secure Enclave/Keychain key is not. Only an explicit
                // signed admin recovery authorization may clear that namespace.
                let (data, _) = try await post("/api/v2/device/challenge", body: [
                    "key": context.licenseKey, "hwid": context.hwid,
                    "install_id": UUID().uuidString.lowercased(), "recover_installation": true
                ], signed: false, purpose: "device-challenge")
                let response = try dictionary(data)
                try context.validate()
                guard response["license_binding"] as? String == context.binding,
                      response["recovery_authorized"] as? Bool == true else {
                    throw ProtectedDownloadError.rejected("device_recovery_required")
                }
                try selected.resetAuthorizedInstallation()
            }
        }
        self.identity = selected
        return selected
    }

    private func ensureSession(auth: AuthManager, allowDeviceRecovery: Bool = true) async throws {
        guard let context = currentAuthContext else { throw FeaturePatchError.notAuthenticated }
        try context.validate()
        if !sessionID.isEmpty && sessionExpiry.timeIntervalSinceNow > 90 { return }
        if !sessionID.isEmpty && sessionExpiry.timeIntervalSinceNow > 0 {
            do {
                let (data, _) = try await post("/api/v2/novax/session/renew", body: [:], signed: true,
                                             purpose: "novax-session-renew-v2")
                try acceptSession(data)
                return
            } catch ProtectedDownloadError.rejected(let code)
                where ["session_expired", "device_key_invalid", "device_key_revoked", "device_revoked"].contains(code) {
                clearSession()
            }
        }
        clearSession()
        let identity = try await prepareIdentity(context)
        if try identity.persistedEnrollmentID() == nil {
            // The candidate stays only in memory until a signed challenge
            // confirms this active license. An expired legacy A cannot leave
            // fresh conflicting A keys/installation behind during migration.
            let installID = try identity.existingInstallationID() ?? UUID().uuidString.lowercased()
            let (challengeData, _) = try await post("/api/v2/device/challenge", body: [
                "key": context.licenseKey, "hwid": context.hwid, "install_id": installID
            ], signed: false, purpose: "device-challenge")
            let challenge = try dictionary(challengeData)
            guard let id = challenge["challenge_id"] as? String,
                  let value = challenge["challenge"] as? String,
                  challenge["license_binding"] as? String == context.binding,
                  let keyID = challenge["key_id"] as? Int, keyID > 0 else { throw ProtectedDownloadError.invalidResponse }
            try context.validate()
            try identity.persistInstallationID(installID)
            try identity.persistServerKeyID(keyID)
            let (signingKey, assurance) = try identity.getOrCreateKey()
            let (agreementKey, _) = try identity.getOrCreateAgreementKey()
            let signature = try identity.signEnrollment(challengeId: id, challenge: value,
                key: context.licenseKey, hwid: context.hwid, installId: installID,
                publicKeyX963: signingKey, assurance: assurance, agreementPublicKeyX963: agreementKey)
            let (enrollData, _) = try await post("/api/v2/device/enroll", body: [
                "challenge_id": id, "challenge": value, "key": context.licenseKey, "hwid": context.hwid,
                "install_id": installID, "public_key_x963": signingKey,
                "agreement_public_key_x963": agreementKey, "assurance_level": assurance.rawValue,
                "enrollment_revision": 2, "signature": signature
            ], signed: false, purpose: "device-enroll")
            let enrolled = try dictionary(enrollData)
            guard let deviceID = enrolled["device_key_id"] as? String else { throw ProtectedDownloadError.invalidResponse }
            try identity.persistEnrollment(deviceKeyId: deviceID)
        }
        do {
            let (loginData, _) = try await post("/api/v2/novax/session/open", body: [
                "app_release": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                "license_binding": context.binding
            ], signed: true, purpose: "novax-session-open-v2", bearer: false)
            try acceptSession(loginData)
        } catch ProtectedDownloadError.rejected("recipient_upgrade_required") {
            // Only a signed server response for THIS existing identity permits
            // creation of its first recipient key. Never repair a lost v2 key.
            let (legacySession, _) = try await post("/api/v2/novax/login", body: [
                "key": context.licenseKey, "hwid": context.hwid, "license_binding": context.binding,
                "app_release": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            ], signed: true, purpose: "novax-login-v2", bearer: false)
            try acceptSession(legacySession)
            let (agreement, _) = try identity.prepareLegacyRecipientUpgrade()
            let (signing, assurance) = try identity.getOrCreateKey()
            let installID = try identity.installationID()
            let (challengeData, _) = try await post("/api/v2/device/challenge", body: [
                "key": context.licenseKey, "hwid": context.hwid, "install_id": installID
            ], signed: false, purpose: "device-challenge")
            let challenge = try dictionary(challengeData)
            guard let id = challenge["challenge_id"] as? String, let value = challenge["challenge"] as? String else {
                throw ProtectedDownloadError.invalidResponse
            }
            let signature = try identity.signEnrollment(challengeId: id, challenge: value,
                key: context.licenseKey, hwid: context.hwid, installId: installID,
                publicKeyX963: signing, assurance: assurance, agreementPublicKeyX963: agreement)
            let (upgrade, _) = try await post("/api/v2/device/enroll", body: [
                "challenge_id": id, "challenge": value, "key": context.licenseKey, "hwid": context.hwid,
                "install_id": installID, "public_key_x963": signing, "assurance_level": assurance.rawValue,
                "agreement_public_key_x963": agreement, "enrollment_revision": 2, "signature": signature
            ], signed: true, purpose: "device-enroll")
            let upgraded = try dictionary(upgrade)
            guard let id = upgraded["device_key_id"] as? String else { throw ProtectedDownloadError.invalidResponse }
            try identity.persistEnrollment(deviceKeyId: id)
            // Replace the migration session with the normal revision-2 session.
            // Both its release/build and recipient binding now come from this app.
            clearSession()
            try await ensureSession(auth: auth, allowDeviceRecovery: false)
        } catch ProtectedDownloadError.rejected(let code)
            where allowDeviceRecovery && ["device_key_invalid", "device_key_revoked", "device_revoked"].contains(code) {
            try context.validate()
            // The signed server rejected this old installation. New enrollment
            // still requires its bound HWID and a single-use admin reset ticket.
            try identity.resetAuthorizedInstallation()
            clearSession()
            try await ensureSession(auth: auth, allowDeviceRecovery: false)
        }
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
        guard let expiry = formatter.date(from: expiryString), expiry > Date() else { throw ProtectedDownloadError.invalidResponse }
        sessionID = id; sessionToken = token; sessionExpiry = expiry
    }

    func sync(auth: AuthManager) async throws -> Data {
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try await beginOperation(requestedContext)
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            let (data, _) = try await post("/api/v2/artifacts/sync", body: [:], signed: true, purpose: "artifact-sync")
            await gate.release()
            return data
        } catch { await gate.release(); throw error }
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
            try await beginOperation(requestedContext, allowIntegrityIncident: true)
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

    /// Requests a two-hour quarantine for this cryptographically authenticated
    /// installation. The API derives the device/HWID from the signed P-256
    /// request and never accepts a client-selected victim identifier.
    func quarantineForJailbreak(auth: AuthManager, evidenceCodes: [String]) async -> Bool {
        let evidence = SideloadSecurityPolicy.confirmedJailbreakEvidence(evidenceCodes)
        guard auth.authState == .verified, !evidence.isEmpty else { return false }
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        var quarantined = false
        do {
            try Task.checkCancellation()
            try await beginOperation(requestedContext, allowIntegrityIncident: true)
            try await ensureSession(auth: auth)
            let integrityRoute = Obf.s([
                136, 198, 215, 206, 136, 209, 149, 136, 212, 194, 196, 210,
                213, 206, 211, 222, 136, 205, 198, 206, 203, 197, 213, 194,
                198, 204, 138, 214, 210, 198, 213, 198, 201, 211, 206, 201, 194
            ], 0xA7)
            let (data, _) = try await post(integrityRoute, body: [
                "evidence_codes": evidence,
                "app_release": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                "os_build": AppInfo.osBuild
            ], signed: true, purpose: "jailbreak-quarantine-v2")
            let response = try dictionary(data)
            quarantined = response["code"] as? String == "device_jailbreak_quarantined"
            if quarantined { clearSession() }
        } catch {
            // Detection still blocks and terminates locally if the network is
            // unavailable. Never fall back to an unsigned HWID/key report.
        }
        await gate.release()
        return quarantined
    }

    func download(_ patch: PatchItem, auth: AuthManager) async throws -> Data {
        let requestedContext = ProtectedAuthContext(auth)
        await gate.acquire()
        do {
            try Task.checkCancellation()
            try await beginOperation(requestedContext)
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
            try await beginOperation(requestedContext)
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
            try await beginOperation(requestedContext)
            try await ensureSession(auth: auth)
            try await ensureReleaseLease()
            let descriptor = try await resolveCodePatch(variant: variant, kind: kind)
            let result = try await downloadArtifact(descriptor, auth: auth)
            await gate.release()
            return result
        } catch { await gate.release(); throw error }
    }

    /// A short server lease binds every protected artifact request to a release
    /// document signed by Astra. Debug/simulator builds remain usable for local
    /// development. A device build without a seal MUST obtain an explicit signed
    /// compatibility response; it cannot locally declare itself trusted.
    private func ensureReleaseLease() async throws {
        let result = await ReleaseIntegrityRuntime.verify()
        guard !result.requiresLocalBlock else {
            ReleaseCommitBarrier.blockNewCommits()
            throw ProtectedDownloadError.rejected("client_integrity_failed")
        }
        guard result.enforced else { return }
        let subject = "\(result.releaseID)|\(result.sealDigest)|\(result.mask)|\(result.issue?.rawValue ?? "valid")"
        if releaseLeaseSubject != subject { releaseLease.clear() }
        if releaseLease.permitsTransfer(now: ProcessInfo.processInfo.systemUptime) { return }
        let started = ProcessInfo.processInfo.systemUptime
        let (data, _) = try await post("/api/v2/security/integrity", body: [
            "release_id": result.releaseID,
            "seal_digest": result.sealDigest.isEmpty ? String(repeating: "0", count: 64) : result.sealDigest,
            "check_mask": result.mask
        ], signed: true, purpose: "app-integrity-v1")
        let response = try dictionary(data)
        if result.isMissingSeal {
            guard SideloadSecurityPolicy.permitsUnsealedLease(code: response["code"] as? String,
                    assurance: response["assurance"] as? String) else {
                throw ProtectedDownloadError.rejected("release_verification_required")
            }
        }
        guard let ttl = response["lease_ttl_seconds"] as? Double else {
            throw ProtectedDownloadError.invalidResponse
        }
        try releaseLease.accept(ttl: ttl, requestStarted: started,
                                now: ProcessInfo.processInfo.systemUptime)
        releaseLeaseSubject = subject
    }

    /// Best-effort signed notification for a modified release. This deliberately
    /// never enrolls a device or opens a new session after integrity has failed.
    func reportReleaseIntegrityFailure(_ result: SignedReleaseCheckResult) async {
        guard result.requiresLocalBlock, let identity, !sessionID.isEmpty,
              !sessionToken.isEmpty, sessionExpiry > Date(),
              let deviceID = try? identity.persistedEnrollmentID(), !deviceID.isEmpty else { return }
        let id = sessionID, token = sessionToken
        await gate.acquire()
        do {
            var request = URLRequest(url: try endpoint("/api/v2/security/integrity"))
            request.httpMethod = "POST"
            request.timeoutInterval = 2
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "release_id": result.releaseID,
                "seal_digest": result.sealDigest.isEmpty ? String(repeating: "0", count: 64) : result.sealDigest,
                "check_mask": result.mask
            ], options: [.sortedKeys, .withoutEscapingSlashes])
            _ = try RequestProofService.shared.signRequest(
                request: &request, sessionId: id, deviceKeyId: deviceID, identity: identity)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 2
            configuration.timeoutIntervalForResource = 3
            let session = URLSession(configuration: configuration,
                                     delegate: CertPinningDelegate.shared, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            _ = try await session.data(for: request)
        } catch {
            // A reporting failure never keeps a compromised process alive.
        }
        clearSession()
        await gate.release()
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
        for attempt in 0..<3 {
            do { return try await downloadArtifactOnce(descriptor, auth: auth) }
            catch ProtectedDownloadError.rejected(let code)
                where attempt < 2 && ["grant_expired", "grant_invalid", "grant_replayed_or_revoked"].contains(code) {
                try Task.checkCancellation()
                try requireCurrentLicense(auth)
                // A delayed/consumed grant is never replayed. Allocate a new
                // grant with a new signed proof for the same licensed artifact.
            }
        }
        throw ProtectedDownloadError.invalidResponse
    }

    private func downloadArtifactOnce(_ descriptor: ProtectedArtifactDescriptor,
                                      auth: AuthManager) async throws -> ProtectedCodePatchDownload {
        guard UUID(uuidString: descriptor.artifactID) != nil,
              ["package", "mod", "original"].contains(descriptor.kind),
              ["ffth", "ffmax"].contains(descriptor.variant) else {
            throw ProtectedDownloadError.invalidResponse
        }
        let initialLicenseDigest = licenseDigest
        try await ensureReleaseLease()
        let (grantData, _) = try await post("/api/v2/artifacts/\(descriptor.artifactID)/grants",
            body: [:], signed: true, purpose: "artifact-grant")
        let granted = try dictionary(grantData)
        guard let grantID = granted["grant_id"] as? String, UUID(uuidString: grantID) != nil,
              granted["artifact_id"] as? String == descriptor.artifactID else {
            throw ProtectedDownloadError.invalidResponse
        }
        try await ensureReleaseLease()
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
        let plaintext = try decoder.decrypt(signedManifest: manifestData,
            signedGrant: grantDataJSON, ciphertext: ciphertext, recipientID: deviceID, sessionID: sessionID,
            requestNonce: nonce, expectedArtifactID: descriptor.artifactID, expectedGrantID: grantID)
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
