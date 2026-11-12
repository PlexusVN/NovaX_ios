import Foundation

// Native bridges and OS/group access are injected; the Swift helper under test
// is the actual production file. This does not execute an exploit on the host.
enum AppInfo {
    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }
    static let osBuild = "24A435"
}
enum ProcessInfo {
    static var processInfo = FixtureProcessInfo()
}
struct FixtureProcessInfo {
    var operatingSystemVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
}
final class FileManager {
    static let `default` = FileManager()
    var groupAvailable = true
    func containerURL(forSecurityApplicationGroupIdentifier group: String) -> URL? {
        groupAvailable && group == "group.esign.rewritten" ? Foundation.FileManager.default.temporaryDirectory : nil
    }
    func fileExists(atPath path: String) -> Bool { Foundation.FileManager.default.fileExists(atPath: path) }
    func createDirectory(at url: URL, withIntermediateDirectories value: Bool) throws {
        try Foundation.FileManager.default.createDirectory(at: url, withIntermediateDirectories: value)
    }
    func removeItem(at url: URL) throws { try Foundation.FileManager.default.removeItem(at: url) }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try Foundation.FileManager.default.contentsOfDirectory(atPath: path)
    }
}
func AstraSignedApplicationGroups() -> [String] { ["group.esign.rewritten"] }
func worse_query_group_path(_ group: String) -> String? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.path
}
enum NativeFixture {
    static var preflightReady = true
    static var result: Int64 = 42
    static var calls: [(String, String, Bool, Bool)] = []
    static var released: [Int64] = []
}
func worse_query(_ path: String, _ group: String, _ alt: Bool, _ create: Bool) -> Int64 {
    NativeFixture.calls.append((path, group, alt, create))
    return NativeFixture.result
}
func worse_query_release(_ handle: Int64) { NativeFixture.released.append(handle) }
func worse_query_preflight(_ group: String) -> Bool { NativeFixture.preflightReady }
func worse_query_diagnostics() -> String? { "stage=fixture domain=NSPOSIXErrorDomain code=13" }
func pathleak(_ path: String, _ maximum: UInt64) -> NSArray? { nil }
func pathleak_range(_ path: String, _ first: UInt64, _ last: UInt64, _ code: UnsafeMutablePointer<Int32>?) -> NSArray? { [] }
enum FixtureFailure: Error { case operation }

