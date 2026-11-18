"""Run the actual scoped Viet99 adapter with isolated daemon/filesystem boundaries."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Viet99BQCoreTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang'), 'requires macOS Foundation/ARC')
    def test_production_adapter_strategy_order_scope_and_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'viet99-bq-check'
            subprocess.run(['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                str(ROOT / 'Tests/Viet99BQCoreSelfCheck.m'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

    def test_preparation_keeps_real_container_evidence(self):
        helper = (ROOT / 'ThreeOneOSFive/helpers/WorseQueryHelper.swift').read_text(encoding='utf-8')
        self.assertIn('AstraBQAcquireAccess(effectiveTarget, group)', helper)
        preparation = (ROOT / 'ThreeOneOSFive/helpers/IOS27ContainerPreparation.swift').read_text(encoding='utf-8')
        self.assertIn('validatedRoots(roots, requested: targets)', preparation)
        self.assertLess(preparation.index('validatedRoots(roots, requested: targets)'), preparation.index('state = .ready'))
        # Compatibility diagnostics belong to the runtime report. Reusing the
        # access engine does not require adopting the donor's preparation UI.
        self.assertIn('if let note = ExploitSupportPolicy.currentAccessCompatibilityNote { reports.append(note) }', helper)


if __name__ == '__main__':
    unittest.main()
