"""Compile actual pinned-TLS POST, enrollment/session and catalog retry bodies.
Transport/Keychain are isolated; iOS TLS/proxy policy is tested separately.
"""
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'ProtectedDownloadService.swift').read_text(encoding='utf-8')
def section(start, end):
    i = source.index(start)
    return source[i:source.index(end, i)]
prefix = r'''import Foundation
import CryptoKit

enum FeaturePatchError: Error { case notAuthenticated }
@MainActor final class AuthManager {
    enum State: Equatable { case verified, idle }
    var authState: State = .verified
    var authenticationRevision: UInt64 = 0
    var licenseKey = "RESUME-FIXTURE"
    var hwid = "hardware-A"
}
enum FixtureNetworkError: Error { case untrustedTLS, invalidURL }
enum SecureAPIError: Error { case invalidEndpoint }
@MainActor final class SecureAPIClient {
    static let shared = SecureAPIClient()
    static var handler: ((URLRequest) async throws -> (Data,HTTPURLResponse))!
    static func validateURL(_ url: URL) throws {
        guard SecureAPIEndpointPolicy.permits(url) else { throw FixtureNetworkError.invalidURL }
    }
    func data(for request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        try Self.validateURL(request.url!)
        return try await Self.handler(request)
    }
}
@MainActor final class RequestProofService {
    static let shared = RequestProofService()
    func generateNonce() throws -> String { UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased() }
    func signRequest(request: inout URLRequest, sessionId: String, deviceKeyId: String,
                     identity: DeviceIdentityService) throws -> String {
        let nonce = try generateNonce()
        request.setValue(nonce,forHTTPHeaderField:"X-Astra-Nonce")
        request.setValue(deviceKeyId,forHTTPHeaderField:"X-Astra-Device-Key")
        request.setValue(sessionId,forHTTPHeaderField:"X-Astra-Session")
        return nonce
    }
}
'''
parts = [prefix, section('enum ProtectedDownloadError:', '@MainActor'),
         section('@MainActor\nprivate final class ProtectedAuthContext','private struct ProtectedArtifactDescriptor'),
         section('// BEGIN RECOVERY CHALLENGE CONTRACT','// END RECOVERY CHALLENGE CONTRACT'),
         section('private actor ProtectedRequestGate','@MainActor\nfinal class ProtectedDownloadService')]
parts.append((root / 'ProtectedReleaseLease.swift').read_text(encoding='utf-8'))
api = (root / 'SecureAPIClient.swift').read_text(encoding='utf-8')
parts.append(api[api.index('enum SecureAPIEndpointPolicy {'):api.index('/// Validate before attaching credentials')])
utils = (root.parent / 'views/SecurityUtils.swift').read_text(encoding='utf-8')
parts.append(utils.split('// BEGIN STABLE HWID POLICY')[1].split('// END STABLE HWID POLICY')[0].split('\n',1)[1])
parts.append(r'''
@MainActor final class IdentityResumeHarness {
    private let gate = ProtectedRequestGate()
    private let retainedAuth: AuthManager
    private let origin = AppSecurityConfiguration.apiOrigin
    private var currentAuthContext: ProtectedAuthContext?
    private var contextEpoch: UInt64 = 0
    private var identity: DeviceIdentityService?
    private var licenseDigest: String
    private var sessionID = "", sessionToken = ""
    private var sessionExpiry = Date.distantPast
    private var releaseLease = ProtectedReleaseLease()
    var accessNotice: String?
    init(auth: AuthManager, identity: DeviceIdentityService) {
        retainedAuth=auth; self.identity=identity
        licenseDigest=DeviceIdentityService.binding(forLicense:auth.licenseKey)
        currentAuthContext=ProtectedAuthContext(auth)
    }
    func invalidate() { contextEpoch &+= 1 }
    func expireSession() { sessionExpiry = .distantPast }
    func session() async throws { try await ensureSession(auth:retainedAuth) }
    private func ensureReleaseLease() async throws {}
}
''')
# Insert the real production methods into the fixture class.
parts[-1] = parts[-1].rsplit('}',1)[0]
for start,end in [
 ('    private func endpoint(', '    private func post('),
 ('    private func post(', '    private func dictionary('),
 ('    private func dictionary(', '    private func clearSession('),
 ('    private func clearSession(', '    /// Foreground/background'),
 ('    private func beginOperation(', '    private func prepareIdentity('),
 ('    private func prepareIdentity(', '    private func ensureSession('),
 ('    private func ensureSession(', '    private func recordAccessFailure('),
 ('    private func recordAccessFailure(', '    private func requireRecoveryContext('),
 ('    private func requireRecoveryContext(', '    private func recoverInstallation('),
 ('    private func ensureCurrentSession(', '    private func acceptSession('),
 ('    private func acceptSession(', '    func sync(auth:'),
 ('    func sync(auth:', '    /// Best-effort telemetry')]:
    parts.append(section(start,end))
parts.append('\n}\n')
Path(sys.argv[2]).write_text('\n'.join(parts),encoding='utf-8')
