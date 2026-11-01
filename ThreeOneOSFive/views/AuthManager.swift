import SwiftUI
import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {

    @Published var authState: AuthState = .idle
    @Published var licenseKey: String = ""
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

    private let pinnedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config,
                          delegate: CertPinningDelegate.shared,
                          delegateQueue: nil)
    }()

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
        let _ = DecoyAuth.verifyKey(licenseKey, device: hwid)
        let _ = DecoyAuth.buildAuthRequest(key: licenseKey, hwid: hwid, secret: "x")

        guard !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            authState = .error("Vui lòng nhập key kích hoạt")
            return
        }

        authState = .loading("Đang xác thực...")

        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        let hw = hwid
        let devName = DeviceUtils.deviceMarketingName
        let secret = Obf.s([254, 223, 198, 209, 232, 157, 209, 197, 196, 216, 157, 219, 213, 201], 0xB0)

        let urlBase = Obf.s([219, 199, 199, 195, 192, 137, 156, 156, 201, 202, 221, 220, 203, 157, 208, 223, 218, 208, 216, 156, 210, 195, 218, 156, 197, 214, 193, 218, 213, 202, 140, 216, 214, 202, 142], 0xB3)
        let sepHwid = Obf.s([149, 219, 196, 218, 215, 142], 0xB3)
        let sepSecret = Obf.s([149, 192, 214, 208, 193, 214, 199, 142], 0xB3)
        let sepDevName = "&device_name="

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedHw = hw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedSecret = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedDevName = devName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(urlBase)\(encodedKey)\(sepHwid)\(encodedHw)\(sepSecret)\(encodedSecret)\(sepDevName)\(encodedDevName)") else {
            authState = .error("Liên kết không hợp lệ")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(devName, forHTTPHeaderField: "X-Device-Name")

        do {
            let (data, response) = try await pinnedSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                authState = .error("Không nhận được phản hồi từ máy chủ")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                authState = .error("Phản hồi từ máy chủ không hợp lệ")
                return
            }

            guard httpResp.statusCode == 200, json["success"] as? Bool == true else {
                let serverMsg = json["message"] as? String ?? ""
                let code = json["code"] as? String ?? ""

                let msg: String
                if !serverMsg.isEmpty {
                    msg = serverMsg
                } else if !code.isEmpty {
                    switch code {
                    case "key_expired":       msg = "KEY đã hết hạn"
                    case "key_banned":        msg = "KEY đã bị khóa"
                    case "key_invalid":       msg = "KEY không hợp lệ"
                    case "key_max_devices":   msg = "KEY đã đạt số thiết bị tối đa"
                    case "key_used":          msg = "KEY đã được sử dụng"
                    case "hwid_mismatch":     msg = "KEY không khớp với thiết bị này"
                    case "invalid_secret":    msg = "Lỗi xác thực sản phẩm"
                    default:                  msg = "Xác thực thất bại"
                    }
                } else if httpResp.statusCode == 404 {
                    msg = "Máy chủ xác thực không khả dụng"
                } else if httpResp.statusCode >= 500 {
                    msg = "Máy chủ đang bảo trì, vui lòng thử lại sau"
                } else {
                    msg = "Xác thực thất bại"
                }
                authState = .error(msg)
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

            _ = KeychainUtils.save(key: "novax_saved_license_key", value: key)
            defaults.removeObject(forKey: keyKey)
            authState = .verified
            errorMessage = nil
            startMonitor()
            Task { [weak self] in
                await self?.enrollDeviceIfNeeded(key: key, hwid: hw)
            }
        } catch let error as URLError {
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
            default:
                authState = .error("Lỗi mạng: \(error.localizedDescription)")
            }
        } catch {
            authState = .error("Lỗi không xác định: \(error.localizedDescription)")
        }
    }

    func restoreSessionIfNeeded() async {
        guard !licenseKey.isEmpty else { return }
        authState = .loading("Đang phục hồi phiên...")
        try? await Task.sleep(nanoseconds: 600_000_000)
        await login()
    }

    func logout() {
        clearSession()
        authState = .idle
    }

    private func clearSession() {
        licenseKey = ""
        keyType = .basic
        expiresAt = nil
        errorMessage = nil
        defaults.removeObject(forKey: keyKey)
        KeychainUtils.delete(key: "novax_saved_license_key")
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Astra Anti-Crack v2 Device Enrollment

    private func enrollDeviceIfNeeded(key: String, hwid: String) async {
        guard DeviceIdentityService.shared.enrolledDeviceKeyId == nil else { return }
        do {
            let (pubKeyX963, assurance) = try DeviceIdentityService.shared.getOrCreateKey()
            let installId = DeviceIdentityService.shared.installId

            guard let challengeUrl = URL(string: "https://zynox.click/api/v2/device/challenge") else { return }
            var challengeReq = URLRequest(url: challengeUrl)
            challengeReq.httpMethod = "POST"
            challengeReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            challengeReq.timeoutInterval = 10
            let cBody: [String: Any] = [
                "key": key,
                "hwid": hwid,
                "install_id": installId
            ]
            challengeReq.httpBody = try JSONSerialization.data(withJSONObject: cBody)

            let (cData, cResp) = try await pinnedSession.data(for: challengeReq)
            guard (cResp as? HTTPURLResponse)?.statusCode == 200,
                  let cJson = try JSONSerialization.jsonObject(with: cData) as? [String: Any],
                  let challengeId = cJson["challenge_id"] as? String,
                  let challenge = cJson["challenge"] as? String else {
                return
            }

            let signature = try DeviceIdentityService.shared.signEnrollment(
                challengeId: challengeId,
                challenge: challenge,
                key: key,
                hwid: hwid,
                installId: installId,
                publicKeyX963: pubKeyX963,
                assurance: assurance
            )

            guard let enrollUrl = URL(string: "https://zynox.click/api/v2/device/enroll") else { return }
            var enrollReq = URLRequest(url: enrollUrl)
            enrollReq.httpMethod = "POST"
            enrollReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            enrollReq.timeoutInterval = 10
            let eBody: [String: Any] = [
                "challenge_id": challengeId,
                "challenge": challenge,
                "key": key,
                "hwid": hwid,
                "install_id": installId,
                "public_key_x963": pubKeyX963,
                "assurance_level": assurance.rawValue,
                "signature": signature
            ]
            enrollReq.httpBody = try JSONSerialization.data(withJSONObject: eBody)

            let (eData, eResp) = try await pinnedSession.data(for: enrollReq)
            if (eResp as? HTTPURLResponse)?.statusCode == 200,
               let eJson = try JSONSerialization.jsonObject(with: eData) as? [String: Any],
               let deviceKeyId = eJson["device_key_id"] as? String {
                DeviceIdentityService.shared.enrolledDeviceKeyId = deviceKeyId
            }
        } catch {
            // Shadow mode: enrollment failure does not block login in early phases
        }
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

        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        let hw = hwid
        let secret = Obf.s([254, 223, 198, 209, 232, 157, 209, 197, 196, 216, 157, 219, 213, 201], 0xB0)

        let urlBase = Obf.s([219, 199, 199, 195, 192, 137, 156, 156, 201, 202, 221, 220, 203, 157, 208, 223, 218, 208, 216, 156, 210, 195, 218, 156, 197, 214, 193, 218, 213, 202, 140, 216, 214, 202, 142], 0xB3)
        let sepHwid = Obf.s([149, 219, 196, 218, 215, 142], 0xB3)
        let sepSecret = Obf.s([149, 192, 214, 208, 193, 214, 199, 142], 0xB3)

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedHw = hw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedSecret = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(urlBase)\(encodedKey)\(sepHwid)\(encodedHw)\(sepSecret)\(encodedSecret)") else { return .authFailed }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await pinnedSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else { return .authFailed }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .authFailed }

            if httpResp.statusCode == 200, json["success"] as? Bool == true {
                // HMAC verification — MANDATORY
                guard let serverHmac = json["hmac"] as? String, !serverHmac.isEmpty else {
                    return .authFailed
                }
                let success = json["success"] as? Bool ?? false
                let rawType = json["type"] as? String ?? ""
                let expires = json["expires_at"] as? String ?? ""
                let computed = HMACUtils.compute(key: secret, message: "\(success)|\(rawType)|\(expires)")
                guard serverHmac == computed else {
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
                // Auth failure (key expired/banned) — logout and stop monitor
                let serverMsg = json["message"] as? String ?? ""
                let code = json["code"] as? String ?? ""
                let msg: String
                if !serverMsg.isEmpty {
                    msg = serverMsg
                } else {
                    switch code {
                    case "key_expired":     msg = "KEY đã hết hạn"
                    case "key_banned":      msg = "KEY đã bị khóa"
                    case "key_invalid":     msg = "KEY không hợp lệ"
                    case "key_max_devices": msg = "KEY đã đạt số thiết bị tối đa"
                    default:                msg = "Phiên đăng nhập hết hạn, vui lòng đăng nhập lại"
                    }
                }
                clearSession()
                authState = .error(msg)
                return .authFailed
            }
        } catch {
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
