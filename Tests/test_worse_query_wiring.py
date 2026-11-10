"""Verify worse_query and pathleak integration wiring in Astra (NovaX)."""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]

class WorseQueryWiringTests(unittest.TestCase):
    def test_exploit_files_exist(self):
        exploit_dir = ROOT / 'ThreeOneOSFive' / 'exploit'
        for name in ['worse_query.h', 'worse_query.m', 'pathleak.h', 'pathleak.m']:
            file_path = exploit_dir / name
            self.assertTrue(file_path.exists(), f"Missing exploit file: {name}")
            self.assertGreater(file_path.stat().st_size, 0)

    def test_helper_file_exists(self):
        helper_path = ROOT / 'ThreeOneOSFive' / 'helpers' / 'WorseQueryHelper.swift'
        self.assertTrue(helper_path.exists(), "Missing WorseQueryHelper.swift")
        content = helper_path.read_text(encoding='utf-8')
        self.assertIn('class WorseQueryHelper', content)
        self.assertIn('worse_query(', content)
        self.assertIn('worse_query_release(', content)
        self.assertIn('pathleak(', content)
        self.assertIn('resolveActiveAppGroup', content)
        self.assertIn('withSandboxAccess', content)

    def test_bridging_header_includes_worse_query_and_pathleak(self):
        bridging_path = ROOT / 'ThreeOneOSFive' / 'ThreeOneOSFive-Bridging-Header.h'
        content = bridging_path.read_text(encoding='utf-8')
        self.assertIn('#import "exploit/worse_query.h"', content)
        self.assertIn('#import "exploit/pathleak.h"', content)

    def test_entitlements_include_app_groups(self):
        ent_path = ROOT / 'ThreeOneOSFive' / 'ThreeOneOSFive.entitlements'
        self.assertTrue(ent_path.exists())
        with open(ent_path, 'rb') as f:
            plist = plistlib.load(f)
        self.assertIn('com.apple.security.application-groups', plist)
        groups = plist['com.apple.security.application-groups']
        self.assertIn('group.com.novax.app', groups)
        self.assertIn('group.cc.forcequit.worse-query', groups)

    def test_xcode_project_wiring(self):
        proj_path = ROOT / 'ThreeOneOSFive.xcodeproj' / 'project.pbxproj'
        content = proj_path.read_text(encoding='utf-8')
        # Check PBXFileReferences
        self.assertIn('worse_query.m', content)
        self.assertIn('worse_query.h', content)
        self.assertIn('pathleak.m', content)
        self.assertIn('pathleak.h', content)
        self.assertIn('WorseQueryHelper.swift', content)
        # Check build files in Sources
        self.assertIn('3105W001 /* worse_query.m in Sources */', content)
        self.assertIn('3105W002 /* pathleak.m in Sources */', content)
        self.assertIn('3105W003 /* WorseQueryHelper.swift in Sources */', content)

    def test_storage_coordinator_routes_worse_query(self):
        storage_path = ROOT / 'ThreeOneOSFive' / 'helpers' / 'StorageEngineCoordinator.swift'
        content = storage_path.read_text(encoding='utf-8')
        self.assertIn('WorseQueryHelper.isAvailable', content)
        self.assertIn('WorseQueryHelper.writeFile', content)
        self.assertIn('WorseQueryHelper.readFile', content)

    def test_container_store_uses_worse_query(self):
        store_path = ROOT / 'ThreeOneOSFive' / 'helpers' / 'ContainerStore.swift'
        content = store_path.read_text(encoding='utf-8')
        self.assertIn('WorseQueryHelper.isAvailable', content)
        self.assertIn('WorseQueryHelper.acquireAccess', content)
        self.assertIn('WorseQueryHelper.readFile', content)

    def test_feature_patch_restore_supported_with_worse_query(self):
        patch_path = ROOT / 'ThreeOneOSFive' / 'helpers' / 'FeaturePatchService.swift'
        content = patch_path.read_text(encoding='utf-8')
        self.assertIn('!WorseQueryHelper.isAvailable &&', content)
        self.assertIn('WorseQueryHelper.removeItem', content)

    def test_exploit_support_policy_covers_worse_query(self):
        policy_path = ROOT / 'ThreeOneOSFive' / 'helpers' / 'KernelExploit.swift'
        content = policy_path.read_text(encoding='utf-8')
        self.assertIn('supportsWorseQuery', content)
        self.assertIn('26.0–26.7.2 on-device (worse_query, không cần pairing)', content)

    def test_container_resolution_wiring(self):
        icon_h = ROOT / 'ThreeOneOSFive' / 'helpers' / 'AppIconHelper.h'
        self.assertIn('containerPathForBundleID', icon_h.read_text(encoding='utf-8'))

        store_swift = ROOT / 'ThreeOneOSFive' / 'helpers' / 'ContainerStore.swift'
        content = store_swift.read_text(encoding='utf-8')
        self.assertIn('containerPathForBundleID', content)
        self.assertIn('astra.resolved_container.', content)
        self.assertIn('pathleak(appDataRoot', content)

        helper_swift = ROOT / 'ThreeOneOSFive' / 'helpers' / 'WorseQueryHelper.swift'
        helper_content = helper_swift.read_text(encoding='utf-8')
        self.assertIn('containerRoot(for:', helper_content)
        self.assertIn('currentFilesystemMaxInode()', helper_content)

        tx_swift = ROOT / 'ThreeOneOSFive' / 'helpers' / 'PatchTransaction.swift'
        tx_content = tx_swift.read_text(encoding='utf-8')
        self.assertIn('ContainerStore.grantContainerAccess(path)', tx_content)

if __name__ == '__main__':
    unittest.main()

