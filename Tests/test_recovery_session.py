"""Execute the production session/recovery orchestration with isolated boundaries.

The macOS identity/recovery self-checks exercise the real CryptoKit storage and
canonical enrollment bodies; this portable check tests their orchestration,
retry bounds and cancellation using the actual ensureSession implementation.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]


class SessionRecoveryChecks(unittest.TestCase):
    def test_actual_session_orchestration(self):
        native = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if native:
            compiler, translate = [native], str
            execute = lambda binary: [str(binary)]
        elif os.name == 'nt' and distro:
            native = subprocess.check_output(
                ['wsl', '-d', distro, '--', 'bash', '-lc', 'command -v swiftc'], text=True).strip()
            if not native:
                self.skipTest('Swift unavailable in configured WSL distribution')
            compiler = ['wsl', '-d', distro, '--', native]
            def translate(value):
                value = str(Path(value).resolve()).replace('\\', '/')
                return '/mnt/' + value[0].lower() + value[2:]
            execute = lambda binary: ['wsl', '-d', distro, '--', translate(binary)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')
        pds = (ROOT / 'ThreeOneOSFive/helpers/ProtectedDownloadService.swift').read_text(encoding='utf-8')
        identity = (ROOT / 'ThreeOneOSFive/helpers/DeviceIdentityService.swift').read_text(encoding='utf-8')
        declarations = (pds[pds.index('enum ProtectedDownloadError:'):pds.index('@MainActor')]
                        + identity[identity.index('enum DeviceIdentityError:'):identity.index('struct DeviceIdentityStorage')]
                        + pds[pds.index('// BEGIN RECOVERY CHALLENGE CONTRACT'):pds.index('// END RECOVERY CHALLENGE CONTRACT')])
        source = '''import Foundation
typealias OSStatus = Int32
'''+declarations+'''
enum FeaturePatchError: Error { case notAuthenticated }
@MainActor final class AuthManager {}
@MainActor final class ProtectedAuthContext {
    var valid=true
    func validate() throws { guard valid else { throw FeaturePatchError.notAuthenticated } }
}
@MainActor final class SessionController {
    var pending=false
    var failure: Error?
    var events: [String]=[]
    func pendingRecoveryCandidate(hwid: String) throws -> Bool? {
        events.append("pending")
        if let failure { throw failure }
        return pending ? true : nil
    }
}
extension ProtectedAuthContext { var hwid: String { "hardware-A" } }
@MainActor final class SessionRecoveryHarness {
    var currentAuthContext: ProtectedAuthContext? = ProtectedAuthContext()
    var contextEpoch: UInt64=0
    let controller=SessionController()
    var failures: [Error?]=[]
    var afterOpen: (() -> Void)?
    var authorized=false
    var recoveryFailure: Error?
    var clears=0, opens=0, probes=0, replacements=0
    var cachedSession=false
    var catalogFailures: [Error?]=[]
    var catalogs=0
    func run() async throws { try await ensureSession(auth:AuthManager()) }
    func catalog() async throws { _ = try await syncCatalogWithSessionRetry(auth:AuthManager()) }
    private func recoveryController(_ context:ProtectedAuthContext) throws -> SessionController { controller }
    private func clearSession() { clears += 1; cachedSession=false; controller.events.append("clear") }
    private func requireRecoveryContext(_ context:ProtectedAuthContext, epoch:UInt64) throws {
        guard contextEpoch == epoch, currentAuthContext === context, context.valid else { throw CancellationError() }
    }
    private func ensureCurrentSession(auth:AuthManager) async throws {
        if cachedSession { controller.events.append("cached"); return }
        opens += 1; controller.events.append("open")
        afterOpen?()
        if !failures.isEmpty, let error=failures.removeFirst() { throw error }
    }
    private func ensureReleaseLease() async throws {}
    private func post(_ route:String, body:[String:Any],signed:Bool,purpose:String) async throws -> (Data,String) {
        guard route == "/api/v2/artifacts/sync", signed else { throw ProtectedDownloadError.invalidResponse }
        catalogs += 1
        if !catalogFailures.isEmpty, let error=catalogFailures.removeFirst() { throw error }
        return (Data(),"")
    }
    private func recoverInstallation(context:ProtectedAuthContext, epoch:UInt64) async throws {
        try requireRecoveryContext(context,epoch:epoch)
        probes += 1; controller.events.append("recover")
        if let recoveryFailure { throw recoveryFailure }
        guard controller.pending || authorized else { throw ProtectedDownloadError.rejected("device_recovery_required") }
        if !controller.pending { replacements += 1 }
        controller.pending=false
    }
'''+extract_function(pds, 'private func ensureSession(')+'\n'+extract_function(pds, 'private func syncCatalogWithSessionRetry(')+'\n}\n'
        with tempfile.TemporaryDirectory() as directory:
            source_file = Path(directory) / 'ActualSessionRecovery.swift'
            source_file.write_text(source, encoding='utf-8')
            binary = Path(directory) / 'session-recovery-check'
            subprocess.run(compiler + ['-swift-version', '5', translate(source_file),
                translate(ROOT / 'Tests/ProtectedSessionRecoverySelfCheck.swift'), '-o', translate(binary)], check=True)
            subprocess.run(execute(binary), check=True)


if __name__ == '__main__':
    unittest.main()
