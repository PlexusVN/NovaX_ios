"""Offline configuration checks. No credentials, production API or database reads."""
from pathlib import Path
import re,hashlib,base64
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'ThreeOneOSFive/helpers/AppSecurityConfiguration.swift').read_text(encoding='utf-8')
assert 'https://zynox.click' in text and 'astra-rsa-2026-01' in text
key=re.search(r'signingPublicKeyPKCS1Base64 = "([^"]+)"',text)[1]
assert hashlib.sha256(base64.b64decode(key)).hexdigest()=='b7ea531c327235ad0463df5d9e5bc8bcc13f34230d9cee9beba452c296294cb8'
assert '7NfgIVpP+fdJQCMiloG7ljIWxP5OZEiAGfsc6+jgcQA=' in text
for path in (ROOT/'ThreeOneOSFive').rglob('*.swift'):
    data=path.read_text(encoding='utf-8')
    assert all(term not in data for term in ['QAConfiguration','trycloudflare.com','astra-qa-20261103','qa_patch_applied_']),str(path)
policy=(ROOT/'ThreeOneOSFive/helpers/SecureAPIClient.swift').read_text(encoding='utf-8')
assert '"/api/v2/security/integrity"' in policy
print('Production origin, signer, pin, persistent namespaces and integrity endpoint validated offline.')

assert '"/api/v2/security/integrity-v2"' in policy
