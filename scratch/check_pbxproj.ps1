$pbxPath = "c:\Users\Khai\Desktop\Nova IOS 27\NovaX\ThreeOneOSFive.xcodeproj\project.pbxproj"
$content = Get-Content -Path $pbxPath -Raw

Write-Host "=== CHECKING PBXPROJ SYNTAX & STRUCTURE ==="

# Check brackets
$openBrace = ($content.ToCharArray() | Where-Object { $_ -eq '{' }).Count
$closeBrace = ($content.ToCharArray() | Where-Object { $_ -eq '}' }).Count
$openParen = ($content.ToCharArray() | Where-Object { $_ -eq '(' }).Count
$closeParen = ($content.ToCharArray() | Where-Object { $_ -eq ')' }).Count

Write-Host "Braces Balance: Open=$openBrace, Close=$closeBrace (Diff: $($openBrace - $closeBrace))"
Write-Host "Parens Balance: Open=$openParen, Close=$closeParen (Diff: $($openParen - $closeParen))"

$sections = @(
    "PBXBuildFile",
    "PBXFileReference",
    "PBXFrameworksBuildPhase",
    "PBXGroup",
    "PBXNativeTarget",
    "PBXProject",
    "PBXResourcesBuildPhase",
    "PBXSourcesBuildPhase",
    "XCBuildConfiguration",
    "XCConfigurationList"
)

foreach ($sec in $sections) {
    $hasBegin = $content.Contains("/* Begin $sec section */")
    $hasEnd = $content.Contains("/* End $sec section */")
    Write-Host "Section $($sec): Begin=$hasBegin, End=$hasEnd"
}

$has3105Target = $content.Contains("3105A500 /* 3105 */ = {")
Write-Host "Target 3105 present: $has3105Target"
Write-Host "TunnelProv fully removed: $(-not $content.Contains('TunnelProv'))"

$hasAirlift = $content.Contains("AirliftFFI.xcframework in Frameworks")
$hasCPP = $content.Contains('OTHER_LDFLAGS = "-lz -lc++";')
Write-Host "AirliftFFI linked: $hasAirlift"
Write-Host "C++ runtime linked: $hasCPP"
