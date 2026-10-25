import Foundation
import CommonCrypto

/// Dịch vụ gắn Request Proof v2 vào các HTTP request nhạy cảm của Astra/NovaX.
/// Bảo vệ chống replay và chứng minh quyền sở hữu thiết bị bằng chữ ký P-256.
public final class RequestProofService {
    public static let shared = RequestProofService()

    private let counterQueue = DispatchQueue(label: "click.zynox.counterQueue", qos: .userInitiated)
    private let counterKeychainKey = "novax_proof_monotonic_counter"
    private var inMemoryCounter: Int64 = 0

    private init() {
        if let stored = KeychainUtils.read(key: counterKeychainKey), let val = Int64(stored), val > 0 {
            inMemoryCounter = val
        } else {
            inMemoryCounter = 1
        }
    }

    /// Cấp phát monotonic counter tăng dần một cách tuần tự.
    public func nextCounter() -> Int64 {
        return counterQueue.sync {
            inMemoryCounter += 1
            _ = KeychainUtils.save(key: counterKeychainKey, value: String(inMemoryCounter))
            return inMemoryCounter
        }
    }

    /// Sinh nonce ngẫu nhiên 128-bit (32 ký tự hex).
    public func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Tính SHA256 hex của data.
    public func sha256Hex(_ data: Data) -> String {
        return HMACUtils.sha256Hex(data)
    }

    /// Ký và đính kèm các header v2 vào URLRequest.
    public func signRequest(
        request: inout URLRequest,
        sessionId: String,
        deviceKeyId: String
    ) throws {
        let method = request.httpMethod?.uppercased() ?? "GET"
        let path = request.url?.path ?? ""
        let body = request.httpBody ?? Data()
        let bodySha = sha256Hex(body)

        let nonce = generateNonce()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let counter = nextCounter()

        let signature = try DeviceIdentityService.shared.signRequest(
            method: method,
            path: path,
            bodySha256: bodySha,
            sessionId: sessionId,
            deviceKeyId: deviceKeyId,
            nonce: nonce,
            timestamp: timestamp,
            counter: counter
        )

        request.setValue("2", forHTTPHeaderField: "X-Astra-Protocol")
        request.setValue(deviceKeyId, forHTTPHeaderField: "X-Astra-Device-Key")
        request.setValue(sessionId, forHTTPHeaderField: "X-Astra-Session")
        request.setValue(nonce, forHTTPHeaderField: "X-Astra-Nonce")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-Astra-Timestamp")
        request.setValue(String(counter), forHTTPHeaderField: "X-Astra-Counter")
        request.setValue(bodySha, forHTTPHeaderField: "X-Astra-Body-SHA256")
        request.setValue(signature, forHTTPHeaderField: "X-Astra-Signature")
    }
}
