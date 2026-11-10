"""Seal a production unsigned IPA locally, before re-signing/installing it.
Private key is read only by the child Node process and never uploaded to CI.
"""
from pathlib import Path
import argparse,zipfile,plistlib,hashlib,json,uuid,subprocess,os
from macho_release import inspect_macho

def merge_registry(previous, document, retired=()):
    """Keep distributed releases, including rebuilds sharing a build number."""
    known = {item['body']['release_id'] for item in previous}
    if set(retired) - known:
        raise ValueError('retired_release_unknown')
    identity = document['body']['release_id']
    retained = [item for item in previous if item['body']['release_id'] not in retired]
    for item in retained:
        if item['body']['release_id'] == identity:
            if item != document:
                raise ValueError('release_identity_conflict')
            return retained
    if len(retained) >= 20:
        raise ValueError('registry_full_requires_explicit_retirement')
    return retained + [document]

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--ipa',type=Path,required=True);p.add_argument('--private-key',type=Path,required=True)
    p.add_argument('--registry',type=Path,required=True)
    p.add_argument('--retire-release', action='append', default=[])
    p.add_argument('--key-id',default='astra-rsa-2026-01')
    p.add_argument('--expected-fingerprint',default='b7ea531c327235ad0463df5d9e5bc8bcc13f34230d9cee9beba452c296294cb8')
    a=p.parse_args();ipa=a.ipa.resolve();registry=a.registry.resolve()
    if not ipa.is_file() or not a.private_key.is_file():raise ValueError('release_inputs_missing')
    previous=json.loads(registry.read_text(encoding='utf-8'))['releases']if registry.exists()else[]
    with zipfile.ZipFile(ipa)as z:
        names=[n for n in z.namelist()if n.startswith('Payload/')and n.count('/')==2 and n.endswith('/Info.plist')]
        if len(names)!=1:raise ValueError('single_app_required')
        info=plistlib.loads(z.read(names[0]));base=names[0].rsplit('/',1)[0]
        if info['CFBundleIdentifier']!='com.apple.mobile.MobileHouseArrest':raise ValueError('production_bundle_required')
        sections,deps=inspect_macho(z.read(base+'/'+info['CFBundleExecutable']))
        body={'release_id':str(uuid.uuid4()),'bundle_id':info['CFBundleIdentifier'],'version':info['CFBundleShortVersionString'],
              'build':info['CFBundleVersion'],'executable':info['CFBundleExecutable'],'sections':sections,'dependencies':deps}
        comparable={k:v for k,v in body.items()if k!='release_id'}
        for old in previous:
            if {k:v for k,v in old['body'].items()if k!='release_id'}==comparable:
                body['release_id']=str(uuid.UUID(old['body']['release_id']))
                break
        signed=subprocess.run(['node',str(Path(__file__).with_name('sign_release.js')),str(a.private_key.resolve()),a.key_id,a.expected_fingerprint],
          input=json.dumps(body).encode(),capture_output=True)
        if signed.returncode:raise ValueError('release_signing_failed_check_key_fingerprint')
        doc=json.loads(signed.stdout);seal=json.dumps(doc,separators=(',',':'),sort_keys=True).encode()
        # Validate retention before modifying the IPA or registry.
        releases=merge_registry(previous, doc, a.retire_release)
        staged=ipa.with_suffix('.seal.tmp')
        with zipfile.ZipFile(staged,'w',compression=zipfile.ZIP_DEFLATED)as out:
            for item in z.infolist():
                if item.filename!=base+'/Astra.release':out.writestr(item,z.read(item))
            out.writestr(base+'/Astra.release',seal)
    os.replace(staged,ipa)
    registry.parent.mkdir(parents=True,exist_ok=True);registry.write_text(json.dumps({'releases':releases},indent=2),encoding='utf-8')
    report={'releaseID':body['release_id'],'build':body['build'],'sealDigest':hashlib.sha256(seal).hexdigest(),
            'ipaSHA256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'registry':str(registry)}
    ipa.with_suffix('.release.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':main()
