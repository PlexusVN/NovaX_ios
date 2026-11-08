"""Read-only deployment/ABI checks. Never rewrites Mach-O version metadata."""
import argparse
from collections import Counter
from pathlib import Path
import plistlib
import struct


class CompatibilityError(ValueError):
    pass


def version(text):
    try:
        parts = tuple(int(v) for v in text.split('.'))
        if not 1 <= len(parts) <= 3 or any(v < 0 or v > 255 for v in parts):
            raise ValueError()
        return (parts + (0, 0))[:3]
    except (TypeError, ValueError):
        raise CompatibilityError('invalid iOS version')


def packed_version(value):
    return value >> 16, (value >> 8) & 255, value & 255


def label(value):
    return '.'.join(map(str, value))


def macho(data):
    def read(fmt, at):
        size = struct.calcsize(fmt)
        if at < 0 or at + size > len(data):
            raise CompatibilityError('truncated Mach-O')
        return struct.unpack_from(fmt, data, at)

    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        raise CompatibilityError('arm64 Mach-O required')
    if read('<I', 4)[0] != 0x100000c:
        raise CompatibilityError('arm64 CPU required')
    count, commands = read('<II', 16)
    if count > 4096 or commands > len(data) - 32:
        raise CompatibilityError('invalid load commands')
    at = 32
    deployments, exports, imports = [], set(), {}
    for _ in range(count):
        cmd, size = read('<II', at)
        if size < 8 or at + size > 32 + commands:
            raise CompatibilityError('invalid load command bounds')
        if cmd == 0x32:
            if size < 24:
                raise CompatibilityError('invalid build-version command')
            platform, minimum = read('<II', at + 8)
            deployments.append((platform, packed_version(minimum)))
        elif cmd == 0x25:
            if size < 16:
                raise CompatibilityError('invalid legacy iOS version')
            deployments.append((2, packed_version(read('<I', at + 8)[0])))
        elif cmd == 2:
            if size < 24:
                raise CompatibilityError('invalid symbol table command')
            symoff, num, stroff, strsize = read('<IIII', at + 8)
            if symoff + num * 16 > len(data) or stroff + strsize > len(data):
                raise CompatibilityError('invalid symbol table bounds')
            for index in range(num):
                offset, typ, section, desc, value = read('<IBBHQ', symoff + index * 16)
                if typ & 0xe0 or not typ & 1:
                    continue
                if offset >= strsize:
                    raise CompatibilityError('invalid symbol name offset')
                end = data.find(b'\0', stroff + offset, stroff + strsize)
                if end == -1:
                    raise CompatibilityError('unterminated symbol name')
                name = data[stroff + offset:end].decode('utf-8', errors='strict')
                if typ & 0xe == 0 and value == 0:
                    imports[name] = bool(desc & 0x40)  # N_WEAK_REF
                elif typ & 0xe == 0xe:
                    exports.add(name)
        at += size
    if at != 32 + commands or len(deployments) != 1:
        raise CompatibilityError('exactly one deployment command required')
    return deployments[0], exports, imports


def archive_members(data):
    if not data.startswith(b'!<arch>\n'):
        raise CompatibilityError('plain static archive required')
    at = 8
    while at < len(data):
        if at + 60 > len(data) or data[at + 58:at + 60] != b'`\n':
            raise CompatibilityError('invalid ar member header')
        try:
            size = int(data[at + 48:at + 58])
            name = data[at:at + 16].decode('ascii').strip()
        except ValueError:
            raise CompatibilityError('invalid ar member size')
        start, end = at + 60, at + 60 + size
        if size < 0 or end > len(data):
            raise CompatibilityError('invalid ar member bounds')
        body = data[start:end]
        if name.startswith('#1/'):
            length = int(name[3:])
            if not 0 < length <= len(body):
                raise CompatibilityError('invalid BSD ar name')
            name = body[:length].rstrip(b'\0').decode('utf-8')
            body = body[length:]
        if not name.startswith('__.SYMDEF') and name not in ('/', '//', '/SYM64/'):
            yield name, body
        at = end + (size & 1)
    if at != len(data):
        raise CompatibilityError('invalid ar alignment')


REQUIRED_EXPORTS = {
    '_al_log_init', '_al_string_free', '_al_pairing_run_host',
    '_al_exploit_run', '_al_exploit_write_dir', '_al_find_app_container',
    '_al_set_target_hosts', '_al_clear_target_hosts',
}
REQUIRED_MARKERS = (
    b'RemoteXPC timed out after 6s', b'timeout fallback trying raw RPPairing',
    b'AirTraffic write timed out after 180s; operation cancelled',
)


def check_archive(path, maximum=(16, 0, 0), platform=2, require_abi=True):
    data = Path(path).read_bytes()
    versions, exports, failures = Counter(), set(), []
    count = 0
    for name, body in archive_members(data):
        (actual_platform, minimum), symbols, _ = macho(body)
        if struct.unpack_from('<I', body, 12)[0] != 1:
            raise CompatibilityError('archive member is not a relocatable object')
        count += 1
        versions[label(minimum)] += 1
        exports.update(symbols)
        if actual_platform != platform or minimum > maximum:
            failures.append(f'{name}: platform={actual_platform}, iOS={label(minimum)}')
    if not count:
        raise CompatibilityError('empty native archive')
    if failures:
        raise CompatibilityError(f'{len(failures)} incompatible objects (limit iOS {label(maximum)}): '
                                 + '; '.join(failures[:3]))
    if require_abi:
        missing = REQUIRED_EXPORTS - exports
        if missing:
            raise CompatibilityError('missing AirLift ABI exports: ' + ', '.join(sorted(missing)))
        if any(marker not in data for marker in REQUIRED_MARKERS):
            raise CompatibilityError('missing existing iOS 27 AirLift safety/fallback patch')
        if b'proceeding with direct writeDirectory' in data:
            raise CompatibilityError('unsafe direct-write fallback is present')
    return {'objects': count, 'deployment_versions': dict(versions)}


def check_app(path, maximum=(16, 0, 0)):
    app = Path(path)
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if version(info.get('MinimumOSVersion', '')) > maximum:
        raise CompatibilityError('Info.plist requires newer iOS')
    executable = info['CFBundleExecutable']
    if Path(executable).name != executable or executable in ('.', '..'):
        raise CompatibilityError('invalid executable name')
    data = (app / executable).read_bytes()
    (platform, minimum), _, imports = macho(data)
    if struct.unpack_from('<I', data, 12)[0] != 2:
        raise CompatibilityError('app binary is not an executable')
    if platform != 2 or minimum > maximum:
        raise CompatibilityError('executable requires newer iOS/platform')
    # A manually declared private API has no availability annotation in the SDK.
    # Require optional binding so an older OS cannot die before Swift starts.
    symbol = '_IOSurfacePrefetchPages'
    if symbol in imports and not imports[symbol]:
        raise CompatibilityError('IOSurfacePrefetchPages must be weak-imported')
    return {'minimum_ios': label(minimum), 'private_prefetch_weak': imports.get(symbol)}


if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--archive', type=Path)
    group.add_argument('--app', type=Path)
    parser.add_argument('--max-ios', default='16.0')
    parser.add_argument('--platform', choices=['device', 'simulator'], default='device')
    args = parser.parse_args()
    try:
        result = (check_archive(args.archive, version(args.max_ios), 2 if args.platform == 'device' else 7)
                  if args.archive else check_app(args.app, version(args.max_ios)))
        print(json.dumps(result))
    except (CompatibilityError, OSError, KeyError, UnicodeError, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Native compatibility check failed: {error}\n')
