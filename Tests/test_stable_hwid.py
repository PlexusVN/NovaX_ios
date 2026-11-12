"""Compile real HWID policy and real AuthManager retry methods, without iOS services."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]
VIEWS = ROOT / 'ThreeOneOSFive/views'


class StableHWIDChecks(unittest.TestCase):
    def test_login_and_copy_preserve_the_actual_identity_error(self):
        auth = (VIEWS / 'AuthManager.swift').read_text(encoding='utf-8')
        utils = (VIEWS / 'SecurityUtils.swift').read_text(encoding='utf-8')
        view = (VIEWS / 'SplashLoginView.swift').read_text(encoding='utf-8')
        self.assertNotIn('try? StableDeviceHWID.resolve', utils)
        self.assertIn('UIApplication.protectedDataDidBecomeAvailableNotification', auth)
        self.assertIn('UIApplication.didBecomeActiveNotification', auth)
        self.assertIn('saveStatus', extract_function(auth, 'func login('))
        self.assertIn('auth.hwidFailure', view)
        self.assertIn('isExcludedFromBackup = true', utils)
        self.assertIn('.completeFileProtectionUntilFirstUserAuthentication', utils)

    def test_actual_swift_policy_and_login_retry(self):
        native = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if native:
            compiler = [native]
            translate = str
            execute = lambda binary: [str(binary)]
        elif os.name == 'nt' and distro:
            path = subprocess.check_output(['wsl','-d',distro,'--','bash','-lc','command -v swiftc'],text=True).strip()
            if not path:
                self.skipTest('Swift compiler unavailable in requested WSL distribution')
            compiler = ['wsl','-d',distro,'--',path]
            def translate(path):
                path = str(Path(path).resolve()).replace('\\','/')
                return '/mnt/' + path[0].lower() + path[2:]
            execute = lambda binary: ['wsl','-d',distro,'--',translate(binary)]
        else:
            self.skipTest('requires Swift; optional ASTRA_SWIFT_WSL_DISTRIBUTION enables local Windows checks')
        utils = (VIEWS / 'SecurityUtils.swift').read_text(encoding='utf-8')
        policy = utils[utils.index('enum StableDeviceHWID {'):utils.index('// END STABLE HWID POLICY')]
        auth = (VIEWS / 'AuthManager.swift').read_text(encoding='utf-8')
        methods = '\n'.join(extract_function(auth, signature) for signature in
                            ['private func refreshDeviceHWID(', 'private func retryDeviceHWID('])
        gate = extract_function(auth, 'func login(')
        gate = gate[gate.index('        guard refreshDeviceHWID() else {'):gate.index('        authState = .loading(')]
        harness = '''
@MainActor final class HWIDLoginHarness {
    enum State: Equatable { case idle, loading(String), verified, error(String) }
    var authState: State = .idle
    var hwid = ""
    var hwidFailure: String?
    private var hwidRetryTask: Task<Void,Never>?
    private var hwidRetryable = false
    private var loginBlockedByHWID: String?
    var networkRequests = 0
    deinit { hwidRetryTask?.cancel() }
'''+methods+'''
    func foregroundOrUnlock() { retryDeviceHWID() }
    func attemptLogin() {
'''+gate+'''
        networkRequests += 1
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'ActualHWID.swift'
            source.write_text('import Foundation\n'+policy+harness,encoding='utf-8')
            binary = Path(directory) / 'hwid-check'
            subprocess.run(compiler+['-swift-version','5',translate(source),translate(ROOT/'Tests/StableHWIDSelfCheck.swift'),'-o',translate(binary)],check=True)
            subprocess.run(execute(binary),check=True)


if __name__ == '__main__':
    unittest.main()
