import Foundation

enum AppInfo {
    static let versionTuple = (major: 27, minor: 0, patch: 1)
    static let osBuild = "24A500"
}

@main struct EnginePolicySelfCheck {
    static func main() {
        typealias P = ExploitSupportPolicy
        let cases: [(Int, Int, Int, String, P.AccessProvider)] = [
            (15,9,0,"",.unsupported), (16,0,0,"",.legacy3105), (16,8,0,"",.legacy3105),
            (17,0,0,"",.legacy3105), (17,7,12,"",.legacy3105), (17,8,0,"",.unsupported),
            (18,7,1,"",.legacy3105), (18,7,2,"",.airLift), (18,11,0,"",.airLift),
            (19,0,0,"",.unsupported), (25,0,0,"",.unsupported),
            (26,0,0,"",.legacy3105), (26,6,1,"",.legacy3105), (26,6,2,"",.worseQuery),
            (26,7,2,"",.worseQuery), (26,7,3,"",.airLift), (26,8,0,"",.airLift),
            (27,0,0,"24A5355q",.legacy3105), (27,0,0,"24A5370h",.legacy3105),
            (27,0,0,"24A5380h",.legacy3105), (27,0,0,"24A5390f",.legacy3105),
            (27,0,0,"24A437",.worseQuery), (27,0,1,"24A5355q",.worseQuery),
            (27,0,1,"Unknown",.worseQuery), (27,1,9,"",.worseQuery),
            (27,2,0,"24B5099f",.worseQuery), (27,2,0,"24B119",.worseQuery),
            (27,2,1,"24B119",.unsupported), (27,3,0,"",.unsupported),
            (28,0,0,"",.unsupported), (26,-1,0,"",.unsupported), (18,7,-1,"",.unsupported)
        ]
        var checks = 0
        for (major,minor,patch,build,expected) in cases {
            let provider = P.accessProvider(major:major, minor:minor, patch:patch, build:build)
            precondition(provider == expected, "wrong route for \(major).\(minor).\(patch) \(build)")
            let expectedMode: P.StorageMode = expected == .unsupported ? .unsupported : expected == .airLift ? .airLift : .direct
            precondition(P.storageMode(major:major,minor:minor,patch:patch,build:build) == expectedMode)
            for sandbox in [false,true] { for group in [false,true] {
                precondition(P.runtimeStorageMode(major:major,minor:minor,patch:patch,build:build,
                    hasSandboxAccess:sandbox,worseQueryAvailable:group) == expectedMode)
                checks += 1
            } }
            precondition(!(P.supports3105(major:major,minor:minor,patch:patch,build:build)
                && P.supportsWorseQuery(major:major,minor:minor,patch:patch,build:build)))
            let pairing = P.pairingMode(major:major,minor:minor,patch:patch,build:build)
            precondition(pairing == (expected == .airLift ? .importedFile : expected == .unsupported ? .unavailable : .none))
            checks += 4
        }
        for missing in ["", "Unknown", "unknown", "  "] {
            precondition(P.accessProvider(major:27,minor:0,patch:0,build:missing) == .unsupported)
            checks += 1
        }
        print("[PASS] Independent engine boundary matrix: \(checks) assertions")
    }
}
