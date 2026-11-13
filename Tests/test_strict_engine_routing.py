"""Exercise production resolver dispatch, with native/file transport replaced by spies."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'ThreeOneOSFive/helpers'


class StrictEngineRouting(unittest.TestCase):
    def test_missing_wq_group_cannot_skip_preparation_or_write_raw_files(self):
        coordinator = (HELPERS / 'StorageEngineCoordinator.swift').read_text(encoding='utf-8')
        for signature in ['func writeFileInOperation(', 'func readFile(']:
            body = extract_function(coordinator, signature)
            self.assertLess(body.index('currentStorageMode != .unsupported'), body.index('if isAirLiftActive'))
            self.assertLess(body.index('currentAccessProvider == .worseQuery'), body.index('if isAirLiftActive'))
            self.assertIn('guard WorseQueryHelper.isAvailable else { throw WorseQueryError.appGroupUnavailable }', body)
        preparation = (HELPERS / 'IOS27ContainerPreparation.swift').read_text(encoding='utf-8')
        self.assertNotIn('chooseAirLift', preparation)
        self.assertNotIn('canUseAirLift', preparation)
        restore = extract_function((HELPERS / 'FeaturePatchService.swift').read_text(encoding='utf-8'), 'func restorePatch(')
        self.assertNotIn('AppInfo.versionTuple.major >= 27', restore)

    def test_actual_production_container_resolver_and_grant_routing(self):
        native = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if native:
            compiler, translate = [native], str
            execute = lambda binary: [str(binary)]
        elif os.name == 'nt' and distro:
            native = subprocess.check_output(['wsl','-d',distro,'--','bash','-lc','command -v swiftc'], text=True).strip()
            if not native:
                self.skipTest('Swift unavailable in configured WSL distribution')
            compiler = ['wsl','-d',distro,'--',native]
            def translate(value):
                value = str(Path(value).resolve()).replace('\\','/')
                return '/mnt/' + value[0].lower() + value[2:]
            execute = lambda binary: ['wsl','-d',distro,'--',translate(binary)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')
        policy = (HELPERS / 'KernelExploit.swift').read_text(encoding='utf-8')
        policy = policy[policy.index('enum ExploitSupportPolicy {'):policy.index('// MARK: - Sandbox & Filesystem Access Helpers')]
        store = (HELPERS / 'ContainerStore.swift').read_text(encoding='utf-8')
        code = 'import Foundation\n' + policy + '\nenum ContainerStore {\n'
        code += extract_function(store, 'private static var shouldUseBadQuery: Bool') + '\n'
        for signature in ['static func resolveAppContainerPath(', 'static func resolveAppContainerForPatch(', 'static func grantContainerAccess(']:
            code += extract_function(store, signature) + '\n'
        code += '''
static func isApplicationContainerPath(_ path: String) -> Bool { path == Calls.root || path == Calls.freshRoot }
static func resolveAppContainerPathByMetadataScan(bundleID: String) -> String? { Calls.events.append("metadata"); return nil }
static func resolveContainerWithWorseQuery(bundleID: String) throws -> String { preconditionFailure("unexpected scan") }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'Routing.swift'
            source.write_text(code, encoding='utf-8')
            binary = Path(directory) / 'routing'
            subprocess.run(compiler + ['-swift-version', '5', translate(source), translate(ROOT / 'Tests/EngineDispatchSelfCheck.swift'), '-o', translate(binary)], check=True)
            subprocess.run(execute(binary), check=True)


if __name__ == '__main__':
    unittest.main()
