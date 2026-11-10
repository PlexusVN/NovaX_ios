"""Check the current network-only app and native rebuild workflow.

The standalone endpoint harness does not execute the UIKit TLS delegate.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
TRUST = 'ThreeOneOSFive/helpers/AstraServerTrust.swift'


class SecurityBuildWiringTests(unittest.TestCase):
    def test_endpoint_harness_uses_portable_production_sources(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        command = re.search(r'swiftc\s+.*?Tests/ProtectedArtifactSelfCheck\.swift\s+-o',
                            workflow, re.DOTALL)
        self.assertIsNotNone(command)
        inputs = re.findall(r'(?:ThreeOneOSFive|Tests)/[\w/]+\.swift', command.group())
        self.assertIn('ThreeOneOSFive/helpers/SecureAPIClient.swift', inputs)
        for source in inputs:
            self.assertTrue((ROOT / source).is_file(), source)
            self.assertNotRegex((ROOT / source).read_text(encoding='utf-8'), r'(?m)^import UIKit\b')

    def test_compiled_ios_trust_checks_system_trust_and_the_configured_pin(self):
        source = (ROOT / 'ThreeOneOSFive/views/SecurityUtils.swift').read_text(encoding='utf-8')
        trust = source.split('enum AstraServerTrust {')[1].split('final class CertPinningDelegate')[0]
        self.assertIn('SecTrustEvaluateWithError(trust, &trustError)', trust)
        self.assertIn('AppSecurityConfiguration.tlsCertificatePins', trust)
        self.assertIn('if leafCertificatePins.contains(pin) { return true }', trust)
        self.assertTrue(trust.rstrip().endswith('return false\n    }\n}'))
        self.assertNotRegex((ROOT / 'Tests/ProtectedArtifactSelfCheck.swift').read_text(encoding='utf-8'),
                            r'\b(?:enum|class|struct) AstraServerTrust\b')

    def test_actual_tls_delegate_is_in_the_ios_sources_build_phase(self):
        project = (ROOT / 'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        build = re.search(r'(\w+) /\* SecurityUtils\.swift in Sources \*/ = '
                          r'\{isa = PBXBuildFile; fileRef = (\w+);', project)
        self.assertIsNotNone(build)
        self.assertRegex(project, re.escape(build[2]) + r' /\* SecurityUtils\.swift \*/ = '
                         r'\{isa = PBXFileReference;[^\n]*path = SecurityUtils\.swift;')
        phase = project.split('/* Begin PBXSourcesBuildPhase section */')[1].split(
            '/* End PBXSourcesBuildPhase section */')[0]
        self.assertIn(build[1] + ',', phase)
        self.assertNotIn('AstraServerTrust.swift in Sources', phase)

    def test_moving_trust_preserves_the_host_origin_and_leaf_pin(self):
        source = (ROOT / TRUST).read_text(encoding='utf-8')
        for name, expected in [('protectedHost', 'zynox.click'),
                               ('protectedOrigin', 'https://zynox.click')]:
            encoded = re.search(r'static let ' + name + r' = decode\(\[(.*?)\],\s*(0x[\da-fA-F]+)\)',
                                source, re.DOTALL)
            self.assertIsNotNone(encoded)
            decoded = bytes(int(value) ^ int(encoded[2], 16)
                            for value in re.findall(r'\d+', encoded[1])).decode('utf-8')
            self.assertEqual(decoded, expected)
        self.assertIn('7NfgIVpP+fdJQCMiloG7ljIWxP5OZEiAGfsc6+jgcQA=', source)

    def test_framework_gate_checks_rust_exports_not_the_app_objc_helper(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        gate = (ROOT / 'ReleaseTools/verify_native_compatibility.py').read_text(encoding='utf-8')
        script = (ROOT / 'ReleaseTools/build_airlift_compat.sh').read_text(encoding='utf-8')
        exports = gate.split('REQUIRED_EXPORTS =')[1].split('REQUIRED_MARKERS =')[0]
        self.assertNotIn('_ALGetGrappaToken', exports)
        for symbol in ['_al_exploit_run', '_al_exploit_write_dir', '_al_pairing_run_host']:
            self.assertIn(symbol, exports)
        for platform in ['ios-arm64', 'ios-arm64-simulator']:
            self.assertIn(platform, script)
        self.assertIn('--archive "$DEVICE" --max-ios "$MIN_IOS"', script)
        self.assertIn('--archive "$SIM" --platform simulator --max-ios "$MIN_IOS"', script)
        self.assertLess(workflow.index('bash ReleaseTools/build_airlift_compat.sh'), workflow.index('- name: Build App'))
        # Do not accidentally remove the independent post-link patch checks.
        for marker in ['RemoteXPC timed out after 6s', 'timeout fallback trying raw RPPairing',
                       'AirTraffic write timed out after 180s; operation cancelled',
                       '! strings "$APP_NAME/$EXECUTABLE" | grep -F "proceeding with direct writeDirectory"']:
            self.assertIn(marker, workflow)

    def test_network_only_distribution_does_not_quarantine_unsigned_installs(self):
        app = (ROOT / 'ThreeOneOSFive/App.swift').read_text(encoding='utf-8')
        self.assertNotIn('evidence.append(binaryEvidence)', app)
        self.assertNotIn('evidence.append(releaseEvidence)', app)
        self.assertNotIn('quarantineForJailbreak', app)
        config = (ROOT / 'ThreeOneOSFive/helpers/AppSecurityConfiguration.swift').read_text(encoding='utf-8')
        self.assertIn('static let localIntegrityEnforced = false', config)
        download = (ROOT / 'ThreeOneOSFive/helpers/ProtectedDownloadService.swift').read_text(encoding='utf-8')
        lease = download.split('private func ensureReleaseLease()')[1].split('func reportIntegrityFailure')[0]
        self.assertIn('guard AppSecurityConfiguration.localIntegrityEnforced else { return }', lease)
        self.assertIn('post("/api/v2/security/integrity-v2"', lease)
        self.assertIn('signed:true,purpose:"app-integrity-v2"', lease)


if __name__ == '__main__':
    unittest.main()
