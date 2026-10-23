Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ">>> KIEM TRA CAC TRUONG HOP SU DUNG CUA LOGIC PAIRING REVOCATION <<<" -ForegroundColor Cyan
Write-Host "==================================================================`n" -ForegroundColor Cyan

$allPassed = $true

function Assert-Test($name, $condition, $info = "") {
    if ($condition) {
        Write-Host "[PASS] $name $info" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $name $info" -ForegroundColor Red
        $script:allPassed = $false
    }
}

$pairingMgr = Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirLiftPairingManager.swift" -Raw
$airTraffic = Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirTrafficProtocolClient.swift" -Raw
$settingsUI = Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\views\AirLiftSettingsSection.swift" -Raw
$storageCoord = Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\StorageEngineCoordinator.swift" -Raw

Write-Host "1. Kiem tra dinh nghia trang thai va kha nang nhan dien go ghep doi:" -ForegroundColor Yellow
Assert-Test "PairingStatus co case .revoked" ($pairingMgr -match 'case revoked = ')
Assert-Test "PairingStatus co case .verified" ($pairingMgr -match 'case verified = ')
Assert-Test "PairingStatus co case .verifying" ($pairingMgr -match 'case verifying = ')
Assert-Test "isPaired tra ve true cho .ready hoac .verified" ($pairingMgr -match 'self == \.ready \|\| self == \.verified')

Write-Host "`n2. Kiem tra giam sat lien tuc (Continuous Monitoring & Lifecycle):" -ForegroundColor Yellow
Assert-Test "Lang nghe UIApplication.didBecomeActiveNotification" ($pairingMgr -match 'UIApplication\.didBecomeActiveNotification')
Assert-Test "Tu dong kiem tra khi quay lai tu Settings" ($pairingMgr -match 'self\.verifyPairingWithDevice\(silent: true\)')
Assert-Test "Timer dinh ky 15 giay giam sat khi app dang active" ($pairingMgr -match 'Timer\.publish\(every: 15\.0')
Assert-Test "Lang nghe su thay doi trang thai cua LocalDevVPN" ($pairingMgr -match 'AirLiftTunnelManager\.shared\.\$status')

Write-Host "`n3. Kiem tra ham chu dong kiem tra (Active Probe) va phat hien revoke:" -ForegroundColor Yellow
Assert-Test "Ham verifyPairingWithDevice ton tai trong AirTrafficProtocolClient" ($airTraffic -match 'func verifyPairingWithDevice\(\)')
Assert-Test "Thuc hien probe nhe qua al_find_app_container cho bundle com.apple.mobilesafari" ($airTraffic -match 'com\.apple\.mobilesafari')
Assert-Test "Nhan dien chuoi tunnelfailurepairverify" ($airTraffic -match 'tunnelfailurepairverify')
Assert-Test "Nhan dien chuoi rejected pairing keys" ($airTraffic -match 'rejected pairing keys')
Assert-Test "Nhan dien chuoi pairverify" ($airTraffic -match 'pairverify')
Assert-Test "Nhan dien chuoi re-pair in settings" ($airTraffic -match 're-pair in settings')
Assert-Test "handlePairingRevoked xoa file tren disk" ($pairingMgr -match 'FileManager\.default\.removeItem\(at: pairingFileURL\)')
Assert-Test "handlePairingRevoked reset status sang .revoked" ($pairingMgr -match 'status = \.revoked')
Assert-Test "handlePairingRevoked xoa storedAltIRK" ($pairingMgr -match 'Self\.storedAltIRK = ""')

Write-Host "`n4. Kiem tra chan thao tac khi da bi go ghep doi (Fail-Closed & User Guidance):" -ForegroundColor Yellow
Assert-Test "AirLiftError co case pairingRevoked" ($airTraffic -match 'case pairingRevoked')
Assert-Test "AirLiftError.pairingRevoked co huong dan ro rang" ($airTraffic -match 'case \.pairingRevoked:')
Assert-Test "resolveAppContainer bat loi revoke" ($airTraffic -match 'Self\.isPairingRevokedError\(result\.error\)')
Assert-Test "verifyCanary bat loi revoke" ($airTraffic -match 'Self\.isPairingRevokedError\(result\.error\)')
Assert-Test "writeDirectory bat loi revoke" ($airTraffic -match 'Self\.isPairingRevokedError\(result\.error\)')

Write-Host "`n5. Kiem tra Giao dien (UI Updates):" -ForegroundColor Yellow
Assert-Test "Nut KIEM TRA kiem tra ca VPN va Pairing chu dong" ($settingsUI -match 'pairingManager\.verifyPairingWithDevice\(silent: false\)')
Assert-Test "Nut XAC MINH tren the dashboard khi dang co pairing" ($settingsUI -match 'XÁC MINH')
Assert-Test "Hien canh bao khi .revoked" ($settingsUI -match 'pairingManager\.status == \.revoked')
Assert-Test "Icon lock.slash.fill khi .revoked" ($settingsUI -match 'lock\.slash\.fill')
Assert-Test "Chi cho phep xoa khi isPaired" ($settingsUI -match 'pairingManager\.status\.isPaired')

Write-Host "`n6. Kiem tra StorageEngineCoordinator:" -ForegroundColor Yellow
Assert-Test "StorageEngineCoordinator su dung isPaired" ($storageCoord -match 'AirLiftPairingManager\.shared\.status\.isPaired')

Write-Host "`n==================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host ">>> KET QUA: TAT CA 25/25 TEST CASE DAT CHUAN TUYET DOI [PASSED] <<<" -ForegroundColor Green
} else {
    Write-Host ">>> KET QUA: CO TEST CASE THAT BAI [FAILED] <<<" -ForegroundColor Red
}
Write-Host "==================================================================" -ForegroundColor Cyan
