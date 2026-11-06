"""Extract actual PDS recovery bodies for macOS tests with the real identity class.
No production file is edited. Transport fixtures return already-verified payloads;
signature/nonce/purpose failures are covered by validate_diagnostics.js separately.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
source=(root/'ProtectedDownloadService.swift').read_text(encoding='utf-8')
def section(start,end):
    at=source.index(start)
    return source[at:source.index(end,at)]
errors=section('enum ProtectedDownloadError:', '@MainActor')
context=section('@MainActor\nprivate final class ProtectedAuthContext', 'private struct ProtectedSessionSnapshot')
policy=section('// BEGIN RECOVERY CHALLENGE CONTRACT', '// END RECOVERY CHALLENGE CONTRACT')
dictionary=section('    private func dictionary(', '    private func clearSession(')
checks=section('    private func requireRecoveryContext(', '    private func recoverInstallation(')
recovery=section('    private func recoverInstallation(', '    private func ensureCurrentSession(')
prefix='''import Foundation
import CryptoKit

enum FeaturePatchError: Error { case notAuthenticated }
@MainActor final class AuthManager {
    enum State: Equatable { case verified, idle }
    var authState: State = .verified
    var authenticationRevision: UInt64 = 0
    var licenseKey: String
    var hwid: String
    init(licenseKey: String, hwid: String) { self.licenseKey=licenseKey;self.hwid=hwid }
}
'''
harness='''
@MainActor final class ProtectedRecoveryFlowHarness {
    typealias Transport = (String, [String: Any]) async throws -> [String: Any]
    private var identity: DeviceIdentityService?
    private var currentAuthContext: ProtectedAuthContext?
    private let retainedAuth: AuthManager
    private var contextEpoch: UInt64 = 0
    private let transport: Transport
    private(set) var clearedSessionCount = 0
    var currentIdentity: DeviceIdentityService { identity! }
    init(auth: AuthManager, identity: DeviceIdentityService, transport: @escaping Transport) {
        retainedAuth=auth;self.identity=identity;currentAuthContext=ProtectedAuthContext(auth);self.transport=transport
    }
    func invalidate() { contextEpoch &+= 1 }
    func recover() async throws {
        guard let context=currentAuthContext else { throw FeaturePatchError.notAuthenticated }
        try await recoverInstallation(context: context, epoch: contextEpoch)
    }
    private func clearSession() { clearedSessionCount += 1 }
    private func post(_ route: String, body: [String: Any], signed: Bool,
                      purpose: String?) async throws -> (Data, String) {
        guard !signed, (route=="/api/v2/device/challenge" && purpose=="device-challenge") ||
            (route=="/api/v2/device/enroll" && purpose=="device-enroll") else {
            throw ProtectedDownloadError.invalidResponse
        }
        let payload=try await transport(route,body)
        return (try JSONSerialization.data(withJSONObject:payload),String(repeating:"1",count:32))
    }
'''
Path(sys.argv[2]).write_text(prefix+errors+context+policy+harness+dictionary+checks+recovery+'\n}\n',encoding='utf-8')
