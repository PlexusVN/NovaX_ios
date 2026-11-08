import SwiftUI
import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    private(set) var authenticationRevision: UInt64 = 0

    @Published var authState: AuthState = .idle
    @Published var licenseKey: String = "" {
        didSet { if oldValue != licenseKey { authenticationRevision &+= 1 } }
    }
    @Published var hwid: String = DeviceUtils.hwid
    @Published var deviceName: String = DeviceUtils.deviceMarketingName
    @Published var keyType: KeyType = .basic
    @Published var expiresAt: Date?
    @Published var errorMessage: String?

    enum AuthState: Equatable {
        case idle
        case loading(String)
        case verified
        case error(String)
    }

    enum KeyType: String, Codable {
        case basic, pro, vip, admin
    }

    private let defaults = UserDefaults.standard
    private let keyKey = "saved_license_key"

    init() {
        loadSavedKey()
        let _ = DecoyAuth.deriveHWID(from: DeviceUtils.deviceModel)
        let _ = DecoyAuth.generateToken()
    }

    private func loadSavedKey() {
        if let keychainKey = KeychainUtils.read(key: "novax_saved_license_key"), !keychainKey.isEmpty {
            licenseKey = keychainKey
            return
        }
        if let saved = defaults.string(forKey: keyKey), !saved.isEmpty {
            licenseKey = saved
            _ = KeychainUtils.save(key: "novax_saved_license_key", value: saved)
            defaults.removeObject(forKey: keyKey)
        }
    }

    func login() async {
        authenticationRevision &+= 1
        let revision = authenticationRevision
        let _ = DecoyAuth.verifyKey(licenseKey, device: hwid)
        let _ = DecoyAuth.buildAuthRequest(key: licenseKey, hwid: hwid, secret: "x")

        guard !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authState = .error("Vui lòng nhập key kích hoạt")
            return
        }

        authState = .loading("Đang xác thực...")

        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let hw = hwid
        let devName = DeviceUtils.deviceMarketingName
        let secret = AppSecurityConfiguration.productSecret

        guard let request = try? LicenseVerification.request(
            origin: AppSecurityConfiguration.apiOrigin, key: key, hwid: hw,
            secret: secret, deviceName: devName) else {
            authState = .error("Liên kết không hợp lệ")
            return
        }

        do {
            let (data, response) = try await SecureAPIClient.shared.data(for: request)
            guard authenticationRevision == revision,
                  DeviceIdentityService.canonicalLicense(licenseKey) == DeviceIdentityService.canonicalLicense(key),
                  hwid == hw else { return }
            guard let httpResp = response as? HTTPURLResponse else {
                authState = .error("Không nhận được phản hồi từ máy chủ")
                return
            }
            if httpResp.statusCode == 429 || httpResp.statusCode >= 500 {
                authState = .error(LicenseVerification.message(statusCode: httpResp.statusCode, json: [:]))
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                authState = .error("Phản hồi từ máy chủ không hợp lệ")
                return
            }

            guard httpResp.statusCode == 200, json["success"] as? Bool == true else {
                authState = .error(LicenseVerification.message(statusCode: httpResp.statusCode, json: json))
                return
            }

            // HMAC verification — MANDATORY, reject if missing
            guard let serverHmac = json["hmac"] as? String, !serverHmac.isEmpty else {
                authState = .error("Phản hồi thiếu mã xác thực, vui lòng thử lại")
                return
            }
            let success = json["success"] as? Bool ?? false
            let rawType = json["type"] as? String ?? ""
            let expires = json["expires_at"] as? String ?? ""
            let computed = HMACUtils.compute(key: secret, message: "\(success)|\(rawType)|\(expires)")
            guard serverHmac == computed else {
                authState = .error("Lỗi xác thực phản hồi, vui lòng thử lại")
                return
            }

            if let rawType = json["type"] as? String {
                switch rawType.lowercased() {
                case "vip", "admin": keyType = .vip
                case "pro":          keyType = .pro
                default:             keyType = .basic
                }
            }

            if let expires = json["expires_at"] as? String {
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                expiresAt = df.date(from: expires)
            }

            licenseKey = key
            _ = KeychainUtils.save(key: "novax_saved_license_key", value: key)
            defaults.removeObject(forKey: keyKey)
            authState = .verified
            errorMessage = nil
            startMonitor()
            // ProtectedDownloadService enrolls with the recipient-bound contract
            // and verifies server signatures before accepting any device ID.
        } catch let error as URLError {
            guard authenticationRevision == revision else { return }
            switch error.code {
            case .notConnectedToInternet:
                authState = .error("Không có kết nối Internet")
            case .timedOut:
                authState = .error("Kết nối đến máy chủ bị quá thời gian")
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                authState = .error("Không thể kết nối đến máy chủ xác thực")
            case .networkConnectionLost:
                authState = .error("Mất kết nối mạng trong quá trình xác thực")
            case .secureConnectionFailed:
                authState = .error("Kết nối bảo mật thất bại")
            case .cancelled:
                authState = .error("Yêu cầu xác thực bị gián đoạn, vui lòng thử lại")
            default:
                authState = .error("Lỗi mạng: \(error.localizedDescription)")
            }
        } catch {
            guard authenticationRevision == revision else { return }
            authState = .error("Lỗi không xác định: \(error.localizedDescription)")
        }
    }

    func restoreSessionIfNeeded() async {
        guard !licenseKey.isEmpty else { return }
        let revision = authenticationRevision
        authState = .loading("Đang phục hồi phiên...")
        do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
        guard authenticationRevision == revision else { return }
        await login()
    }

    func logout() {
        ProtectedDownloadService.shared.requestLogout()
        clearSession()
        authState = .idle
    }

    private func clearSession() {
        authenticationRevision &+= 1
        licenseKey = ""
        keyType = .basic
        expiresAt = nil
        errorMessage = nil
        defaults.removeObject(forKey: keyKey)
        KeychainUtils.delete(key: "novax_saved_license_key")
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Re-verify monitor

    private var monitorTask: Task<Void, Never>?
    private var reVerifyFailCount = 0
    private let maxReVerifyRetries = 3

    private func startMonitor() {
        monitorTask?.cancel()
        reVerifyFailCount = 0
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                // Read failCount on MainActor to avoid data race
                let failCount = await MainActor.run { self?.reVerifyFailCount ?? 0 }
                let backoff = 60 * pow(2.0, Double(min(failCount, 3)))
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Re-verify — break if self deallocated or auth failed
                guard let self else { break }
                let result = await self.reVerify()
                if result == .authFailed {
                    break
                }
            }
        }
    }

    @discardableResult
    private func reVerify() async -> ReVerifyResult {
        guard !licenseKey.isEmpty else { return .authFailed }
        let revision = authenticationRevision

        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let hw = hwid
        let secret = AppSecurityConfiguration.productSecret

        guard let request = try? LicenseVerification.request(
            origin: AppSecurityConfiguration.apiOrigin, key: key, hwid: hw,
            secret: secret, deviceName: DeviceUtils.deviceMarketingName) else { return .authFailed }

        do {
            let (data, response) = try await SecureAPIClient.shared.data(for: request)
            guard authenticationRevision == revision, authState == .verified else { return .authFailed }
            guard let httpResp = response as? HTTPURLResponse else {
                reVerifyFailCount += 1
                return .networkError
            }
            // Transient HTTP/server errors must not erase a valid saved key.
            // Protected operations still require their own live server grants.
            if httpResp.statusCode == 429 || httpResp.statusCode >= 500 {
                reVerifyFailCount += 1
                return .networkError
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                reVerifyFailCount += 1
                return .networkError
            }

            if httpResp.statusCode == 200, json["success"] as? Bool == true {
                // HMAC verification — MANDATORY
                guard let serverHmac = json["hmac"] as? String, !serverHmac.isEmpty else {
                    clearSession()
                    authState = .error("Phản hồi thiếu mã xác thực. Hãy thử đăng nhập lại.")
                    return .authFailed
                }
                let success = json["success"] as? Bool ?? false
                let rawType = json["type"] as? String ?? ""
                let expires = json["expires_at"] as? String ?? ""
                let computed = HMACUtils.compute(key: secret, message: "\(success)|\(rawType)|\(expires)")
                guard serverHmac == computed else {
                    clearSession()
                    authState = .error("Không thể xác minh phản hồi máy chủ. Hãy thử đăng nhập lại.")
                    return .authFailed
                }
                if let rawType = json["type"] as? String {
                    switch rawType.lowercased() {
                    case "vip", "admin": keyType = .vip
                    case "pro":          keyType = .pro
                    default:             keyType = .basic
                    }
                }
                // Update expiresAt from re-verify response
                if let expires = json["expires_at"] as? String {
                    let df = ISO8601DateFormatter()
                    df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    expiresAt = df.date(from: expires)
                }
                reVerifyFailCount = 0
                return .ok
            } else {
                if LicenseVerification.isTransient(statusCode: httpResp.statusCode, json: json) {
                    reVerifyFailCount += 1
                    return .networkError
                }
                // Auth failure (key expired/banned) — logout and stop monitor
                let msg = LicenseVerification.message(statusCode: httpResp.statusCode, json: json)
                clearSession()
                authState = .error(msg)
                return .authFailed
            }
        } catch {
            guard authenticationRevision == revision, authState == .verified, !Task.isCancelled else { return .authFailed }
            // A foreground/security gate denial is not evidence that the server
            // stopped recognizing this license. Resume verification after recovery.
            if error is NetworkAccessError || error is CancellationError { return .networkError }
            reVerifyFailCount += 1
            if authState == .verified, reVerifyFailCount >= maxReVerifyRetries {
                authState = .error(reVerifyFailCount > 3
                    ? "Mất kết nối đến máy chủ trong thời gian dài"
                    : "Mất kết nối đến máy chủ, kiểm tra lại kết nối mạng")
                return .authFailed
            }
            return .networkError
        }
    }

    private enum ReVerifyResult {
        case ok, authFailed, networkError
    }
}
