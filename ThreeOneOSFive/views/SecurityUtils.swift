import Foundation
import UIKit
import CryptoKit
import Security
import CommonCrypto
import CFNetwork

// MARK: - Keychain helpers (default signing access group; no hard-coded Team ID)

enum KeychainUtils {
    private static let lock = NSLock()
    static func save(key: String, value: String) -> Bool {
        saveStatus(key: key, value: value) == errSecSuccess
    }

    static func saveStatus(key: String, value: String) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard let data = value.data(using: .utf8) else { return errSecParam }

        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        // Updating preserves the previous value if Keychain is temporarily
        // unavailable. Never delete a valid HWID/license before a write succeeds.
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let update = SecItemUpdate(identityQuery as CFDictionary, values as CFDictionary)
        if update == errSecSuccess { return update }
        guard update == errSecItemNotFound else { return update }
        var insert = identityQuery
        values.forEach { insert[$0.key] = $0.value }
        let added = SecItemAdd(insert as CFDictionary, nil)
        if added == errSecSuccess { return added }
        if added == errSecDuplicateItem {
            return SecItemUpdate(identityQuery as CFDictionary, values as CFDictionary)
        }
        return added
    }

    static func read(key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
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
        lock.lock(); defer { lock.unlock() }
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

enum AstraServerTrust {
    static let protectedHost = "zynox.click"

    static let leafCertificatePins = AppSecurityConfiguration.tlsCertificatePins

    static func accepts(_ trust: SecTrust, host: String) -> Bool {
        guard host.caseInsensitiveCompare(protectedHost) == .orderedSame else { return false }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else { return false }

        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            for certificate in chain {
                let der = SecCertificateCopyData(certificate) as Data
                let pin = Data(SHA256.hash(data: der)).base64EncodedString()
                if leafCertificatePins.contains(pin) { return true }
            }
        }

        // Normal trust and hostname validation alone also accept a user CA.
        // No unpinned fallback, even when iOS trusts the certificate.
        return false
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

        guard let url = URL(string: "https://zynox.click/Nova-logo.png?network_probe=\(UUID().uuidString)") else {
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

// BEGIN STABLE HWID POLICY — compiled with isolated storage by regression tests.
enum StableDeviceHWID {
    private static let lock = NSLock()
    private static let tag = "deviceHwid"
    private static let fallbackTag = "deviceHwidFallbackV1"
    private static let fallbackPrefix = "ASTRA-HWID-v1-"

    private struct SavedHWID {
        let value: String
        let identity: String
    }

    private static func validated(_ data: Data) throws -> SavedHWID {
        guard data.count <= 4_096, String(data: data, encoding: .utf8) != nil else {
            throw DeviceIdentityError.invalidIdentity
        }
        // The strict decode above rejects malformed UTF-8. Preserve its BOM
        // here: String(data:encoding:) may consume one before comparison.
        let stored = String(decoding: data, as: UTF8.self)
        var value = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\u{feff}") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.utf8.count == 36, let uuid = UUID(uuidString: value) {
            return SavedHWID(value: value, identity: "uuid:" + uuid.uuidString)
        }
        throw DeviceIdentityError.invalidIdentity
    }

    private static func validatedFallback(_ data: Data) throws -> SavedHWID {
        guard let value = String(data: data, encoding: .utf8),
              value.utf8.count == fallbackPrefix.utf8.count + 36,
              value.hasPrefix(fallbackPrefix),
              let uuid = UUID(uuidString: String(value.dropFirst(fallbackPrefix.count))) else {
            throw DeviceIdentityError.invalidIdentity
        }
        return SavedHWID(value: value, identity: "fallback:" + uuid.uuidString)
    }

    static func isUsable(_ value: String) -> Bool {
        let data = Data(value.utf8)
        return (try? validated(data).value) == value || (try? validatedFallback(data).value) == value
    }

    private struct SavedPair {
        var primary: Data?, mirror: Data?
        var primaryError: Error?, mirrorError: Error?
    }

    private static func readPair(_ primary: DeviceIdentityStorage?, _ mirror: DeviceIdentityStorage?, tag: String) -> SavedPair {
        var pair = SavedPair()
        if let primary {
            do { pair.primary = try primary.read(tag) } catch { pair.primaryError = error }
        }
        if let mirror {
            do { pair.mirror = try mirror.read(tag) } catch { pair.mirrorError = error }
        }
        return pair
    }

    private static func selected(_ pair: SavedPair, parse: (Data) throws -> SavedHWID) throws -> SavedHWID? {
        let primary = pair.primary.flatMap { try? parse($0) }
        let mirror = pair.mirror.flatMap { try? parse($0) }
        if let primary, let mirror, primary.identity != mirror.identity {
            throw DeviceIdentityError.ambiguousIdentity
        }
        return primary ?? mirror
    }

    /// Synchronize only missing or already-valid copies. Invalid bytes remain
    /// untouched for diagnosis; a read failure never authorizes overwriting.
    private static func synchronize(_ value: SavedHWID, pair: SavedPair,
                                    primary: DeviceIdentityStorage?, mirror: DeviceIdentityStorage?,
                                    tag: String, parse: (Data) throws -> SavedHWID) {
        let bytes = Data(value.value.utf8)
        if pair.primary == nil, pair.primaryError == nil { try? primary?.write(tag, bytes) }
        if pair.mirrorError == nil,
           pair.mirror == nil || pair.mirror.flatMap({ try? parse($0) }) != nil,
           pair.mirror != bytes { try? mirror?.write(tag, bytes) }
    }

    private static func persistFallback(primary: DeviceIdentityStorage?, mirror: DeviceIdentityStorage?,
                                        generate: () -> UUID) throws -> String {
        let value = fallbackPrefix + generate().uuidString
        let bytes = Data(value.utf8)
        var firstError: Error?
        // Re-read any persisted value before writing its mirror, including a
        // failed-insert winner. The outer lock serializes this app process.
        if let primary {
            do { try primary.write(fallbackTag, bytes) } catch { firstError = error }
            let pair = readPair(primary, mirror, tag: fallbackTag)
            if let stored = try selected(pair, parse: validatedFallback) {
                synchronize(stored, pair: pair, primary: primary, mirror: mirror,
                            tag: fallbackTag, parse: validatedFallback)
                return stored.value
            }
            if pair.primary != nil || pair.mirror != nil { throw DeviceIdentityError.invalidIdentity }
            if let error = pair.primaryError { throw error }
            if let error = pair.mirrorError { throw error }
        }
        if let mirror {
            do { try mirror.write(fallbackTag, bytes) } catch { throw error }
            let pair = readPair(primary, mirror, tag: fallbackTag)
            if let stored = try selected(pair, parse: validatedFallback) { return stored.value }
            if let error = pair.mirrorError { throw error }
            if let error = pair.primaryError { throw error }
            throw DeviceIdentityError.invalidIdentity
        }
        throw firstError ?? DeviceIdentityError.identityMissing
    }

    /// The mirror contains a public HWID only, never keys, license or credentials.
    /// A primary read error without a known saved ID must not create a new device.
    static func resolve(storage: DeviceIdentityStorage, vendorID: String?,
                        mirror: DeviceIdentityStorage? = nil,
                        fallbackStorage: DeviceIdentityStorage? = nil,
                        fallbackMirror: DeviceIdentityStorage? = nil,
                        generateFallback: () -> UUID = { UUID() }) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let regular = readPair(storage, mirror, tag: tag)
        let fallback = readPair(fallbackStorage, fallbackMirror, tag: fallbackTag)
        let regularValue = try selected(regular, parse: validated)
        let fallbackValue = try selected(fallback, parse: validatedFallback)
        if regularValue != nil && fallbackValue != nil {
            // Returning a regular identity after publishing a fallback would
            // silently switch the server-bound HWID. Preserve both instead.
            throw DeviceIdentityError.ambiguousIdentity
        }
        if let regularValue {
            synchronize(regularValue, pair: regular, primary: storage, mirror: mirror, tag: tag, parse: validated)
            return regularValue.value
        }
        if let fallbackValue {
            synchronize(fallbackValue, pair: fallback, primary: fallbackStorage, mirror: fallbackMirror,
                        tag: fallbackTag, parse: validatedFallback)
            return fallbackValue.value
        }
        // Unknown/inaccessible data must not be mistaken for a new install.
        for error in [regular.primaryError, regular.mirrorError, fallback.primaryError, fallback.mirrorError] {
            if let error { throw error }
        }
        let regularMissing = regular.primary == nil && regular.mirror == nil
        let fallbackMissing = fallback.primary == nil && fallback.mirror == nil
        guard fallbackMissing else { throw DeviceIdentityError.invalidIdentity }
        if (!regularMissing || vendorID.flatMap(UUID.init(uuidString:)) == nil),
           fallbackStorage != nil || fallbackMirror != nil {
            return try persistFallback(primary: fallbackStorage, mirror: fallbackMirror, generate: generateFallback)
        }
        guard regularMissing else { throw DeviceIdentityError.invalidIdentity }
        guard let vendorID, UUID(uuidString: vendorID) != nil else {
            throw DeviceIdentityError.identityMissing
        }
        let data = Data(vendorID.utf8)
        do { try storage.write(tag, data) }
        catch {
            let writeError = error
            // Another writer can win SecItemAdd. Read its ID rather than
            // overwriting the winner with a newly observed IDFV.
            if let winner = try storage.read(tag) {
                let value = try validated(winner)
                try? mirror?.write(tag, Data(value.value.utf8))
                return value.value
            }
            guard let mirror else { throw writeError }
            try mirror.write(tag, data) // Publish only after durable local storage succeeds.
            return vendorID
        }
        try? mirror?.write(tag, data)
        return vendorID
    }

    static func isRetryable(_ error: Error) -> Bool {
        guard let identity = error as? DeviceIdentityError else { return false }
        switch identity {
        case .identityMissing: return true
        case .keychain(let status): return status == -25308 || status == -25291
        default: return false
        }
    }

    static func failureMessage(_ error: Error, protectedDataAvailable: Bool) -> String {
        if let identity = error as? DeviceIdentityError {
            switch identity {
            case .keychain(let status):
                if status == -34018 {
                    return "Bản ký Astra không có quyền truy cập Keychain. Hãy kiểm tra profile và quyền Keychain khi ký lại (HW02; OSStatus \(status))."
                }
                if !protectedDataAvailable {
                    return "Dữ liệu bảo mật chưa sẵn sàng. Hãy mở khóa iPhone rồi thử lại (HW01; OSStatus \(status))."
                }
                return "Keychain từ chối truy cập định danh thiết bị. Hãy thử lại; nếu vẫn lỗi, gửi mã này để kiểm tra bản ký (HW03; OSStatus \(status))."
            case .identityMissing:
                return protectedDataAvailable
                    ? "iOS chưa trả về định danh thiết bị. Astra sẽ tự đọc lại khi ứng dụng hoạt động; hãy thử lại sau giây lát (HW04)."
                    : "Định danh thiết bị chưa sẵn sàng. Hãy mở khóa iPhone rồi thử lại (HW01)."
            case .invalidIdentity:
                return "Chưa đọc được định danh đã lưu hoặc HWID dự phòng bền vững. Astra giữ nguyên dữ liệu; hãy sao chép thông tin lỗi để được kiểm tra (HW05-DATA)."
            case .ambiguousIdentity:
                return "Các bản lưu chứa định danh HWID khác nhau. Astra giữ nguyên dữ liệu và không tự đổi thiết bị; hãy sao chép thông tin lỗi để được kiểm tra (HW05-CONFLICT)."
            case .invalidInput: break
            }
        }
        let detail = error as NSError
        return "Không thể đọc hoặc lưu định danh thiết bị trong ứng dụng (HW06; \(detail.domain) \(detail.code))."
    }
}
// END STABLE HWID POLICY

struct DeviceUtils {

    /// Public identity backup in this application's private, protected storage.
    /// Private keys continue to use DeviceIdentityStorage.keychain exclusively.
    private static func hwidMirrorURL(create: Bool, fallback: Bool = false) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: create)
        let directory = base.appendingPathComponent("AstraDeviceIdentity", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
        }
        return directory.appendingPathComponent(fallback ? "hwid-fallback-v1" : "hwid-v1")
    }

    private static let hwidMirror = DeviceIdentityStorage(read: { _ in
        do { return try Data(contentsOf: hwidMirrorURL(create: false)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }, write: { _, data in
        let url = try hwidMirrorURL(create: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }, remove: { _ in
        // Identity is deliberately retained across logout and transient errors.
    })

    private static let hwidFallbackMirror = DeviceIdentityStorage(read: { _ in
        do { return try Data(contentsOf: hwidMirrorURL(create: false, fallback: true)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }, write: { _, data in
        let url = try hwidMirrorURL(create: true, fallback: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }, remove: { _ in
        // The application HWID survives logout just like the original HWID.
    })

    static func resolveHWID() throws -> String {
        try StableDeviceHWID.resolve(storage: .keychain,
            vendorID: UIDevice.current.identifierForVendor?.uuidString, mirror: hwidMirror,
            fallbackStorage: .keychain, fallbackMirror: hwidFallbackMirror)
    }

    static var deviceModel: String {
        var s = utsname()
        uname(&s)
        return Mirror(reflecting: s.machine).children.reduce("") { id, e in
            guard let v = e.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
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
