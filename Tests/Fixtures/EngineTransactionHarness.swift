// Platform/native boundaries only; coordinator, state, persistence and gate
// bodies are extracted unchanged from production by test_engine_transactions.
enum FixtureError: Error { case failed(String), nativeFailure }
enum ExploitSupportPolicy {
    enum Mode { case direct, airLift, unsupported }
    static var currentStorageMode:Mode = .airLift
}
enum AppInfo { static let osBuild="fixture" }
enum WorseQueryError:Error { case unsupportedOS(String) }
enum AirLiftError:LocalizedError {
    case executionFailed(String)
    var requiresRePairing:Bool { false }
    var errorDescription:String? { if case .executionFailed(let value)=self { return value }; return nil }
}
enum PatchPackageCodec {
    static func validate(_ project:PatchProject) throws {}
    static func inspect(_ data:Data) throws -> PatchPackageSummary { throw FixtureError.nativeFailure }
}
enum ContainerStore { static func isApplicationContainerPath(_ path:String) -> Bool { true } }
struct FixturePublisher { func send() {} }
@MainActor enum Fixture {
    static var root=URL(fileURLWithPath:"/unused")
    static var store:PatchEngineApplicationStore { PatchEngineApplicationStore(backupRoot:root) }
    static var writes=0,failBatch:Int?,directWrites=0,restores=0
    static var receipt:PatchTransactionReceipt?
    static var observed:[PatchEngineApplicationRecord]=[]
    static var events:[String]=[]
    static var onWrite:(() async throws -> Void)?
    static var journal:PatchApplicationState?
    static func reset(_ root:URL) {
        // The executable owns an isolated temporary process domain; no device
        // preferences are accessed by this fixture.
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("airlift.applied.") {
            UserDefaults.standard.removeObject(forKey:key)
        }
        self.root=root;writes=0;failBatch=nil;directWrites=0;observed=[];events=[];onWrite=nil;journal=nil;restores=0;receipt=nil
    }
}
@MainActor final class AppIntegrityRuntime {
    static let shared=AppIntegrityRuntime()
    func requireAllowed(force:Bool) async throws {}
}
@MainActor final class NetworkAccessGate {
    static let shared=NetworkAccessGate()
    func requireAllowed() async throws -> UInt64 { 1 }
    func validateGeneration(_ value:UInt64) throws { try Task.checkCancellation() }
}
@MainActor final class AuthManager {
    enum State { case verified, idle }
    var authState:State = .verified
    var authenticationRevision:UInt64=0
}
enum FeaturePatchError:Error { case notAuthenticated }
enum PatchRestoreError:Error { case missingReceipt }
struct PatchItem { let identity:String }
enum WorseQueryHelper {
    static let isAvailable=false
    static func isScopeSupported(for path:String)->Bool { false }
    static func removeItem(at path:String) throws { throw FixtureError.nativeFailure }
}
@MainActor final class AirLiftGatekeeperManager {
    static let shared=AirLiftGatekeeperManager()
    func triggerRePair(reason:String) {}
}
@MainActor final class AirTrafficProtocolClient {
    static let shared=AirTrafficProtocolClient()
    func resolveAppContainer(bundleID:String) async throws -> String { "/fixture/"+bundleID }
    func writeFiles(_ files:[String:Data],targetDirectory:String) async throws {
        Fixture.writes += 1; Fixture.events.append("native-start")
        let records=try FileManager.default.contentsOfDirectory(at:Fixture.root.appendingPathComponent(".engine-applications"),includingPropertiesForKeys:nil)
        for url in records {
            let id=UUID(uuidString:url.deletingPathExtension().lastPathComponent)!
            Fixture.observed.append(try Fixture.store.read(id)!)
        }
        try await Fixture.onWrite?()
        if Fixture.failBatch == Fixture.writes { throw FixtureError.nativeFailure }
        Fixture.events.append("native-end")
    }
}
enum DirectPatchExecutor {
    @MainActor static func run<T>(validation: @escaping @MainActor () throws -> Void,
                                  operation: () throws -> T) async throws -> T {
        try validation(); return try operation()
    }
}
enum IntegrityCommitBarrier { static func withCommit<T>(_ operation:() throws -> T) rethrows -> T { try operation() } }
enum DevicePatchService {
    static func activeTargetKeys() throws -> Set<String> { [] }
    @MainActor static func prepareContainers(bundleIDs:[String]) async throws -> [String:URL] { [:] }
    @MainActor static func apply(project:PatchProject,preparedContainers:[String:URL]?) throws { Fixture.directWrites += 1 }
    @MainActor static func recordedApplicationState(projectID:UUID) -> PatchApplicationState? { Fixture.journal }
    @MainActor static func latestReceipt(projectID:UUID)->PatchTransactionReceipt? { Fixture.receipt }
    @MainActor static func prepareContainers(receipt:PatchTransactionReceipt) async throws -> [String:URL] { [:] }
    @MainActor static func restore(receipt:PatchTransactionReceipt,allowChangedTargets:Bool,preparedContainers:[String:URL]) throws {
        Fixture.restores += 1;Fixture.journal = .off
        if var record=try Fixture.store.read(receipt.projectID) { record.phase = .restored; try Fixture.store.save(record) }
    }
}
