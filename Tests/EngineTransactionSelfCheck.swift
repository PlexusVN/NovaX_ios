import Foundation

@main struct EngineTransactionSelfCheck {
    static var checks=0
    static func check(_ value: @autoclosure () throws -> Bool,_ message:String) throws {
        guard try value() else { throw FixtureError.failed(message) }; checks += 1
    }
    static func project() -> PatchProject {
        PatchProject(name:"fixture",rules:[
            PatchRule(bundleID:"com.fixture.app",relativePath:"a/file",replacementFilename:"file",replacementData:Data([1])),
            PatchRule(bundleID:"com.fixture.app",relativePath:"b/file",replacementFilename:"file",replacementData:Data([2]))])
    }
    @MainActor static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("astra-engine-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        func setup() { Fixture.reset(root.appendingPathComponent(UUID().uuidString)) }
        setup()
        let id=UUID(),journalID=UUID(),targets=["com.fixture.app\0a/file"]
        var direct=PatchEngineApplicationRecord(projectID:id,engine:.worseQuery,baseline:.capturedPriorState,targetKeys:targets,journalID:journalID,phase:.applied)
        try check(PatchEngineApplicationStore.reconcile(record:direct,journal:.applied,legacyAirLift:true) == .applied,"bound direct provenance outranks historical preference")
        try check(PatchEngineApplicationStore.reconcile(record:nil,journal:.applied,legacyAirLift:true) == .recoveryRequired,"legacy direct/AL conflict is ambiguous")
        do { try PatchEngineApplicationStore.requireDirectRestore(record:nil,receiptID:journalID,journal:.applied,legacyAirLift:true);throw FixtureError.failed("legacy ambiguity accepted") }
        catch PatchEngineStateError.legacyAmbiguous {}
        try PatchEngineApplicationStore.requireDirectRestore(record:direct,receiptID:journalID,journal:.applied,legacyAirLift:true)
        try check(PatchEngineApplicationStore.reconcile(record:direct,journal:.off,legacyAirLift:true) == .off,"restored journal is not resurrected by AL boolean")
        do { try PatchEngineApplicationStore.requireDirectRestore(record:direct,receiptID:UUID(),journal:.applied,legacyAirLift:false);throw FixtureError.failed("wrong receipt accepted") }
        catch PatchEngineStateError.invalidRecord {}
        direct.phase = .writing
        try Fixture.store.save(direct)
        try check(try Fixture.store.read(id)==direct,"provenance survives persistence/reconstruction")
        let coordinator=StorageEngineCoordinator()
        do {
            let unknownID=UUID(),unknownKey="airlift.applied.\(UUID().uuidString)"
            UserDefaults.standard.set(true,forKey:unknownKey)
            do { try await coordinator.applyPatchProject(project());throw FixtureError.failed("different project bypassed unknown legacy history") }
            catch PatchEngineStateError.legacyTargetsUnknown {}
            try check(Fixture.writes==0 && UserDefaults.standard.bool(forKey:unknownKey),"unknown legacy targets block new baselines without deleting history")
            UserDefaults.standard.removeObject(forKey:unknownKey)
            let knownKey="airlift.applied.\(unknownID.uuidString)"
            UserDefaults.standard.set(true,forKey:knownKey)
            let known=PatchEngineApplicationRecord(projectID:unknownID,engine:.airLift,baseline:.unavailable,
                targetKeys:["com.other.app\0unrelated"],phase:.applied,totalBatches:1)
            try Fixture.store.save(known)
            try Fixture.store.requireResolvedLegacyHistory()
            try Fixture.store.requireNoUnbackedOverlap(projectID:UUID(),targetKeys:targets)
            try check(UserDefaults.standard.bool(forKey:knownKey),"known unrelated AirLift history uses target overlap without global denial")
            UserDefaults.standard.removeObject(forKey:knownKey)
        }
        do {
            var patch=project();patch.rules[0].relativePath="a/file"
            do { try await coordinator.applyPatchProject(patch);throw FixtureError.failed("AirLift overwrote direct transaction") }
            catch PatchEngineStateError.recoveryRequired {}
            try check(Fixture.writes==0,"AirLift cannot overwrite a backed direct transaction")
        }
        for failed in [1,2] {
            setup();let patch=project();Fixture.failBatch=failed
            do { try await coordinator.applyPatchProject(patch);throw FixtureError.failed("native failure ignored") }
            catch is FixtureError {} catch is AirLiftError {}
            let record=try Fixture.store.read(patch.id)!
            try check(record.phase == .recoveryRequired && record.completedBatches==failed-1,"partial or unknown first batch remains recovery-required")
            try check(Fixture.observed.allSatisfy{$0.phase == .writing},"writing record exists BEFORE every dispatch")
            try check(coordinator.projectApplicationState(patch.id) == .recoveryRequired,"partial AirLift never displays OFF")
            let writes=Fixture.writes
            do { try await coordinator.applyPatchProject(patch);throw FixtureError.failed("unbacked reapply permitted") }
            catch PatchEngineStateError.recoveryRequired {}
            try check(Fixture.writes==writes,"unresolved AirLift cannot be reapplied")
        }
        setup();let success=project()
        try await coordinator.applyPatchProject(success)
        let successful=try Fixture.store.read(success.id)!
        try check(successful.phase == .applied && successful.completedBatches==2,"success records all acknowledged batches")
        do { try PatchEngineApplicationStore.requireDirectRestore(record:successful,receiptID:nil,journal:nil,legacyAirLift:false);throw FixtureError.failed("AL invents originals") }
        catch PatchEngineStateError.airLiftNoBackup {}
        do { try Fixture.store.requireNoUnbackedOverlap(projectID:UUID(),targetKeys:successful.targetKeys);throw FixtureError.failed("new project overwrites AL baseline") }
        catch PatchEngineStateError.recoveryRequired {}
        for onlyDirectory in [false,true] {
            setup();var patch=project();patch.directories=[PatchDirectory(bundleID:"com.fixture.app",relativePath:"empty")]
            if onlyDirectory { patch.rules=[] }
            do { try await coordinator.applyPatchProject(patch);throw FixtureError.failed("empty directory silently ignored") }
            catch PatchEngineStateError.unsupportedAirLiftDirectory {}
            try check(Fixture.writes==0 && !FileManager.default.fileExists(atPath:Fixture.root.path),"capability failure precedes storage/native effects")
        }
        setup();var parent=project();parent.directories=[PatchDirectory(bundleID:"com.fixture.app",relativePath:"a")]
        try await coordinator.applyPatchProject(parent)
        try check(Fixture.writes==2,"AL accepts directories represented by payload parents")
        setup();ExploitSupportPolicy.currentStorageMode = .direct
        try await coordinator.applyPatchProject(project())
        try check(Fixture.directWrites==1 && Fixture.writes==0,"direct dispatch never enters AirLift")
        ExploitSupportPolicy.currentStorageMode = .airLift
        setup()
        let first=project()
        var second=project()
        second.rules[0].relativePath="c/file"; second.rules[1].relativePath="d/file"
        Fixture.onWrite={
            try await Task.sleep(nanoseconds:10_000_000)
        }
        async let one:Void=coordinator.applyPatchProject(first)
        let secondProject=second
        async let two:Void=coordinator.applyPatchProject(secondProject)
        _ = try await (one,two)
        try check(Fixture.events == ["native-start","native-end","native-start","native-end","native-start","native-end","native-start","native-end"],"filesystem operations serialize across native awaits")
        let held=try await PatchFilesystemGate.shared.acquire()
        let waiting=Task { @MainActor in try await coordinator.applyPatchProject(project()) }
        await Task.yield();waiting.cancel()
        do { try await waiting.value;throw FixtureError.failed("cancelled waiter entered filesystem") }
        catch is CancellationError {}
        await PatchFilesystemGate.shared.release(held)
        try check(Fixture.writes==4,"cancelled waiter never dispatches")
        setup();ExploitSupportPolicy.currentStorageMode = .direct
        let catalog=FeaturePatchService(),auth=AuthManager(),catalogProject=UUID(),catalogReceipt=UUID()
        let item=PatchItem(identity:"test_"+UUID().uuidString)
        let legacyKey="airlift.applied.\(catalogProject.uuidString)"
        UserDefaults.standard.set(true,forKey:legacyKey)
        defer { UserDefaults.standard.removeObject(forKey:legacyKey);catalog.catalogApplications.clear(item.identity) }
        catalog.catalogApplications.associate(catalogProject,with:item.identity)
        catalog.catalogApplications.markApplied(item.identity)
        Fixture.journal = .applied
        Fixture.receipt=PatchTransactionReceipt(id:catalogReceipt,projectID:catalogProject,journalURL:Fixture.root.appendingPathComponent("journal.plist"))
        try check(catalog.patchApplicationState(item) == .recoveryRequired,"actual catalog exposes ambiguous legacy provenance")
        do { try await catalog.restorePatch(item,auth:auth);throw FixtureError.failed("actual legacy conflict restored") }
        catch PatchEngineStateError.legacyAmbiguous {}
        try check(Fixture.restores==0 && catalog.catalogApplications.projectID(for:item.identity)==catalogProject,"ambiguous restore preserves original association")
        let catalogRecord=PatchEngineApplicationRecord(projectID:catalogProject,engine:.worseQuery,baseline:.capturedPriorState,
            targetKeys:targets,journalID:catalogReceipt,phase:.applied)
        try Fixture.store.save(catalogRecord)
        try await catalog.restorePatch(item,auth:auth)
        try check(Fixture.restores==1 && catalog.patchApplicationState(item) == .off,"actual bound direct restore succeeds despite historical AL boolean")
        try check(UserDefaults.standard.bool(forKey:legacyKey),"migration retains historical AirLift evidence")
        print("Actual coordinator/provenance/gate: \(checks) checks passed")
    }
}
