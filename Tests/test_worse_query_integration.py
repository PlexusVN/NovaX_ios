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
from check_airlift_pairing_finish import extract_function

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
        self.assertIn('ContainerStore.resolveAppContainerForPatch(bundleID: bundleID)', body)
        self.assertIn('handles.append(try WorseQueryHelper.acquireAccess(for: path))', body)
        self.assertIn('defer { handles.reversed().forEach { sandbox_extension_release_handle($0) } }', body)
        self.assertLess(body.index('acquireAccess(for: path)'), body.index('try operation(roots)'))
        coordinator = (HELPERS / 'StorageEngineCoordinator.swift').read_text(encoding='utf-8')
        direct = coordinator.split('func applyPatchProject(')[1].split('guard isAirLiftActive')[0]
        self.assertIn('DevicePatchService.apply(project: project, preparedContainers: roots)', direct)
        self.assertNotIn('UserDefaults.standard.set(true', direct)

    def test_native_query_constants_and_symlink_lifecycle(self):
        native = (ROOT / 'ThreeOneOSFive/exploit/worse_query.m').read_text(encoding='utf-8')
        for call in ['query_set_class(query, 7)', 'query_set_part(query, 3)',
                     '0x0000000800000000ULL', '0x0000008000000000ULL',
                     'copy_sandbox_token(result)', 'consume_extension(resources->token)',
                     '@synchronized (query_lock())', 'errno != EACCES && errno != EPERM']:
            self.assertIn(call, native)
        self.assertIn('@finally', native)
        self.assertIn('resources.free_query(resources.query)', native)
        self.assertIn('if (resources.changed_caches) clean_symlink(group)', native)

    def test_missing_group_and_no_vpn_do_not_reach_native_timeout(self):
        client = (HELPERS / 'AirTrafficProtocolClient.swift').read_text(encoding='utf-8')
        guard = client.split('private func verifyTransportAndPairing()')[1].split('private func activePairingPath()')[0]
        self.assertIn('try requireSelectedProvider()', guard)
        provider_guard = client.split('private func requireSelectedProvider()')[1].split('private func verifyTransportAndPairing()')[0]
        self.assertIn('currentAccessProvider == .airLift', provider_guard)
        tunnel = (HELPERS / 'AirLiftTunnelManager.swift').read_text(encoding='utf-8')
        self.assertNotIn('hasAnyTunnelInterface()', tunnel)
        self.assertIn('guard Self.hasTunnelRoute(to: host) else { continue }', tunnel)
        self.assertNotIn('else if rsdProbe.reachable', tunnel)

    def test_discovery_has_no_artificial_inode_cutoff_or_parent_application_grant(self):
        helper = (HELPERS / 'WorseQueryHelper.swift').read_text(encoding='utf-8')
        self.assertNotIn('500_000', helper)
        self.assertIn('enumerationUpperBound(probeInode: UInt64(st.st_ino))', helper)
        store = (HELPERS / 'ContainerStore.swift').read_text(encoding='utf-8')
        scan = extract_function(store, 'static func prepareIOS27Access(')
        self.assertIn('while first <= maximum', scan)
        self.assertIn('first = last + 1', scan)
        self.assertIn('WorseQueryHelper.acquireAccess(for: clean)', scan)
        self.assertNotIn('grantContainerAccess(appDataRoot)', scan)

    def test_ios27_launch_does_not_probe_target_or_consume_tokens(self):
        app = (ROOT / 'ThreeOneOSFive/App.swift').read_text(encoding='utf-8')
        self.assertIn('value: ios27Preparation.didContinue', app)
        self.assertNotIn('value: gatekeeper.canBypassGatekeeper', app)
        probe = extract_function(app, 'func checkDirectDirectoryAccessAsync(')
        self.assertLess(probe.index('guard ExploitSupportPolicy.currentAccessProvider == .legacy3105'), probe.index('DispatchQueue.global'))
        kernel = (HELPERS / 'KernelExploit.swift').read_text(encoding='utf-8')
        probe = extract_function(kernel, 'static func hasSandboxAccess(')
        self.assertLess(probe.index('currentAccessProvider == .legacy3105'), probe.index('sandbox_access_is_active()'))
        helper = (HELPERS / 'WorseQueryHelper.swift').read_text(encoding='utf-8')
        group = extract_function(helper, 'public static func resolveActiveAppGroup(')
        self.assertIn('worse_query_group_path(group)', group)
        self.assertNotIn('containerURL(forSecurityApplicationGroupIdentifier:', group)

    def test_scan_overlay_reports_actual_discovery_and_keeps_security_overlays_above_it(self):
        app = (ROOT / 'ThreeOneOSFive/App.swift').read_text(encoding='utf-8')
        self.assertIn('requiresWorseQueryPreparation && containerScan.isPresented', app)
        self.assertIn('ContainerScanProgressView(progress: containerScan)', app)
        self.assertIn('.zIndex(2.5)', app)
        self.assertIn('.zIndex(100)', app)
        store = (HELPERS / 'ContainerStore.swift').read_text(encoding='utf-8')
        scan = extract_function(store, 'static func prepareIOS27Access(')
        self.assertIn('ContainerScanProgress.shared.track(bundleID: targets.sorted().joined', scan)
        self.assertIn('ContainerScanProgress.shared.checkCancellation(sessionID)', scan)
        self.assertIn('scanned: last, total: maximum, candidates: candidates, grants: grants', scan)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'requires macOS Swift/Combine')
    def test_actual_scan_monitor_lifecycle_cancellation_and_restart(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'scan-monitor-check'
            subprocess.run(['swiftc', str(HELPERS / 'ContainerScanProgress.swift'),
                            str(ROOT / 'Tests/ContainerScanProgressSelfCheck.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang'), 'requires macOS Objective-C compiler')
    def test_native_production_query_and_inode_enumerator(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ['PathLeakSelfCheck', 'WorseQueryNativeSelfCheck', 'BadQueryEnumerationSelfCheck', 'MCMPathLookupSelfCheck']:
                binary = Path(folder) / name
                subprocess.run(['clang', '-fno-objc-arc' if name == 'BadQueryEnumerationSelfCheck' else '-fobjc-arc', '-framework', 'Foundation',
                                str(ROOT / 'Tests' / (name + '.m')), '-o', str(binary)], check=True)
                subprocess.run([str(binary)], check=True)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'requires macOS Swift compiler')
    def test_actual_container_discovery_and_background_preparation(self):
        store = (HELPERS / 'ContainerStore.swift').read_text(encoding='utf-8')
        helper = (HELPERS / 'WorseQueryHelper.swift').read_text(encoding='utf-8')
        validator = (HELPERS / 'PatchProjectModels.swift').read_text(encoding='utf-8')
        merger = (HELPERS / 'ContainerBrowserLogic.swift').read_text(encoding='utf-8')
        policy = (HELPERS / 'KernelExploit.swift').read_text(encoding='utf-8')
        policy = policy.split('enum ExploitSupportPolicy {', 1)[1].split('// MARK: - Sandbox & Filesystem Access Helpers', 1)[0]
        code = helper.split('public final class WorseQueryHelper')[0] + '\nenum ExploitSupportPolicy {' + policy
        code += merger.split('enum ContainerAccessPolicy {')[0].replace('import Foundation', '')
        code += '\nenum PatchPathValidator {\n' + extract_function(validator, 'static func canonicalBundleIdentifier(') + '\n}\n'
        code += store.split('// BEGIN CONTAINER IDENTITY EVIDENCE', 1)[1].split('// END CONTAINER IDENTITY EVIDENCE', 1)[0]
        code += '\nenum ContainerStore {\nstatic let discoveryLock = NSLock()\nprivate static var worseQueryResume: [String: (next: UInt64, maximum: UInt64)] = [:]\nstatic let appDataRoot = "/var/mobile/Containers/Data/Application"\n'
        for signature in ['static func prepareIOS27Access(', 'static func resolveAppContainerForPatch(',
                          'static func isApplicationContainerPath(', 'static func metadataPath(', 'static func readWorseQueryIdentity(']:
            code += extract_function(store, signature).replace('ContainerScanProgress.shared', 'DiscoveryFixture.progress') + '\n'
        code += 'static func resolveAppContainerPath(bundleID: String, allowMetadataScan: Bool = true, retainAccess: Bool = true) -> String? { DiscoveryFixture.legacyCalls += 1; return nil }\n}\n'
        code = code.replace('static func resolveAppContainerPath(bundleID:', 'static func resolveContainerWithWorseQuery(bundleID: String) throws -> String { preconditionFailure("legacy scan reached on iOS27") }\nstatic func resolveAppContainerPath(bundleID:')
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'Discovery.swift'; source.write_text(code, encoding='utf-8')
            binary = Path(folder) / 'discovery-check'
            subprocess.run(['swiftc', str(source), str(HELPERS / 'ContainerScanProgress.swift'),
                            str(HELPERS / 'IOS27ContainerPreparation.swift'), str(ROOT / 'Tests/ContainerDiscoverySelfCheck.swift'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'requires macOS Swift')
    def test_actual_direct_executor_and_revocation(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'direct-executor-check'
            subprocess.run(['swiftc', str(HELPERS / 'DirectPatchExecutor.swift'),
                            str(ROOT / 'Tests/DirectPatchExecutorSelfCheck.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    def test_ios27_gate_precedes_content_and_legacy_resolvers(self):
        app = (ROOT / 'ThreeOneOSFive/App.swift').read_text(encoding='utf-8')
        self.assertLess(app.index('IOS27PreparationView(preparation:'), app.index('ContentView()'))
        self.assertIn('requiresWorseQueryPreparation && !ios27Preparation.didContinue', app)
        store = (HELPERS / 'ContainerStore.swift').read_text(encoding='utf-8')
        resolver = extract_function(store, 'static func resolveAppContainerForPatch(')
        self.assertLess(resolver.index('IOS27ContainerSession.path'), resolver.index('resolveAppContainerPath('))
        scan = extract_function(store, 'static func prepareIOS27Access(')
        self.assertNotIn('MCMActivateContainerPath(', scan)
        self.assertIn('MCMContainerPathForWorseQuery(2, bundleID, false', scan)
        self.assertIn('containerPathForBundleID(bundleID)', scan)
        self.assertLess(scan.index('MCMContainerPathForWorseQuery('), scan.index('enumeratePaths('))
        self.assertIn('evidence.identifier == nil || evidence.identifier == boundBundleID', scan)
        self.assertIn('source: "mcm_bundle_id"', scan)
        self.assertIn('chunkSize: UInt64 = 50_000', scan)
        self.assertIn('checkpoint(sessionID', scan)
        self.assertIn('currentAccessProvider == .legacy3105', store.split('private static var shouldUseBadQuery: Bool')[1].split('private static let')[0])
        native_mcm = (ROOT / 'ThreeOneOSFive/exploit/mcm_bridge.m').read_text(encoding='utf-8')
        activate = extract_function(native_mcm, 'NSString *MCMActivateContainerPath(')
        self.assertLess(activate.index('!AstraUses3105ContainerAccess()'), activate.index('MCMActiveLeases()'))
        service = (HELPERS / 'FeaturePatchService.swift').read_text(encoding='utf-8')
        self.assertGreaterEqual(service.count('try await DirectPatchExecutor.run(validation:'), 3)

    def test_ipa_keeps_requested_entitlements_and_rejects_missing_native_code(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        stage = workflow.index('- name: Preserve App Group entitlements for external signing')
        self.assertLess(stage, workflow.index('- name: Package IPA'))
        self.assertIn('--entitlements ThreeOneOSFive/ThreeOneOSFive.entitlements', workflow[stage:])
        self.assertIn('codesign -d --entitlements :-', workflow[stage:])
        for symbol in ['_worse_query', '_worse_query_release', '_AstraSignedApplicationGroups']:
            self.assertIn('nm -j "$APP_NAME/$EXECUTABLE" | grep -Fx "' + symbol + '"', workflow)

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
            subprocess.run(['swiftc', str(policy), str(ROOT / 'Tests/IOSCompatibilitySelfCheck.swift'), str(ROOT / 'Tests/Upstream3105SupportPolicy.swift'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
