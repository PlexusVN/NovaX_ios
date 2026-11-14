"""Execute actual engine provenance, strict restore and desired-OFF policy.

Production methods/registry are extracted intact. Native restoration is a
controlled boundary; temporary files prove failed OFF attempts retain existing
target, package, journal, backup and provenance bytes. Direct transaction I/O is
covered separately by DirectTransactionProvenanceSelfCheck.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]


class EngineTransactions(unittest.TestCase):
    def test_actual_coordinator_and_provenance(self):
        native = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if native:
            compiler, translate = [native], str
            execute = lambda binary: [str(binary)]
        elif os.name == 'nt' and distro:
            native = subprocess.check_output(['wsl', '-d', distro, '--', 'bash', '-lc', 'command -v swiftc'], text=True).strip()
            compiler = ['wsl', '-d', distro, '--', native]
            def translate(value):
                value = str(Path(value).resolve()).replace('\\', '/')
                return '/mnt/' + value[0].lower() + value[2:]
            execute = lambda binary: ['wsl', '-d', distro, '--', translate(binary)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')
        transaction = (ROOT / 'ThreeOneOSFive/helpers/PatchTransaction.swift').read_text(encoding='utf-8')
        begin = transaction.index('enum PatchApplicationState:')
        end = transaction.index('enum PatchTransaction {')
        source = 'import Foundation\n' + transaction[begin:end]
        source += transaction[transaction.index('struct PatchTransactionReceipt:'):transaction.index('enum PatchTargetChangeKind:')]
        models = (ROOT / 'ThreeOneOSFive/helpers/PatchProjectModels.swift').read_text(encoding='utf-8')
        source += models[:models.index('extension PatchPackageError: LocalizedError')]
        source += models[models.index('enum PatchPackageLimits {'):models.index('enum PatchPathValidator {')]
        source += models[models.index('enum PatchPathValidator {'):]
        source += (ROOT / 'Tests/Fixtures/EngineTransactionHarness.swift').read_text(encoding='utf-8')
        coordinator = (ROOT / 'ThreeOneOSFive/helpers/StorageEngineCoordinator.swift').read_text(encoding='utf-8')
        source += '\n@MainActor final class StorageEngineCoordinator {\n'
        source += '''
let objectWillChange=FixturePublisher()
let isAirTrafficEngineLinked=true
static let shared=StorageEngineCoordinator()
var isAirLiftActive:Bool { ExploitSupportPolicy.currentStorageMode == .airLift }
func applicationStore() throws -> PatchEngineApplicationStore { Fixture.store }
'''
        for signature in ['private func airLiftAppliedKey(', 'func isProjectAppliedThroughAirLift(',
                          'func projectApplicationState(', 'func applyPatchProject(', 'func applyPatchProjectInOperation(']:
            source += extract_function(coordinator, signature) + '\n'
        source += '}\n'
        feature = (ROOT / 'ThreeOneOSFive/helpers/FeaturePatchService.swift').read_text(encoding='utf-8')
        source += '''
@MainActor final class FeaturePatchService {
let defaults=UserDefaults.standard
var catalogApplications:CatalogPatchApplicationRegistry { CatalogPatchApplicationRegistry(defaults:defaults) }
var patchProjectsDir:URL { Fixture.root }
var applicationRevision=0
func patchStorageSlug(_ patch:PatchItem)->String { patch.identity }
func attemptEnable(_ patch:PatchItem,newProjectID:UUID) throws {
    try requirePatchEnableAllowed(patch)
    catalogApplications.associate(newProjectID,with:patchStorageSlug(patch))
    Fixture.enableAssociations += 1
}
'''
        for signature in ['func restorePatch(', 'func disablePatch(', 'private func patchDisableBinding(',
                          'func isPatchDisabledPendingRestore(', 'func isPatchToggleOn(',
                          'private func requirePatchEnableAllowed(',
                          'private func restorePatchInOperation(', 'func patchApplicationState(']:
            source += extract_function(feature, signature) + '\n'
        source += '}\n'
        apply = extract_function(feature, 'private func applyPatchInOperation(')
        self.assertLess(apply.index('try requirePatchEnableAllowed(patch)'), apply.index('downloadPatch('))
        self.assertLess(apply.index('try requirePatchEnableAllowed(patch)'), apply.index('catalogApplications.associate('))
        with tempfile.TemporaryDirectory() as directory:
            actual = Path(directory) / 'ActualCoordinator.swift'
            actual.write_text(source, encoding='utf-8')
            binary = Path(directory) / 'engine-transaction-check'
            subprocess.run(compiler + ['-swift-version', '5', translate(actual),
                translate(ROOT / 'Tests/EngineTransactionSelfCheck.swift'), '-o', translate(binary)], check=True)
            subprocess.run(execute(binary), check=True)


if __name__ == '__main__':
    unittest.main()
