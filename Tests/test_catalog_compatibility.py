"""Run the production catalog decoder/access policy with the existing server format."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CatalogCompatibility(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'requires Swift compiler')
    def test_actual_catalog_decoder_and_tier_policy(self):
        source = (ROOT / 'ThreeOneOSFive/helpers/FeaturePatchService.swift').read_text(encoding='utf-8')
        models = source[:source.index('struct PatchSyncResponse:')]
        models = models.replace('import UIKit', '').replace('import CryptoKit', '').replace('import Combine', '')
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            production = directory / 'Catalog.swift'
            production.write_text(models, encoding='utf-8')
            binary = directory / 'catalog-compatibility'
            subprocess.run(['swiftc', str(production), str(ROOT / 'Tests/CatalogCompatibilitySelfCheck.swift'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
