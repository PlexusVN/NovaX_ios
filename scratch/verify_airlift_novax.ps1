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
    "ThreeOneOSFive/views/FeaturesView.swift",
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

# 3. iOS Storage Support Policy
Write-Host "`n3. Kiem tra ma tran Direct/AirLift (ExploitSupportPolicy):" -ForegroundColor Yellow
$kernelSwift = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\KernelExploit.swift" -Raw
Assert-Condition "iOS 16 nam trong kernel/direct policy" ($kernelSwift -match "if major == 16")
Assert-Condition "iOS 18.7.1 tro xuong la direct" ($kernelSwift -match 'minor == 7 && patch <= 1')
Assert-Condition "iOS 18.7.2 den 18.8.x la AirLift" ($kernelSwift -match '\(minor == 7 && patch >= 2\) \|\| minor == 8')
Assert-Condition "iOS 26.6.1 tro xuong la direct" ($kernelSwift -match 'minor == 6 && patch <= 1')
Assert-Condition "iOS 26.6.2 tro len la AirLift" (($kernelSwift -match 'if major == 26') -and ($kernelSwift -match 'return \.airLift'))
Assert-Condition "iOS 26.7 dung AirLift theo nhanh 26.6.2+" (
    ($kernelSwift -match 'if major == 26') -and
    ($kernelSwift -match 'minor < 6 \|\| \(minor == 6 && patch <= 1\)') -and
    ($kernelSwift -match 'return \.airLift')
)
Assert-Condition "iOS 27.2 beta 1 duoc ho tro" ($kernelSwift -match "24B5084k")
Assert-Condition "iOS 27.2 beta 2 duoc ho tro" ($kernelSwift -match "24B5089g")
Assert-Condition "iOS 27.2 build la phai dung allowlist" ($kernelSwift -match 'minor == 2, supportedIOS272Builds\.contains\(build\)')
Assert-Condition "Kernel exploit khong dung chung voi danh sach AirLift" ($kernelSwift -match 'ExploitSupportPolicy\.supportsKernelExploit')
$pairingSwift = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirLiftPairingManager.swift" -Raw
Assert-Condition "Policy tach pairing none/imported/on-device" (
    ($kernelSwift -match 'enum PairingMode') -and
    ($kernelSwift -match 'case importedFile') -and
    ($kernelSwift -match 'case onDeviceOrImportedFile')
)
Assert-Condition "iOS 18 va 26 AirLift dung pairing file nhap" ($kernelSwift -match 'major >= 27 \? \.onDeviceOrImportedFile : \.importedFile')
Assert-Condition "Pair truc tiep phai qua policy build iOS" ($pairingSwift -match 'currentPairingMode == \.onDeviceOrImportedFile')
$appSwift = Get-Content -Path "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\App.swift" -Raw
Assert-Condition "Trang thai ho tro chi dua tren ma tran OS/build" (
    ($appSwift -match 'var isSupported: Bool\s*\{[\s\S]*?ExploitSupportPolicy\.isSupported') -and
    ($appSwift -match 'var accessLevelDescription: String\s*\{\s*switch ExploitSupportPolicy\.currentStorageMode')
)
Assert-Condition "Trang thai phan biet Direct va tung kieu pairing AirLift" (
    ($appSwift -match 'case \.direct:[\s\S]*?case \.airLift:') -and
    ($appSwift -match 'case \.importedFile:') -and
    ($appSwift -match 'case \.onDeviceOrImportedFile:') -and
    ($appSwift -match 'case \.unsupported:')
)
Assert-Condition "iOS 26.7 duoc huong dan pairing bang may tinh" ($pairingSwift -match 'bao gồm iOS 26\.7')
Assert-Condition "Bonjour chi bao dang phat sau delegate thanh cong" (
    ($pairingSwift -match 'NetServiceDelegate') -and
    ($pairingSwift -match 'func netServiceDidPublish') -and
    ($pairingSwift -match 'func netService\(_ sender: NetService, didNotPublish') -and
    ($pairingSwift -notmatch 'service\.publish\(\)\s*\r?\n\s*netService = service\s*\r?\n\s*isBroadcastingBonjour = true')
)
Assert-Condition "Probe Local Network timeout khong chan RPPairing" (
    ($pairingSwift -match 'request\(timeout: TimeInterval = 2\.0\)') -and
    ($pairingSwift -match 'MainActor\.assumeIsolated \{ self\?\.finish\(true\) \}')
)
Assert-Condition "Bonjour co retry va host watchdog" (
    ($pairingSwift -match 'retryBonjourAdvertisement') -and
    ($pairingSwift -match 'startHostReadyWatchdog')
)
Assert-Condition "Bonjour khong tu doi service ID cua RPPairing" ($pairingSwift -match 'publish\(options: \.noAutoRename\)')

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
Assert-Condition "Tat ca deployment target la iOS 16.0" (([regex]::Matches($pbxContent, 'IPHONEOS_DEPLOYMENT_TARGET = 16\.0;')).Count -eq 4)
Assert-Condition "Khong hard-code MinimumOSVersion trong Info.plist" (-not ((Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\Info.plist" -Raw) -match 'MinimumOSVersion'))
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
$airTrafficClient = Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive\helpers\AirTrafficProtocolClient.swift" -Raw
$airliftPatch = Get-Content "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\patches\airlift-rsd-timeout-fallback.patch" -Raw
Assert-Condition "Canary fail-closed, khong ghi tiep khi verify loi" ($airTrafficClient -notmatch "proceeding with direct writeDirectory")
Assert-Condition "Moi FFI call duoc serialize tren mot queue" (
    ($airTrafficClient -match "ffiExecutionQueue") -and
    ($airTrafficClient -match "configureTargetHosts\(candidates\)")
)
Assert-Condition "Rust huy canary/write khi qua timeout" (
    ($airliftPatch -match "AIRTRAFFIC_OPERATION_TIMEOUT") -and
    ($airliftPatch -match "operation cancelled")
)
Assert-Condition "Health check xac nhan Apple Books cho AirTraffic" (
    ($airTrafficClient -match 'resolveAppContainer\(bundleID: "com\.apple\.iBooks"\)') -and
    ($airTrafficClient -match "Apple Books/AirTraffic")
)

Write-Host "`n================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host ">>> KET QUA: 100% TIEU CHI XAC MINH DAT CHUAN [PASSED] <<<" -ForegroundColor Green
    Write-Host ">>> MA TRAN HO TRO VA TICH HOP CODE DAT KIEM TRA TINH; KHONG TEST THIET BI THEO YEU CAU. <<<" -ForegroundColor Green
} else {
    Write-Host ">>> KET QUA: CO LOI CAN DIEU CHINH [FAILED] <<<" -ForegroundColor Red
}
Write-Host "================================================================" -ForegroundColor Cyan
