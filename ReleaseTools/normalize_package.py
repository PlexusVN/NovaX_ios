"""Convert a public legacy v2/v9 source to schema 3 before protected publishing.
Requires cryptography. Never reads credentials or modifies the source file.
"""
from pathlib import Path
import argparse,plistlib,hashlib,os,uuid,json
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
MAGIC=b'3105PATCH\0'
BUNDLES={'ffth':'com.dts.freefireth','ffmax':'com.dts.freefiremax','capcut':'com.lemon.lvoverseas'}
def convert(raw,variant):
    if len(raw)>50*1024*1024 or not raw.startswith(MAGIC):raise ValueError('invalid_package_header')
    envelope=plistlib.loads(raw[len(MAGIC):])
    if envelope.get('schemaVersion')not in (2,3,9)or envelope.get('isPasswordProtected')is not False:raise ValueError('public_source_required')
    if set(envelope)-{'schemaVersion','packageID','isPasswordProtected','publicContentKey','keyFingerprint','encryptedPayload'}:raise ValueError('unexpected_envelope_field')
    key=envelope['publicContentKey'];package=str(uuid.UUID(envelope['packageID'])).upper();sealed=envelope['encryptedPayload']
    if len(key)!=32 or hashlib.sha256(key).digest()!=envelope['keyFingerprint']:raise ValueError('source_key_invalid')
    plain=AESGCM(key).decrypt(sealed[:12],sealed[12:],('3105PATCH/v'+str(envelope['schemaVersion'])+'/payload/'+package).encode())
    payload=plistlib.loads(plain)
    if set(payload)!= {'project','replacementDigests'}:raise ValueError('payload_fields_invalid')
    project=payload['project'];expected=BUNDLES[variant]
    if project.get('isPrivate',False):raise ValueError('private_source_not_supported')
    if set(project)-{'id','name','author','isPrivate','createdAt','updatedAt','bundleIdentifiers','directories','rules','appGroupIdentifiers','systemAppGroupIdentifiers','settings'}:raise ValueError('unknown_project_field')
    for field in ['appGroupIdentifiers','systemAppGroupIdentifiers','settings']:
        if project.get(field):raise ValueError('nonempty_extension_not_supported')
        project.pop(field,None)
    if str(uuid.UUID(project['id'])).upper()!=package or not 1<=len(project['rules'])<=256:raise ValueError('project_identity_invalid')
    bundles=project.get('bundleIdentifiers',[])
    if len(bundles)>1 or any(b!=expected for b in bundles):raise ValueError('wrong_target_bundle')
    original_rules=[];targets=set();digests=payload['replacementDigests']
    if len(digests)!=len(project['rules']):raise ValueError('replacement_digests_invalid')
    for item in project.get('directories',[])+project['rules']:
        if item.get('containerKind')not in (None,'application')or item.get('operation')not in (None,'replace'):raise ValueError('unsupported_operation')
        item.pop('containerKind',None);item.pop('operation',None)
        relative=item['relativePath']
        if item['bundleID']!=expected or '\\'in relative or relative.strip()!=relative or any(p in ('','.','..')for p in relative.split('/')):raise ValueError('unsafe_target')
        if relative in targets:raise ValueError('duplicate_target')
        targets.add(relative)
        if 'replacementData'in item:
            filename=item['replacementFilename'];data=item['replacementData'];rid=str(uuid.UUID(item['id'])).upper()
            if not filename or '/'in filename or '\\'in filename or hashlib.sha256(data).digest()!=digests[rid]:raise ValueError('replacement_invalid')
            original_rules.append((item['bundleID'],relative,filename,hashlib.sha256(data).hexdigest()))
    # Only default extension fields are removed; replacement bytes and targets
    # are kept exactly. The publisher performs its bounded plist preflight next.
    new_key=os.urandom(32);nonce=os.urandom(12)
    encoded=plistlib.dumps(payload,fmt=plistlib.FMT_BINARY,sort_keys=False)
    envelope.update(schemaVersion=3,publicContentKey=new_key,keyFingerprint=hashlib.sha256(new_key).digest(),
      encryptedPayload=nonce+AESGCM(new_key).encrypt(nonce,encoded,('3105PATCH/v3/payload/'+package).encode()))
    out=MAGIC+plistlib.dumps(envelope,fmt=plistlib.FMT_BINARY,sort_keys=False)
    verified=plistlib.loads(AESGCM(new_key).decrypt(nonce,envelope['encryptedPayload'][12:],('3105PATCH/v3/payload/'+package).encode()))
    assert original_rules==[(r['bundleID'],r['relativePath'],r['replacementFilename'],hashlib.sha256(r['replacementData']).hexdigest())for r in verified['project']['rules']]
    return out
def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);p.add_argument('--variant',choices=BUNDLES,required=True);a=p.parse_args()
    if a.source.resolve()==a.output.resolve()or a.output.exists():raise ValueError('new_output_path_required')
    raw=a.source.read_bytes();out=convert(raw,a.variant);a.output.write_bytes(out)
    print(json.dumps({'sourceSHA256':hashlib.sha256(raw).hexdigest(),'outputSHA256':hashlib.sha256(out).hexdigest(),'variant':a.variant,'schema':3,'replacementDataPreserved':True}))
if __name__=='__main__':main()
