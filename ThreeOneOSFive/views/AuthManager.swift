import SwiftUI
import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {

    @Published var authState: AuthState = .idle
    @Published var licenseKey: String = ""
    @Published var hwid: String = DeviceUtils.hwid
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
    }

    private func loadSavedKey() {
        if let saved = defaults.string(forKey: keyKey), !saved.isEmpty {
            licenseKey = saved
        }
    }

    func login() async {
        guard !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Vui long nhap key kich hoat"
            return
        }

        authState = .loading("Dang xac thuc...")

        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        let hw = hwid
        let secret = Obf.s([182, 204, 211, 161, 132, 178, 207, 214, 161, 214, 204, 174, 161, 146, 191, 146], 0xB0)

        let urlBase = Obf.s([219, 199, 199, 195, 192, 137, 156, 156, 195, 223, 214, 203, 198, 192, 158, 210, 198, 199, 219, 158, 210, 195, 218, 158, 220, 131, 130, 219, 157, 220, 221, 193, 214, 221, 215, 214, 193, 157, 208, 220, 222, 156, 210, 195, 218, 156, 197, 214, 193, 218, 213, 202, 140, 216, 214, 202, 142], 0xB3)
        let sepHwid = Obf.s([149, 219, 196, 218, 215, 142], 0xB3)
        let sepSecret = Obf.s([149, 192, 214, 208, 193, 214, 199, 142], 0xB3)

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedHw = hw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedSecret = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(urlBase)\(encodedKey)\(sepHwid)\(encodedHw)\(sepSecret)\(encodedSecret)") else {
            authState = .error("Lien ket khong hop le")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await pinnedSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                authState = .error("Khong nhan duoc phan hoi tu may chu")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                authState = .error("Phan hoi tu may chu khong hop le")
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
                    case "key_expired":       msg = "KEY da het han"
                    case "key_banned":        msg = "KEY da bi khoa"
                    case "key_invalid":       msg = "KEY khong hop le"
                    case "key_max_devices":   msg = "KEY da dat so thiet bi toi da"
                    case "key_used":          msg = "KEY da duoc su dung"
                    case "hwid_mismatch":     msg = "KEY khong khop voi thiet bi nay"
                    case "invalid_secret":    msg = "Loi xac thuc san pham"
                    default:                  msg = "Xac thuc that bai"
                    }
                } else if httpResp.statusCode == 404 {
                    msg = "May chu xac thuc khong kha dung"
                } else if httpResp.statusCode >= 500 {
                    msg = "May chu dang bao tri, vui long thu lai sau"
                } else {
                    msg = "Xac thuc that bai"
                }
                authState = .error(msg)
                return
            }

            if let serverHmac = json["hmac"] as? String {
                let success = json["success"] as? Bool ?? false
                let rawType = json["type"] as? String ?? ""
                let expires = json["expires_at"] as? String ?? ""
                let computed = HMACUtils.compute(key: secret, message: "\(success)|\(rawType)|\(expires)")
                guard serverHmac == computed else {
                    authState = .error("Loi xac thuc phan hoi, vui long thu lai")
                    return
                }
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

            defaults.set(key, forKey: keyKey)
            authState = .verified
            errorMessage = nil
            startMonitor()
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                authState = .error("Khong co ket noi Internet")
            case .timedOut:
                authState = .error("Ket noi den may chu bi qua thoi gian")
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                authState = .error("Khong the ket noi den may chu xac thuc")
            case .networkConnectionLost:
                authState = .error("Mat ket noi mang trong qua trinh xac thuc")
            case .secureConnectionFailed:
                authState = .error("Ket noi bao mat that bai")
            default:
                authState = .error("Loi mang: \(error.localizedDescription)")
            }
        } catch {
            authState = .error("Loi khong xac dinh: \(error.localizedDescription)")
        }
    }

    func restoreSessionIfNeeded() async {
        guard !licenseKey.isEmpty else { return }
        authState = .loading("Dang phuc hoi phien...")
        try? await Task.sleep(nanoseconds: 600_000_000)
        await login()
    }

    func logout() {
        authState = .idle
        licenseKey = ""
        keyType = .basic
        expiresAt = nil
        errorMessage = nil
        defaults.removeObject(forKey: keyKey)
        monitorTask?.cancel()
    }

    // MARK: - Re-verify monitor

    private var monitorTask: Task<Void, Never>?
    private var reVerifyFailCount = 0
    private let maxReVerifyRetries = 3
    private var reVerifyBackoff: Double { 60 * pow(2, Double(min(reVerifyFailCount, 3))) }

    private func startMonitor() {
        monitorTask?.cancel()
        reVerifyFailCount = 0
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let backoff = self?.reVerifyBackoff ?? 60
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                await self?.reVerify()
            }
        }
    }

    private func reVerify() async {
        guard !licenseKey.isEmpty else { return }
        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        let hw = hwid
        let secret = Obf.s([182, 204, 211, 161, 132, 178, 207, 214, 161, 214, 204, 174, 161, 146, 191, 146], 0xB0)

        let urlBase = Obf.s([219, 199, 199, 195, 192, 137, 156, 156, 195, 223, 214, 203, 198, 192, 158, 210, 198, 199, 219, 158, 210, 195, 218, 158, 220, 131, 130, 219, 157, 220, 221, 193, 214, 221, 215, 214, 193, 157, 208, 220, 222, 156, 210, 195, 218, 156, 197, 214, 193, 218, 213, 202, 140, 216, 214, 202, 142], 0xB3)
        let sepHwid = Obf.s([149, 219, 196, 218, 215, 142], 0xB3)
        let sepSecret = Obf.s([149, 192, 214, 208, 193, 214, 199, 142], 0xB3)

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedHw = hw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedSecret = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(urlBase)\(encodedKey)\(sepHwid)\(encodedHw)\(sepSecret)\(encodedSecret)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await pinnedSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if httpResp.statusCode == 200, json["success"] as? Bool == true {
                reVerifyFailCount = 0
                if let serverHmac = json["hmac"] as? String {
                    let success = json["success"] as? Bool ?? false
                    let rawType = json["type"] as? String ?? ""
                    let expires = json["expires_at"] as? String ?? ""
                    let computed = HMACUtils.compute(key: secret, message: "\(success)|\(rawType)|\(expires)")
                    guard serverHmac == computed else {
                        authState = .error("Loi xac thuc phan hoi, vui long dang nhap lai")
                        return
                    }
                }
                if let rawType = json["type"] as? String {
                    switch rawType.lowercased() {
                    case "vip", "admin": keyType = .vip
                    case "pro":          keyType = .pro
                    default:             keyType = .basic
                    }
                }
            } else {
                if authState == .verified {
                    let serverMsg = json["message"] as? String ?? ""
                    let code = json["code"] as? String ?? ""
                    let msg: String
                    if !serverMsg.isEmpty {
                        msg = serverMsg
                    } else {
                        switch code {
                        case "key_expired":     msg = "KEY da het han"
                        case "key_banned":      msg = "KEY da bi khoa"
                        case "key_invalid":     msg = "KEY khong hop le"
                        case "key_max_devices": msg = "KEY da dat so thiet bi toi da"
                        default:                msg = "Phien dang nhap het han, vui long dang nhap lai"
                        }
                    }
                    authState = .error(msg)
                }
            }
        } catch {
            reVerifyFailCount += 1
            if authState == .verified, reVerifyFailCount >= maxReVerifyRetries {
                authState = .error(reVerifyFailCount > 3
                    ? "Mat ket noi den may chu trong thoi gian dai"
                    : "Mat ket noi den may chu, kiem tra lai ket noi mang")
            }
        }
    }
}
