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

        // Try with access group first (works for sideload with matching entitlements)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return true }

        // Fallback: no access group (works across re-signing tools)
        let fallback: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(fallback as CFDictionary)
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

    var errorDescription: String? {
        switch self {
        case .proxyConfigured:
            return "Lỗi hệ thống: phát hiện HTTP/HTTPS proxy. Hãy tắt ProxyPin, proxy hoặc VPN bắt gói tin rồi thử lại. LocalDevVPN của AirLift vẫn được hỗ trợ."
        case .tlsInterceptionDetected:
            return "Lỗi hệ thống: kết nối HTTPS đang bị giải mã bởi chứng chỉ CA proxy. Hãy tắt ProxyPin/proxy VPN và gỡ hoặc tắt tin cậy chứng chỉ CA rồi thử lại."
        }
    }
}

private enum AstraServerTrust {
    static let protectedHost = "zynox.click"

    // SHA-256 of the DER certificates currently authorized for zynox.click:
    // the active leaf, Google Trust Services WE1 intermediate, and its
    // GlobalSign ECC Root CA R4. Keeping the intermediate/root pins permits
    // ordinary leaf renewal without accepting a user-installed MITM CA.
    private static let certificatePins: Set<String> = [
        "IdQUF8E+9XNz3x4jmjWBYdYAZvahNfxagxuz9wc77wA=",
        "oof/q3Ysxpom1IIDft9wH2U86JkCXGKn5cuIu5tBnLs=",
        "sIXXC5ZPGRpz5K8NVK56Dgeq/a+bcd0IYhOKtzJaJKI="
    ]

    static func accepts(_ trust: SecTrust, host: String) -> Bool {
        guard host.caseInsensitiveCompare(protectedHost) == .orderedSame else { return false }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else { return false }

        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return false }
        for certificate in chain {
            let der = SecCertificateCopyData(certificate) as Data
            let pin = Data(SHA256.hash(data: der)).base64EncodedString()
            if certificatePins.contains(pin) { return true }
        }
        return false
    }
}

final class CertPinningDelegate: NSObject, URLSessionDelegate {
    static let shared = CertPinningDelegate()

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(AstraServerTrust.protectedHost) == .orderedSame,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard AstraServerTrust.accepts(trust, host: challenge.protectionSpace.host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private final class ProxyProbeDelegate: NSObject, URLSessionDelegate {
    private let lock = NSLock()
    private var rejectedTrust = false

    var detectedInterception: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejectedTrust
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(AstraServerTrust.protectedHost) == .orderedSame,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if AstraServerTrust.accepts(trust, host: challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            lock.lock()
            rejectedTrust = true
            lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

final class NetworkSecurityGuard {
    static let shared = NetworkSecurityGuard()

    private init() {}

    func requireSafeConnection() async throws {
        if Self.hasExplicitSystemProxy() {
            throw NetworkSecurityError.proxyConfigured
        }

        let delegate = ProxyProbeDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let url = URL(string: "https://zynox.click/Nova-logo.png") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            _ = try await session.data(for: request)
        } catch {
            if delegate.detectedInterception {
                throw NetworkSecurityError.tlsInterceptionDetected
            }
            // Offline/DNS failures are handled by the protected API call. They
            // must not be mislabeled as a proxy or block LocalDevVPN/AirLift.
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
var expectedServerPin: String { "oof/q3Ysxpom1IIDft9wH2U86JkCXGKn5cuIu5tBnLs=" }

// MARK: - Device Utils

struct DeviceUtils {

    /// HWID = hardware-derived (identifierForVendor + model + bundleID)
    /// Each device produces a unique, non-spoofable HWID.
    /// Cracker cannot predict HWID of other devices.
    static var hwid: String {
        if let cached = KeychainUtils.read(key: "deviceHwid") {
            return cached
        }
        let vendorID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let model = deviceModel
        let bundleID = Bundle.main.bundleIdentifier ?? "com.novax"
        let combined = "\(vendorID)|\(model)|\(bundleID)"
        let newHwid = sha256Hex(combined).prefix(16).lowercased()
        if KeychainUtils.save(key: "deviceHwid", value: newHwid) {
            return newHwid
        }
        return sha256Hex(combined).prefix(16).lowercased()
    }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }
        guard !bytes.isEmpty else { return "Unknown" }
        return String(cString: bytes).trimmingCharacters(in: .whitespaces)
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
