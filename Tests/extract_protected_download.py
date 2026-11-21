"""Compile actual protected-download orchestration with isolated OS/crypto I/O.

The real CryptoKit decoder is exercised independently by CatalogApplicationSelfCheck.
This harness targets the production transport/descriptor/identity guards that those
tests previously skipped. It never accesses a device key store or network service.
"""
from pathlib import Path
import sys
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'ThreeOneOSFive/helpers'


def source() -> str:
    download = (HELPERS/'ProtectedDownloadService.swift').read_text(encoding='utf-8')
    decoder = (HELPERS/'ProtectedArtifactDecoder.swift').read_text(encoding='utf-8')
    errors = download[download.index('enum ProtectedDownloadError:'):download.index('@MainActor')]
    descriptor = download[download.index('private struct ProtectedArtifactDescriptor {'):
                          download.index('// BEGIN RECOVERY CHALLENGE CONTRACT')].replace('private struct', 'struct', 1)
    result = download[download.index('struct ProtectedCodePatchDownload {'):
                      download.index('/// Serializes the entire signed operation')]
    manifest = decoder[decoder.index('struct ProtectedArtifactManifest:'):
                       decoder.index('private struct ProtectedArtifactGrant:')]
    response_time = decoder[decoder.index('struct ProtectedResponseTime {'):
                            decoder.index('struct ProtectedArtifactManifest:')]
    canonical = extract_function(decoder, 'private static func canonicalJSON(')
    methods = '\n'.join(extract_function(download, signature) for signature in [
        'private func dictionary(', 'private func downloadArtifact(', 'private func validateDescriptor(',
        'private func serverGrantDate('])
    return '''import Foundation
import CoreFoundation

enum DownloadCheckFailure: Error { case failed(String) }
enum FeaturePatchError: Error { case notAuthenticated }
enum DeviceIdentityError: Error { case identityMissing, invalidIdentity }
enum ProtectedArtifactError: Error { case invalidDocument, contextMismatch, authenticationFailed }
typealias SharedSecret = Data

// Use the host's independent SHA-256 implementation, never a fake digest table.
// No shell or network is involved. macOS uses shasum; Linux uses sha256sum.
enum SHA256 {
    static func hash(data: Data) -> [UInt8] {
        let process = Process(), input = Pipe(), output = Pipe()
        #if os(Linux)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sha256sum")
        #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256"]
        #endif
        process.standardInput = input; process.standardOutput = output
        try! process.run()
        input.fileHandleForWriting.write(data)
        try! input.fileHandleForWriting.close()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let hex = String(data: bytes, encoding: .utf8)!.split(separator: " ")[0]
        return stride(from: 0, to: 64, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }
}

final class DeviceIdentityService {
    var deviceID: String? = "30000000-0000-4000-8000-000000000001"
    var agreementBase64 = Data(repeating: 7, count: 65).base64EncodedString()
    func persistedEnrollmentID() throws -> String? { deviceID }
    func getOrCreateAgreementKey() throws -> (publicKeyX963Base64: String, assurance: String) {
        (agreementBase64, "fixture-only")
    }
    func agreementSharedSecret(peerPublicKeyX963: Data) throws -> SharedSecret { Data() }
}
final class ServerSignatureVerifier { static let shared = ServerSignatureVerifier() }
@MainActor final class AppIntegrityRuntime {
    static let shared = AppIntegrityRuntime()
    var checks = 0
    var hook: (() -> Void)?
    func requireAllowed(force: Bool) async throws {
        checks += 1; hook?()
    }
}
@MainActor final class AuthManager {}
''' + errors + descriptor + result + response_time + manifest + '''
// Boundary double only: cryptographic verification/decryption is covered with
// production CryptoKit in the separate signed-catalog regression. Here the
// double checks that orchestration forwards every binding and exact byte string.
final class ProtectedArtifactDecoder {
    static let shared = ProtectedArtifactDecoder()
    static var plaintext = Data()
    static var expectedCiphertext = Data()
    static var expectedSessionID = "40000000-0000-4000-8000-000000000001"
    static var expectedRecipientID = "30000000-0000-4000-8000-000000000001"
    static var expectedNonce = String(repeating: "a", count: 32)
    static var decryptCalls = 0
    static var verificationDate: Date?
    static var afterDecrypt: (() -> Void)?
    private let recipientIdentity: (() throws -> (id: String, publicKey: Data))?
    init() { recipientIdentity = nil }
    init(verifier: ServerSignatureVerifier,
         recipientIdentity: @escaping () throws -> (id: String, publicKey: Data),
         sharedSecret: @escaping (Data) throws -> SharedSecret) {
        self.recipientIdentity = recipientIdentity
    }
    func verifyManifest(_ data: Data) throws -> ProtectedArtifactManifest {
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let manifest = try JSONDecoder().decode(ProtectedArtifactManifest.self,
            from: Self.canonicalData(object["body"]!))
        guard AppSecurityConfiguration.permitsProtectedArtifact(variant: manifest.variant, kind: manifest.kind) else {
            throw ProtectedArtifactError.invalidDocument
        }
        return manifest
    }
    func decrypt(signedManifest: Data, signedGrant: Data, ciphertext: Data,
                 recipientID: String, sessionID: String, requestNonce: String,
                 expectedArtifactID: String, expectedGrantID: String, now: Date) throws -> Data {
        Self.decryptCalls += 1
        Self.verificationDate = now
        let recipient = try recipientIdentity!()
        let manifest = try JSONSerialization.jsonObject(with: signedManifest) as! [String: Any]
        let grant = try JSONSerialization.jsonObject(with: signedGrant) as! [String: Any]
        let body = grant["body"] as! [String: Any]
        guard recipient.id == recipientID, recipientID == Self.expectedRecipientID,
              sessionID == Self.expectedSessionID, requestNonce == Self.expectedNonce,
              ciphertext == Self.expectedCiphertext,
              (manifest["body"] as! [String: Any])["artifactId"] as? String == expectedArtifactID,
              body["grantId"] as? String == expectedGrantID else {
            throw ProtectedArtifactError.contextMismatch
        }
        Self.afterDecrypt?()
        return Self.plaintext
    }
    static func canonicalData(_ value: Any) throws -> Data { Data(try canonicalJSON(value).utf8) }
''' + canonical + '''
}

@MainActor final class ProtectedDownloadHarness {
    typealias Transport = (String, [String: Any]) async throws -> (Data, String)
    var identity: DeviceIdentityService? = DeviceIdentityService()
    var sessionID = ProtectedArtifactDecoder.expectedSessionID
    var licenseDigest = "fixture-license"
    var lastResponseTime: ProtectedResponseTime?
    var validLicense = true
    var requests: [String] = []
    var transport: Transport
    init(transport: @escaping Transport) { self.transport = transport }
    func run(_ descriptor: ProtectedArtifactDescriptor) async throws -> ProtectedCodePatchDownload {
        try await downloadArtifact(descriptor, auth: AuthManager())
    }
    func validate(_ descriptor: ProtectedArtifactDescriptor,
                  manifest: ProtectedArtifactManifest, signedDocument: Any) throws {
        try validateDescriptor(descriptor, manifest: manifest, signedDocument: signedDocument)
    }
    private func post(_ path: String, body: [String: Any], signed: Bool,
                      purpose: String?) async throws -> (Data, String) {
        guard signed else { throw DownloadCheckFailure.failed("unsigned protected request") }
        requests.append(path)
        return try await transport(path, body)
    }
    private func requireCurrentLicense(_ auth: AuthManager) throws {
        if !validLicense { throw FeaturePatchError.notAuthenticated }
    }
''' + methods + '\n}\n'


if __name__ == '__main__':
    Path(sys.argv[1]).write_text(source(), encoding='utf-8')
