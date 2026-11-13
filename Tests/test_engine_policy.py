"""Compile actual production policy against an independent boundary matrix."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EnginePolicyChecks(unittest.TestCase):
    def test_actual_policy_boundaries(self):
        compiler = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if compiler:
            command, translate = [compiler], str
            execute = lambda path: [str(path)]
        elif os.name == 'nt' and distro:
            compiler = subprocess.check_output(['wsl','-d',distro,'--','bash','-lc','command -v swiftc'], text=True).strip()
            command = ['wsl','-d',distro,'--',compiler]
            def translate(path):
                path = str(Path(path).resolve()).replace('\\','/')
                return '/mnt/' + path[0].lower() + path[2:]
            execute = lambda path: ['wsl','-d',distro,'--',translate(path)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')
        source = (ROOT/'ThreeOneOSFive/helpers/KernelExploit.swift').read_text(encoding='utf-8')
        policy = source[source.index('enum ExploitSupportPolicy {'):source.index('// MARK: - Sandbox & Filesystem Access Helpers')]
        with tempfile.TemporaryDirectory() as folder:
            actual = Path(folder)/'Policy.swift'
            actual.write_text('import Foundation\n'+policy, encoding='utf-8')
            binary = Path(folder)/'policy-check'
            subprocess.run(command+['-swift-version','5',translate(actual),translate(ROOT/'Tests/EnginePolicySelfCheck.swift'),'-o',translate(binary)],check=True)
            subprocess.run(execute(binary),check=True)

    def test_ui_and_library_use_only_selected_engine(self):
        settings = (ROOT/'ThreeOneOSFive/views/SettingsView.swift').read_text(encoding='utf-8')
        self.assertIn('currentAccessProvider == .airLift', settings)
        ui = (ROOT/'ThreeOneOSFive/views/AirLiftSettingsSection.swift').read_text(encoding='utf-8')
        self.assertNotIn('Toggle(isOn: $storageCoordinator.useAirLiftForAll)', ui)
        self.assertNotIn('engineHealthState.isHealthy ||', ui)
        library = (ROOT/'ThreeOneOSFive/views/PatchProjectsView.swift').read_text(encoding='utf-8')
        self.assertIn('runPatchLibraryDirectOperation', library)
        self.assertIn('DirectPatchExecutor.run', library)
        app = (ROOT/'ThreeOneOSFive/App.swift').read_text(encoding='utf-8')
        self.assertIn('configureTargets(bundleIDs: AppSecurityConfiguration.protectedBundleIDs)', app)


if __name__ == '__main__':
    unittest.main()
