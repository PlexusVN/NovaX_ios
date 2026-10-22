const fs = require('fs');

let failed = false;
function check(label, condition, detail = '') {
    console.log(`   - ${label}:`, detail, condition ? '[PASS]' : '[FAIL]');
    if (!condition) failed = true;
}

console.log('=== BẮT ĐẦU KIỂM TRA & XÁC MINH TOÀN DIỆN TRƯỚC KHI BUILD ===\n');

// 1. Info.plist
const plist = fs.readFileSync('ThreeOneOSFive/Info.plist', 'utf8');
const shortVer = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)[1];
const bundleVer = plist.match(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/)[1];
const displayVer = plist.match(/<key>AppReleaseDisplayVersion<\/key>\s*<string>([^<]+)<\/string>/)[1];

console.log('1. Info.plist:');
check('CFBundleShortVersionString', shortVer === '1.2.6', shortVer);
check('CFBundleVersion (Build)', bundleVer === '12', bundleVer);
check('AppReleaseDisplayVersion', displayVer === '1.2.6', displayVer);
check('CFBundleDisplayName Astra', /<key>CFBundleDisplayName<\/key>\s*<string>Astra<\/string>/.test(plist));
check('CFBundleName Astra', /<key>CFBundleName<\/key>\s*<string>Astra<\/string>/.test(plist));

// 2. project.pbxproj
const pbx = fs.readFileSync('ThreeOneOSFive.xcodeproj/project.pbxproj', 'utf8');
const mktVers = [...pbx.matchAll(/MARKETING_VERSION\s*=\s*([^;]+);/g)].map(m => m[1].trim());
const projVers = [...pbx.matchAll(/CURRENT_PROJECT_VERSION\s*=\s*([^;]+);/g)].map(m => m[1].trim());
const entitlements = [...pbx.matchAll(/CODE_SIGN_ENTITLEMENTS\s*=\s*([^;]+);/g)].map(m => m[1].trim());

console.log('\n2. project.pbxproj Build Settings:');
check('MARKETING_VERSION in configurations', mktVers.length > 0 && mktVers.every(v => v === '1.2.6'), mktVers.join(', '));
check('CURRENT_PROJECT_VERSION in configurations', projVers.length > 0 && projVers.every(v => v === '12'), projVers.join(', '));
check('CODE_SIGN_ENTITLEMENTS', entitlements.length > 0 && entitlements.every(e => e.includes('ThreeOneOSFive.entitlements')), entitlements.join(', '));
check('PRODUCT_NAME Astra', [...pbx.matchAll(/PRODUCT_NAME\s*=\s*([^;]+);/g)].every(match => match[1].trim() === 'Astra'));

// Check braces in pbxproj
const openPBX = (pbx.match(/\{/g) || []).length;
const closePBX = (pbx.match(/\}/g) || []).length;
check('PBX syntax balance', openPBX === closePBX, `${openPBX}/${closePBX}`);

// 3. ThreeOneOSFive.entitlements
const ent = fs.readFileSync('ThreeOneOSFive/ThreeOneOSFive.entitlements', 'utf8');
const hasNE = ent.includes('com.apple.developer.networking.networkextension');
const hasDNS = ent.includes('dns-settings');
console.log('\n3. ThreeOneOSFive.entitlements:');
check('com.apple.developer.networking.networkextension', hasNE);
check('dns-settings array value', hasDNS);

// 4. Utils.swift
const utils = fs.readFileSync('ThreeOneOSFive/helpers/Utils.swift', 'utf8');
const hasUtils126 = utils.includes('1.2.6');
console.log('\n4. Utils.swift:');
check('Fallback version constant', hasUtils126, hasUtils126 ? '1.2.6' : 'missing');

// 5. NextDNSManager.swift & DNSManagerView.swift syntax
console.log('\n5. Swift Code Syntax Balance:');
['ThreeOneOSFive/helpers/NextDNSManager.swift', 'ThreeOneOSFive/views/DNSManagerView.swift'].forEach(f => {
    const c = fs.readFileSync(f, 'utf8');
    const ob = (c.match(/\{/g) || []).length;
    const cb = (c.match(/\}/g) || []).length;
    check(f, ob === cb, `${ob}/${cb}`);
});

// 6. Astra branding, contacts, game scanner and IPA artifact
console.log('\n6. Astra Branding & Game Scanner:');
const designSystem = fs.readFileSync('ThreeOneOSFive/views/DesignSystem.swift', 'utf8');
const loginView = fs.readFileSync('ThreeOneOSFive/views/SplashLoginView.swift', 'utf8');
const featuresView = fs.readFileSync('ThreeOneOSFive/views/FeaturesView.swift', 'utf8');
const appIconHelper = fs.readFileSync('ThreeOneOSFive/helpers/AppIconHelper.m', 'utf8');
const appIconHeader = fs.readFileSync('ThreeOneOSFive/helpers/AppIconHelper.h', 'utf8');
const featureService = fs.readFileSync('ThreeOneOSFive/helpers/FeaturePatchService.swift', 'utf8');
const workflow = fs.readFileSync('.github/workflows/build.yml', 'utf8');
const localizationFiles = [
    'ThreeOneOSFive/en.lproj/Localizable.strings',
    'ThreeOneOSFive/vi.lproj/Localizable.strings',
    'ThreeOneOSFive/zh-Hans.lproj/Localizable.strings'
];

check('Developer cards have no Zalo', !designSystem.includes('Zalo') && !designSystem.includes('openZalo'));
check('Community Telegram links', loginView.includes('keyvnstorehax') && loginView.includes('Sondevx'));
check('No Zalo community links', !loginView.includes('zalo.me'));
check('Installed-game filtering', featuresView.includes('installedGameVariants') && featuresView.includes('Máy chưa tải Free Fire'));
check('FF bundle scan', featuresView.includes('isApplicationInstalled(bundleID)') && featuresView.includes('appInfoForBundleID(bundleID)'));
check('System icon extraction', appIconHelper.includes('iconForBundleID') && appIconHelper.includes('_applicationIconImageForBundleIdentifier'));
check('Nullable icon bridge contract', appIconHeader.includes('UIImage * _Nullable iconForBundleID'));
check('Free Fire TH fallback asset', fs.existsSync('ThreeOneOSFive/Assets.xcassets/FreeFireTHIcon.imageset/free-fire-th.jpg'));
check('Free Fire MAX fallback asset', fs.existsSync('ThreeOneOSFive/Assets.xcassets/FreeFireMAXIcon.imageset/free-fire-max.jpg'));
check('No device fallback to Astra sandbox', /#else\s*return nil\s*#endif/.test(featureService));
check('Astra.ipa workflow', workflow.includes('zip -r Astra.ipa Payload') && workflow.includes('build/Astra.ipa'));
check('Localized branding is Astra', localizationFiles.every(file => !fs.readFileSync(file, 'utf8').includes('NovaX')));

if (failed) {
    throw new Error('Prebuild verification failed.');
}

console.log('\n======================================================');
console.log('>>> KẾT QUẢ: STATIC CHECKLIST HOÀN TẤT & SẴN SÀNG BUILD TRÊN macOS! <<<');
console.log('======================================================');
