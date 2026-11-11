"""Compile real resume/session/catalog retry bodies with isolated transport on macOS."""
from pathlib import Path
import sys

source = (Path(sys.argv[1]) / 'ProtectedDownloadService.swift').read_text(encoding='utf-8')
def section(start, end):
    i = source.index(start)
    return source[i:source.index(end, i)]

prefix = '''import Foundation
import CryptoKit
enum FeaturePatchError: Error { case notAuthenticated }
@MainActor final class AuthManager {
    enum State: Equatable { case verified, idle }
    var authState: State = .verified
    var authenticationRevision: UInt64 = 0
    var licenseKey = "RESUME-FIXTURE"
    var hwid = "hardware-A"
}
'''
parts = [prefix,
    section('enum ProtectedDownloadError:', '@MainActor'),
    section('@MainActor\nprivate final class ProtectedAuthContext', 'private struct ProtectedSessionSnapshot'),
    section('// BEGIN RECOVERY CHALLENGE CONTRACT', '// END RECOVERY CHALLENGE CONTRACT'),
    section('private actor ProtectedRequestGate', '@MainActor\nfinal class ProtectedDownloadService')]
parts.append('''
@MainActor final class IdentityResumeHarness {
    typealias Transport = (String, [String: Any]) async throws -> [String: Any]
    private let gate = ProtectedRequestGate()
    private let retainedAuth: AuthManager
    private let transport: Transport
    private var currentAuthContext: ProtectedAuthContext?
    private var contextEpoch: UInt64 = 0
    private var identity: DeviceIdentityService?
    private var licenseDigest: String
    var accessNotice: String?
    var openFailures: [Error] = []
    private(set) var openCount = 0
    private(set) var recoveryCount = 0
    private(set) var clearCount = 0
    var currentIdentity: DeviceIdentityService { identity! }
    init(auth: AuthManager, identity: DeviceIdentityService, transport: @escaping Transport) {
        self.retainedAuth=auth; self.identity=identity; self.transport=transport
        licenseDigest=DeviceIdentityService.binding(forLicense:auth.licenseKey)
        currentAuthContext=ProtectedAuthContext(auth)
    }
    func invalidate() { contextEpoch &+= 1 }
    func session() async throws { try await ensureSession(auth:retainedAuth) }
    private func ensureCurrentSession(auth: AuthManager) async throws {
        openCount += 1
        if !openFailures.isEmpty { throw openFailures.removeFirst() }
    }
    private func recoverInstallation(context: ProtectedAuthContext, epoch: UInt64) async throws {
        recoveryCount += 1
        throw ProtectedDownloadError.rejected("device_recovery_required")
    }
    private func clearSession() { clearCount += 1 }
    private func ensureReleaseLease() async throws {}
    private func post(_ route: String, body: [String: Any], signed: Bool,
                      purpose: String?) async throws -> (Data,String) {
        let payload=try await transport(route,body)
        return (try JSONSerialization.data(withJSONObject:payload),String(repeating:"1",count:32))
    }
''')
parts += [section('    private func dictionary(', '    private func clearSession('),
          section('    private func beginOperation(', '    private func prepareIdentity('),
          section('    private func ensureSession(', '    private func resumeExistingInstallation('),
          section('    private func resumeExistingInstallation(', '    private func recordAccessFailure('),
          section('    private func recordAccessFailure(', '    private func requireRecoveryContext('),
          section('    private func requireRecoveryContext(', '    private func recoverInstallation('),
          section('    func sync(auth:', '    /// Best-effort telemetry'), '\n}\n']
Path(sys.argv[2]).write_text('\n'.join(parts), encoding='utf-8')
