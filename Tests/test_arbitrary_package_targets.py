"""Execute production package policy and preparation without native device I/O."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'ThreeOneOSFive/helpers'


def swift_commands(test):
    compiler = shutil.which('swiftc')
    distribution = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
    if compiler:
        return [compiler], str, lambda binary: [str(binary)]
    if os.name == 'nt' and distribution:
        compiler = subprocess.check_output(['wsl', '-d', distribution, '--', 'bash', '-lc',
            'command -v swiftc'], text=True).strip()
        def translate(value):
            value = str(Path(value).resolve()).replace('\\', '/')
            return '/mnt/' + value[0].lower() + value[2:]
        return ['wsl', '-d', distribution, '--', compiler], translate, lambda binary: [
            'wsl', '-d', distribution, '--', translate(binary)]
    test.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')


class ArbitraryPackageTargets(unittest.TestCase):
    def test_production_policy_matches_server_generated_matrix(self):
        compiler, translate, execute = swift_commands(self)
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'target-policy-check'
            subprocess.run(compiler + ['-swift-version', '5',
                translate(HELPERS/'AppSecurityConfiguration.swift'),
                translate(ROOT/'Tests/ProtectedTargetPolicySelfCheck.swift'),
                '-o', translate(binary)], check=True)
            subprocess.run(execute(binary) + [translate(ROOT/'Tests/Fixtures/package_target_policy.json')], check=True)

    def test_fixture_matrix_still_matches_current_server_policy(self):
        server = ROOT.parents[1] / 'production-server/AUTH/server/patch_targets.js'
        if not server.is_file() or not shutil.which('node'):
            self.skipTest('server sibling source and Node are required for cross-repository parity')
        fixture = ROOT/'Tests/Fixtures/package_target_policy.json'
        script = """const fs=require('node:fs');const t=require(process.argv[1]);
const f=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
for(const c of f.cases){if(t.bundleIDForVariant(c.variant)!==c.expectedBundleID
|| t.isArtifactTarget(c.variant,c.kind)!==c.expectedAllowed)throw Error('Target policy fixture drift');}
process.stdout.write(String(f.cases.length));"""
        result = subprocess.check_output(['node', '-e', script, str(server), str(fixture)], text=True)
        self.assertEqual(int(result), len(json.loads(fixture.read_text(encoding='utf-8'))['cases']))

    def test_actual_preparation_uses_authenticated_catalog_and_rejects_stale_results(self):
        compiler, translate, execute = swift_commands(self)
        # Only Combine publication and device/native boundaries are replaced.
        # All preparation/session state transitions execute the production body.
        code = '''import Foundation
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
enum WorseQueryError: Error { case preparationRequired, invalidPath(String), containerDiscoveryFailed(String) }
final class ContainerScanProgress {
    enum Phase { case idle, scanning, interrupted }
    struct Snapshot { var phase = Phase.idle }
    static let shared = ContainerScanProgress()
    var snapshot = Snapshot()
    func dismiss() {}
    func requestCancellation() { snapshot.phase = .interrupted }
}
enum PatchPathValidator {
    static func canonicalBundleIdentifier(_ value: String) throws -> String {
        guard AppSecurityConfiguration.isValidProtectedBundleID(value) else { throw WorseQueryError.invalidPath(value) }
        return value
    }
}
enum ContainerStore {
    static func isApplicationContainerPath(_ path: String) -> Bool { path.hasPrefix("/fixture/") }
    static func prepareIOS27Access(bundleIDs: [String], forceScan: Bool) throws -> [String: String] {
        fatalError("a self-check must inject its native boundary")
    }
}
'''
        code += (HELPERS/'IOS27ContainerPreparation.swift').read_text(encoding='utf-8').replace('import Combine', '')
        with tempfile.TemporaryDirectory() as directory:
            actual = Path(directory)/'Preparation.swift'
            actual.write_text(code, encoding='utf-8')
            binary = Path(directory)/'preparation-check'
            subprocess.run(compiler+['-swift-version','5',translate(HELPERS/'AppSecurityConfiguration.swift'),
                translate(actual),translate(ROOT/'Tests/ArbitraryTargetPreparationSelfCheck.swift'),
                '-o',translate(binary)],check=True)
            subprocess.run(execute(binary),check=True)


if __name__ == '__main__':
    unittest.main()
