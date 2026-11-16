"""Compile the unchanged production catalog filename policy in an offline harness."""
from pathlib import Path
import sys
from check_airlift_pairing_finish import extract_function

root = Path(__file__).resolve().parents[1]
source = (root/'ThreeOneOSFive/helpers/FeaturePatchService.swift').read_text(encoding='utf-8')
body = extract_function(source, 'static func catalogStorageIdentity(')
Path(sys.argv[1]).write_text('import Foundation\nimport CryptoKit\nenum CatalogIdentityCheck {\n'
    + body + '\n}\n', encoding='utf-8')
