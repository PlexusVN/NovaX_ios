"""Catch missing production sources in the standalone macOS security harness."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
TRUST = 'ThreeOneOSFive/helpers/AstraServerTrust.swift'


class SecurityBuildWiringTests(unittest.TestCase):
    def test_harness_compiles_the_production_trust_definition(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        command = re.search(r'swiftc\s+.*?Tests/ProtectedArtifactSelfCheck\.swift\s+-o',
                            workflow, re.DOTALL)
        self.assertIsNotNone(command)
        inputs = re.findall(r'(?:ThreeOneOSFive|Tests)/[\w/]+\.swift', command.group())
        self.assertIn(TRUST, inputs)
        for source in inputs:
            self.assertTrue((ROOT / source).is_file(), source)
            self.assertNotRegex((ROOT / source).read_text(encoding='utf-8'), r'(?m)^import UIKit\b')

    def test_only_one_real_trust_definition_without_an_ios_dependency(self):
        definitions = []
        for source in (ROOT / 'ThreeOneOSFive').rglob('*.swift'):
            if re.search(r'\benum AstraServerTrust\s*\{', source.read_text(encoding='utf-8')):
                definitions.append(source.relative_to(ROOT).as_posix())
        self.assertEqual(definitions, [TRUST])
        source = (ROOT / TRUST).read_text(encoding='utf-8')
        self.assertNotIn('import UIKit', source)
        self.assertNotIn('Obf.', source)
        self.assertIn('SecTrustEvaluateWithError(trust, &trustError)', source)
        self.assertIn('leafCertificatePins.contains(Data(SHA256.hash(data: der)).base64EncodedString())', source)
        self.assertNotRegex((ROOT / 'Tests/ProtectedArtifactSelfCheck.swift').read_text(encoding='utf-8'),
                            r'\b(?:enum|class|struct) AstraServerTrust\b')

    def test_production_trust_is_in_the_ios_sources_build_phase(self):
        project = (ROOT / 'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        build = re.search(r'(\w+) /\* AstraServerTrust\.swift in Sources \*/ = '
                          r'\{isa = PBXBuildFile; fileRef = (\w+);', project)
        self.assertIsNotNone(build)
        self.assertRegex(project, re.escape(build[2]) + r' /\* AstraServerTrust\.swift \*/ = '
                         r'\{isa = PBXFileReference;[^\n]*path = AstraServerTrust\.swift;')
        phase = project.split('/* Begin PBXSourcesBuildPhase section */')[1].split(
            '/* End PBXSourcesBuildPhase section */')[0]
        self.assertIn(build[1] + ',', phase)

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


if __name__ == '__main__':
    unittest.main()
