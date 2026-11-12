import Foundation
import Darwin

enum PatchPackageError: Error { case invalidBundleIdentifier; case targetAppUnavailable(String) }
enum AppInfo {
    static let osBuild = "24A-fixture"
    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }
}
enum ProcessInfo {
    static var processInfo = FixtureProcessInfo()
    struct FixtureProcessInfo { var operatingSystemVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1) }
}
enum UserDefaults {
    static let suite = "astra-ios27-fixture-" + UUID().uuidString
    static let standard = Foundation.UserDefaults(suiteName: suite)!
}
enum DiscoveryFixture {
    static let gameID = "com.dts.freefireth", maxID = "com.dts.freefiremax"
    static let game = "/private/var/mobile/Containers/Data/Application/CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
    static let max = "/private/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    static let other = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    static let progress = ContainerScanProgress(historyURL: nil)
    static var ranges: [(UInt64, UInt64)] = []
    static var active: [Int64: String] = [:]
    static var next: Int64 = 1
    static var calls = 0, legacyCalls = 0
    static var reject = false, noMatch = false, setupError = false, missingGroup = false, cancel = false
    static var ranOnMain = false
    static var preflightFailed = false, localLinkFailed = false
    static func reset(clearCache: Bool = true) {
        ranges = []; active = [:]; next = 1; calls = 0; legacyCalls = 0
        reject = false; noMatch = false; setupError = false; missingGroup = false; cancel = false; ranOnMain = false
        preflightFailed = false; localLinkFailed = false
        if clearCache { UserDefaults.standard.removePersistentDomain(forName: UserDefaults.suite) }
        IOS27ContainerSession.reset()
    }
}
enum WorseQueryHelper {
    static let preparationContext = "fixture signed groups"
    static let nativeDiagnostics = "stage=create_Caches_symlink domain=NSPOSIXErrorDomain code=13"
    static func preparationDiagnostics() throws -> String {
        precondition(!Thread.isMainThread)
        if DiscoveryFixture.preflightFailed { throw WorseQueryError.localFilesystemFailure("preflight denied: NSPOSIXErrorDomain code=13") }
        return "preflight passed"
    }
    static func invalidateActiveAppGroup() {}
    static let isOSSupported = true
    static var isAppGroupConfigured: Bool { !DiscoveryFixture.missingGroup }
    static let isAvailable = true
    static func currentFilesystemMaxInode() throws -> UInt64 { 2_100_000 }
    static func enumeratePaths(in path: String, from first: UInt64, through last: UInt64) throws -> [String] {
        DiscoveryFixture.ranOnMain = DiscoveryFixture.ranOnMain || Thread.isMainThread
        if DiscoveryFixture.setupError { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        DiscoveryFixture.ranges.append((first, last))
        if DiscoveryFixture.cancel { DiscoveryFixture.progress.requestCancellation() }
        var paths: [String] = []
        for (inode, path) in [(UInt64(20), DiscoveryFixture.other), (2_000_000, DiscoveryFixture.game), (2_050_000, DiscoveryFixture.max)] {
            if first <= inode && last >= inode { paths.append(path) }
        }
        return paths
    }
    static func acquireAccess(for path: String) throws -> Int64 {
        precondition(!Thread.isMainThread, "native query executed on main thread")
        DiscoveryFixture.calls += 1
        if DiscoveryFixture.localLinkFailed { throw WorseQueryError.localFilesystemFailure(nativeDiagnostics) }
        if DiscoveryFixture.reject { throw WorseQueryError.queryRejected }
        let handle = DiscoveryFixture.next; DiscoveryFixture.next += 1
        DiscoveryFixture.active[handle] = path
        return handle
    }
    static func releaseAccess(handle: Int64) { DiscoveryFixture.active.removeValue(forKey: handle) }
}
func getxattr(_ path: String, _ name: String, _ value: UnsafeMutableRawPointer?, _ size: Int, _ position: UInt32, _ options: Int32) -> Int {
    precondition(DiscoveryFixture.active.values.contains(path), "read identifier before consuming this UUID's token")
    let identifier = DiscoveryFixture.noMatch ? "com.fixture.other" : path == DiscoveryFixture.game ? DiscoveryFixture.gameID : path == DiscoveryFixture.max ? DiscoveryFixture.maxID : "com.fixture.other"
    let bytes = Array(identifier.utf8) + [0]
    precondition(bytes.count <= size)
    bytes.withUnsafeBytes { value!.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
    return bytes.count - 1
}
func log(_ line: String) {}
final class RestartFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

@main struct ContainerDiscoverySelfCheck {
    @MainActor static func drain() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }
    @MainActor static func main() async throws {
        for (major,minor,patch) in [(26,6,2),(26,7,0),(26,7,2),(27,0,1)] {
            ProcessInfo.processInfo.operatingSystemVersion = OperatingSystemVersion(majorVersion:major,minorVersion:minor,patchVersion:patch)
            DiscoveryFixture.reset()
            try await checkVersion()
        }
    }
    @MainActor static func checkVersion() async throws {
        defer { UserDefaults.standard.removePersistentDomain(forName: UserDefaults.suite); IOS27ContainerSession.reset() }
        let preparation = IOS27ContainerPreparation(progress: DiscoveryFixture.progress, operation: { try ContainerStore.prepareIOS27Access(forceScan: $0) })
        precondition(preparation.state == .idle && !preparation.didContinue)
        preparation.enterApplication()
        precondition(!preparation.didContinue, "gate allowed entry before preparation")
        await preparation.prepareIfNeeded()
        await drain()
        precondition(preparation.state == .ready && !preparation.didContinue)
        precondition(!DiscoveryFixture.ranOnMain && DiscoveryFixture.legacyCalls == 0)
        precondition(DiscoveryFixture.ranges.first!.0 == 1 && DiscoveryFixture.ranges.last!.1 >= 2_050_000)
        for index in 1..<DiscoveryFixture.ranges.count { precondition(DiscoveryFixture.ranges[index].0 == DiscoveryFixture.ranges[index - 1].1 + 1) }
        precondition(DiscoveryFixture.active.isEmpty)
        preparation.enterApplication()
        precondition(preparation.didContinue)
        let roots = try await DevicePatchService.prepareContainers(bundleIDs: [DiscoveryFixture.gameID])
        precondition(roots[DiscoveryFixture.gameID]?.path == DiscoveryFixture.game && DiscoveryFixture.legacyCalls == 0)

        preparation.reset(); DiscoveryFixture.reset(clearCache: false)
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .ready && DiscoveryFixture.ranges.isEmpty)
        precondition(DiscoveryFixture.calls == 2, "cache bypassed real token/identifier verification")

        preparation.reset(); DiscoveryFixture.reset(clearCache: false)
        UserDefaults.standard.removeObject(forKey: "astra.resolved_container.\(DiscoveryFixture.maxID)")
        await preparation.prepareIfNeeded(); await drain()
        precondition(preparation.state == .ready && DiscoveryFixture.ranges.isEmpty && DiscoveryFixture.calls == 1,
                     "single installed game caused a full scan on every launch")
        preparation.reset(forceScan: true); DiscoveryFixture.reset(clearCache: false)
        await preparation.prepareIfNeeded(); await drain()
        precondition(preparation.state == .ready && !DiscoveryFixture.ranges.isEmpty && IOS27ContainerSession.path(for: DiscoveryFixture.maxID) != nil,
                     "explicit rescan could not discover a newly installed variant")

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.missingGroup = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && !preparation.didContinue)
        preparation.enterApplication(); precondition(!preparation.didContinue)
        precondition(DiscoveryFixture.calls == 0 && DiscoveryFixture.ranges.isEmpty)

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.preflightFailed = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && !preparation.didContinue)
        precondition(DiscoveryFixture.calls == 0 && DiscoveryFixture.ranges.isEmpty,
                     "failed local write probe still scanned the entire filesystem")
        precondition(DiscoveryFixture.progress.shareText.contains("NSPOSIXErrorDomain code=13"))

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.localLinkFailed = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && !preparation.didContinue)
        precondition(DiscoveryFixture.calls == 1 && DiscoveryFixture.ranges.count == 1,
                     "global Caches failure retried on every unrelated container")
        precondition(DiscoveryFixture.progress.snapshot.candidates == 1 && DiscoveryFixture.progress.snapshot.grants == 0)
        precondition(DiscoveryFixture.progress.shareText.contains("stage=create_Caches_symlink"))

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.reject = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && IOS27ContainerSession.path(for: DiscoveryFixture.gameID) == nil)
        precondition(DiscoveryFixture.progress.snapshot.detail.contains("query"))

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.noMatch = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && DiscoveryFixture.ranges.last!.1 == 2_100_000)

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.cancel = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && !preparation.didContinue && DiscoveryFixture.active.isEmpty)
        precondition(DiscoveryFixture.progress.snapshot.phase == .cancelled)
        do { _ = try ContainerStore.resolveAppContainerForPatch(bundleID: DiscoveryFixture.gameID); preconditionFailure("patch bypassed preparation") }
        catch WorseQueryError.preparationRequired {}
        precondition(DiscoveryFixture.legacyCalls == 0)
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("astra-gate-interrupted-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: history) }
        let previous = ContainerScanSnapshot(id: UUID(), bundleID: DiscoveryFixture.gameID, phase: .scanning)
        try JSONEncoder().encode(previous).write(to: history)
        let interruptedProgress = ContainerScanProgress(historyURL: history)
        let restarted = RestartFlag()
        let interruptedGate = IOS27ContainerPreparation(progress: interruptedProgress, operation: { _ in
            restarted.set()
            return [DiscoveryFixture.gameID: DiscoveryFixture.game]
        })
        await interruptedGate.prepareIfNeeded()
        precondition(interruptedGate.state == .failed && !restarted.value && !interruptedGate.didContinue)
        await interruptedGate.prepareIfNeeded(force: true)
        precondition(interruptedGate.state == .ready && restarted.value && !interruptedGate.didContinue)
        print("[PASS] actual preparation gate: \(AppInfo.versionTuple.major).\(AppInfo.versionTuple.minor).\(AppInfo.versionTuple.patch), high inodes, both games, cache revalidation, no legacy MCM/LS, per-UUID tokens, off-main, missing group, failure/cancel blocks entry and patch")
    }
}