@main struct WorseQueryHelperSelfCheck {
    @MainActor static func main() async throws {
        for (major,minor,patch) in [(26,6,2),(26,7,0),(26,7,2),(27,0,1)] {
            ProcessInfo.processInfo.operatingSystemVersion = OperatingSystemVersion(majorVersion:major,minorVersion:minor,patchVersion:patch)
            WorseQueryHelper.invalidateActiveAppGroup()
            precondition(WorseQueryHelper.resolveActiveAppGroup() == nil, "UI probed App Group before preparation")
            do {
                _ = try WorseQueryHelper.acquireAccess(for: "/var/mobile/Containers/Data/Application/fixture")
                preconditionFailure("main-thread query reached native code")
            } catch WorseQueryError.mainThreadAccess {}
        }
        precondition(NativeFixture.calls.isEmpty)
        ProcessInfo.processInfo.operatingSystemVersion = OperatingSystemVersion(majorVersion:27,minorVersion:0,patchVersion:0)
        precondition(WorseQueryHelper.resolveActiveAppGroup() == nil, "UI performed a native group probe before preparation")
        do {
            _ = try WorseQueryHelper.acquireAccess(for: "/var/mobile/Containers/Data/Application/fixture")
            preconditionFailure("main-thread native query was not rejected")
        } catch WorseQueryError.mainThreadAccess {}
        try await Task.detached(priority: .userInitiated) { try checkBackground() }.value
    }
    static func checkBackground() throws {
        let root = "/var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000001"
        let canonicalRoot = "/private" + root
        precondition(WorseQueryHelper.resolveActiveAppGroup() == "group.esign.rewritten")
        precondition(WorseQueryHelper.isAvailable)
        let preflight = try WorseQueryHelper.preparationDiagnostics()
        precondition(preflight.contains("group.esign.rewritten"))
        NativeFixture.preflightReady = false
        do {
            _ = try WorseQueryHelper.preparationDiagnostics()
            preconditionFailure("failed write probe allowed discovery")
        } catch WorseQueryError.localFilesystemFailure(let detail) {
            precondition(detail.contains("NSPOSIXErrorDomain code=13"))
        }
        NativeFixture.preflightReady = true
        NativeFixture.result = -4
        do {
            _ = try WorseQueryHelper.acquireAccess(for: root)
            preconditionFailure("symlink failure was swallowed")
        } catch WorseQueryError.localFilesystemFailure(let detail) {
            precondition(detail.contains("NSPOSIXErrorDomain code=13"))
        }
        NativeFixture.calls = []
        NativeFixture.result = 42
        ProcessInfo.processInfo.operatingSystemVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
        precondition(WorseQueryHelper.isOSSupported)
        let maximum = try WorseQueryHelper.enumerationUpperBound(probeInode: 5_000_000)
        precondition(maximum == 5_002_048)
        precondition(WorseQueryHelper.containerRoot(for: root + "/Documents/a") == canonicalRoot)
        precondition(WorseQueryHelper.isScopeSupported(for: root))
        precondition(WorseQueryHelper.isScopeSupported(for: canonicalRoot))
        precondition(!WorseQueryHelper.isScopeSupported(for: "/var/mobile/Containers/Data/ApplicationFake/a"))
        precondition(!WorseQueryHelper.isScopeSupported(for: "/etc/passwd"))

        let value = try WorseQueryHelper.withSandboxAccess(for: root + "/Documents/a") {
            precondition(NativeFixture.released.isEmpty)
            precondition(NativeFixture.calls.last!.0 == canonicalRoot)
            precondition(NativeFixture.calls.last!.1 == "group.esign.rewritten")
            precondition(!NativeFixture.calls.last!.2)
            return 7
        }
        precondition(value == 7 && NativeFixture.released == [42])
        do {
            try WorseQueryHelper.withSandboxAccess(for: root) { throw FixtureFailure.operation }
            preconditionFailure("operation failure was swallowed")
        } catch FixtureFailure.operation {}
        precondition(NativeFixture.released == [42, 42])

        NativeFixture.result = -5
        do {
            _ = try WorseQueryHelper.acquireAccess(for: root)
            preconditionFailure("query rejection was swallowed")
        } catch WorseQueryError.queryRejected {}
        NativeFixture.result = -7
        do {
            _ = try WorseQueryHelper.acquireAccess(for: root)
            preconditionFailure("token consumption failure was ignored")
        } catch WorseQueryError.extensionConsumptionFailed {}
        precondition(NativeFixture.released == [42, 42])
        FileManager.default.groupAvailable = false
        WorseQueryHelper.invalidateActiveAppGroup()
        precondition(!WorseQueryHelper.isAvailable)
        do {
            _ = try WorseQueryHelper.acquireAccess(for: root)
            preconditionFailure("missing signed group was ignored")
        } catch WorseQueryError.appGroupUnavailable {}
        FileManager.default.groupAvailable = true
        WorseQueryHelper.invalidateActiveAppGroup()
        NativeFixture.result = 43
        ProcessInfo.processInfo.operatingSystemVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        let handle = try WorseQueryHelper.acquireAccess(for: "/var/mobile/Containers/Shared/AppGroup/test")
        precondition(NativeFixture.calls.last!.2)
        WorseQueryHelper.releaseAccess(handle: handle)
        print("[PASS] production worse_query helper: rewritten signed group, scope boundaries, root grant, flags, success/error release, daemon errors, missing group")
    }
}
