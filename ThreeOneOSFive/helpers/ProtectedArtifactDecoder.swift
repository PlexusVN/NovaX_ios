import Foundation
import CryptoKit
import CoreFoundation

enum ProtectedArtifactError: LocalizedError {
    case invalidDocument
    case invalidSignature
    case contextMismatch
    case authenticationFailed

    var errorDescription: String? { "Không thể xác minh hoặc giải mã dữ liệu được cấp cho thiết bị này." }
}

struct ProtectedArtifactManifest: Codable {
    let artifactId: String
    let releaseId: String
    let releaseVersion: Int64
    let variant: String
    let kind: String
    let fileName: String
    let plaintextSHA256: String
    let plaintextSize: Int
    let ciphertextSHA256: String
    let ciphertextSize: Int
    let contentEncryption: ContentEncryption

    struct ContentEncryption: Codable {
        let algorithm: String
        let nonce: String
        let tag: String
    }
}

private struct ProtectedArtifactGrant: Decodable {
    let grantId: String
    let artifactId: String
    let manifestDigest: String
    let recipientId: String
    let recipientKeySHA256: String
    let sessionId: String
    let requestNonce: String
    let issuedAt: Int64
    let expiresAt: Int64
    let keyEnvelope: KeyEnvelope

    struct KeyEnvelope: Decodable {
        let algorithm: String
        let ephemeralPublicKey: String
        let salt: String
        let nonce: String
        let tag: String
        let ciphertext: String
    }
}

/// Protocol v1 uses printable ASCII strings and safe integer numbers only.
/// Canonical bytes deliberately match artifact_crypto.js instead of relying on
/// JSONEncoder formatting, locale, escaped slashes or unordered dictionaries.
final class ProtectedArtifactDecoder {
    static let shared = ProtectedArtifactDecoder()
    static let maximumArtifactBytes = 50 * 1024 * 1024
    private static let artifactProtocol = "astra-artifact-v1"
    private static let wrapAlgorithm = "P256-ECDH-HKDF-SHA256-A256GCM"
    private let verifier: ServerSignatureVerifier
    private let recipientIdentity: () throws -> (id: String, publicKey: Data)
    private let sharedSecret: (Data) throws -> SharedSecret

    private convenience init() {
        self.init(verifier: .shared, recipientIdentity: {
            let identity = DeviceIdentityService.shared
            guard let id = try identity.persistedEnrollmentID(),
                  let publicKey = Data(base64Encoded: try identity.getOrCreateAgreementKey().publicKeyX963Base64) else {
                throw ProtectedArtifactError.contextMismatch
            }
            return (id, publicKey)
        }, sharedSecret: { try DeviceIdentityService.shared.agreementSharedSecret(peerPublicKeyX963: $0) })
    }

    /// Dependency injection supports public interoperability fixtures without
    /// trusting their test signer or test private scalar in production.
    init(verifier: ServerSignatureVerifier,
         recipientIdentity: @escaping () throws -> (id: String, publicKey: Data),
         sharedSecret: @escaping (Data) throws -> SharedSecret) {
        self.verifier = verifier
        self.recipientIdentity = recipientIdentity
        self.sharedSecret = sharedSecret
    }

    func verifyManifest(_ data: Data) throws -> ProtectedArtifactManifest {
        let document = try verifiedDocument(data, type: "manifest")
        return try manifestBody(document)
    }

