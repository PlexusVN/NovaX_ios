const fs = require('fs');
const path = require('path');

console.log('================================================================');
console.log('>>> BẮT ĐẦU KIỂM TRA & XÁC MINH TOÀN DIỆN ASTRA + AIRLIFT 2026 <<<');
console.log('================================================================\n');

let allPassed = true;

function check(label, condition, extra = '') {
    if (condition) {
        console.log(`[PASS] ${label} ${extra}`);
    } else {
        console.error(`[FAIL] ${label} ${extra}`);
        allPassed = false;
    }
}

// 1. Kiểm tra tính cân bằng cú pháp các file Swift mới & cập nhật
console.log('1. Kiểm tra Cú pháp & Cấu trúc Tệp Swift (Syntax & Brace Balance):');
const swiftFiles = [
    'ThreeOneOSFive/helpers/AirLiftTunnelManager.swift',
    'ThreeOneOSFive/helpers/AirLiftPairingManager.swift',
    'ThreeOneOSFive/helpers/AirTrafficProtocolClient.swift',
    'ThreeOneOSFive/helpers/StorageEngineCoordinator.swift',
    'ThreeOneOSFive/helpers/FeaturePatchService.swift',
    'ThreeOneOSFive/views/AirLiftSettingsSection.swift',
    'ThreeOneOSFive/views/SecurityUtils.swift',
    'ThreeOneOSFive/views/SettingsView.swift',
    'ThreeOneOSFive/helpers/KernelExploit.swift',
    'ThreeOneOSFive/App.swift'
];

swiftFiles.forEach(relPath => {
    const fullPath = path.join(__dirname, '..', relPath);
    const exists = fs.existsSync(fullPath);
    check(`Tồn tại tệp: ${relPath}`, exists);
    if (exists) {
        const content = fs.readFileSync(fullPath, 'utf8');
        const openBraces = (content.match(/\{/g) || []).length;
        const closeBraces = (content.match(/\}/g) || []).length;
        const openParens = (content.match(/\(/g) || []).length;
        const closeParens = (content.match(/\)/g) || []).length;
        const openBrackets = (content.match(/\[/g) || []).length;
        const closeBrackets = (content.match(/\]/g) || []).length;
        
        check(`   -> ${path.basename(relPath)} { }`, openBraces === closeBraces, `(${openBraces}/${closeBraces})`);
        check(`   -> ${path.basename(relPath)} ( )`, openParens === closeParens, `(${openParens}/${closeParens})`);
        check(`   -> ${path.basename(relPath)} [ ]`, openBrackets === closeBrackets, `(${openBrackets}/${closeBrackets})`);
    }
});

// 2. Kiểm tra Entitlements
console.log('\n2. Kiểm tra Quyền Hạn (Entitlements Verification):');
const mainEntPath = path.join(__dirname, '..', 'ThreeOneOSFive/ThreeOneOSFive.entitlements');
const mainEnt = fs.readFileSync(mainEntPath, 'utf8');
check('Quyền Network Extension trong App chính', mainEnt.includes('com.apple.developer.networking.networkextension'));
check('Quyền dns-settings (NextDNS)', mainEnt.includes('dns-settings'));
check('Đã gỡ quyền packet-tunnel-provider', !mainEnt.includes('packet-tunnel-provider'));
check('Đã gỡ TunnelProv', !fs.existsSync(path.join(__dirname, '..', 'TunnelProv/PacketTunnelProvider.swift')));

// 3. Kiểm tra Support Policy iOS 27
console.log('\n3. Kiểm tra Phạm vi Hỗ trợ iOS 27 (ExploitSupportPolicy):');
const kernelSwift = fs.readFileSync(path.join(__dirname, '..', 'ThreeOneOSFive/helpers/KernelExploit.swift'), 'utf8');
check('Chứa build iOS 27 RC (24A435)', kernelSwift.includes('24A435'));
check('Chứa build iOS 27 Final (24A437)', kernelSwift.includes('24A437'));
check('Chứa build iOS 27 Beta (24A5390f)', kernelSwift.includes('24A5390f'));
check('Hỗ trợ iOS 27 qua AirLift Engine', kernelSwift.includes('if major == 27'));

// 4. Kiểm tra LocalDevVPN bên ngoài
console.log('\n4. Kiểm tra kết nối LocalDevVPN bên ngoài:');
const tunnelDetector = fs.readFileSync(path.join(__dirname, '..', 'ThreeOneOSFive/helpers/AirLiftTunnelManager.swift'), 'utf8');
check('Mở app LocalDevVPN bằng URL scheme', tunnelDetector.includes('localdevvpn://'));
check('Kiểm tra peer 10.7.0.1', tunnelDetector.includes('10.7.0.1'));
check('Nhận diện route VPN theo interface utun/ipsec thực tế', tunnelDetector.includes('hasTunnelRoute') && tunnelDetector.includes('hasPrefix("utun")'));
check('UI báo ONLINE khi route LocalDevVPN đã có (không phụ thuộc lockdownd cứng)',
    tunnelDetector.includes('var isOperational: Bool { isTunnelRouteDetected || isServiceReachable }'));
