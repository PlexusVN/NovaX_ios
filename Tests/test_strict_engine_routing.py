"""Exercise production resolver dispatch, with native/file transport replaced by spies."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'ThreeOneOSFive/helpers'


class StrictEngineRouting(unittest.TestCase):
    def test_missing_wq_group_cannot_skip_preparation_or_write_raw_files(self):
        coordinator = (HELPERS / 'StorageEngineCoordinator.swift').read_text(encoding='utf-8')
        for signature in ['func writeFile(', 'func readFile(']:
            body = extract_function(coordinator, signature)
            self.assertLess(body.index('currentStorageMode != .unsupported'), body.index('if isAirLiftActive'))
            self.assertLess(body.index('currentAccessProvider == .worseQuery'), body.index('if isAirLiftActive'))
            self.assertIn('guard WorseQueryHelper.isAvailable else { throw WorseQueryError.appGroupUnavailable }', body)
        preparation = (HELPERS / 'IOS27ContainerPreparation.swift').read_text(encoding='utf-8')
        self.assertNotIn('chooseAirLift', preparation)
        self.assertNotIn('canUseAirLift', preparation)
        restore = extract_function((HELPERS / 'FeaturePatchService.swift').read_text(encoding='utf-8'), 'func restorePatch(')
        self.assertNotIn('AppInfo.versionTuple.major >= 27', restore)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'requires macOS Swift')
    def test_actual_production_container_resolver_and_grant_routing(self):
        policy = (HELPERS / 'KernelExploit.swift').read_text(encoding='utf-8')
        policy = policy[policy.index('enum ExploitSupportPolicy {'):policy.index('// MARK: - Sandbox & Filesystem Access Helpers')]
        store = (HELPERS / 'ContainerStore.swift').read_text(encoding='utf-8')
        code = 'import Foundation\n' + policy + '\nenum ContainerStore {\n'
        code += extract_function(store, 'private static var shouldUseBadQuery: Bool') + '\n'
        for signature in ['static func resolveAppContainerPath(', 'static func resolveAppContainerForPatch(', 'static func grantContainerAccess(']:
            code += extract_function(store, signature) + '\n'
        code += '''
static func isApplicationContainerPath(_ path: String) -> Bool { path == Calls.root }
static func resolveAppContainerPathByMetadataScan(bundleID: String) -> String? { Calls.events.append("metadata"); return nil }
static func resolveContainerWithWorseQuery(bundleID: String) throws -> String { preconditionFailure("unexpected scan") }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'Routing.swift'
            source.write_text(code, encoding='utf-8')
            binary = Path(directory) / 'routing'
            subprocess.run(['swiftc', str(source), str(ROOT / 'Tests/EngineDispatchSelfCheck.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
