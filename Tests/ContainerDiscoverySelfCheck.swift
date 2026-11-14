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
final class FileManager {
    static let `default` = FileManager()
    var temporaryDirectory: URL { Foundation.FileManager.default.temporaryDirectory }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        precondition(DiscoveryFixture.active.values.contains(path), "directory read without this UUID grant")
        if DiscoveryFixture.readDenied { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        return []
    }
    func urls(for directory: Foundation.FileManager.SearchPathDirectory, in domain: Foundation.FileManager.SearchPathDomainMask) -> [URL] {
        Foundation.FileManager.default.urls(for: directory, in: domain)
    }
    func removeItem(at url: URL) throws { try Foundation.FileManager.default.removeItem(at: url) }
    func createDirectory(at url: URL, withIntermediateDirectories value: Bool) throws {
        try Foundation.FileManager.default.createDirectory(at: url, withIntermediateDirectories: value)
    }
}

enum UserDefaults {
    static let suite = "astra-ios27-fixture-" + UUID().uuidString
    static let standard = Foundation.UserDefaults(suiteName: suite)!
}
enum DiscoveryFixture {
    static let gameID = "com.fixture.first", maxID = "com.fixture.second"
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
    static var preflightFailed = false, localLinkFailed = false, readDenied = false
    static var onlyFirst = false, duplicateFirst = false
    static var mcmPaths: [String: String] = [:], lsPaths: [String: String] = [:]
    static var lookupCalls: [String] = []
    static var identityUnavailable = false, cancelDuringLookup = false
    static func reset(clearCache: Bool = true) {
        ranges = []; active = [:]; next = 1; calls = 0; legacyCalls = 0
        reject = false; noMatch = false; setupError = false; missingGroup = false; cancel = false; ranOnMain = false
        preflightFailed = false; localLinkFailed = false; readDenied = false; onlyFirst = false; duplicateFirst = false
        mcmPaths = [:]; lsPaths = [:]; lookupCalls = []
        identityUnavailable = false; cancelDuringLookup = false
        if clearCache { UserDefaults.standard.removePersistentDomain(forName: UserDefaults.suite) }
        IOS27ContainerSession.reset()
    }
}

