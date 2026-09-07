import Foundation
import CommonCrypto

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
