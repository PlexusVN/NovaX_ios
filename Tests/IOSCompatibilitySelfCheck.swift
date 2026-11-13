import Foundation

enum AppInfo {
    static let versionTuple = (major: 16, minor: 0, patch: 0)
    static let osBuild = "fixture"
}

@main struct IOSCompatibilitySelfCheck {
    static func main() {
        typealias Policy = ExploitSupportPolicy
        for (major,minor,patch,expected) in [(16,7,0,false),(17,0,0,false),(18,7,2,false),
            (26,0,0,false),(26,6,0,false),(26,6,1,false),(26,6,2,true),(26,6,9,true),
            (26,7,0,true),(26,7,1,true),(26,7,2,true),(26,7,3,false),(26,8,0,false),
            (27,0,1,true),(27,1,0,true),(27,3,0,false)] {
            precondition(Policy.requiresWorseQueryPreparation(major:major,minor:minor,patch:patch,build:"")==expected,
                         "preparation boundary changed: \(major).\(minor).\(patch)")
        }
        for minor in [0, 1, 4, 6, 7] {
            precondition(Policy.storageMode(major:16, minor:minor, patch:0, build:"") == .direct)
            precondition(Policy.pairingMode(major:16, minor:minor, patch:0, build:"") == .none)
        }
        for minor in [0, 1] {
            precondition(Policy.storageMode(major:27, minor:minor, patch:0, build:"24A437") == .direct)
            precondition(Policy.pairingMode(major:27, minor:minor, patch:0, build:"24A437") == .none)
        }
        for missing in ["", "Unknown", "unknown", "  "] {
            precondition(Policy.accessProvider(major:27, minor:0, patch:0, build:missing) == .unsupported)
            precondition(Policy.pairingMode(major:27, minor:0, patch:0, build:missing) == .unavailable)
        }
        precondition(Policy.supportsWorseQuery(major:27, minor:0, patch:1, build:"fixture-27.0.1"))
        precondition(Policy.storageMode(major:27, minor:0, patch:1, build:"fixture-27.0.1") == .direct)
        for build in ["24B5084k", "24B5089g"] {
            precondition(Policy.requiresWorseQueryPreparation(major:27,minor:2,patch:0,build:build))
            precondition(Policy.storageMode(major:27, minor:2, patch:0, build:build) == .direct)
            precondition(Policy.pairingMode(major:27, minor:2, patch:0, build:build) == .none)
        }
        for build in ["", "unknown-build", "24B5099f", "24A1"] {
            precondition(Policy.requiresWorseQueryPreparation(major:27,minor:2,patch:0,build:build))
            precondition(Policy.supportsWorseQuery(major:27,minor:2,patch:0,build:build))
            precondition(Policy.accessProvider(major:27,minor:2,patch:0,build:build) == .worseQuery,
                         "AirLift beta restriction leaked into worse_query routing")
            precondition(Policy.storageMode(major:27,minor:2,patch:1,build:build) == .unsupported)
            precondition(Policy.storageMode(major:27,minor:3,patch:0,build:build) == .unsupported)
        }
        var comparisons = 0
        let builds = ["", "24A5355q", "24A5370h", "24A5380h", "24A5390f", "24A435", "24B5084k", "24B5089g", "24B5099f"]
        for major in 15...28 {
            for minor in -1...12 {
                for patch in -1...12 {
                    for build in builds {
                        let legacy = Upstream3105SupportPolicy.isSupported(major:major,minor:minor,patch:patch,build:build)
                        let expectedLegacy = legacy || (major == 16 && minor >= 0 && patch >= 0)
                        precondition(Policy.supports3105(major:major,minor:minor,patch:patch,build:build) == expectedLegacy)
                        precondition(Policy.supportsKernelExploit(major:major,minor:minor,patch:patch) ==
                            Upstream3105SupportPolicy.supportsKernelExploit(major:major,minor:minor,patch:patch))
                        let provider = Policy.accessProvider(major:major,minor:minor,patch:patch,build:build)
                        precondition((provider == .legacy3105) == expectedLegacy)
                        precondition((provider == .worseQuery) == Policy.requiresWorseQueryPreparation(major:major,minor:minor,patch:patch,build:build))
                        precondition(!expectedLegacy || !Policy.supportsWorseQuery(major:major,minor:minor,patch:patch,build:build))
                        let mode = Policy.storageMode(major:major,minor:minor,patch:patch,build:build)
                        for sandbox in [false, true] {
                            for group in [false, true] {
                                precondition(Policy.runtimeStorageMode(major:major,minor:minor,patch:patch,build:build,
                                    hasSandboxAccess:sandbox,worseQueryAvailable:group) == mode,
                                    "permission probe changed engine for \(major).\(minor).\(patch) \(build)")
                            }
                        }
                        if provider == .airLift {
                            precondition((major == 18 || major == 26) && Policy.pairingMode(for:mode,major:major) == .importedFile)
                        }
                        comparisons += 1
                    }
                }
            }
        }
        for build in ["24A5355q", "24A5370h", "24A5380h", "24A5390f"] {
            precondition(Policy.accessProvider(major:27,minor:0,patch:0,build:build) == .legacy3105)
            precondition(!Policy.requiresWorseQueryPreparation(major:27,minor:0,patch:0,build:build))
            // Build-only matching must not accidentally override a different version.
            precondition(Policy.accessProvider(major:27,minor:0,patch:1,build:build) == .worseQuery)
        }
        precondition(Policy.accessProvider(major:26,minor:6,patch:1,build:"") == .legacy3105)
        precondition(Policy.accessProvider(major:26,minor:6,patch:2,build:"") == .worseQuery)
        precondition(Policy.accessProvider(major:26,minor:7,patch:3,build:"") == .airLift)
        precondition(Policy.accessProvider(major:18,minor:7,patch:2,build:"") == .airLift)
        precondition(Policy.accessProvider(major:17,minor:8,patch:0,build:"") == .unsupported)
        print("[PASS] \(comparisons) OS/build comparisons against upstream 3105, fixed engine priority under all sandbox/App Group states")
        precondition(Policy.storageMode(major:26, minor:6, patch:1, build:"") == .direct)
        precondition(Policy.pairingMode(major:26, minor:6, patch:2, build:"") == .none)
        precondition(Policy.pairingMode(major:26, minor:7, patch:0, build:"") == .none)
        precondition(Policy.pairingMode(major:26, minor:7, patch:2, build:"") == .none)
        precondition(Policy.pairingMode(major:26, minor:8, patch:0, build:"") == .importedFile)
        precondition(Policy.storageMode(major:18, minor:7, patch:1, build:"") == .direct)
        precondition(Policy.pairingMode(major:18, minor:7, patch:2, build:"") == .importedFile)
        print("[PASS] Strict 3105 / worse_query / imported-pairing AirLift routing, worse_query 27.2 is independent of the AirLift beta allowlist; 27.2.1+ blocked")
    }
}
