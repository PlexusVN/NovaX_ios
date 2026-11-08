import Foundation

enum AppInfo {
    static let versionTuple = (major: 16, minor: 0, patch: 0)
    static let osBuild = "fixture"
}

@main struct IOSCompatibilitySelfCheck {
    static func main() {
        typealias Policy = ExploitSupportPolicy
        for minor in [0, 1, 4, 6, 7] {
            precondition(Policy.storageMode(major:16, minor:minor, patch:0, build:"") == .direct)
            precondition(Policy.pairingMode(major:16, minor:minor, patch:0, build:"") == .none)
        }
        for minor in [0, 1] {
            precondition(Policy.storageMode(major:27, minor:minor, patch:0, build:"") == .airLift)
            precondition(Policy.pairingMode(major:27, minor:minor, patch:0, build:"") == .onDeviceOrImportedFile)
        }
        for build in ["24B5084k", "24B5089g"] {
            precondition(Policy.storageMode(major:27, minor:2, patch:0, build:build) == .airLift)
        }
        precondition(Policy.storageMode(major:27, minor:2, patch:0, build:"unsupported-build") == .unsupported)
        precondition(Policy.storageMode(major:26, minor:6, patch:1, build:"") == .direct)
        precondition(Policy.pairingMode(major:26, minor:6, patch:2, build:"") == .importedFile)
        precondition(Policy.pairingMode(major:26, minor:7, patch:0, build:"") == .importedFile)
        precondition(Policy.storageMode(major:18, minor:7, patch:1, build:"") == .direct)
        precondition(Policy.pairingMode(major:18, minor:7, patch:2, build:"") == .importedFile)
        print("[PASS] Actual routing policy: iOS 16 direct/no pair; supported iOS 27 AirLift/pair; existing 18/26 routes retained")
    }
}
