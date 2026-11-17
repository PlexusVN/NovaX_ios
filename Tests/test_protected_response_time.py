"""Execute the production pinned-response time policy with real Foundation."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]


class ProtectedResponseTimeChecks(unittest.TestCase):
    def test_actual_policy_is_independent_of_wall_clock_and_never_extends_expiry(self):
        compiler = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if compiler:
            command, translate = [compiler], str
            execute = lambda p: [str(p)]
        elif os.name == 'nt' and distro:
            compiler = subprocess.check_output(['wsl', '-d', distro, '--', 'bash', '-lc',
                'command -v swiftc'], text=True).strip()
            command = ['wsl', '-d', distro, '--', compiler]
            def translate(path):
                path = str(Path(path).resolve()).replace('\\', '/')
                return '/mnt/' + path[0].lower() + path[2:]
            execute = lambda p: ['wsl', '-d', distro, '--', translate(p)]
        else:
            self.skipTest('requires Swift; WSL enables Foundation checks on Windows')
        decoder = (ROOT/'ThreeOneOSFive/helpers/ProtectedArtifactDecoder.swift').read_text(encoding='utf-8')
        policy = extract_function(decoder, 'struct ProtectedResponseTime {')
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'ResponseTime.swift'
            source.write_text('import Foundation\n'+policy, encoding='utf-8')
            binary = Path(folder)/'time-check'
            subprocess.run(command+['-swift-version','5',translate(source),
                translate(ROOT/'Tests/ProtectedResponseTimeSelfCheck.swift'),'-o',translate(binary)],check=True)
            subprocess.run(execute(binary),check=True)

    def test_only_pinned_successful_response_can_supply_the_sample(self):
        source = (ROOT/'ThreeOneOSFive/helpers/ProtectedDownloadService.swift').read_text(encoding='utf-8')
        body = extract_function(source, '    private func post(')
        sample = body.index('lastResponseTime = ProtectedResponseTime.httpDate')
        self.assertLess(body.index('SecureAPIClient.shared.data(for: request)'), sample)
        self.assertLess(body.index('epoch == contextEpoch'), sample)
        self.assertLess(body.index('guard (200..<300).contains(response.statusCode)'), sample)
        artifact = extract_function(source, '    private func downloadArtifact(')
        self.assertIn('let contentTime = lastResponseTime', artifact)
        self.assertIn('now: contentTime?.verificationDate', artifact)
        self.assertIn('try validateDescriptor(', artifact)
        self.assertIn('try requireCurrentLicense(auth)', artifact)
        self.assertNotIn('while true', artifact)


if __name__ == '__main__':
    unittest.main()