func MCMContainerPathForWorseQuery(_ cls: UInt64, _ bundleID: String, _ group: Bool,
                                  _ error: UnsafeMutablePointer<NSString?>?) -> String? {
    precondition(!Thread.isMainThread && cls == 2 && !group)
    DiscoveryFixture.lookupCalls.append("mcm:" + bundleID)
    if DiscoveryFixture.cancelDuringLookup { DiscoveryFixture.progress.requestCancellation() }
    return DiscoveryFixture.mcmPaths[bundleID]
}
func containerPathForBundleID(_ bundleID: String) -> String? {
    precondition(!Thread.isMainThread)
    DiscoveryFixture.lookupCalls.append("ls:" + bundleID)
    return DiscoveryFixture.lsPaths[bundleID]
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
    static func resolveActiveAppGroup() -> String? { "group.fixture" }
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
        for (inode, path) in [(UInt64(20), DiscoveryFixture.other), (DiscoveryFixture.duplicateFirst ? 25 : 2_000_000, DiscoveryFixture.game), (2_050_000, DiscoveryFixture.max)] {
            if DiscoveryFixture.onlyFirst && path == DiscoveryFixture.max { continue }
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
    if DiscoveryFixture.identityUnavailable { errno = ENOATTR; return -1 }
    let identifier = DiscoveryFixture.noMatch ? "com.fixture.other" : (DiscoveryFixture.duplicateFirst && path == DiscoveryFixture.other) ? DiscoveryFixture.gameID : path == DiscoveryFixture.game ? DiscoveryFixture.gameID : path == DiscoveryFixture.max ? DiscoveryFixture.maxID : "com.fixture.other"
    let bytes = Array(identifier.utf8) + [0]
    if value == nil { return bytes.count - 1 }
    precondition(bytes.count - 1 <= size)
    Array(bytes.dropLast()).withUnsafeBytes { value!.copyMemory(from: $0.baseAddress!, byteCount: bytes.count - 1) }
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
        // Actual production preparation with the WQ02 device boundary: metadata
        // unavailable while a Bundle-ID lookup and granted directory read work.
        DiscoveryFixture.reset()
        DiscoveryFixture.identityUnavailable = true
        DiscoveryFixture.mcmPaths[DiscoveryFixture.gameID] = DiscoveryFixture.game
        var roots = try await Task.detached {
            try ContainerStore.prepareIOS27Access(bundleIDs: [DiscoveryFixture.gameID])
        }.value
        precondition(roots[DiscoveryFixture.gameID] == DiscoveryFixture.game && DiscoveryFixture.ranges.isEmpty)
        precondition(DiscoveryFixture.active.isEmpty && DiscoveryFixture.calls == 1)
        precondition(DiscoveryFixture.lookupCalls == ["mcm:" + DiscoveryFixture.gameID])

        // Persisted UUID alone is still insufficient; it must be rebound by an
        // exact current lookup or independently readable identifier.
        DiscoveryFixture.reset(clearCache: false)
        DiscoveryFixture.identityUnavailable = true
        DiscoveryFixture.lsPaths[DiscoveryFixture.gameID] = DiscoveryFixture.game
        roots = try await Task.detached {
            try ContainerStore.prepareIOS27Access(bundleIDs: [DiscoveryFixture.gameID])
        }.value
        precondition(roots[DiscoveryFixture.gameID] == DiscoveryFixture.game && DiscoveryFixture.ranges.isEmpty)
        precondition(DiscoveryFixture.calls == 2 && DiscoveryFixture.active.isEmpty)
        precondition(DiscoveryFixture.lookupCalls == ["mcm:" + DiscoveryFixture.gameID, "ls:" + DiscoveryFixture.gameID])

        DiscoveryFixture.reset()
        DiscoveryFixture.identityUnavailable = true
        DiscoveryFixture.mcmPaths[DiscoveryFixture.gameID] = DiscoveryFixture.game
        DiscoveryFixture.readDenied = true
        do {
            _ = try await Task.detached { try ContainerStore.prepareIOS27Access(bundleIDs: [DiscoveryFixture.gameID]) }.value
            preconditionFailure("Bundle-ID lookup replaced a required directory read")
        } catch { precondition(DiscoveryFixture.active.isEmpty) }

        DiscoveryFixture.reset()
        DiscoveryFixture.mcmPaths[DiscoveryFixture.gameID] = DiscoveryFixture.max
        DiscoveryFixture.onlyFirst = true
        roots = try await Task.detached { try ContainerStore.prepareIOS27Access(bundleIDs: [DiscoveryFixture.gameID]) }.value
        precondition(roots[DiscoveryFixture.gameID] == DiscoveryFixture.game && !DiscoveryFixture.ranges.isEmpty,
                     "conflicting MCM identity was accepted instead of scan fallback")

        DiscoveryFixture.reset()
        DiscoveryFixture.identityUnavailable = true
        DiscoveryFixture.mcmPaths = [DiscoveryFixture.gameID: DiscoveryFixture.game, DiscoveryFixture.maxID: DiscoveryFixture.game]
        do {
            _ = try await Task.detached {
                try ContainerStore.prepareIOS27Access(bundleIDs: [DiscoveryFixture.gameID, DiscoveryFixture.maxID])
            }.value
            preconditionFailure("one root accepted for two applications")
        } catch { precondition(DiscoveryFixture.active.isEmpty) }

        DiscoveryFixture.reset()
        DiscoveryFixture.mcmPaths[DiscoveryFixture.gameID] = DiscoveryFixture.game
        DiscoveryFixture.cancelDuringLookup = true
        do {
            _ = try await Task.detached { try ContainerStore.prepareIOS27Access(bundleIDs: [DiscoveryFixture.gameID]) }.value
            preconditionFailure("cancelled lookup continued to grant")
        } catch { precondition(DiscoveryFixture.calls == 0 && DiscoveryFixture.active.isEmpty) }

        DiscoveryFixture.reset()
        let preparation = IOS27ContainerPreparation(progress: DiscoveryFixture.progress, operation: { try ContainerStore.prepareIOS27Access(bundleIDs: $0, forceScan: $1) })
        preparation.configureTargets(bundleIDs: [DiscoveryFixture.gameID, DiscoveryFixture.maxID])
        precondition(preparation.state == .idle && !preparation.didContinue)
        preparation.enterApplication()
        precondition(!preparation.didContinue, "gate allowed entry before preparation")
        await preparation.prepareIfNeeded()
        await drain()
        precondition(preparation.state == .ready && !preparation.didContinue)
        precondition(!DiscoveryFixture.ranOnMain && DiscoveryFixture.legacyCalls == 0)
        precondition(DiscoveryFixture.ranges.first!.0 == 1 && DiscoveryFixture.ranges.last!.1 == 2_000_000)
        for index in 1..<DiscoveryFixture.ranges.count { precondition(DiscoveryFixture.ranges[index].0 == DiscoveryFixture.ranges[index - 1].1 + 1) }
        precondition(DiscoveryFixture.active.isEmpty)
        preparation.enterApplication()
        precondition(preparation.didContinue)
        precondition(IOS27ContainerSession.path(for: DiscoveryFixture.maxID) == nil,
                     "initial gate unnecessarily scanned for every optional app")
        try await preparation.prepareAdditionalTargets(bundleIDs: [DiscoveryFixture.gameID, DiscoveryFixture.maxID])
        precondition(IOS27ContainerSession.path(for: DiscoveryFixture.gameID) == DiscoveryFixture.game && DiscoveryFixture.legacyCalls == 0)
        precondition(IOS27ContainerSession.path(for: DiscoveryFixture.maxID) == DiscoveryFixture.max,
                     "cached first target short-circuited the installed second target")

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

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.onlyFirst = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .ready && IOS27ContainerSession.path(for: DiscoveryFixture.gameID) != nil,
                     "one absent optional application blocked the installed target")
        precondition(IOS27ContainerSession.path(for: DiscoveryFixture.maxID) == nil)
        preparation.enterApplication()
        do {
            try await preparation.prepareAdditionalTargets(bundleIDs: [DiscoveryFixture.maxID])
            preconditionFailure("missing requested application became prepared")
        } catch WorseQueryError.containerDiscoveryFailed {}
        precondition(preparation.didContinue && IOS27ContainerSession.path(for: DiscoveryFixture.gameID) != nil,
                     "failed additional target erased the already verified session")

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

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.readDenied = true
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && DiscoveryFixture.progress.snapshot.grants == 3)
        precondition(DiscoveryFixture.progress.snapshot.readable == 0 && DiscoveryFixture.progress.snapshot.identified == 3)
        precondition(IOS27ContainerSession.path(for: DiscoveryFixture.gameID) == nil)

        preparation.reset(); DiscoveryFixture.reset(); DiscoveryFixture.duplicateFirst = true
        preparation.configureTargets(bundleIDs: [DiscoveryFixture.gameID])
        await preparation.prepareIfNeeded(force: true); await drain()
        precondition(preparation.state == .failed && IOS27ContainerSession.path(for: DiscoveryFixture.gameID) == nil,
                     "duplicate container identifiers selected an arbitrary UUID")
        precondition(DiscoveryFixture.progress.shareText.contains("nhiều UUID"))
        preparation.configureTargets(bundleIDs: [DiscoveryFixture.gameID, DiscoveryFixture.maxID])

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
        let interruptedGate = IOS27ContainerPreparation(progress: interruptedProgress, operation: { _, _ in
            restarted.set()
            return [DiscoveryFixture.gameID: DiscoveryFixture.game]
        })
        interruptedGate.configureTargets(bundleIDs: [DiscoveryFixture.gameID])
        await interruptedGate.prepareIfNeeded()
        precondition(interruptedGate.state == .failed && !restarted.value && !interruptedGate.didContinue)
        await interruptedGate.prepareIfNeeded(force: true)
        precondition(interruptedGate.state == .ready && restarted.value && !interruptedGate.didContinue)
        print("[PASS] actual preparation gate: \(AppInfo.versionTuple.major).\(AppInfo.versionTuple.minor).\(AppInfo.versionTuple.patch), Bundle-ID lookup before inode fallback, missing/conflicting identity, cache revalidation, per-UUID tokens, off-main, failure/cancel blocks entry and patch")
    }
}
