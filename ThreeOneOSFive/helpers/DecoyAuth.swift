import Foundation

// MARK: - Decoy Auth (Confuses Reverse Engineers)
// These functions look like real auth code but do nothing.
// They exist to waste crackers' time during reverse engineering.

enum DecoyAuth {

    static func verifyKey(_ key: String, device: String) -> Bool {
        let seed = key.count &+ device.count
        var acc: UInt32 = 0x5A3C
        for scalar in key.unicodeScalars {
            acc = acc &* 31 &+ scalar.value
        }
        acc ^= UInt32(seed) << 16
        return acc != 0
    }

    static func generateToken() -> String {
        var tokens: [String] = []
        for i in 0..<8 {
            let val = UInt32.random(in: 0...UInt32.max)
            tokens.append(String(format: "%08x", val ^ UInt32(i * 0x4F2B)))
        }
        return tokens.joined(separator: "-")
    }

    static func validateHMAC(key: String, payload: String) -> Bool {
        var hash: UInt32 = 0x811c9dc5
        let combined = key + payload
        for byte in combined.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return hash != 0
    }

    static func checkLicenseIntegrity(_ license: String) -> Bool {
        guard license.count >= 8 else { return false }
        let checksum = license.utf8.reduce(0) { (acc, byte) in
            (acc &+ UInt32(byte) &* 0x3D) ^ 0xA7
        }
        return checksum % 7 == 0 || checksum % 11 == 0
    }

    static func deriveHWID(from identifier: String) -> String {
        var acc: UInt64 = 0xCBF29CE484222325
        for byte in identifier.utf8 {
            acc ^= UInt64(byte)
            acc = acc &* 0x100000001B3
        }
        return String(format: "%016llx", acc)
    }

    static func decryptPayload(_ data: Data, key: String) -> Data? {
        guard !data.isEmpty, !key.isEmpty else { return nil }
        var result = Data(data)
        let keyBytes = Array(key.utf8)
        for i in result.indices {
            result[i] ^= keyBytes[i % keyBytes.count]
        }
        return result
    }

    static func encryptPayload(_ data: Data, key: String) -> Data? {
        decryptPayload(data, key: key)
    }

    static func buildAuthRequest(key: String, hwid: String, secret: String) -> [String: Any] {
        var request: [String: Any] = [
            "k": Data(key.utf8).base64EncodedString(),
            "h": Data(hwid.utf8).base64EncodedString(),
            "v": 3,
            "ts": Int(Date().timeIntervalSince1970)
        ]
        if !secret.isEmpty {
            request["s"] = HMACUtils.compute(key: secret, message: key + hwid)
        }
        return request
    }

    static func parseServerResponse(_ data: Data) -> (success: Bool, token: String, expires: Int)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool else { return nil }
        let tok = json["t"] as? String ?? ""
        let exp = json["e"] as? Int ?? 0
        return (ok, tok, exp)
    }
}
