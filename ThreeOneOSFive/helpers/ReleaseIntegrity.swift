import Foundation
import CryptoKit
import Darwin
import MachO

struct SignedReleaseSection: Codable, Equatable, Sendable {
    let name: String
    let size: Int
    let sha256: String
}

struct SignedReleaseBody: Codable, Sendable {
    let release_id: String
    let bundle_id: String
    let version: String
    let build: String
    let executable: String
    let sections: [SignedReleaseSection]
    let dependencies: [String]
}

private struct SignedReleaseSeal: Codable {
    let `protocol`: String
    let keyId: String
    let body: SignedReleaseBody
    let signature: String
}

struct SignedReleaseCheckResult: Sendable {
    let enforced: Bool
    let mask: Int
    let releaseID: String
    let sealDigest: String

    var isCompromised: Bool { enforced && mask != SignedReleaseIntegrity.allChecksMask }
    var evidenceCode: String? { isCompromised ? "signed_release_integrity_failed" : nil }

    static let notConfigured = SignedReleaseCheckResult(
        enforced: false, mask: SignedReleaseIntegrity.allChecksMask,
        releaseID: "", sealDigest: ""
    )
}

private struct SignedReleaseImage {
    let sections: [SignedReleaseSection]
    let dependencies: [String]
    let textOffset: Int
    let textSize: Int

