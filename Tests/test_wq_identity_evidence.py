"""Run the actual production container identity resolver without native APIs."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]


class IdentityEvidenceChecks(unittest.TestCase):
    def test_actual_identity_evidence(self):
        native = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if native:
            compiler, translate = [native], str
            execute = lambda path: [str(path)]
        elif os.name == 'nt' and distro:
            executable = subprocess.check_output(['wsl', '-d', distro, '--', 'bash', '-lc',
                'command -v swiftc'], text=True).strip()
            if not executable:
                self.skipTest('Swift compiler unavailable in configured WSL')
            compiler = ['wsl', '-d', distro, '--', executable]
            def translate(path):
                value = str(Path(path).resolve()).replace('\\', '/')
                return '/mnt/' + value[0].lower() + value[2:]
            execute = lambda path: ['wsl', '-d', distro, '--', translate(path)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')
        store = (ROOT / 'ThreeOneOSFive/helpers/ContainerStore.swift').read_text(encoding='utf-8')
        models = (ROOT / 'ThreeOneOSFive/helpers/PatchProjectModels.swift').read_text(encoding='utf-8')
        evidence = store.split('// BEGIN CONTAINER IDENTITY EVIDENCE', 1)[1].split('// END CONTAINER IDENTITY EVIDENCE', 1)[0]
        validator = extract_function(models, 'static func canonicalBundleIdentifier(')
        source = ('import Foundation\nenum PatchPackageError: Error { case invalidBundleIdentifier }\n'
                  + 'enum PatchPathValidator {\n' + validator + '\n}\n' + evidence)
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            production = folder / 'Production.swift'
            production.write_text(source, encoding='utf-8')
            binary = folder / 'identity-evidence-check'
            subprocess.run(compiler + [translate(production),
                translate(ROOT / 'Tests/ContainerIdentityEvidenceSelfCheck.swift'), '-o', translate(binary)], check=True)
            subprocess.run(execute(binary), check=True)

    def test_engine_has_no_game_list_or_cross_engine_discovery(self):
        store = (ROOT / 'ThreeOneOSFive/helpers/ContainerStore.swift').read_text(encoding='utf-8')
        scan = extract_function(store, 'static func prepareIOS27Access(')
        self.assertNotIn('com.dts.', scan)
        self.assertNotIn('containerPathForBundleID', scan)
        self.assertNotIn('MCMActivate', scan)
        self.assertIn('readWorseQueryIdentity(clean)', scan)
        self.assertIn('evidence.readable', scan)
        self.assertIn('worseQueryResume', scan)
        self.assertNotIn('token hợp lệ', scan)


if __name__ == '__main__':
    unittest.main()
