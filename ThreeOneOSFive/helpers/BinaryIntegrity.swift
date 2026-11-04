import Foundation
import CryptoKit

struct BinaryIntegrityResult {
    enum Status {
        case valid
        case notConfigured
        case mismatch
        case unreadable
    }

    let status: Status
    var isCompromised: Bool { status == .mismatch || status == .unreadable }
    var evidenceCode: String? {
        switch status {
        case .mismatch: return "binary_text_mismatch"
        case .unreadable: return "binary_text_unreadable"
        case .valid, .notConfigured: return nil
        }
    }
}

enum BinaryIntegrity {
    static func evaluate() -> BinaryIntegrityResult {
#if DEBUG || targetEnvironment(simulator)
        return BinaryIntegrityResult(status: .notConfigured)
#else
        let expected = String(cString: AstraExpectedTextHash()).lowercased()
        guard expected.count == 64,
              expected.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              expected != String(repeating: "0", count: 64) else {
            return BinaryIntegrityResult(status: .unreadable)
        }
        guard let url = Bundle.main.executableURL,
              let executable = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let text = machOTextSection(in: executable) else {
            return BinaryIntegrityResult(status: .unreadable)
        }
        let actual = SHA256.hash(data: text).map { String(format: "%02x", $0) }.joined()
        return BinaryIntegrityResult(status: constantTimeEqual(actual, expected) ? .valid : .mismatch)
#endif
    }

    private static func machOTextSection(in data: Data) -> Data? {
        // Astra's device executable is a thin arm64 Mach-O. The unsigned IPA is
        // built for iphoneos only; ESign/KSign change the code-signature blob,
        // not this section.
        guard data.count >= 32, u32(data, 0) == 0xfeedfacf,
              u32(data, 4) == 0x0100000c else { return nil }
        let commandCount = Int(u32(data, 16))
        let commandBytes = Int(u32(data, 20))
        guard commandCount > 0, commandCount <= 16_384,
              32 + commandBytes <= data.count else { return nil }

        var commandOffset = 32
        for _ in 0..<commandCount {
            guard commandOffset + 8 <= data.count else { return nil }
            let command = u32(data, commandOffset)
            let commandSize = Int(u32(data, commandOffset + 4))
            guard commandSize >= 8, commandOffset + commandSize <= data.count else { return nil }
            if command == 0x19, commandSize >= 72,
               fixedString(data, commandOffset + 8, 16) == "__TEXT" {
                let sectionCount = Int(u32(data, commandOffset + 64))
                guard sectionCount <= 4096,
                      72 + sectionCount * 80 <= commandSize else { return nil }
                var sectionOffset = commandOffset + 72
                for _ in 0..<sectionCount {
                    let sectionName = fixedString(data, sectionOffset, 16)
                    let segmentName = fixedString(data, sectionOffset + 16, 16)
                    if sectionName == "__text", segmentName == "__TEXT" {
                        let size64 = u64(data, sectionOffset + 40)
                        let fileOffset = UInt64(u32(data, sectionOffset + 48))
                        guard size64 > 0, size64 <= UInt64(Int.max), fileOffset <= UInt64(Int.max),
                              fileOffset + size64 <= UInt64(data.count) else { return nil }
                        return data.subdata(in: Int(fileOffset)..<Int(fileOffset + size64))
                    }
                    sectionOffset += 80
                }
            }
            commandOffset += commandSize
        }
        return nil
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(data[offset + index]) << UInt64(index * 8) }
        return value
    }

    private static func fixedString(_ data: Data, _ offset: Int, _ count: Int) -> String {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return "" }
        let bytes = data[offset..<(offset + count)].prefix { $0 != 0 }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static func constantTimeEqual(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}
