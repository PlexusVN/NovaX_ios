'use strict';
const fs=require('node:fs'),crypto=require('node:crypto');
function canonical(value){
 if(typeof value==='string'){if(!/^[\x20-\x7e]*$/.test(value))throw Error('non_ascii_manifest');return JSON.stringify(value);}
 if(typeof value==='number'){if(!Number.isSafeInteger(value))throw Error('invalid_number');return String(value);}
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 if(value&&typeof value==='object')return '{'+Object.keys(value).sort().map(k=>canonical(k)+':'+canonical(value[k])).join(',')+'}';
 throw Error('invalid_manifest_value');
}
let input='';process.stdin.on('data',b=>{input+=b;if(input.length>65536)throw Error('release_size_invalid')});
process.stdin.on('end',()=>{
 const body=JSON.parse(input),[privatePath,keyID,fingerprint]=process.argv.slice(2);
 if(body.bundle_id!=='com.apple.mobile.MobileHouseArrest'||!(/^[0-9]{1,10}$/).test(body.build)
   ||!keyID||!fingerprint||body.sections.length>128)throw Error('release_invalid');
 const privateKey=crypto.createPrivateKey(fs.readFileSync(privatePath));
 const actual=crypto.createHash('sha256').update(crypto.createPublicKey(privateKey).export({format:'der',type:'pkcs1'})).digest('hex');
 if(actual!==fingerprint)throw Error('release_signer_mismatch');
 const signature=crypto.sign('RSA-SHA256',Buffer.from('ASTRA-RELEASE-V1\n'+canonical(body)),privateKey).toString('base64');
 process.stdout.write(JSON.stringify({protocol:'astra-release-v1',keyId:keyID,body,signature}));
});