    func decrypt(signedManifest: Data, signedGrant: Data, ciphertext: Data,
                 recipientID: String, sessionID: String, requestNonce: String,
                 expectedArtifactID: String, expectedGrantID: String, now: Date = Date()) throws -> Data {
        let manifestDocument = try verifiedDocument(signedManifest, type: "manifest")
        let manifest = try manifestBody(manifestDocument)
        let grantDocument = try verifiedDocument(signedGrant, type: "grant")
        let grant = try grantBody(grantDocument)
        let recipient = try recipientIdentity()
        let nowSeconds = Int64(now.timeIntervalSince1970)
        guard manifest.artifactId == expectedArtifactID,
              grant.grantId == expectedGrantID,
              grant.artifactId == manifest.artifactId,
              grant.manifestDigest == Self.sha256(try Self.canonicalData(manifestDocument)),
              recipient.id == recipientID, grant.recipientId == recipientID,
              recipient.publicKey.count == 65, recipient.publicKey.first == 4,
              grant.recipientKeySHA256 == Self.sha256(recipient.publicKey),
              grant.sessionId == sessionID, grant.requestNonce == requestNonce,
              Self.matches(requestNonce, #"^[0-9a-f]{32}$"#),
              UUID(uuidString: sessionID) != nil, UUID(uuidString: recipientID) != nil,
              grant.issuedAt <= nowSeconds + 30, nowSeconds < grant.expiresAt,
              ciphertext.count == manifest.ciphertextSize,
              Self.sha256(ciphertext) == manifest.ciphertextSHA256 else {
            throw ProtectedArtifactError.contextMismatch
        }

        let envelope = grant.keyEnvelope
        let peer = try Self.base64(envelope.ephemeralPublicKey, count: 65)
        guard peer.first == 4 else { throw ProtectedArtifactError.invalidDocument }
        // Parsing the curve point rejects malformed or off-curve peer keys.
        _ = try P256.KeyAgreement.PublicKey(x963Representation: peer)
        let shared = try sharedSecret(peer)
        let wrappingKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
            salt: try Self.base64(envelope.salt, count: 32),
            sharedInfo: Data("astra-artifact-v1/device-key-wrap".utf8), outputByteCount: 32)
        do {
            let wrapped = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: Self.base64(envelope.nonce, count: 12)),
                ciphertext: Self.base64(envelope.ciphertext, count: 32),
                tag: Self.base64(envelope.tag, count: 16))
            var contentKey = try AES.GCM.open(wrapped, using: wrappingKey,
                                             authenticating: Self.grantAAD(grant))
            defer { contentKey.resetBytes(in: 0..<contentKey.count) }
            guard contentKey.count == 32 else { throw ProtectedArtifactError.authenticationFailed }
            let sealedContent = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: Self.base64(manifest.contentEncryption.nonce, count: 12)),
                ciphertext: ciphertext,
                tag: Self.base64(manifest.contentEncryption.tag, count: 16))
            let plaintext = try AES.GCM.open(sealedContent, using: SymmetricKey(data: contentKey),
                                            authenticating: Self.contentAAD(manifest))
            guard plaintext.count == manifest.plaintextSize,
                  Self.sha256(plaintext) == manifest.plaintextSHA256 else {
                throw ProtectedArtifactError.authenticationFailed
            }
            return plaintext
        } catch {
            throw ProtectedArtifactError.authenticationFailed
        }
    }

    private func verifiedDocument(_ data: Data, type: String) throws -> [String: Any] {
        guard data.count <= 64 * 1024,
              let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProtectedArtifactError.invalidDocument
        }
        try Self.exact(document, ["protocol", "type", "algorithm", "keyId", "body", "signature"])
        guard document["protocol"] as? String == Self.artifactProtocol,
              document["type"] as? String == type, document["algorithm"] as? String == "RS256",
              let keyID = document["keyId"] as? String,
              Self.matches(keyID, #"^[A-Za-z0-9_.:@-]{1,128}$"#),
              let signature = document["signature"] as? String else {
            throw ProtectedArtifactError.invalidDocument
        }
        let signatureBytes = try Self.base64(signature)
        guard (256...1024).contains(signatureBytes.count) else { throw ProtectedArtifactError.invalidSignature }
        var unsigned = document
        unsigned.removeValue(forKey: "signature")
        guard verifier.verifyRS256(keyID: keyID, signedData: try Self.canonicalData(unsigned),
                                    signatureBase64: signature) else {
            throw ProtectedArtifactError.invalidSignature
        }
        return document
    }

    private func manifestBody(_ document: [String: Any]) throws -> ProtectedArtifactManifest {
        guard let body = document["body"] as? [String: Any],
              let encryption = body["contentEncryption"] as? [String: Any] else {
            throw ProtectedArtifactError.invalidDocument
        }
        try Self.exact(body, ["artifactId", "releaseId", "releaseVersion", "variant", "kind", "fileName",
            "plaintextSHA256", "plaintextSize", "ciphertextSHA256", "ciphertextSize", "contentEncryption"])
        try Self.exact(encryption, ["algorithm", "nonce", "tag"])
        let manifest = try JSONDecoder().decode(ProtectedArtifactManifest.self, from: Self.canonicalData(body))
        guard UUID(uuidString: manifest.artifactId) != nil,
              Self.matches(manifest.releaseId, #"^[A-Za-z0-9_.:@-]{1,128}$"#),
              manifest.releaseVersion > 0, manifest.releaseVersion <= 9_007_199_254_740_991,
              ["ffth", "ffmax"].contains(manifest.variant),
              ["package", "mod", "original"].contains(manifest.kind),
              manifest.fileName.utf8.count <= 255,
              Self.matches(manifest.fileName, #"^[A-Za-z0-9_~%+ .()=-]+$"#),
              manifest.fileName != ".", manifest.fileName != "..",
              Self.matches(manifest.plaintextSHA256, #"^[0-9a-f]{64}$"#),
              Self.matches(manifest.ciphertextSHA256, #"^[0-9a-f]{64}$"#),
              (1...Self.maximumArtifactBytes).contains(manifest.plaintextSize),
              manifest.ciphertextSize == manifest.plaintextSize,
              manifest.contentEncryption.algorithm == "A256GCM" else {
            throw ProtectedArtifactError.invalidDocument
        }
        _ = try Self.base64(manifest.contentEncryption.nonce, count: 12)
        _ = try Self.base64(manifest.contentEncryption.tag, count: 16)
        return manifest
    }

    private func grantBody(_ document: [String: Any]) throws -> ProtectedArtifactGrant {
        guard let body = document["body"] as? [String: Any],
              let envelope = body["keyEnvelope"] as? [String: Any] else {
            throw ProtectedArtifactError.invalidDocument
        }
        try Self.exact(body, ["grantId", "artifactId", "manifestDigest", "recipientId", "recipientKeySHA256",
            "sessionId", "requestNonce", "issuedAt", "expiresAt", "keyEnvelope"])
        try Self.exact(envelope, ["algorithm", "ephemeralPublicKey", "salt", "nonce", "tag", "ciphertext"])
        let grant = try JSONDecoder().decode(ProtectedArtifactGrant.self, from: Self.canonicalData(body))
        guard UUID(uuidString: grant.grantId) != nil, UUID(uuidString: grant.artifactId) != nil,
              UUID(uuidString: grant.recipientId) != nil, UUID(uuidString: grant.sessionId) != nil,
              Self.matches(grant.manifestDigest, #"^[0-9a-f]{64}$"#),
              Self.matches(grant.recipientKeySHA256, #"^[0-9a-f]{64}$"#),
              Self.matches(grant.requestNonce, #"^[0-9a-f]{32}$"#),
              grant.issuedAt > 0, grant.expiresAt > grant.issuedAt,
              grant.expiresAt - grant.issuedAt <= 300,
              grant.keyEnvelope.algorithm == Self.wrapAlgorithm else {
            throw ProtectedArtifactError.invalidDocument
        }
        _ = try Self.base64(grant.keyEnvelope.ephemeralPublicKey, count: 65)
        _ = try Self.base64(grant.keyEnvelope.salt, count: 32)
        _ = try Self.base64(grant.keyEnvelope.nonce, count: 12)
        _ = try Self.base64(grant.keyEnvelope.tag, count: 16)
        _ = try Self.base64(grant.keyEnvelope.ciphertext, count: 32)
        return grant
    }

    private static func contentAAD(_ body: ProtectedArtifactManifest) throws -> Data {
        try canonicalData(["protocol": artifactProtocol, "purpose": "artifact-content",
            "artifactId": body.artifactId, "releaseId": body.releaseId, "releaseVersion": body.releaseVersion,
            "variant": body.variant, "kind": body.kind, "fileName": body.fileName,
            "plaintextSHA256": body.plaintextSHA256, "plaintextSize": body.plaintextSize,
            "algorithm": "A256GCM", "nonce": body.contentEncryption.nonce])
    }

    private static func grantAAD(_ body: ProtectedArtifactGrant) throws -> Data {
        try canonicalData(["protocol": artifactProtocol, "purpose": "device-key-wrap",
            "grantId": body.grantId, "artifactId": body.artifactId, "manifestDigest": body.manifestDigest,
            "recipientId": body.recipientId, "recipientKeySHA256": body.recipientKeySHA256,
            "sessionId": body.sessionId, "requestNonce": body.requestNonce,
            "issuedAt": body.issuedAt, "expiresAt": body.expiresAt,
            "algorithm": body.keyEnvelope.algorithm, "ephemeralPublicKey": body.keyEnvelope.ephemeralPublicKey,
            "salt": body.keyEnvelope.salt, "nonce": body.keyEnvelope.nonce])
    }

    static func canonicalData(_ value: Any) throws -> Data { Data(try canonicalJSON(value).utf8) }

    private static func canonicalJSON(_ value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let text = value as? String {
            guard text.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }) else {
                throw ProtectedArtifactError.invalidDocument
            }
            return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            let double = number.doubleValue
            guard double.isFinite, double.rounded() == double, abs(double) <= 9_007_199_254_740_991 else {
                throw ProtectedArtifactError.invalidDocument
            }
            return String(number.int64Value)
        }
        if let array = value as? [Any] {
            return "[" + (try array.map { try canonicalJSON($0) }).joined(separator: ",") + "]"
        }
        if let dictionary = value as? [String: Any] {
            let members = try dictionary.keys.sorted().map { key in
                try canonicalJSON(key) + ":" + canonicalJSON(dictionary[key]!)
            }
            return "{" + members.joined(separator: ",") + "}"
        }
        throw ProtectedArtifactError.invalidDocument
    }

    private static func exact(_ value: [String: Any], _ keys: Set<String>) throws {
        guard Set(value.keys) == keys else { throw ProtectedArtifactError.invalidDocument }
    }

    private static func base64(_ value: String, count: Int? = nil) throws -> Data {
        guard value.utf8.count <= 4096, let data = Data(base64Encoded: value),
              data.base64EncodedString() == value, count == nil || data.count == count else {
            throw ProtectedArtifactError.invalidDocument
        }
        return data
    }

    private static func sha256(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
