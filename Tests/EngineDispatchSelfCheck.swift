import Foundation

enum AppInfo {
    static var versionTuple = (major: 26, minor: 6, patch: 1)
    static var osBuild = "fixture"
}
enum ProcessInfo {
    struct Info { var operatingSystemVersion: OperatingSystemVersion {
        let v = AppInfo.versionTuple
        return OperatingSystemVersion(majorVersion:v.major,minorVersion:v.minor,patchVersion:v.patch)
    } }
    static let processInfo = Info()
}
enum Calls {
    static let root = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    static let freshRoot = "/private/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    static var events: [String] = []
    static var mcmAvailable = true
    static var mcmRoot = root
    static var mcmLeaseActive = false
    static var cachedRootExists = false
    static var lsAvailable = true
    static func reset() {
        events = []; mcmAvailable = true; mcmRoot = root; mcmLeaseActive = false; cachedRootExists = false; lsAvailable = true
        UserDefaults.standard.removeObject(forKey:"astra.resolved_container.com.example.game")
        IOS27ContainerSession.root = nil
    }
}

// Existence is deliberately independent from activation: a sandbox may expose
// path metadata without granting the read/write access a transaction needs.
enum FileManager {
    struct Manager {
        func fileExists(atPath path: String) -> Bool {
            Calls.events.append("stat-cache")
            return Calls.cachedRootExists && path == Calls.root
        }
    }
    static let `default` = Manager()
}
enum IOS27ContainerSession {
    static var root: String?
    static func path(for bundleID: String) -> String? { Calls.events.append("prepared-root"); return root }
}
enum ContainerDiscoveryMerger { static func canonicalPath(_ path: String) -> String { path } }
enum PatchPathValidator { static func canonicalBundleIdentifier(_ id: String) throws -> String { id } }
enum PatchPackageError: Error { case targetAppUnavailable(String) }
enum WorseQueryError: Error { case unsupportedOS(String), appGroupUnavailable, preparationRequired }
enum WorseQueryHelper {
    static var isAvailable: Bool { ExploitSupportPolicy.currentSupportsWorseQuery }
    static func isScopeSupported(for path: String) -> Bool { true }
    static func withSandboxAccess<T>(for path: String, operation: () throws -> T) throws -> T { try operation() }
    static func acquireAccess(for path: String) throws -> Int64 { Calls.events.append("worse_query"); return 88 }
}
func MCMActivateContainerPath(_ cls: Int, _ id: String, _ group: Bool, _ error: inout NSString?) -> String? {
    precondition(cls == 2 && !group)
    Calls.events.append("MHA-C2")
    if Calls.mcmAvailable { Calls.mcmLeaseActive = true; return Calls.mcmRoot }
    return nil
}
func containerPathForBundleID(_ id: String) -> String? { Calls.events.append("LS"); return Calls.lsAvailable ? Calls.root : nil }
func bad_query(_ path: inout [Int8], _ extended: Bool, _ group: String?, _ create: Bool) -> Int64 {
    Calls.events.append("bad_query"); return 77
}
func log(_ text: String) {}

