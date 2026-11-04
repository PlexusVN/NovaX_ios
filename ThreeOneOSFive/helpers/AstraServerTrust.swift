import Foundation
import CryptoKit
import Security

// Shared by the iOS app and offline macOS security checks. Keep this file
// independent of UIKit and application identity/network-session dependencies.
enum AstraServerTrust {
    // Keep the production origin out of the plaintext string table. This is a
    // static-analysis speed bump only; trust still comes from the certificate
    // pin and signed server protocol below.
    static let protectedHost = decode([
        221, 222, 201, 200, 223, 137, 196, 203, 206, 196, 204
    ], 0xA7)
    static let protectedOrigin = decode([
        207, 211, 211, 215, 212, 157, 136, 136, 221, 222,
        201, 200, 223, 137, 196, 203, 206, 196, 204
    ], 0xA7)

    // SHA-256 of the exact leaf DER, independently checked over system-trusted
    // TLS on 2026-11-03 (certificate expires 2027-01-27). No CA/root pin or
    // unverified backup is accepted. Ship a verified replacement before rotation.
    static let leafCertificatePins: Set<String> = [
        "7NfgIVpP+fdJQCMiloG7ljIWxP5OZEiAGfsc6+jgcQA="
    ]

    static func accepts(_ trust: SecTrust, host: String) -> Bool {
        guard host.caseInsensitiveCompare(protectedHost) == .orderedSame else { return false }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else { return false }

        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return false }
        let der = SecCertificateCopyData(leaf) as Data
        return leafCertificatePins.contains(Data(SHA256.hash(data: der)).base64EncodedString())
    }

    private static func decode(_ data: [UInt8], _ key: UInt8) -> String {
        String(decoding: data.map { $0 ^ key }, as: UTF8.self)
    }
}
