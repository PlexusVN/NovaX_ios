import Foundation

// Native bridges and OS/group access are injected; the Swift helper under test
// is the actual production file. This does not execute an exploit on the host.
enum AppInfo {
    static let versionTuple = (major: 27, minor: 0, patch: 0)
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
enum NativeFixture {
    static var result: Int64 = 42
    static var calls: [(String, String, Bool, Bool)] = []
    static var released: [Int64] = []
}
func worse_query(_ path: String, _ group: String, _ alt: Bool, _ create: Bool) -> Int64 {
    NativeFixture.calls.append((path, group, alt, create))
    return NativeFixture.result
}
func worse_query_release(_ handle: Int64) { NativeFixture.released.append(handle) }
func pathleak(_ path: String, _ maximum: UInt64) -> NSArray? { nil }
enum FixtureFailure: Error { case operation }

@main struct WorseQueryHelperSelfCheck {
    static func main() throws {
        let root = "/var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000001"
        let canonicalRoot = "/private" + root
        precondition(WorseQueryHelper.resolveActiveAppGroup() == "group.esign.rewritten")
        precondition(WorseQueryHelper.isAvailable)
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
        precondition(NativeFixture.released == [42, 42])
        FileManager.default.groupAvailable = false
        precondition(!WorseQueryHelper.isAvailable)
        do {
            _ = try WorseQueryHelper.acquireAccess(for: root)
            preconditionFailure("missing signed group was ignored")
        } catch WorseQueryError.appGroupUnavailable {}
        FileManager.default.groupAvailable = true
        NativeFixture.result = 43
        ProcessInfo.processInfo.operatingSystemVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        let handle = try WorseQueryHelper.acquireAccess(for: "/var/mobile/Containers/Shared/AppGroup/test")
        precondition(NativeFixture.calls.last!.2)
        WorseQueryHelper.releaseAccess(handle: handle)
        print("[PASS] production worse_query helper: rewritten signed group, scope boundaries, root grant, flags, success/error release, daemon errors, missing group")
    }
}
