import Foundation
import Security

/// Signs exact request bytes. A proof cannot be moved to a query, redirect,
/// different body or streamed upload whose bytes have not been hashed.
public final class RequestProofService {
    public static let shared = RequestProofService()
    private let counterQueue = DispatchQueue(label: "click.zynox.counterQueue")
    private let counterKeychainKey = "novax_proof_monotonic_counter"
    private var inMemoryCounter: Int64 = 0
    private init() {}

    public func nextCounter() throws -> Int64 {
        try counterQueue.sync {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: counterKeychainKey,
                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            var stored: Int64 = 0
            if status == errSecSuccess {
                guard let data = result as? Data, let text = String(data: data, encoding: .utf8),
                      let value = Int64(text), value > 0 else { throw DeviceIdentityError.invalidIdentity }
                stored = value
            } else if status != errSecItemNotFound {
                throw DeviceIdentityError.keychain(status)
            }
            let current = max(stored, inMemoryCounter)
            // Backend parses a JavaScript safe integer, not an arbitrary Int64.
            guard current < 9_007_199_254_740_991 else { throw DeviceIdentityError.invalidIdentity }
            let next = current + 1
            let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                          kSecAttrAccount as String: counterKeychainKey]
            let values: [String: Any] = [kSecValueData as String: Data(String(next).utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            var write = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
            if write == errSecItemNotFound {
                var insert = identity
                values.forEach { insert[$0.key] = $0.value }
                write = SecItemAdd(insert as CFDictionary, nil)
            }
            guard write == errSecSuccess else { throw DeviceIdentityError.keychain(write) }
            inMemoryCounter = next
            return next
        }
    }

    public func generateNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw DeviceIdentityError.keychain(status) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func sha256Hex(_ data: Data) -> String { HMACUtils.sha256Hex(data) }

    @discardableResult
    public func signRequest(request: inout URLRequest, sessionId: String,
                            deviceKeyId: String, identity: DeviceIdentityService = .shared) throws -> String {
        try SecureAPIClient.validate(request)
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil,
              request.httpBodyStream == nil,
              UUID(uuidString: deviceKeyId) != nil else {
            throw DeviceIdentityError.invalidInput
        }
        let method = request.httpMethod?.uppercased() ?? "GET"
        let bootstrap = method == "POST" && sessionId.isEmpty &&
            ["/api/v2/novax/login", "/api/v2/novax/session/open", "/api/v2/device/context"].contains(components.path)
        guard bootstrap || UUID(uuidString: sessionId) != nil else { throw DeviceIdentityError.invalidInput }
        guard ["GET", "POST", "PUT", "DELETE", "HEAD"].contains(method) else {
            throw DeviceIdentityError.invalidInput
        }
        let path = components.percentEncodedPath
        let bodySha = sha256Hex(request.httpBody ?? Data())
        let nonce = try generateNonce()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let counter = try nextCounter()
        let signature = try identity.signRequest(
            method: method, path: path, bodySha256: bodySha,
            sessionId: sessionId, deviceKeyId: deviceKeyId, nonce: nonce,
            timestamp: timestamp, counter: counter)

        request.httpMethod = method
        request.setValue("2", forHTTPHeaderField: "X-Astra-Protocol")
        request.setValue(deviceKeyId, forHTTPHeaderField: "X-Astra-Device-Key")
        request.setValue(sessionId, forHTTPHeaderField: "X-Astra-Session")
        request.setValue(nonce, forHTTPHeaderField: "X-Astra-Nonce")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-Astra-Timestamp")
        request.setValue(String(counter), forHTTPHeaderField: "X-Astra-Counter")
        request.setValue(bodySha, forHTTPHeaderField: "X-Astra-Body-SHA256")
        request.setValue(signature, forHTTPHeaderField: "X-Astra-Signature")
        return nonce
    }
}