check('Không dùng cổng RSD 49152 cố định', !tunnelDetector.includes('49152'));
check('Không tạo NETunnelProviderManager', !tunnelDetector.includes('NETunnelProviderManager'));

const airTrafficClient = fs.readFileSync(path.join(__dirname, '..', 'ThreeOneOSFive/helpers/AirTrafficProtocolClient.swift'), 'utf8');
check('AirTraffic cho FFI tự xác minh sau khi có route tunnel',
    airTrafficClient.includes('guard tunnel.isTunnelRouteDetected else') &&
    !airTrafficClient.includes('guard tunnel.isOperational else'));
check('RemoteXPC multihost candidates are configured',
    tunnelDetector.includes('remoteXPCHostCandidates') &&
    airTrafficClient.includes('al_set_target_hosts'));

const featurePatch = fs.readFileSync(path.join(__dirname, '..', 'ThreeOneOSFive/helpers/FeaturePatchService.swift'), 'utf8');
const injectStart = featurePatch.indexOf('func injectCodePatch(');
const injectEnd = featurePatch.indexOf('func unjectCodePatch(', injectStart);
const injectCode = featurePatch.slice(injectStart, injectEnd);
const restoreStart = injectEnd;
const restoreEnd = featurePatch.indexOf('func isCodePatchInjected(', restoreStart);
const restoreCode = featurePatch.slice(restoreStart, restoreEnd);
check('CodePatch AirLift resolve container qua pairing transport', featurePatch.includes('airLiftCodePatchDirectory') && featurePatch.includes('resolveAppContainer'));
check('Không bắt buộc direct container trước nhánh AirLift',
    injectCode.indexOf('if useAirLift') >= 0 &&
    injectCode.indexOf('airLiftCodePatchDirectory') > injectCode.indexOf('if useAirLift') &&
    injectCode.indexOf('codePatchDirectory(variant:') > injectCode.indexOf('airLiftCodePatchDirectory'));
check('Khôi phục cũng resolve container qua AirLift trước direct',
    restoreCode.indexOf('if useAirLift') >= 0 &&
    restoreCode.indexOf('airLiftCodePatchDirectory') > restoreCode.indexOf('if useAirLift') &&
    restoreCode.indexOf('codePatchDirectory(variant:') > restoreCode.indexOf('airLiftCodePatchDirectory'));
check('INJECT giữ nguyên tên file tải xuống khi tạo đích', injectCode.includes('destDir.appendingPathComponent(downloaded.fileName)'));
check('KHÔI PHỤC giữ nguyên tên file tải xuống khi tạo đích', restoreCode.includes('destDir.appendingPathComponent(downloaded.fileName)'));
check('Lỗi resolve AirLift của INJECT được chuyển thành lỗi hiển thị', injectCode.includes('catch let error as AirLiftError'));
check('Lỗi resolve AirLift của KHÔI PHỤC được chuyển thành lỗi hiển thị', restoreCode.includes('catch let error as AirLiftError'));
check('Tên file lấy từ header đã giải mã và được kiểm tra an toàn',
    featurePatch.includes('X-CodePatch-File-Name') &&
    featurePatch.includes('encodedName.removingPercentEncoding') &&
    featurePatch.includes('validCodePatchFileName(decodedName)'));

const securityUtils = fs.readFileSync(path.join(__dirname, '..', 'ThreeOneOSFive/views/SecurityUtils.swift'), 'utf8');
check('Proxy guard chỉ dựa trên cờ proxy tường minh',
    securityUtils.includes('enabled("HTTPEnable")') &&
    securityUtils.includes('enabled("HTTPSEnable")') &&
    securityUtils.includes('enabled("ProxyAutoConfigEnable")'));
check('Proxy guard không chặn LocalDevVPN chỉ vì interface utun',
    !securityUtils.includes('hasPrefix("utun")'));

// 5. Kiểm tra Giao diện Settings
console.log('\n5. Kiểm tra Giao diện Cài đặt (Settings UI):');
const settingsView = fs.readFileSync(path.join(__dirname, '..', 'ThreeOneOSFive/views/SettingsView.swift'), 'utf8');
check('Nhúng AirLiftSettingsSection vào SettingsView', settingsView.includes('AirLiftSettingsSection()'));

console.log('\n================================================================');
if (allPassed) {
    console.log('>>> KẾT QUẢ: KIỂM TRA TĨNH AIRLIFT ĐẠT [PASSED] <<<');
    console.log('>>> VẪN CẦN BUILD TRÊN macOS VÀ KIỂM TRA TRÊN THIẾT BỊ THẬT. <<<');
} else {
    console.error('>>> KẾT QUẢ: CÓ LỖI CẦN ĐIỀU CHỈNH [FAILED] <<<');
    process.exit(1);
}
console.log('================================================================');
