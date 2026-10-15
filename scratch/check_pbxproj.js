const fs = require('fs');
const path = require('path');

const pbxPath = 'c:\\Users\\Khai\\Desktop\\Nova IOS 27\\NovaX\\ThreeOneOSFive.xcodeproj\\project.pbxproj';
const content = fs.readFileSync(pbxPath, 'utf8');

console.log("=== CHECKING PBXPROJ SYNTAX & STRUCTURE ===");

// Check brackets
let braceCount = 0;
let parenCount = 0;
for (let i = 0; i < content.length; i++) {
    if (content[i] === '{') braceCount++;
    if (content[i] === '}') braceCount--;
    if (content[i] === '(') parenCount++;
    if (content[i] === ')') parenCount--;
}

console.log(`Braces Balance: ${braceCount === 0 ? 'OK (0)' : 'MISMATCH: ' + braceCount}`);
console.log(`Parens Balance: ${parenCount === 0 ? 'OK (0)' : 'MISMATCH: ' + parenCount}`);

// Check sections
const sections = [
    'PBXBuildFile',
    'PBXFileReference',
    'PBXFrameworksBuildPhase',
    'PBXGroup',
    'PBXNativeTarget',
    'PBXProject',
    'PBXResourcesBuildPhase',
    'PBXSourcesBuildPhase',
    'XCBuildConfiguration',
    'XCConfigurationList'
];

for (const sec of sections) {
    const hasBegin = content.includes(`/* Begin ${sec} section */`);
    const hasEnd = content.includes(`/* End ${sec} section */`);
    console.log(`Section ${sec}: Begin=${hasBegin}, End=${hasEnd}`);
    if (!hasBegin || !hasEnd) {
        console.error(`ERROR in section ${sec}`);
    }
}

// Check targets in PBXProject
const projectMatch = content.match(/targets\s*=\s*\(([\s\S]*?)\);/);
if (projectMatch) {
    console.log("PBXProject targets list:\n" + projectMatch[1].trim());
}

const has3105Target = content.includes('3105 /* 3105 */ = {');
console.log(`Target 3105 present: ${has3105Target}`);
console.log(`TunnelProv fully removed: ${!content.includes('TunnelProv')}`);
