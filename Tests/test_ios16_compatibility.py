"""Offline Mach-O fixtures + production build/timeout wiring. Not a device test."""
from pathlib import Path
import hashlib
import json
import plistlib
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'ReleaseTools'))
from verify_native_compatibility import (CompatibilityError, REQUIRED_EXPORTS,
    REQUIRED_MARKERS, archive_members, check_app, check_archive, macho, version)


def object_file(minimum=16, platform=2, symbols=(), legacy=False, filetype=1):
    build = (struct.pack('<IIII', 0x25, 16, minimum << 16, 0) if legacy else
             struct.pack('<IIIIII', 0x32, 24, platform, minimum << 16, 0, 0))
    strings = b'\0'; entries = b''
    for name, typ, desc in symbols:
        offset = len(strings); strings += name.encode() + b'\0'
        entries += struct.pack('<IBBHQ', offset, typ, 1 if typ == 0xf else 0, desc,
                               0x1000 if typ == 0xf else 0)
    commands_size = len(build) + 24
    symoff = 32 + commands_size
    symtab = struct.pack('<IIIIII', 2, 24, symoff, len(symbols), symoff + len(entries), len(strings))
    return (struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, filetype, 2, commands_size, 0, 0)
            + build + symtab + entries + strings)


def archive(*objects):
    result = b'!<arch>\n'
    for index, body in enumerate(objects):
        name = f'object{index}.o/'
        result += f'{name:<16}{0:<12}{0:<6}{0:<6}{0o100644:<8}{len(body):<10}`\n'.encode()
        result += body + (b'\n' if len(body) % 2 else b'')
    return result


class NativeCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.path = self.root / 'lib.a'

    def check(self, *objects, platform=2, require_abi=False):
        self.path.write_bytes(archive(*objects))
        return check_archive(self.path, platform=platform, require_abi=require_abi)

    def test_ios16_and_older_objects_are_accepted(self):
        result = self.check(object_file(), object_file(10, legacy=True))
        self.assertEqual(result['objects'], 2)
        self.assertEqual(result['deployment_versions'], {'16.0.0': 1, '10.0.0': 1})

    def test_one_ios18_member_rejects_a_mixed_archive(self):
        with self.assertRaisesRegex(CompatibilityError, '1 incompatible objects'):
            self.check(object_file(), object_file(18))

    def test_simulator_must_not_be_mistaken_for_device(self):
        self.check(object_file(platform=7), platform=7)
        with self.assertRaisesRegex(CompatibilityError, 'incompatible objects'):
            self.check(object_file(platform=7), platform=2)

    def test_all_required_existing_abi_and_markers_are_checked(self):
        obj = object_file(symbols=tuple((name, 0xf, 0) for name in REQUIRED_EXPORTS))
        self.check(obj + b'\n'.join(REQUIRED_MARKERS), require_abi=True)
        with self.assertRaisesRegex(CompatibilityError, 'missing AirLift ABI'):
            self.check(object_file(), require_abi=True)
        with self.assertRaisesRegex(CompatibilityError, 'safety/fallback patch'):
            self.check(obj, require_abi=True)
        with self.assertRaisesRegex(CompatibilityError, 'unsafe direct-write'):
            self.check(obj + b'\n'.join(REQUIRED_MARKERS) + b'proceeding with direct writeDirectory', require_abi=True)

    def test_malformed_archive_and_macho_fail_closed(self):
        for data in [b'', b'!<arch>\nbroken', archive(b'not Mach-O'), archive(object_file()[:35])]:
            self.path.write_bytes(data)
            with self.assertRaises(CompatibilityError): check_archive(self.path, require_abi=False)

    def test_bsd_extended_names_are_parsed(self):
        name = b'long_rust_object_name.rcgu.o\0'
        body = name + object_file()
        header = f'{"#1/" + str(len(name)):<16}{0:<12}{0:<6}{0:<6}{0o100644:<8}{len(body):<10}`\n'.encode()
        raw = b'!<arch>\n' + header + body + (b'\n' if len(body) % 2 else b'')
        members = list(archive_members(raw))
        self.assertEqual(members[0][0], 'long_rust_object_name.rcgu.o')
        self.assertEqual(macho(members[0][1])[0], (2, (16, 0, 0)))

    def app(self, minimum=16, private_weak=True, plist_min='16.0'):
        target = self.root / 'Astra.app'; target.mkdir(exist_ok=True)
        (target / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'Astra', 'MinimumOSVersion': plist_min}))
        symbol = ('_IOSurfacePrefetchPages', 1, 0x40 if private_weak else 0)
        (target / 'Astra').write_bytes(object_file(minimum, symbols=(symbol,), filetype=2))
        return target

    def test_final_ipa_cannot_hide_newer_binary_behind_plist_min16(self):
        with self.assertRaisesRegex(CompatibilityError, 'executable requires newer'):
            check_app(self.app(minimum=18))
        with self.assertRaisesRegex(CompatibilityError, 'Info.plist requires newer'):
            check_app(self.app(plist_min='18.0'))

    def test_private_api_must_be_optional_even_when_the_app_target_is16(self):
        self.assertTrue(check_app(self.app())['private_prefetch_weak'])
        with self.assertRaisesRegex(CompatibilityError, 'must be weak-imported'):
            check_app(self.app(private_weak=False))

    def test_version_comparison_is_numeric(self):
        self.assertLess(version('9.3'), version('16.0'))
        self.assertGreater(version('16.1'), version('16.0'))
        for text in ['', 'bad', '16.-1', '16.0.0.1']:
            with self.assertRaises(CompatibilityError): version(text)


