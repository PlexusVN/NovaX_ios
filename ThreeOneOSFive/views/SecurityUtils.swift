import Foundation
import UIKit
import CryptoKit
import Security
import CommonCrypto
import CFNetwork

// MARK: - Keychain helpers (sideload-safe: no entitlement dependency)

enum KeychainUtils {
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        // Delete by identity only. Including kSecValueData in the delete query
        // would fail whenever an existing item is being updated to new data.
        SecItemDelete(identityQuery as CFDictionary)

        // Try with access group first (works for sideload with matching entitlements)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return true }

        // Fallback: no access group (works across re-signing tools)
        let fallback: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(identityQuery as CFDictionary)
        return SecItemAdd(fallback as CFDictionary, nil) == errSecSuccess
    }

    static func read(key: String) -> String? {
        // Try primary query
        if let value = readInternal(key: key, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly) {
            return value
        }
        // Fallback: after re-signing, accessibility may differ
        return readInternal(key: key, accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    private static func readInternal(key: String, accessible: CFString) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: accessible
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - HMAC helpers

enum HMACUtils {
    static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { buf in
            CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func compute(key: String, message: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let msgData = message.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBuf in
            msgData.withUnsafeBytes { msgBuf in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBuf.baseAddress, keyData.count,
                       msgBuf.baseAddress, msgData.count,
                       &digest)
            }
        }
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Proxy / TLS interception protection

enum NetworkSecurityError: LocalizedError {
    case proxyConfigured
    case tlsInterceptionDetected
    case connectionUnverified

    var errorDescription: String? {
        switch self {
        case .proxyConfigured:
            return "Lỗi hệ thống: phát hiện HTTP/HTTPS proxy. Hãy tắt ProxyPin, proxy hoặc VPN bắt gói tin rồi thử lại. LocalDevVPN của AirLift vẫn được hỗ trợ."
        case .tlsInterceptionDetected:
            return "Không thể xác minh chứng chỉ máy chủ. Nếu đang dùng ProxyPin hoặc proxy HTTPS, hãy tắt proxy rồi kiểm tra lại."
        case .connectionUnverified:
            return "Chưa xác minh được kết nối bảo mật. Hãy kiểm tra mạng rồi thử lại."
        }
    }
}

final class CertPinningDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = CertPinningDelegate()

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(AstraServerTrust.protectedHost) == .orderedSame,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard AstraServerTrust.accepts(trust, host: challenge.protectionSpace.host) else {
            Task { @MainActor in NetworkAccessGate.shared.recordCertificateFailure() }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never replay credentials, a signed body or a request proof at a
        // redirect target, even if it happens to use the same host.
        completionHandler(nil)
    }
}

private final class ProxyProbeDelegate: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var rejectedTrust = false
    private var verifiedTrust = false

    var detectedInterception: Bool {
        lock.lock(); defer { lock.unlock() }
        return rejectedTrust
    }
    var verifiedPinnedTrust: Bool {
        lock.lock(); defer { lock.unlock() }
        return verifiedTrust && !rejectedTrust
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(AstraServerTrust.protectedHost) == .orderedSame,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let accepted = AstraServerTrust.accepts(trust, host: challenge.protectionSpace.host)
        lock.lock()
        verifiedTrust = verifiedTrust || accepted
        rejectedTrust = rejectedTrust || !accepted
        lock.unlock()
        completionHandler(accepted ? .useCredential : .cancelAuthenticationChallenge,
                          accepted ? URLCredential(trust: trust) : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class NetworkSecurityGuard {
    static let shared = NetworkSecurityGuard()

    private init() {}

    func requireSafeConnection() async throws {
        switch await probeConnection() {
        case .allowed: return
        case .blocked(let message), .unavailable(let message):
            throw NetworkAccessError.denied(message)
        }
    }

    /// A fresh, isolated session reduces connection reuse. URLSession does not
    /// expose a universal "disable TLS session resumption" switch: if no actual
    /// server-trust challenge was verified, the result remains unavailable.
    /// The probe never calls SecureAPIClient and never carries API credentials.
    func probeConnection() async -> NetworkProbeResult {
        if Self.hasExplicitSystemProxy() {
            return .blocked(NetworkSecurityError.proxyConfigured.localizedDescription)
        }
        guard !Task.isCancelled else { return .unavailable(NetworkSecurityError.connectionUnverified.localizedDescription) }
        let delegate = ProxyProbeDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpShouldUsePipelining = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let url = URL(string: AstraServerTrust.protectedOrigin
                            + "/Nova-logo.png?network_probe=\(UUID().uuidString)") else {
            return .unavailable(NetworkSecurityError.connectionUnverified.localizedDescription)
        }
        var request = URLRequest(url: url)
        // Express serves HEAD for this GET route without transferring the
        // 1.4 MiB logo body on every five-second trust probe.
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("close", forHTTPHeaderField: "Connection")
        do {
            let (_, response) = try await withTaskCancellationHandler(operation: {
                try await session.data(for: request)
            }, onCancel: { session.invalidateAndCancel() })
            if Self.hasExplicitSystemProxy() {
                return .blocked(NetworkSecurityError.proxyConfigured.localizedDescription)
            }
            if delegate.detectedInterception {
                return .blocked(NetworkSecurityError.tlsInterceptionDetected.localizedDescription)
            }
            guard !Task.isCancelled, delegate.verifiedPinnedTrust,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.host?.caseInsensitiveCompare(AstraServerTrust.protectedHost) == .orderedSame else {
                return .unavailable(NetworkSecurityError.connectionUnverified.localizedDescription)
            }
            return .allowed
        } catch {
            if delegate.detectedInterception {
                return .blocked(NetworkSecurityError.tlsInterceptionDetected.localizedDescription)
            }
            return .unavailable(NetworkSecurityError.connectionUnverified.localizedDescription)
        }
    }

    private static func hasExplicitSystemProxy() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }

        func dictionaryHasProxy(_ dictionary: [String: Any]) -> Bool {
            func enabled(_ key: String) -> Bool {
                if let number = dictionary[key] as? NSNumber { return number.boolValue }
                if let boolean = dictionary[key] as? Bool { return boolean }
                return false
            }
            // Several CFNetwork proxy constants are marked unavailable for an
            // iOS deployment target even though the settings dictionary uses
            // these stable key names. Reading the dictionary by key keeps this
            // check available on-device without relying on macOS-only symbols.
            return enabled("HTTPEnable")
                || enabled("HTTPSEnable")
                || enabled("SOCKSEnable")
                || enabled("ProxyAutoConfigEnable")
                || enabled("ProxyAutoDiscoveryEnable")
        }

        if dictionaryHasProxy(settings) { return true }

        // Wi-Fi/manual proxies can be reported only inside __SCOPED__. Inspect
        // every interface, including utun, but only react to explicit proxy
        // flags. LocalDevVPN configures a route to 10.7.0.1 and no proxy flags,
        // so its AirLift tunnel remains allowed.
        if let scoped = settings["__SCOPED__"] as? [String: Any] {
            for value in scoped.values {
                if let dictionary = value as? [String: Any], dictionaryHasProxy(dictionary) {
                    return true
                }
            }
        }
        return false
    }
}

// Legacy API (backward compat)
var expectedServerPin: String { "7NfgIVpP+fdJQCMiloG7ljIWxP5OZEiAGfsc6+jgcQA=" }

// MARK: - Device Utils

struct DeviceUtils {

    /// HWID: Sử dụng trực tiếp UID định danh của thiết bị (identifierForVendor), không băm hay lấy phần khác.
    static var hwid: String {
        // Lấy trực tiếp UID định danh của máy
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString, !vendorID.isEmpty {
            _ = KeychainUtils.save(key: "deviceHwid", value: vendorID)
            return vendorID
        }
        // Fallback đọc từ Keychain nếu đã lưu UID trước đó (dạng UUID hợp lệ có dấu gạch ngang)
        if let cached = KeychainUtils.read(key: "deviceHwid"), !cached.isEmpty, cached.contains("-") {
            return cached
        }
        // Fallback tạo UID mới bền vững nếu hệ thống không trả về vendorID
        let freshUID = UUID().uuidString
        _ = KeychainUtils.save(key: "deviceHwid", value: freshUID)
        return freshUID
    }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }
        guard !bytes.isEmpty else { return "Unknown" }
        return String(cString: bytes).trimmingCharacters(in: .whitespaces)
    }

    /// Tên thương mại thân thiện của thiết bị (vd: iPhone 18 Pro Max, iPhone 16 Pro, iPad Pro,...)
    static var deviceMarketingName: String {
        #if targetEnvironment(simulator)
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simModel.isEmpty {
            return friendlyModelName(for: simModel)
        }
        return "iPhone 18 Pro Max"
        #else
        let model = deviceModel
        let friendly = friendlyModelName(for: model)
        if friendly != model && !friendly.isEmpty {
            return friendly
        }
        let devName = UIDevice.current.name
        if !devName.isEmpty && devName != "iPhone" && devName != "iPad" {
            return devName
        }
        return friendly.isEmpty ? "iPhone" : friendly
        #endif
    }

    /// Bản đồ tra cứu mã phần cứng utsname sang tên thương mại
    static func friendlyModelName(for identifier: String) -> String {
        switch identifier {
        // iPhone 18 & 17 Series
        case "iPhone18,1": return "iPhone 17 Pro"
        case "iPhone18,2": return "iPhone 17 Pro Max"
        case "iPhone18,3": return "iPhone 17"
        case "iPhone18,4": return "iPhone 17 Air"
        case "iPhone18,5": return "iPhone 18"
        case "iPhone18,6": return "iPhone 18 Pro"
        case "iPhone18,7": return "iPhone 18 Pro Max"

        // iPhone 16 Series
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,5": return "iPhone 16e"

        // iPhone 15 Series
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"

        // iPhone 14 Series
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"

        // iPhone 13 Series
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"

        // iPhone 12 Series
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"

        // iPhone 11 Series
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"

        // iPhone SE
        case "iPhone12,8": return "iPhone SE (2nd gen)"
        case "iPhone14,6": return "iPhone SE (3rd gen)"

        // iPhone XS / XR / X
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone10,3", "iPhone10,6": return "iPhone X"

        // iPad Models
        case let s where s.hasPrefix("iPad"):
            return "iPad"

        default:
            if identifier.hasPrefix("iPhone") {
                return "iPhone (\(identifier))"
            }
            return identifier
        }
    }

    static var osVersion: String { UIDevice.current.systemVersion }

    static var chipName: String {
        let model = deviceModel
        if model.contains("iPhone17") || model.contains("iPhone16,6") { return "A18 / A18 Pro" }
        if model.contains("iPhone15") { return "A17 Pro" }
        if model.contains("iPhone14,7") || model.contains("iPhone14,8") { return "A15 Bionic" }
        if model.contains("iPhone14") { return "A15 Bionic" }
        if model.contains("iPhone13") { return "A15 / A14 Bionic" }
        if model.contains("iPhone12") { return "A14 / A13 Bionic" }
        if model.contains("iPhone11") { return "A13 Bionic" }
        return "Apple Silicon"
    }

    static var totalRAM: String {
        let mem = ProcessInfo.processInfo.physicalMemory
        return "\(mem / 1_073_741_824) GB"
    }

    static var cpuCores: Int { ProcessInfo.processInfo.processorCount }

    static var screenResolution: String {
        let s = UIScreen.main.nativeBounds
        return "\(Int(s.width))x\(Int(s.height))"
    }

    static var refreshRate: Int {
        Int(UIScreen.main.maximumFramesPerSecond)
    }

    static var batteryPercent: Int {
        guard Thread.isMainThread else { return 0 }
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 0 : Int(level * 100)
    }

    private static func sha256Hex(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Obfuscation Utilities (Enhanced)

enum Obf {

    // MARK: - XOR Decode (original)
    static func s(_ data: [UInt8], _ key: UInt8) -> String {
        String(decoding: data.map { $0 ^ key }, as: UTF8.self)
    }

    // MARK: - XOR + Rotate (layer 2)
    static func s2(_ data: [UInt8], _ key: UInt8, _ rotateBy: UInt8) -> String {
        let decoded = data.map { ($0 ^ key).addingReportingOverflow(rotateBy).partialValue }
        return String(decoding: decoded, as: UTF8.self)
    }

    // MARK: - XOR + Byte Swap (layer 3)
    static func s3(_ data: [UInt8], _ key: UInt8) -> String {
        let decoded = data.map { byte -> UInt8 in
            let xored = byte ^ key
            return ((xored & 0xF0) >> 4) | ((xored & 0x0F) << 4)
        }
        return String(decoding: decoded, as: UTF8.self)
    }

    // MARK: - SHA256 helper
    static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Fake endpoint (decoy)
    static func fakeEndpoint() -> String {
        let parts = ["https", "api", "auth", "validate", "key", "check"]
        return parts.joined(separator: ".") + "/v" + "\(parts.count)"
    }

    // MARK: - HMAC decoy
    static func fakeHMAC(_ input: String) -> String {
        var hash: UInt32 = 0xDEADBEEF
        for byte in input.utf8 {
            hash ^= UInt32(byte)
            hash = (hash &<< 3) | (hash &>> 29)
            hash &+= 0x9E3779B9
        }
        return String(format: "%08x", hash)
    }
}