@main struct EngineDispatchSelfCheck {
    static func main() throws {
        let id = "com.example.game"
        for v in [(16,7,12,""),(16,7,16,""),(17,7,9,""),(18,7,1,""),(26,0,0,""),(26,6,1,""),
                  (27,0,0,"24A5355q"),(27,0,0,"24A5370h"),(27,0,0,"24A5380h"),(27,0,0,"24A5390f")] {
            AppInfo.versionTuple = (v.0,v.1,v.2); AppInfo.osBuild = v.3
            Calls.reset()
            let resolved = try ContainerStore.resolveAppContainerForPatch(bundleID:id)
            precondition(resolved == Calls.root)
            precondition(Calls.events == ["MHA-C2"], "3105 did not use class-2 first: \(Calls.events)")
            precondition(ContainerStore.grantContainerAccess(Calls.root) == (v.0 >= 26 ? 77 : -1))
            precondition(!Calls.events.contains("worse_query") && !Calls.events.contains("prepared-root"))
            Calls.reset(); Calls.mcmAvailable = false
            let fallback = try ContainerStore.resolveAppContainerForPatch(bundleID:id)
            precondition(fallback == Calls.root)
            precondition(Calls.events == ["MHA-C2","LS"], "LS fallback did not stay behind MHA-C2")
        }
        for version in [(16,7,16),(17,7,9),(18,7,1),(26,6,1)] {
            AppInfo.versionTuple = version; AppInfo.osBuild = "fixture"
            Calls.reset(); Calls.cachedRootExists = true
            UserDefaults.standard.set(Calls.root, forKey:"astra.resolved_container.\(id)")
            let cached = try ContainerStore.resolveAppContainerForPatch(bundleID:id)
            precondition(cached == Calls.root && Calls.mcmLeaseActive,
                         "cached UUID was treated as an active process lease on iOS \(version)")
            precondition(Calls.events == ["MHA-C2"], "cache stat bypassed fresh MHA-C2: \(Calls.events)")
            Calls.reset(); Calls.cachedRootExists = true; Calls.mcmRoot = Calls.freshRoot
            UserDefaults.standard.set(Calls.root, forKey:"astra.resolved_container.\(id)")
            let updated = try ContainerStore.resolveAppContainerForPatch(bundleID:id)
            precondition(updated == Calls.freshRoot && Calls.mcmLeaseActive, "stale UUID overrode authoritative MCM root")
            precondition(UserDefaults.standard.string(forKey:"astra.resolved_container.\(id)") == Calls.freshRoot,
                         "fresh MCM root was not persisted")
            precondition(Calls.events == ["MHA-C2"], "stale path was trusted before MCM")
        }
        AppInfo.versionTuple = (16,7,16); AppInfo.osBuild = "fixture"
        Calls.reset(); Calls.cachedRootExists = true; Calls.mcmAvailable = false
        UserDefaults.standard.set(Calls.root, forKey:"astra.resolved_container.\(id)")
        let fallback = try ContainerStore.resolveAppContainerForPatch(bundleID:id)
        precondition(fallback == Calls.root && !Calls.mcmLeaseActive, "failed MCM was falsely marked activated")
        precondition(Calls.events == ["MHA-C2","stat-cache"], "legacy cache fallback skipped MCM attempt")
        precondition(ContainerStore.grantContainerAccess(fallback) == -1,
                     "path-only iOS 16 fallback invented a separate sandbox handle")
        for v in [(26,6,2,""),(26,7,1,""),(26,7,2,""),(27,0,1,""),(27,1,0,""),
                  (27,2,0,"24B5084k"),(27,2,0,"24B5089g"),(27,2,0,"24B5099f"),(27,2,0,"")] {
            AppInfo.versionTuple = (v.0,v.1,v.2); AppInfo.osBuild = v.3
            Calls.reset(); Calls.cachedRootExists = true
            UserDefaults.standard.set(Calls.root, forKey:"astra.resolved_container.\(id)")
            do { _ = try ContainerStore.resolveAppContainerForPatch(bundleID:id); preconditionFailure("preparation bypassed") }
            catch WorseQueryError.preparationRequired {}
            precondition(Calls.events == ["prepared-root"])
            IOS27ContainerSession.root = Calls.root
            let prepared = try ContainerStore.resolveAppContainerForPatch(bundleID:id)
            precondition(prepared == Calls.root && Calls.events == ["prepared-root","prepared-root"])
            precondition(ContainerStore.grantContainerAccess(prepared) == 88 && Calls.events.last == "worse_query")
        }
        for v in [(18,7,2,""),(18,11,0,""),(26,7,3,""),(26,8,0,""),(17,8,0,""),
                  (25,0,0,""),(27,2,1,"24B5099f"),(27,3,0,"")] {
            AppInfo.versionTuple = (v.0,v.1,v.2); AppInfo.osBuild = v.3
            Calls.reset(); Calls.cachedRootExists = true
            UserDefaults.standard.set(Calls.root, forKey:"astra.resolved_container.\(id)")
            precondition(ContainerStore.resolveAppContainerPath(bundleID:id) == nil)
            do { _ = try ContainerStore.resolveAppContainerForPatch(bundleID:id); preconditionFailure("non-direct route reached 3105") }
            catch WorseQueryError.unsupportedOS {}
            precondition(ContainerStore.grantContainerAccess(Calls.root) == -1 && Calls.events.isEmpty)
        }
        Calls.reset()
        print("[PASS] Actual container resolver/grant dispatch: cold cached iOS 16.7.16 activation, fresh UUID precedence, MHA failure path-only fallback, MHA before LS, mandatory WQ roots, no cross-engine fallback")
    }
}
