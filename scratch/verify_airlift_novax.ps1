Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ">>> BAT DAU KIEM TRA VA XAC MINH TOAN DIEN NOVAX + AIRLIFT <<<" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

$allPassed = $true

function Assert-Condition($label, $condition, $extra = "") {
    if ($condition) {
        Write-Host "[PASS] $label $extra" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label $extra" -ForegroundColor Red
        $script:allPassed = $false
    }
}

# 1. Swift Files Syntax & Balance Check
Write-Host "1. Kiem tra Cu phap va Cau truc Tep Swift (Syntax & Balance):" -ForegroundColor Yellow
$swiftFiles = @(
    "ThreeOneOSFive/helpers/AirLiftTunnelManager.swift",
    "ThreeOneOSFive/helpers/AirLiftPairingManager.swift",
    "ThreeOneOSFive/helpers/AirTrafficProtocolClient.swift",
    "ThreeOneOSFive/helpers/StorageEngineCoordinator.swift",
    "ThreeOneOSFive/views/AirLiftSettingsSection.swift",
    "ThreeOneOSFive/views/SettingsView.swift",
    "ThreeOneOSFive/helpers/KernelExploit.swift",
    "ThreeOneOSFive/App.swift"
)

foreach ($relPath in $swiftFiles) {
    $fullPath = Join-Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX" $relPath
    $exists = Test-Path $fullPath
    Assert-Condition "Ton tai tep: $relPath" $exists
    
    if ($exists) {
        $content = Get-Content -Path $fullPath -Raw
        $ob = ([regex]::Matches($content, '\{')).Count
        $cb = ([regex]::Matches($content, '\}')).Count
        $op = ([regex]::Matches($content, '\(')).Count
        $cp = ([regex]::Matches($content, '\)')).Count
        $obk = ([regex]::Matches($content, '\[')).Count
        $cbk = ([regex]::Matches($content, '\]')).Count
        
        $base = Split-Path $relPath -Leaf
        Assert-Condition ("   -> " + $base + " { }") ($ob -eq $cb) "($ob/$cb)"
        Assert-Condition ("   -> " + $base + " ( )") ($op -eq $cp) "($op/$cp)"
        Assert-Condition ("   -> " + $base + " [ ]") ($obk -eq $cbk) "($obk/$cbk)"
    }
}

# 2. Entitlements Verification
Write-Host "`n2. Kiem tra Quyen Han (Entitlements Verification):" -ForegroundColor Yellow
$mainEnt = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\ThreeOneOSFive.entitlements" -Raw
Assert-Condition "Quyen Network Extension trong App chinh" ($mainEnt -match "com.apple.developer.networking.networkextension")
Assert-Condition "Quyen dns-settings (NextDNS)" ($mainEnt -match "dns-settings")
Assert-Condition "Da go quyen packet-tunnel-provider" ($mainEnt -notmatch "packet-tunnel-provider")
Assert-Condition "Da go TunnelProv khoi project" (-not (Test-Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\TunnelProv\PacketTunnelProvider.swift"))

# 3. iOS 27 Support Policy
Write-Host "`n3. Kiem tra Pham vi Ho tro iOS 27 (ExploitSupportPolicy):" -ForegroundColor Yellow
$kernelSwift = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\KernelExploit.swift" -Raw
Assert-Condition "Chua build iOS 27 RC (24A435)" ($kernelSwift -match "24A435")
Assert-Condition "Chua build iOS 27 Final (24A437)" ($kernelSwift -match "24A437")
Assert-Condition "Chua build iOS 27 Beta (24A5390f)" ($kernelSwift -match "24A5390f")
Assert-Condition "Ho tro iOS 27 qua AirLift Engine" ($kernelSwift -match "if major == 27")

# 4. External LocalDevVPN
Write-Host "`n4. Kiem tra ket noi LocalDevVPN ben ngoai:" -ForegroundColor Yellow
$tunnelDetector = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirLiftTunnelManager.swift" -Raw
Assert-Condition "Mo app LocalDevVPN bang URL scheme" ($tunnelDetector -match "localdevvpn://")
Assert-Condition "Kiem tra peer 10.7.0.1" ($tunnelDetector -match "10.7.0.1")
Assert-Condition "Khong tao NETunnelProviderManager" ($tunnelDetector -notmatch "NETunnelProviderManager")
Assert-Condition "Dong bo host RemoteXPC Wi-Fi/cellular" (
    ($tunnelDetector -match "remoteXPCHostCandidates") -and
    ((Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirTrafficProtocolClient.swift" -Raw) -match "al_set_target_hosts")
)

# 5. Settings UI Integration
Write-Host "`n5. Kiem tra Giao dien Cai dat (Settings UI):" -ForegroundColor Yellow
$settingsView = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\views\SettingsView.swift" -Raw
Assert-Condition "Nhung AirLiftSettingsSection vao SettingsView" ($settingsView -match "AirLiftSettingsSection\(\)")

# 6. project.pbxproj Integration Check
Write-Host "`n6. Kiem tra Cau hinh Build project.pbxproj:" -ForegroundColor Yellow
$pbxContent = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive.xcodeproj\project.pbxproj" -Raw
Assert-Condition "AirLiftTunnelManager dang ky trong PBXSources" ($pbxContent -match "3105N200")
Assert-Condition "AirLiftPairingManager dang ky trong PBXSources" ($pbxContent -match "3105N201")
Assert-Condition "AirTrafficProtocolClient dang ky trong PBXSources" ($pbxContent -match "3105N202")
Assert-Condition "StorageEngineCoordinator dang ky trong PBXSources" ($pbxContent -match "3105N203")
Assert-Condition "AirLiftSettingsSection dang ky trong PBXSources" ($pbxContent -match "3105N204")
Assert-Condition "AirliftFFI.xcframework dang ky trong Frameworks" ($pbxContent -match "AirliftFFI.xcframework in Frameworks")
Assert-Condition "Khong con TunnelProv target" ($pbxContent -notmatch "TunnelProv")
Assert-Condition "AirliftFFI binary ton tai" (Test-Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\Frameworks\AirliftFFI.xcframework\ios-arm64\libairlift_ffi.a")
Assert-Condition "RPPairing host that duoc goi" ((Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirLiftPairingManager.swift" -Raw) -match "al_pairing_run_host")
Assert-Condition "AirTraffic write that duoc goi" ((Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirTrafficProtocolClient.swift" -Raw) -match "al_exploit_write_dir")
Assert-Condition "Canary read-back duoc bat buoc" ((Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirTrafficProtocolClient.swift" -Raw) -match "exactBytesRecovered")

Write-Host "`n================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host ">>> KET QUA: 100% TIEU CHI XAC MINH DAT CHUAN [PASSED] <<<" -ForegroundColor Green
    Write-Host ">>> TICH HOP BUILD DA DAT; CAN BUILD VA TEST TREN IPHONE/iOS 27 DE XAC NHAN RUNTIME. <<<" -ForegroundColor Green
} else {
    Write-Host ">>> KET QUA: CO LOI CAN DIEU CHINH [FAILED] <<<" -ForegroundColor Red
}
Write-Host "================================================================" -ForegroundColor Cyan
