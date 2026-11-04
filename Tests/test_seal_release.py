import importlib.util
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

TOOLS = Path(__file__).parents[1] / 'ReleaseTools'
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location('seal_release', TOOLS / 'seal_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseRegistryTests(unittest.TestCase):
    @staticmethod
    def document(identity):
        return {'body': {'release_id': identity, 'build': '12'}}

    def test_rebuild_same_build_keeps_previously_distributed_release(self):
        old, new = self.document('old'), self.document('new')
        self.assertEqual(module.merge_registry([old], new), [old, new])

    def test_reseal_same_release_is_idempotent(self):
        doc = self.document('same')
        self.assertEqual(module.merge_registry([doc], doc), [doc])

    def test_full_registry_requires_explicit_retirement(self):
        old = [self.document(str(i)) for i in range(20)]
        with self.assertRaisesRegex(ValueError, 'registry_full'):
            module.merge_registry(old, self.document('new'))
        result = module.merge_registry(old, self.document('new'), ['0'])
        self.assertEqual(len(result), 20)
        self.assertEqual(result[-1], self.document('new'))

    def test_unknown_retirement_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'retired_release_unknown'):
            module.merge_registry([], self.document('new'), ['unknown'])


@unittest.skipUnless(shutil.which('node'), 'Node is required for real release-signing checks')
class ReleaseSigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.key = self.root / 'fixture-private.pem'
        generated = subprocess.run(['node', '-e',
            "const c=require('node:crypto'),fs=require('node:fs');"
            "const k=c.generateKeyPairSync('rsa',{modulusLength:2048});"
            "fs.writeFileSync(process.argv[1],k.privateKey.export({type:'pkcs8',format:'pem'}));"
            "console.log(c.createHash('sha256').update(k.publicKey.export({type:'pkcs1',format:'der'})).digest('hex'));",
            str(self.key)], capture_output=True, check=True, text=True)
        self.fingerprint = generated.stdout.strip()
        self.ipa, self.registry = self.root / 'fixture.ipa', self.root / 'registry.json'

    def package(self, text):
        offset = 32 + 72 + 80
        header = struct.pack('<IiiIIIII', 0xfeedfacf, 0x100000c, 0, 2, 1, 152, 0, 0)
        segment = struct.pack('<II16sQQQQiiII', 0x19, 152, b'__TEXT',
                              0, offset + len(text), 0, offset + len(text), 5, 5, 1, 0)
        section = struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT',
                              offset, len(text), offset, 2, 0, 0, 0, 0, 0, 0)
        info = {'CFBundleIdentifier': 'com.apple.mobile.MobileHouseArrest',
                'CFBundleShortVersionString': '1.2.7', 'CFBundleVersion': '14',
                'CFBundleExecutable': 'Astra'}
        with zipfile.ZipFile(self.ipa, 'w') as output:
            output.writestr('Payload/Astra.app/Info.plist', plistlib.dumps(info))
            output.writestr('Payload/Astra.app/Astra', header + segment + section + text)

    def seal(self, fingerprint=None):
        return subprocess.run([sys.executable, str(TOOLS / 'seal_release.py'),
            '--ipa', str(self.ipa), '--private-key', str(self.key), '--registry', str(self.registry),
            '--expected-fingerprint', fingerprint or self.fingerprint], capture_output=True, text=True)

    def test_real_rsa_seal_reseal_and_rebuild_keep_both_releases(self):
        self.package(b'original-fixture-text')
        first = self.seal(); self.assertEqual(first.returncode, 0, first.stderr)
        original = json.loads(first.stdout)['releaseID']
        second = self.seal(); self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(json.loads(second.stdout)['releaseID'], original)
        self.package(b'rebuilt-fixture-text')
        rebuilt = self.seal(); self.assertEqual(rebuilt.returncode, 0, rebuilt.stderr)
        self.assertNotEqual(json.loads(rebuilt.stdout)['releaseID'], original)
        registry = json.loads(self.registry.read_text())
        self.assertEqual(len(registry['releases']), 2)
        with zipfile.ZipFile(self.ipa) as package:
            seal = package.read('Payload/Astra.app/Astra.release')
        self.assertEqual(hashlib.sha256(seal).hexdigest(), json.loads(rebuilt.stdout)['sealDigest'])
        document = json.loads(seal)
        canonical = json.dumps(document['body'], sort_keys=True, separators=(',', ':')).encode()
        verified = subprocess.run(['node', '-e',
            "const c=require('node:crypto'),fs=require('node:fs');"
            "let x='';process.stdin.on('data',b=>x+=b);process.stdin.on('end',()=>{"
            "const d=JSON.parse(x);process.exit(c.verify('RSA-SHA256',Buffer.from(d.message,'base64'),"
            "c.createPublicKey(fs.readFileSync(process.argv[1])),Buffer.from(d.signature,'base64'))?0:1)});",
            str(self.key)], input=json.dumps({'message': __import__('base64').b64encode(
                b'ASTRA-RELEASE-V1\n' + canonical).decode(), 'signature': document['signature']}),
            capture_output=True, text=True)
        self.assertEqual(verified.returncode, 0, verified.stderr)

    def test_wrong_signer_does_not_modify_unsigned_ipa(self):
        self.package(b'fixture-text')
        before = self.ipa.read_bytes()
        result = self.seal('0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.ipa.read_bytes(), before)
        self.assertFalse(self.registry.exists())


if __name__ == '__main__':
    unittest.main()
