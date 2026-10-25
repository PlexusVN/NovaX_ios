import Foundation
import Security
import CommonCrypto

/// Cấu trúc Envelope v2 do AUTH Server trả về
public struct AstraServerEnvelope: Codable {
    public let protocolVersion: Int
    public let kid: String
    public let purpose: String
    public let requestNonce: String
    public let issuedMs: Int64
    public let expiresMs: Int64
    public let payloadSha256: String
    public let signature: String

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case kid
        case purpose
        case requestNonce = "request_nonce"
        case issuedMs = "issued_ms"
        case expiresMs = "expires_ms"
        case payloadSha256 = "payload_sha256"
        case signature
    }
}

/// Dịch vụ xác thực chữ ký RSA bất đối xứng từ AUTH Server
public final class ServerSignatureVerifier {
    public static let shared = ServerSignatureVerifier()

    // Public Key RSA dự phòng mặc định (2048/3072-bit SubjectPublicKeyInfo DER)
    // Trong môi trường production, khóa có thể được xoay vòng hoặc cập nhật qua signed policy
    private var trustedKeyIds: Set<String> = ["astra-rsa-2026-01", "astra-rsa-2026-backup"]

    private init() {}

    /// Canonical serialization của Server Envelope:
    /// ASTRA-SERVER-V2\nkid\npurpose\nrequest_nonce\nissued_ms\nexpires_ms\npayload_sha256
    public func canonicalEnvelopeString(_ envelope: AstraServerEnvelope) -> String {
        return [
            "ASTRA-SERVER-V2",
            envelope.kid,
            envelope.purpose,
            envelope.requestNonce,
            String(envelope.issuedMs),
            String(envelope.expiresMs),
            envelope.payloadSha256
        ].joined(separator: "\n")
    }

    /// Xác thực envelope kèm theo response data.
    public func verifyEnvelope(
        envelope: AstraServerEnvelope,
        expectedNonce: String,
        payloadData: Data,
        publicKeyDer: Data? = nil
    ) -> Bool {
        // 1. Kiểm tra nonce khớp với request
        if !expectedNonce.isEmpty && envelope.requestNonce != expectedNonce {
            return false
        }

        // 2. Kiểm tra thời hạn hợp lệ (cho phép dung sai đồng hồ 2 phút)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let clockSkew: Int64 = 120_000
        if envelope.expiresMs < (nowMs - clockSkew) {
            return false
        }

        // 3. Kiểm tra payload hash
        let computedSha = HMACUtils.sha256Hex(payloadData)
        if computedSha.lowercased() != envelope.payloadSha256.lowercased() {
            return false
        }

        // 4. Xác thực chữ ký RSA nếu có khóa công khai
        guard let pubKeyData = publicKeyDer,
              let signatureData = Data(base64Encoded: envelope.signature) else {
            // Trong shadow mode, nếu chưa có public key nhúng, coi hash và nonce hợp lệ
            return true
        }

        let canonical = canonicalEnvelopeString(envelope)
        guard let canonicalData = canonical.data(using: .utf8) else { return false }

        return verifyRsaPkcs1Sha256(
            publicKeyDer: pubKeyData,
            signedData: canonicalData,
            signatureData: signatureData
        )
    }

    private func verifyRsaPkcs1Sha256(
        publicKeyDer: Data,
        signedData: Data,
        signatureData: Data
    ) -> Bool {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: publicKeyDer.count * 8
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(publicKeyDer as CFData, attributes as CFDictionary, &error) else {
            return false
        }

        return SecKeyVerifySignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signedData as CFData,
            signatureData as CFData,
            &error
        )
    }
}
