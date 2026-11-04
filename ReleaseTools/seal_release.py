"""Seal a production unsigned IPA locally, before ESign/KSign re-signing.

The private RSA key is read only by the child Node process and is never placed
inside the app, the generated registry, or a CI artifact.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import uuid
import zipfile

from macho_release import inspect_macho


def merge_registry(previous, document, retire=()):
    retired = set(retire)
    known = {item['body']['release_id'] for item in previous}
    if not retired.issubset(known):
        raise ValueError('retired_release_unknown')
    release_id = document['body']['release_id']
    retained = [item for item in previous
                if item['body']['release_id'] != release_id
                and item['body']['release_id'] not in retired]
    # A rebuild is not an authorization to disable an already distributed IPA,
    # even if both binaries accidentally have the same CFBundleVersion.
    if len(retained) >= 20:
        raise ValueError('registry_full_retire_old_release_explicitly')
    return retained + [document]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--private-key', type=Path, required=True)
    parser.add_argument('--registry', type=Path, required=True)
    parser.add_argument('--key-id', default='astra-rsa-2026-01')
    parser.add_argument('--retire-release', action='append', default=[])
    parser.add_argument('--expected-fingerprint',
                        default='b7ea531c327235ad0463df5d9e5bc8bcc13f34230d9cee9beba452c296294cb8')
    args = parser.parse_args()
    ipa, registry = args.ipa.resolve(), args.registry.resolve()
    if not ipa.is_file() or not args.private_key.is_file():
        raise ValueError('release_inputs_missing')
    previous = json.loads(registry.read_text(encoding='utf-8'))['releases'] if registry.exists() else []
    with zipfile.ZipFile(ipa) as source:
        plist_names = [name for name in source.namelist()
                       if name.startswith('Payload/') and name.count('/') == 2
                       and name.endswith('/Info.plist')]
        if len(plist_names) != 1:
            raise ValueError('single_app_required')
        info = plistlib.loads(source.read(plist_names[0]))
        base = plist_names[0].rsplit('/', 1)[0]
        if info['CFBundleIdentifier'] != 'com.apple.mobile.MobileHouseArrest':
            raise ValueError('production_bundle_required')
        sections, dependencies = inspect_macho(source.read(base + '/' + info['CFBundleExecutable']))
        body = {
            'release_id': str(uuid.uuid4()),
            'bundle_id': info['CFBundleIdentifier'],
            'version': info['CFBundleShortVersionString'],
            'build': info['CFBundleVersion'],
            'executable': info['CFBundleExecutable'],
            'sections': sections,
            'dependencies': dependencies,
        }
        comparable = {key: value for key, value in body.items() if key != 'release_id'}
        for old in previous:
            if {key: value for key, value in old['body'].items() if key != 'release_id'} == comparable:
                body['release_id'] = str(uuid.UUID(old['body']['release_id']))
                break
        signed = subprocess.run([
            'node', str(Path(__file__).with_name('sign_release.js')),
            str(args.private_key.resolve()), args.key_id, args.expected_fingerprint,
        ], input=json.dumps(body).encode(), capture_output=True, check=False)
        if signed.returncode:
            raise ValueError('release_signing_failed_check_key_fingerprint')
        document = json.loads(signed.stdout)
        releases = merge_registry(previous, document, args.retire_release)
        seal = json.dumps(document, separators=(',', ':'), sort_keys=True).encode()
        staged = ipa.with_suffix('.seal.tmp')
        with zipfile.ZipFile(staged, 'w', compression=zipfile.ZIP_DEFLATED) as output:
            for item in source.infolist():
                if item.filename != base + '/Astra.release':
                    output.writestr(item, source.read(item))
            output.writestr(base + '/Astra.release', seal)
    os.replace(staged, ipa)
    registry.parent.mkdir(parents=True, exist_ok=True)
    registry_staged = registry.with_suffix(registry.suffix + '.tmp')
    registry_staged.write_text(json.dumps({'releases': releases}, indent=2), encoding='utf-8')
    os.replace(registry_staged, registry)
    report = {
        'releaseID': body['release_id'],
        'build': body['build'],
        'sealDigest': hashlib.sha256(seal).hexdigest(),
        'ipaSHA256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'registry': str(registry),
    }
    ipa.with_suffix('.release.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
