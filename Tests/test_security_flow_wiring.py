"""Source wiring guards complement (do not replace) macOS/iPhone execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
def source(name): return (ROOT / 'ThreeOneOSFive' / name).read_text(encoding='utf-8')

class SecurityFlowWiringTests(unittest.TestCase):
    def test_no_fabricated_release_and_explicit_network_only_policy(self):
        text = source('helpers/AntiTamper.swift')
        self.assertNotIn('#if os(iOS)', text)
        self.assertNotIn('b906fe5c-c908-40e1-b2a9-464d00196957', text)
        self.assertIn('current().map { inspect($0,verifier:.shared) }', text)
        self.assertIn('Task.detached(priority:.utility) { inspect() }', text)
        self.assertIn('DeviceEnvironmentInspector.commitMeasurement()', text)
        self.assertNotIn('guard Bundle.main.url(forResource:', text)
        self.assertIn('static let localIntegrityEnforced = false', source('helpers/AppSecurityConfiguration.swift'))
        self.assertIn('guard enforcesIntegrity else', text)
        self.assertIn('acceptedResult=nil; allowed=true; blocked=false; failureDetail=nil', text)
        text = source('helpers/DeviceEnvironmentInspector.swift')
        probes = text.split('static func inspect()')[1]
        self.assertNotIn('runtimeSnapshot()', probes)
        self.assertNotIn('signalMask: 0)', probes)
        self.assertEqual(probes.count('return .unverified'), 2)

    def test_api_trust_requires_both_system_trust_and_pin(self):
        text = source('views/SecurityUtils.swift').split('enum AstraServerTrust {')[1].split('final class CertPinningDelegate')[0]
        self.assertIn('guard SecTrustEvaluateWithError', text)
        self.assertIn('if leafCertificatePins.contains(pin) { return true }', text)
        self.assertTrue(text.rstrip().endswith('return false\n    }\n}'))
        self.assertIn('AppSecurityConfiguration.tlsCertificatePins', text)

    def test_release_snapshot_and_pinned_transport_errors(self):
        text = source('helpers/ProtectedDownloadService.swift')
        lease = text.split('private func ensureReleaseLease()')[1].split('func reportIntegrityFailure')[0]
        self.assertIn('AppIntegrityRuntime.shared.acceptedResult', lease)
        self.assertIn('guard AppSecurityConfiguration.localIntegrityEnforced else { return }', lease)
        self.assertNotIn('AntiTamper.checkAtLaunch()', lease)
        post = text.split('    private func post(')[1].split('    private func dictionary(')[0]
        self.assertLess(post.index('SecureAPIClient.shared.data(for: request)'), post.index('ProtectedDownloadError.fromPinnedPayload'))
        self.assertIn('RequestProofService.shared.signRequest', post)
        self.assertNotIn('ServerSignatureVerifier', post)
        self.assertIn('X-Astra-Response-Mode', post)
        errors = post.split('guard (200..<300).contains(response.statusCode)')[1].split('let payload = data')[0]
        self.assertIn('data.count <= 256 * 1024', errors)
        self.assertIn('(object["session_revoked"] as? Bool) == true', errors)

    def test_same_key_bootstrap_and_authorized_recovery_share_canonical_contract(self):
        text = source('helpers/ProtectedDownloadService.swift')
        active = text.split('    private func ensureSession(')[1].split('    private func recordAccessFailure(')[0]
        self.assertNotIn('/api/v2/device/resume', text)
        self.assertNotIn('identity_resume_unavailable', text)
        bootstrap = active.split('    private func bootstrapEnrollment(')[1]
        self.assertNotIn('recoverInstallation(', bootstrap)
        self.assertIn('ProtectedRecoveryChallenge.permitsAttempt(after: error)', active)
        self.assertLess(active.index('pendingRecoveryCandidate'), active.index('ensureCurrentSession(auth: auth)'))
        self.assertIn('prepareInitialEnrollment(installationID: installID)', bootstrap)
        self.assertLess(bootstrap.index('finishInitialEnrollmentPreparation'), bootstrap.index('post("/api/v2/device/enroll"'))
        self.assertIn('canonical_enrollment', active)
        self.assertIn('existingResumeMaterial()', active)
        self.assertIn('acceptCanonicalEnrollment(', active)
        recovery = text.split('    private func recoverInstallation(')[1].split('    private func ensureCurrentSession(')[0]
        self.assertIn('guard challenge.recoveryAuthorized else', recovery)
        self.assertIn('"canonical_enrollment": true', recovery)
        self.assertIn('enrolled["public_key_fingerprint"]', recovery)
        self.assertIn('enrolled["license_binding"]', recovery)

    def test_airlift_cannot_claim_a_restore_without_writing_originals(self):
        text = source('helpers/FeaturePatchService.swift')
        branch = text.split('private func restorePatchInOperation(')[1].split('func isPatchApplied(')[0]
        self.assertIn('PatchEngineApplicationStore.requireDirectRestore', branch)
        self.assertIn('throw PatchEngineStateError.restoreProviderUnavailable', branch)
        self.assertLess(branch.index('requireDirectRestore'), branch.index('DevicePatchService.restore'))
        self.assertLess(branch.index('DevicePatchService.restore'), branch.index('catalogApplications.clear'))

    def test_catalog_state_uses_id_variant_not_editable_name(self):
        text = source('helpers/FeaturePatchService.swift')
        identity = text.split('private func patchStorageSlug(')[1].split('private func cachePath')[0]
        self.assertIn('catalog_\\(patch.id)_', identity)
        self.assertIn('migrateIdentity(from: legacy, to: stable)', identity)
        self.assertIn('for previous in patches { _ = patchStorageSlug(previous) }', text)
        registry = source('helpers/PatchTransaction.swift').split('enum PatchTransaction {')[0]
        self.assertIn('clear(legacy)', registry)

    def test_network_only_distribution_needs_no_release_signing_secret(self):
        flow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        self.assertNotIn('secrets.ASTRA_RELEASE_SIGNING_KEY', flow)
        self.assertNotIn('ReleaseTools/seal_release.py', flow)
        self.assertIn('path: build/Astra.ipa', flow)

if __name__ == '__main__': unittest.main()
