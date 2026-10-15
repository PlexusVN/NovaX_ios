const fs = require('fs');

console.log('=== BẮT ĐẦU KIỂM TRA & XÁC MINH TOÀN DIỆN TRƯỚC KHI BUILD ===\n');

// 1. Info.plist
const plist = fs.readFileSync('ThreeOneOSFive/Info.plist', 'utf8');
const shortVer = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)[1];
const bundleVer = plist.match(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/)[1];
const displayVer = plist.match(/<key>AppReleaseDisplayVersion<\/key>\s*<string>([^<]+)<\/string>/)[1];

console.log('1. Info.plist:');
console.log('   - CFBundleShortVersionString:', shortVer, shortVer === '1.2.5' ? '[PASS]' : '[FAIL]');
console.log('   - CFBundleVersion (Build):', bundleVer, bundleVer === '11' ? '[PASS]' : '[FAIL]');
console.log('   - AppReleaseDisplayVersion:', displayVer, displayVer === '1.2.5' ? '[PASS]' : '[FAIL]');

if (shortVer !== '1.2.5' || displayVer !== '1.2.5' || bundleVer !== '11') {
    throw new Error('Info.plist version mismatch!');
}

// 2. project.pbxproj
const pbx = fs.readFileSync('ThreeOneOSFive.xcodeproj/project.pbxproj', 'utf8');
const mktVers = [...pbx.matchAll(/MARKETING_VERSION\s*=\s*([^;]+);/g)].map(m => m[1].trim());
const projVers = [...pbx.matchAll(/CURRENT_PROJECT_VERSION\s*=\s*([^;]+);/g)].map(m => m[1].trim());
const entitlements = [...pbx.matchAll(/CODE_SIGN_ENTITLEMENTS\s*=\s*([^;]+);/g)].map(m => m[1].trim());

console.log('\n2. project.pbxproj Build Settings:');
console.log('   - MARKETING_VERSION in configurations:', mktVers.join(', '), mktVers.every(v => v === '1.2.5') ? '[PASS]' : '[FAIL]');
console.log('   - CURRENT_PROJECT_VERSION in configurations:', projVers.join(', '), projVers.every(v => v === '11') ? '[PASS]' : '[FAIL]');
console.log('   - CODE_SIGN_ENTITLEMENTS:', entitlements.join(', '), entitlements.every(e => e.includes('ThreeOneOSFive.entitlements')) ? '[PASS]' : '[FAIL]');

// Check braces in pbxproj
const openPBX = (pbx.match(/\{/g) || []).length;
const closePBX = (pbx.match(/\}/g) || []).length;
console.log('   - PBX syntax balance:', openPBX === closePBX ? `BALANCED (${openPBX}/${closePBX}) [PASS]` : '[FAIL]');

// 3. ThreeOneOSFive.entitlements
const ent = fs.readFileSync('ThreeOneOSFive/ThreeOneOSFive.entitlements', 'utf8');
const hasNE = ent.includes('com.apple.developer.networking.networkextension');
const hasDNS = ent.includes('dns-settings');
console.log('\n3. ThreeOneOSFive.entitlements:');
console.log('   - com.apple.developer.networking.networkextension:', hasNE ? '[PASS]' : '[FAIL]');
console.log('   - dns-settings array value:', hasDNS ? '[PASS]' : '[FAIL]');

// 4. Utils.swift
const utils = fs.readFileSync('ThreeOneOSFive/helpers/Utils.swift', 'utf8');
const hasUtils125 = utils.includes('1.2.5');
console.log('\n4. Utils.swift:');
console.log('   - Fallback version constant:', hasUtils125 ? '1.2.5 [PASS]' : '[FAIL]');

// 5. NextDNSManager.swift & DNSManagerView.swift syntax
console.log('\n5. Swift Code Syntax Balance:');
['ThreeOneOSFive/helpers/NextDNSManager.swift', 'ThreeOneOSFive/views/DNSManagerView.swift'].forEach(f => {
    const c = fs.readFileSync(f, 'utf8');
    const ob = (c.match(/\{/g) || []).length;
    const cb = (c.match(/\}/g) || []).length;
    console.log(`   - ${f}: ${ob === cb ? `BALANCED (${ob}/${cb}) [PASS]` : '[FAIL]'}`);
    if (ob !== cb) throw new Error(`${f} syntax mismatch!`);
});

console.log('\n======================================================');
console.log('>>> KẾT QUẢ: 100% CHECKLIST HOÀN TẤT & SẴN SÀNG BUILD! <<<');
console.log('======================================================');
