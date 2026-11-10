import Foundation
import Darwin

// The resolver loop, canonical path logic, bundle validator and detached
// preparation are extracted from production by the Python runner. Only OS and
// token providers are fixtures. No file is written outside the test defaults.
enum PatchPackageError: Error {
    case invalidBundleIdentifier
    case targetAppUnavailable(String)
}
enum DiscoveryFixture {
    static let gameID = "com.fixture.discovery.game"
    static let otherID = "com.fixture.discovery.other"
    static let game = "/private/var/mobile/Containers/Data/Application/CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
    static let other = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    static var ranges: [(UInt64, UInt64)] = []
    static var active: [Int64: String] = [:]
    static var nextHandle: Int64 = 1
    static var rejectGrants = false
    static var noMatch = false
    static var setupError = false
    static var ranOnMain = false
    static func reset() {
        ranges = []; active = [:]; nextHandle = 1
        rejectGrants = false; noMatch = false; setupError = false; ranOnMain = false
    }
}
enum WorseQueryHelper {
    static func currentFilesystemMaxInode() throws -> UInt64 { 2_100_000 }
    static func enumeratePaths(in path: String, from first: UInt64, through last: UInt64) throws -> [String] {
        DiscoveryFixture.ranOnMain = DiscoveryFixture.ranOnMain || Thread.isMainThread
        if DiscoveryFixture.setupError { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        DiscoveryFixture.ranges.append((first, last))
        var result: [String] = []
        if first <= 20 && last >= 20 { result.append(DiscoveryFixture.other) }
        if first <= 2_000_000 && last >= 2_000_000 { result.append(DiscoveryFixture.game) }
        return result
    }
    static func acquireAccess(for path: String) throws -> Int64 {
        if DiscoveryFixture.rejectGrants { throw WorseQueryError.queryRejected }
        let handle = DiscoveryFixture.nextHandle; DiscoveryFixture.nextHandle += 1
        DiscoveryFixture.active[handle] = path
        return handle
    }
    static func releaseAccess(handle: Int64) { DiscoveryFixture.active.removeValue(forKey: handle) }
}
func getxattr(_ path: String, _ name: String, _ value: UnsafeMutableRawPointer?,
              _ size: Int, _ position: UInt32, _ options: Int32) -> Int {
    precondition(DiscoveryFixture.active.values.contains(path), "identifier read before granting this UUID container")
    let id = path == DiscoveryFixture.game && !DiscoveryFixture.noMatch
        ? DiscoveryFixture.gameID : DiscoveryFixture.otherID
    let bytes = Array(id.utf8) + [0]
    precondition(bytes.count <= size)
    bytes.withUnsafeBytes { value!.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
    return bytes.count - 1
}
func log(_ line: String) {}

@main struct ContainerDiscoverySelfCheck {
    @MainActor static func main() async throws {
        defer {
            for id in [DiscoveryFixture.gameID, DiscoveryFixture.otherID] {
                UserDefaults.standard.removeObject(forKey: "astra.resolved_container.\(id)")
            }
        }
        let roots = try await DevicePatchService.prepareContainers(bundleIDs: [DiscoveryFixture.gameID])
        precondition(roots[DiscoveryFixture.gameID]?.path == DiscoveryFixture.game)
        precondition(!DiscoveryFixture.ranOnMain, "MainActor service still scans on the UI thread")
        precondition(DiscoveryFixture.ranges.last!.1 >= 2_000_000)
        precondition(DiscoveryFixture.ranges.first!.0 == 1)
        for index in 1..<DiscoveryFixture.ranges.count {
            precondition(DiscoveryFixture.ranges[index].0 == DiscoveryFixture.ranges[index - 1].1 + 1)
        }
        precondition(DiscoveryFixture.active.isEmpty, "matched container leaked its temporary discovery grant")
        DiscoveryFixture.reset(); DiscoveryFixture.noMatch = true
        do {
            _ = try await DevicePatchService.prepareContainers(bundleIDs: [DiscoveryFixture.gameID])
            preconditionFailure("unmatched metadata was accepted")
        } catch WorseQueryError.containerDiscoveryFailed(let id) { precondition(id == DiscoveryFixture.gameID) }
        precondition(DiscoveryFixture.ranges.last!.1 == 2_100_000, "discovery silently truncated the baseline range")
        precondition(DiscoveryFixture.active.isEmpty)
        DiscoveryFixture.reset(); DiscoveryFixture.rejectGrants = true
        do {
            _ = try await DevicePatchService.prepareContainers(bundleIDs: [DiscoveryFixture.gameID])
            preconditionFailure("token errors collapsed to missing app")
        } catch WorseQueryError.queryRejected {}
        DiscoveryFixture.reset(); DiscoveryFixture.setupError = true
        do {
            _ = try await DevicePatchService.prepareContainers(bundleIDs: [DiscoveryFixture.gameID])
            preconditionFailure("filesystem setup error was hidden")
        } catch let error as NSError { precondition(error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES)) }
        precondition(DiscoveryFixture.active.isEmpty)
        print("[PASS] production discovery/preparation: high inode, all chunks, per-UUID grants, metadata match, cleanup, errors and off-MainActor execution")
    }
}
