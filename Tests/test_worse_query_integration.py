"""Offline source contracts plus actual Swift wrapper behavior on macOS.

No test here proves a signed IPA can obtain a token from an iPhone daemon.
"""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'ThreeOneOSFive/helpers'


class IntegrationContracts(unittest.TestCase):
    def test_resigning_uses_runtime_entitlements_before_fallback_names(self):
        native = (HELPERS / 'AppIconHelper.m').read_text(encoding='utf-8')
        for symbol in ['SecTaskCreateFromSelf', 'SecTaskCopyValueForEntitlement',
                       'com.apple.security.application-groups', 'CFBridgingRelease(value)']:
            self.assertIn(symbol, native)
        helper = (HELPERS / 'WorseQueryHelper.swift').read_text(encoding='utf-8')
        self.assertLess(helper.index('AstraSignedApplicationGroups()'), helper.index('group.com.novax.app'))
        self.assertIn('ExploitSupportPolicy.supportsWorseQuery(', helper)
        self.assertNotIn('build <=', helper)

    def test_transaction_owns_grants_and_direct_writes_keep_the_journal(self):
        transaction = (HELPERS / 'PatchTransaction.swift').read_text(encoding='utf-8')
        body = transaction.split('private static func withResolvedContainers<T>(')[1]
        self.assertIn('retainAccess: false', body)
        self.assertIn('handles.append(try WorseQueryHelper.acquireAccess(for: path))', body)
        self.assertIn('defer { handles.reversed().forEach { sandbox_extension_release_handle($0) } }', body)
        self.assertLess(body.index('acquireAccess(for: path)'), body.index('try operation(roots)'))
        coordinator = (HELPERS / 'StorageEngineCoordinator.swift').read_text(encoding='utf-8')
        direct = coordinator.split('func applyPatchProject(')[1].split('guard isAirLiftActive')[0]
        self.assertIn('DevicePatchService.apply(project: project)', direct)
        self.assertNotIn('UserDefaults.standard.set(true', direct)

    def test_native_query_constants_and_symlink_lifecycle(self):
        native = (ROOT / 'ThreeOneOSFive/exploit/worse_query.m').read_text(encoding='utf-8')
        for call in ['query_set_class(query, 7)', 'query_set_part(query, 3)',
                     '0x0000000800000000ULL', '0x0000008000000000ULL',
                     'copy_sandbox_token(result)', 'consume_extension(token)',
                     '@synchronized (query_lock())', 'errno != EACCES && errno != EPERM']:
            self.assertIn(call, native)
        self.assertIn('query_free(query);\n        dlclose(mgr);\n        clean_symlink(group);\n        return -4;', native)

    def test_missing_group_and_no_vpn_do_not_reach_native_timeout(self):
        client = (HELPERS / 'AirTrafficProtocolClient.swift').read_text(encoding='utf-8')
        guard = client.split('private func verifyTransportAndPairing()')[1].split('private func activePairingPath()')[0]
        self.assertIn('throw WorseQueryError.appGroupUnavailable', guard)
        tunnel = (HELPERS / 'AirLiftTunnelManager.swift').read_text(encoding='utf-8')
        self.assertNotIn('hasAnyTunnelInterface()', tunnel)
        self.assertIn('guard Self.hasTunnelRoute(to: host) else { continue }', tunnel)
        self.assertNotIn('else if rsdProbe.reachable', tunnel)

    def test_ipa_keeps_requested_entitlements_and_rejects_missing_native_code(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        stage = workflow.index('- name: Preserve App Group entitlements for external signing')
        self.assertLess(stage, workflow.index('- name: Package IPA'))
        self.assertIn('--entitlements ThreeOneOSFive/ThreeOneOSFive.entitlements', workflow[stage:])
        self.assertIn('codesign -d --entitlements :-', workflow[stage:])
        for symbol in ['_worse_query', '_worse_query_release', '_AstraSignedApplicationGroups']:
            self.assertIn('grep -Fx "' + symbol + '"', workflow)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'requires macOS Swift compiler')
    def test_actual_swift_helper_and_routing(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            policy = folder / 'SupportPolicy.swift'
            subprocess.run([sys.executable, str(ROOT / 'Tests/extract_support_policy.py'),
                            str(HELPERS / 'KernelExploit.swift'), str(policy)], check=True)
            # Extract the complete production enum, not a reimplementation.
            merger = (HELPERS / 'ContainerBrowserLogic.swift').read_text(encoding='utf-8')
            canonical = folder / 'ContainerDiscoveryMerger.swift'
            canonical.write_text(merger.split('enum ContainerAccessPolicy {')[0], encoding='utf-8')
            binary = folder / 'helper-check'
            subprocess.run(['swiftc', str(policy), str(canonical),
                            str(HELPERS / 'WorseQueryHelper.swift'),
                            str(ROOT / 'Tests/WorseQueryHelperSelfCheck.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
            binary = folder / 'routing-check'
            subprocess.run(['swiftc', str(policy), str(ROOT / 'Tests/IOSCompatibilitySelfCheck.swift'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
