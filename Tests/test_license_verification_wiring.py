from pathlib import Path
import re
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LicenseVerificationWiringTests(unittest.TestCase):
    def test_login_and_monitor_share_literal_post_builder_and_pinned_client(self):
        source = (ROOT / 'ThreeOneOSFive/views/AuthManager.swift').read_text(encoding='utf-8')
        self.assertEqual(source.count('LicenseVerification.request('), 2)
        self.assertEqual(source.count('SecureAPIClient.shared.data(for: request)'), 2)
        self.assertNotIn('urlQueryAllowed', source)
        self.assertNotIn('let serverMsg', source)
        self.assertIn('HMACUtils.compute', source)
        self.assertEqual(source.count('AppSecurityConfiguration.apiOrigin'), 2)
        self.assertEqual(source.count('AppSecurityConfiguration.productSecret'), 2)
        self.assertNotIn('AstraServerTrust', source)
        monitor = source.split('private func reVerify()')[1]
        transient = monitor.split('if httpResp.statusCode == 429')[1].split('guard let json')[0]
        self.assertIn('return .networkError', transient)
        self.assertNotIn('clearSession()', transient)

    def test_helper_and_selfcheck_are_in_build(self):
        project = (ROOT / 'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        build = re.search(r'(\w+) /\* LicenseVerification.swift in Sources \*/', project)[1]
        phase = project.split('/* Begin PBXSourcesBuildPhase section */')[1].split(
            '/* End PBXSourcesBuildPhase section */')[0]
        self.assertIn(build + ',', phase)
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        self.assertIn('swiftc ThreeOneOSFive/helpers/LicenseVerification.swift', workflow)
        self.assertIn('Tests/LicenseVerificationSelfCheck.swift', workflow)

    def test_next_build_is_consistent_with_ci_gate(self):
        info = plistlib.loads((ROOT / 'ThreeOneOSFive/Info.plist').read_bytes())
        build = info['CFBundleVersion']
        self.assertTrue(build.isdigit())
        project = (ROOT / 'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'CURRENT_PROJECT_VERSION = (\d+);', project), [build, build])
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        self.assertIn('Astra-Unsigned-IPA-' + info['CFBundleShortVersionString'] + '-' + build, workflow)
        self.assertIn('CFBundleVersion\' "$APP_NAME/Info.plist")" = "' + build + '"', workflow)
        self.assertNotIn('CFBundleVersion\' "$APP_NAME/Info.plist")" = "16"', workflow)


if __name__ == '__main__':
    unittest.main()
