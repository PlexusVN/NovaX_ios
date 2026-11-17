"""Run the production catalog task lifecycle against suspended worker boundaries."""
from pathlib import Path
import tempfile
import subprocess
import unittest
from check_airlift_pairing_finish import extract_function
from test_arbitrary_package_targets import swift_commands

ROOT = Path(__file__).resolve().parents[1]


class FeaturePatchProgress(unittest.TestCase):
    def test_actual_operation_progress_cancellation_and_worker_lifetime(self):
        compiler, translate, execute = swift_commands(self)
        feature = (ROOT/'ThreeOneOSFive/helpers/FeaturePatchService.swift').read_text(encoding='utf-8')
        model = feature[feature.index('// BEGIN CATALOG OPERATION PROGRESS'):
                        feature.index('// END CATALOG OPERATION PROGRESS')]
        actual = 'import Foundation\n' + model + '''
struct PatchItem { let downloadIdentity:String }
enum FeaturePatchError:Error { case operationInProgress }
@MainActor final class FeaturePatchService {
    var patchOperation:FeaturePatchOperationProgress?
    var cancelCatalogOperation:(()->Void)?
'''
        for signature in ['func cancelPatchOperation(', 'private func updatePatchOperation(',
                          'private func withCatalogOperation<T:']:
            actual += extract_function(feature, signature).replace('private func ', 'func ') + '\n'
        actual += '}\n'
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'ActualFeatureProgress.swift'
            source.write_text(actual, encoding='utf-8')
            binary = Path(directory)/'feature-progress-check'
            subprocess.run(compiler+['-swift-version','5',translate(source),
                translate(ROOT/'Tests/FeaturePatchProgressSelfCheck.swift'),'-o',translate(binary)],check=True)
            subprocess.run(execute(binary),check=True)

    def test_ui_reports_real_phase_and_keeps_busy_until_completion(self):
        ui=(ROOT/'ThreeOneOSFive/views/FeaturesView.swift').read_text(encoding='utf-8')
        card=ui.split('struct PatchCardView: View {',1)[1]
        self.assertIn('operationTask = Task { @MainActor in',card)
        self.assertNotIn('Task.detached',card)
        self.assertIn('defer { isSubmitting = false; operationTask = nil }',card)
        self.assertIn('service.cancelPatchOperation(identity: patch.downloadIdentity)',card)
        self.assertIn('Text(progress.message)',card)
        self.assertIn('.disabled(service.patchOperation != nil)',card)
        self.assertIn('progress.canCancel || progress.cancellationPending',card)


if __name__=='__main__':
    unittest.main()