    static func read(_ data: Data) throws -> SignedReleaseImage {
        func word(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset <= data.count - 4 else { throw SignedReleaseIntegrityError.invalid }
            return UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        }
        func wide(_ offset: Int) throws -> UInt64 {
            UInt64(try word(offset)) | (UInt64(try word(offset + 4)) << 32)
        }
        func name(_ offset: Int, _ length: Int) throws -> String {
            guard offset >= 0, length >= 0, offset <= data.count - length,
                  let text = String(data: data[offset..<(offset + length)].prefix { $0 != 0 },
                                    encoding: .ascii) else {
                throw SignedReleaseIntegrityError.invalid
            }
            return text
        }

        guard data.count >= 32, try word(0) == 0xfeedfacf,
              try word(4) == 0x0100000c else { throw SignedReleaseIntegrityError.invalid }
        let commandCount = Int(try word(16))
        let commandBytes = Int(try word(20))
        guard commandCount > 0, commandCount <= 4096,
              commandBytes >= 0, commandBytes <= data.count - 32 else {
            throw SignedReleaseIntegrityError.invalid
        }

        var position = 32
        var sections: [SignedReleaseSection] = []
        var dependencies: [String] = []
        var textOffset = 0
        var textSize = 0

        for _ in 0..<commandCount {
            let command = try word(position)
            let commandSize = Int(try word(position + 4))
            guard commandSize >= 8, position <= 32 + commandBytes - commandSize else {
                throw SignedReleaseIntegrityError.invalid
            }
            if command == 0x19 {
                guard commandSize >= 72 else { throw SignedReleaseIntegrityError.invalid }
                let segmentName = try name(position + 8, 16)
                let sectionCount = Int(try word(position + 64))
                guard sectionCount <= 256, 72 + sectionCount * 80 <= commandSize else {
                    throw SignedReleaseIntegrityError.invalid
                }
                let segmentVMAddress = try wide(position + 24)
                let segmentVMSize = try wide(position + 32)
                let segmentFileOffset = try wide(position + 40)
                let segmentFileSize = try wide(position + 48)
                let (segmentVMEnd, segmentVMOverflow) = segmentVMAddress.addingReportingOverflow(segmentVMSize)
                let (segmentFileEnd, segmentFileOverflow) = segmentFileOffset.addingReportingOverflow(segmentFileSize)
                guard !segmentVMOverflow, !segmentFileOverflow else {
                    throw SignedReleaseIntegrityError.invalid
                }
                for index in 0..<sectionCount {
                    let offset = position + 72 + index * 80
                    let sectionName = try name(offset, 16)
                    let address = try wide(offset + 32)
                    let length = try wide(offset + 40)
                    let fileOffset = UInt64(try word(offset + 48))
                    if segmentName == "__TEXT", length > 0 {
                        let (fileEnd, fileOverflow) = fileOffset.addingReportingOverflow(length)
                        let (addressEnd, addressOverflow) = address.addingReportingOverflow(length)
                        guard length <= 128 * 1024 * 1024,
                              !fileOverflow, !addressOverflow,
                              fileOffset >= segmentFileOffset,
                              fileEnd <= segmentFileEnd,
                              address >= segmentVMAddress,
                              addressEnd <= segmentVMEnd,
                              address - segmentVMAddress == fileOffset - segmentFileOffset,
                              fileEnd <= UInt64(data.count) else {
                            throw SignedReleaseIntegrityError.invalid
                        }
                        let start = Int(fileOffset)
                        let count = Int(length)
                        sections.append(SignedReleaseSection(
                            name: sectionName,
                            size: count,
                            sha256: Self.digest(data.subdata(in: start..<(start + count)))
                        ))
                        if sectionName == "__text" {
                            textOffset = start
                            textSize = count
                        }
                    }
                }
            }
            if [UInt32(0x0c), 0x80000018, 0x8000001f, 0x80000023].contains(command) {
                guard commandSize >= 24 else { throw SignedReleaseIntegrityError.invalid }
                let stringOffset = Int(try word(position + 8))
                guard stringOffset >= 24, stringOffset < commandSize else {
                    throw SignedReleaseIntegrityError.invalid
                }
                dependencies.append(try name(position + stringOffset, commandSize - stringOffset))
            }
            position += commandSize
        }

        guard position == 32 + commandBytes, textSize > 0,
              Set(sections.map(\.name)).count == sections.count else {
            throw SignedReleaseIntegrityError.invalid
        }
        return SignedReleaseImage(
            sections: sections.sorted { $0.name < $1.name },
            dependencies: dependencies.sorted(),
            textOffset: textOffset,
            textSize: textSize
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SignedReleaseIntegrityError: LocalizedError {
    case invalid
    var errorDescription: String? {
        "Không thể xác minh phiên bản ứng dụng. Hãy cài lại bản chính thức được cung cấp."
    }
}

private struct SignedReleaseInspection {
    let sealData: Data
    let image: SignedReleaseImage
    let bundleID: String
    let version: String
    let build: String
    let executableName: String
    let regularExecutable: Bool
    let memoryTextHash: String?
    let loadedImages: [String]
    let debuggerAttached: Bool
}

enum SignedReleaseIntegrity {
    static let allChecksMask = 1023
    private static let lock = NSLock()
    private static var latest: SignedReleaseCheckResult = .notConfigured

    static var lastResult: SignedReleaseCheckResult {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    static func check() -> SignedReleaseCheckResult {
#if DEBUG || targetEnvironment(simulator)
        store(.notConfigured)
        return .notConfigured
#else
        let result = currentInspection().map(inspect) ?? SignedReleaseCheckResult(
            enforced: true, mask: 0, releaseID: "", sealDigest: ""
        )
        store(result)
        return result
#endif
    }

    private static func store(_ result: SignedReleaseCheckResult) {
        lock.lock(); latest = result; lock.unlock()
    }

    private static func inspect(_ value: SignedReleaseInspection) -> SignedReleaseCheckResult {
        guard value.sealData.count <= 65_536,
              let seal = try? JSONDecoder().decode(SignedReleaseSeal.self, from: value.sealData) else {
            return SignedReleaseCheckResult(enforced: true, mask: 0, releaseID: "", sealDigest: "")
        }
        let image = value.image

        let checks = [
            validShape(seal),
            validSignature(seal),
            value.bundleID == "com.apple.mobile.MobileHouseArrest" && value.bundleID == seal.body.bundle_id,
            !value.version.isEmpty && value.version == seal.body.version
                && !value.build.isEmpty && value.build == seal.body.build,
            value.regularExecutable && value.executableName == seal.body.executable
                && !value.executableName.isEmpty && !value.executableName.contains("/")
                && !value.executableName.contains("\\"),
            image.sections == seal.body.sections.sorted { $0.name < $1.name },
            memoryTextMatches(image: image, inspection: value),
            image.dependencies == seal.body.dependencies.sorted(),
            loadedImagesAllowed(value.loadedImages, seal: seal),
            !value.debuggerAttached
        ]
        let mask = checks.enumerated().reduce(0) { partial, item in
            item.element ? partial | (1 << item.offset) : partial
        }
        return SignedReleaseCheckResult(
            enforced: true,
            mask: mask,
            releaseID: seal.body.release_id,
            sealDigest: digest(value.sealData)
        )
    }

    private static func validShape(_ seal: SignedReleaseSeal) -> Bool {
        seal.protocol == "astra-release-v1"
            && UUID(uuidString: seal.body.release_id) != nil
            && (1...128).contains(seal.body.sections.count)
            && seal.body.dependencies.count <= 256
            && seal.body.sections.allSatisfy {
                $0.size > 0 && $0.size <= 128 * 1024 * 1024
                    && $0.sha256.range(of: #"^[0-9a-f]{64}$"#,
                                       options: .regularExpression) != nil
            }
    }

    private static func validSignature(_ seal: SignedReleaseSeal) -> Bool {
        guard let encoded = try? JSONEncoder().encode(seal.body),
              let object = try? JSONSerialization.jsonObject(with: encoded),
              let canonical = try? ProtectedArtifactDecoder.canonicalData(object) else { return false }
        return ServerSignatureVerifier.shared.verifyRS256(
            keyID: seal.keyId,
            signedData: Data("ASTRA-RELEASE-V1\n".utf8) + canonical,
            signatureBase64: seal.signature
        )
    }

    private static func memoryTextMatches(image: SignedReleaseImage,
                                          inspection: SignedReleaseInspection) -> Bool {
        guard let expected = image.sections.first(where: { $0.name == "__text" }),
              let actual = inspection.memoryTextHash else { return false }
        return constantTimeEqual(expected.sha256, actual)
    }

    private static func loadedImagesAllowed(_ images: [String], seal: SignedReleaseSeal) -> Bool {
        let expected = Set(seal.body.dependencies.map { ($0 as NSString).lastPathComponent })
        guard let main = images.first,
              (main as NSString).lastPathComponent == seal.body.executable else { return false }
        return images.dropFirst().allSatisfy { image in
            image.hasPrefix("/System/")
                || image.hasPrefix("/usr/lib/")
                || image.hasPrefix("/private/preboot/Cryptexes/OS/")
                || (image.contains(".app/Frameworks/")
                    && expected.contains((image as NSString).lastPathComponent))
        }
    }

    private static func currentInspection() -> SignedReleaseInspection? {
        guard let executableURL = Bundle.main.executableURL,
              let sealURL = Bundle.main.url(forResource: "Astra", withExtension: "release"),
              let executable = try? Data(contentsOf: executableURL, options: .mappedIfSafe),
              let seal = try? Data(contentsOf: sealURL),
              let image = try? SignedReleaseImage.read(executable) else { return nil }

        let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path)
        var loadedImages: [String] = []
        for index in 0..<_dyld_image_count() {
            if let name = _dyld_get_image_name(index) { loadedImages.append(String(cString: name)) }
        }
        var memoryTextHash: String?
        if image.textOffset > 0, image.textSize > 0, let header = _dyld_get_image_header(0) {
            let pointer = UnsafeRawPointer(header).advanced(by: image.textOffset)
            memoryTextHash = digest(Data(bytes: pointer, count: image.textSize))
        }
        return SignedReleaseInspection(
            sealData: seal,
            image: image,
            bundleID: Bundle.main.bundleIdentifier ?? "",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            executableName: executableURL.lastPathComponent,
            regularExecutable: attributes?[.type] as? FileAttributeType == .typeRegular,
            memoryTextHash: memoryTextHash,
            loadedImages: loadedImages,
            debuggerAttached: AntiTamper.isDebuggerAttached || AntiTamper.isCodeSignatureDebugged
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}

@MainActor
enum ReleaseIntegrityRuntime {
    private static var pending: Task<SignedReleaseCheckResult, Never>?
    private static var checkedAt: TimeInterval = -100

    static func verify(force: Bool = false) async -> SignedReleaseCheckResult {
        let cached = SignedReleaseIntegrity.lastResult
        if cached.isCompromised { return cached }
        if !force, ProcessInfo.processInfo.systemUptime - checkedAt < 2 { return cached }
        if pending == nil {
            pending = Task.detached(priority: .utility) { SignedReleaseIntegrity.check() }
        }
        let result = await pending!.value
        pending = nil
        checkedAt = ProcessInfo.processInfo.systemUptime
        return result
    }
}
