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
            precondition(Policy.storageMode(major:27, minor:minor, patch:0, build:"") == .direct)
            precondition(Policy.pairingMode(major:27, minor:minor, patch:0, build:"") == .none)
        }
        precondition(Policy.supportsWorseQuery(major:27, minor:0, patch:1, build:"fixture-27.0.1"))
        precondition(Policy.storageMode(major:27, minor:0, patch:1, build:"fixture-27.0.1") == .direct)
        for build in ["24B5084k", "24B5089g"] {
            precondition(Policy.storageMode(major:27, minor:2, patch:0, build:build) == .direct)
            precondition(Policy.pairingMode(major:27, minor:2, patch:0, build:build) == .none)
        }
        for build in ["", "unsupported-build", "24B5099f", "24A1"] {
            precondition(!Policy.supportsWorseQuery(major:27, minor:2, patch:0, build:build))
            precondition(Policy.storageMode(major:27, minor:2, patch:0, build:build) == .unsupported)
        }
        for major in [26, 27] {
            let noGroup = Policy.runtimeStorageMode(major:major, minor:0, patch:0, build:"",
                                                   hasSandboxAccess:false, worseQueryAvailable:false)
            precondition(noGroup == .airLift)
            precondition(Policy.pairingMode(for:noGroup, major:major) == (major == 27 ? .onDeviceOrImportedFile : .importedFile))
            for sandbox in [false, true] {
                let ready = Policy.runtimeStorageMode(major:major, minor:0, patch:0, build:"",
                                                     hasSandboxAccess:sandbox, worseQueryAvailable:true)
                precondition(ready == .direct && Policy.pairingMode(for:ready, major:major) == .none)
            }
            precondition(Policy.runtimeStorageMode(major:major, minor:0, patch:0, build:"",
                                                  hasSandboxAccess:true, worseQueryAvailable:false) == .direct)
        }
        precondition(Policy.storageMode(major:26, minor:6, patch:1, build:"") == .direct)
        precondition(Policy.pairingMode(major:26, minor:6, patch:2, build:"") == .none)
        precondition(Policy.pairingMode(major:26, minor:7, patch:0, build:"") == .none)
        precondition(Policy.pairingMode(major:26, minor:7, patch:2, build:"") == .none)
        precondition(Policy.pairingMode(major:26, minor:8, patch:0, build:"") == .importedFile)
        precondition(Policy.storageMode(major:18, minor:7, patch:1, build:"") == .direct)
        precondition(Policy.pairingMode(major:18, minor:7, patch:2, build:"") == .importedFile)
        print("[PASS] Actual routing policy: iOS 16 direct/no pair; iOS 26 & supported iOS 27 direct via worse_query (no pairing); AirLift retained for 18.7.2+ and fallback")
    }
}