class BuildWiringTests(unittest.TestCase):
    def test_rebuild_uses_the_reviewed_source_compiler_lockfile_patch_and_header(self):
        lock = json.loads((ROOT / 'patches/airlift-source.lock.json').read_text(encoding='utf-8'))
        self.assertEqual(lock['revision'], '40640c4d827aeab8d798285b57d24fcf6be070d0')
        self.assertEqual(lock['rust_toolchain'], '1.98.1')
        self.assertEqual(lock['deployment_target'], '16.0')
        for path, expected in [(ROOT / lock['patch'], lock['patch_sha256']),
                (ROOT / 'Frameworks/AirliftFFI.xcframework/ios-arm64/Headers/airlift.h', lock['header_sha256'])]:
            self.assertEqual(hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest(), expected)
        script = (ROOT / 'ReleaseTools/build_airlift_compat.sh').read_text(encoding='utf-8')
        for term in ['IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"', '--locked',
                     '-miphoneos-version-min=$MIN_IOS', '-mios-simulator-version-min=$MIN_IOS',
                     'patched_exploit_sha256', '--platform simulator']:
            self.assertIn(term, script)
        self.assertNotIn('build-ios.sh', script)
        self.assertLess(script.index('--archive "$SIM"'), script.index('cp "$DEVICE"'))

    def test_ci_and_xcode_reject_wrong_native_target_before_distribution(self):
        flow = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
        self.assertLess(flow.index('bash ReleaseTools/build_airlift_compat.sh'), flow.index('- name: Build App'))
        self.assertLess(flow.index('--app "$APP_NAME" --max-ios 16.0'), flow.index('- name: Package IPA'))
        project = (ROOT / 'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        phases = project.split('buildPhases = (')[1].split(');')[0]
        self.assertLess(phases.index('Verify Native iOS Compatibility'), phases.index('Sources'))
        self.assertIn('--max-ios 16.0', project)

    def test_private_symbol_is_guarded_before_native_work_starts(self):
        source = (ROOT / 'ThreeOneOSFive/kexploit/kexploit_opa334.m').read_text(encoding='utf-8')
        self.assertIn('IOSurfacePrefetchPages(IOSurfaceRef surface) __attribute__((weak_import))', source)
        entry = source.split('int kexploit_opa334(void) {')[1]
        self.assertLess(entry.index('IOSurfacePrefetchPages == NULL'), entry.index('g_inExploitPhase = 1'))
        self.assertIn('return -ENOSYS', entry.split('g_inExploitPhase = 1')[0])

    def test_airlift_deadline_cannot_unlock_live_or_newer_work(self):
        source = (ROOT / 'ThreeOneOSFive/helpers/AirTrafficProtocolClient.swift').read_text(encoding='utf-8')
        timer = source.split('DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {')[1]
        timer = timer.split('private nonisolated static func')[0]
        self.assertNotIn('ffiWorkState.end()', timer)
        self.assertEqual(source.count('self.ffiWorkState.end()'), 1)
        self.assertIn('Astra.AirLift.FindContainer", timeout: 135', source)
        self.assertIn('Astra.AirLift.Write", timeout: 195', source)
        self.assertIn('Astra.AirLift.Canary", timeout: 195', source)
        write = source.split('private func writeDirectory(')[1].split('private func runBlocking')[0]
        self.assertIn('al_exploit_write_dir(', write)
        self.assertIn('IntegrityCommitBarrier.withCommit', write)


if __name__ == '__main__': unittest.main()
