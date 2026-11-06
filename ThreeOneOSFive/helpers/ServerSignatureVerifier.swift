import Foundation
import Security
import CryptoKit

public struct AstraServerEnvelope: Codable {
    public let protocolVersion: Int
    public let kid: String
    public let purpose: String
    public let requestNonce: String
    public let issuedMs: Int64
    public let expiresMs: Int64
    public let payloadSha256: String
    public let payloadBase64: String
    public let signature: String

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case kid, purpose
        case requestNonce = "request_nonce"
        case issuedMs = "issued_ms"
        case expiresMs = "expires_ms"
        case payloadSha256 = "payload_sha256"
        case payloadBase64 = "payload_b64"
        case signature
    }
}

enum ServerSignatureError: LocalizedError {
    case invalidSignedResponse
    var errorDescription: String? { "Không thể xác minh phản hồi có chữ ký của máy chủ." }
}

/// Keyring shipped with the signed app, never learned from a network response.
public final class ServerSignatureVerifier {
    public static let shared = ServerSignatureVerifier()

    // Public-only PKCS#1 DER from AUTH/server/keys/rsa_public.xml.
    // SHA-256(DER): b7ea531c327235ad0463df5d9e5bc8bcc13f34230d9cee9beba452c296294cb8
    // Deployment must use the corresponding persistent signing key and this kid.
    // A replacement public key requires a reviewed application release.
    private static let embeddedPublicKeys: [String: String] = [
        "astra-rsa-2026-01": "MIIBCgKCAQEA1SwdZU9s51D/5e+2ktR3IAergpRnQ9idTn2ENrUk2Hr7njStvyoPXeF/mVz+vwtXrMMF2gknnHhle7fAJE5X8So2gI4L2z20mZQB6qkXIEj2V/N7qEDRe1JvmZwmoWWg58KLmrnNfSIIYopUIRnF8zVEu8OhjBuDRHAIaNJ1Gdw9gNbHA2GIk4LAfX1KrlG6IM7qCEa7RlZJJODr8h5s8NoYAK6UKaHY/1wGWLKtQFaJX/PL01LLDR8pgbBwuflT8ze/XIh6rV4uTqFW6Mw7RXI5mEtrO95O8z9DUFkuPBxmAlMRGcp5Zg3BeDwBtdHZgm/Klg/wkb8SOVTc69pXWQIDAQAB"
    ]
    private let trustedPublicKeys: [String: Data]

    private convenience init() {
        self.init(trustedPublicKeys: Self.embeddedPublicKeys.compactMapValues { Data(base64Encoded: $0) })
    }

    /// Offline fixture tests or explicitly configured build-time keyrings only.
    /// Never populate this dictionary from an unverified response.
    init(trustedPublicKeys: [String: Data]) {
        self.trustedPublicKeys = trustedPublicKeys
    }

    public func canonicalEnvelopeString(_ envelope: AstraServerEnvelope) -> String {
        ["ASTRA-SERVER-V2", envelope.kid, envelope.purpose,
         envelope.requestNonce, String(envelope.issuedMs), String(envelope.expiresMs),
         envelope.payloadSha256].joined(separator: "\n")
    }

    /// Decode only the exact signed bytes, never the response's unsigned siblings.
    public func verifiedPayload(in responseData: Data, expectedNonce: String,
                                expectedPurpose: String) throws -> Data {
        struct Response: Decodable { let astra_v2: AstraServerEnvelope }
        guard responseData.count <= 24 * 1024 * 1024,
              let response = try? JSONDecoder().decode(Response.self, from: responseData),
              let payload = Data(base64Encoded: response.astra_v2.payloadBase64),
              verifyEnvelope(envelope: response.astra_v2, expectedNonce: expectedNonce,
                             expectedPurpose: expectedPurpose, payloadData: payload) else {
            throw ServerSignatureError.invalidSignedResponse
        }
        return payload
    }

    public func verifyEnvelope(envelope: AstraServerEnvelope, expectedNonce: String,
                               expectedPurpose: String, payloadData: Data,
                               now: Date = Date(), maximumLifetimeMs: Int64 = 300_000) -> Bool {
        guard envelope.protocolVersion == 2,
              Self.matches(envelope.kid, #"^[A-Za-z0-9_-]{1,64}$"#),
              Self.matches(expectedNonce, #"^[0-9a-f]{32}$"#),
              envelope.requestNonce == expectedNonce,
              !expectedPurpose.isEmpty, expectedPurpose.utf8.count <= 160,
              expectedPurpose.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }),
              envelope.purpose == expectedPurpose,
              Self.matches(envelope.payloadSha256, #"^[0-9a-f]{64}$"#),
              maximumLifetimeMs > 0, maximumLifetimeMs <= 3_600_000,
              envelope.issuedMs > 0, envelope.expiresMs > envelope.issuedMs,
              envelope.expiresMs - envelope.issuedMs <= maximumLifetimeMs else { return false }

        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard envelope.issuedMs <= nowMs + 30_000,
              envelope.expiresMs > nowMs,
              Self.sha256Hex(payloadData) == envelope.payloadSha256,
              Data(base64Encoded: envelope.payloadBase64) == payloadData else { return false }

        return verifyRS256(keyID: envelope.kid,
                           signedData: Data(canonicalEnvelopeString(envelope).utf8),
                           signatureBase64: envelope.signature)
    }

    /// Artifact callers additionally validate their document type and context.
    func verifyRS256(keyID: String, signedData: Data, signatureBase64: String) -> Bool {
        guard let publicKeyDer = trustedPublicKeys[keyID],
              signatureBase64.utf8.count <= 1400,
              let signature = Data(base64Encoded: signatureBase64), !signature.isEmpty,
              signature.base64EncodedString() == signatureBase64 else { return false }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        guard let key = SecKeyCreateWithData(publicKeyDer as CFData, attributes as CFDictionary, nil),
              let actualAttributes = SecKeyCopyAttributes(key) as? [String: Any],
              let bits = actualAttributes[kSecAttrKeySizeInBits as String] as? Int,
              bits >= 2048,
              signature.count == SecKeyGetBlockSize(key),
              SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                     signedData as CFData, signature as CFData, nil)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
