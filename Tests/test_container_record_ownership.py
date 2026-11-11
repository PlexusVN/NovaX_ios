"""Exercise the actual Objective-C resolver with isolated initializer fixtures.

Reproduces build 29's over-release when LSApplicationRecord returns nil, without
loading any private framework or requiring a device. Does not test iOS access.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]


class ContainerRecordOwnershipTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang'),
                         'requires macOS Objective-C Foundation/ARC')
    def test_actual_resolver_initializer_failure_success_and_replacement(self):
        source = (ROOT / 'ThreeOneOSFive/helpers/AppIconHelper.m').read_text(encoding='utf-8')
        protocol = re.search(r'@protocol AstraApplicationRecordInitializing .*?@end', source, re.S)
        self.assertIsNotNone(protocol)
        resolver = extract_function(source, 'NSString * _Nullable containerPathForBundleID(')
        resolver = resolver.replace('@"LSApplicationProxy"', '@"AstraCrashFixtureProxy"')
        resolver = resolver.replace('@"LSApplicationRecord"', '@"AstraCrashFixtureRecord"')
        validation = extract_function(source, 'static NSString *applicationDataContainerPath(')
        fixture = (ROOT / 'Tests/ContainerRecordOwnershipSelfCheck.m').read_text(encoding='utf-8')
        prefix = '#import <Foundation/Foundation.h>\n#import <objc/message.h>\n'
        body = prefix + protocol.group() + '\n' + fixture.replace(
            '// ACTUAL PRODUCTION RESOLVER', validation + '\n' + resolver)
        env = dict(os.environ, NSZombieEnabled='YES')
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)

            def run(text, name):
                native = path / (name + '.m')
                binary = path / name
                native.write_text(text, encoding='utf-8')
                subprocess.run(['clang', '-fobjc-arc', '-fobjc-arc-exceptions', '-O2',
                                '-framework', 'Foundation', str(native), '-o', str(binary)], check=True)
                return subprocess.run([str(binary)], env=env, text=True,
                                      capture_output=True, timeout=30)

            fixed = run(body, 'fixed')
            self.assertEqual(fixed.returncode, 0, fixed.stdout + fixed.stderr)
            self.assertNotIn('sent to deallocated instance', fixed.stderr)
            self.assertIn('[PASS] actual container resolver ARC ownership: 5000 cases', fixed.stdout)
            print(fixed.stdout.strip())

            # Negative control: the exact build-29 call must trigger the zombie
            # diagnostic or crash, so this fixture detects the reported defect.
            old_call = ('id record = ((id (*)(id, SEL, id, BOOL, id*))objc_msgSend)'
                        '([recordClass alloc], initSel, bundleID, NO, &err);')
            broken, count = re.subn(
                r'id record = \[\(id<AstraApplicationRecordInitializing>\)\[recordClass alloc\]\s*'
                r'initWithBundleIdentifier:bundleID allowPlaceholder:NO error:&err\];',
                old_call, body)
            self.assertEqual(count, 1)
            baseline = run(broken, 'build29-control')
            self.assertTrue(baseline.returncode != 0 or
                            'sent to deallocated instance' in baseline.stderr,
                            'negative control failed to expose the build-29 ownership defect')
            print('[PASS] build-29 negative control detects initializer over-release')


if __name__ == '__main__':
    unittest.main()
