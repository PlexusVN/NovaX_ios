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
    static var events: [String] = []
    static var mcmAvailable = true
    static var lsAvailable = true
    static func reset() {
        events = []; mcmAvailable = true; lsAvailable = true
        UserDefaults.standard.removeObject(forKey:"astra.resolved_container.com.example.game")
        IOS27ContainerSession.root = nil
    }
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
    static func withSandboxAccess<T>(for path: String, operation: () throws -> T) rethrows -> T { try operation() }
    static func acquireAccess(for path: String) throws -> Int64 { Calls.events.append("worse_query"); return 88 }
}
func MCMActivateContainerPath(_ cls: Int, _ id: String, _ group: Bool, _ error: inout NSString?) -> String? {
    precondition(cls == 2 && !group)
    Calls.events.append("MHA-C2")
    return Calls.mcmAvailable ? Calls.root : nil
}
func containerPathForBundleID(_ id: String) -> String? { Calls.events.append("LS"); return Calls.lsAvailable ? Calls.root : nil }
func bad_query(_ path: inout [Int8], _ extended: Bool, _ group: String?, _ create: Bool) -> Int64 {
    Calls.events.append("bad_query"); return 77
}
func log(_ text: String) {}

@main struct EngineDispatchSelfCheck {
    static func main() throws {
        let id = "com.example.game"
        for v in [(16,7,12,""),(17,7,9,""),(18,7,1,""),(26,0,0,""),(26,6,1,""),
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
        for v in [(26,6,2,""),(26,7,1,""),(26,7,2,""),(27,0,1,""),(27,1,0,""),
                  (27,2,0,"24B5084k"),(27,2,0,"24B5089g"),(27,2,0,"24B5099f"),(27,2,0,"")] {
            AppInfo.versionTuple = (v.0,v.1,v.2); AppInfo.osBuild = v.3
            Calls.reset()
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
            Calls.reset()
            precondition(ContainerStore.resolveAppContainerPath(bundleID:id) == nil)
            do { _ = try ContainerStore.resolveAppContainerForPatch(bundleID:id); preconditionFailure("non-direct route reached 3105") }
            catch WorseQueryError.unsupportedOS {}
            precondition(ContainerStore.grantContainerAccess(Calls.root) == -1 && Calls.events.isEmpty)
        }
        print("[PASS] Actual container resolver/grant dispatch: MHA-C2 before LS, legacy 27 beta exceptions, mandatory WQ roots, no cross-engine fallback")
    }
}
