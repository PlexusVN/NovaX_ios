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

        // Actual disable API: desired OFF is independent of the retained
        // filesystem recovery obligation, association and backup evidence.
        func disableFixture(_ label:String) throws -> (FeaturePatchService,AuthManager,PatchItem,UUID,[URL:Data]) {
            setup();ExploitSupportPolicy.currentStorageMode = .direct
            let service=FeaturePatchService(),auth=AuthManager()
            let item=PatchItem(identity:"fixture_disable_"+label+"_"+UUID().uuidString)
            let projectID=UUID(),receiptID=UUID()
            try FileManager.default.createDirectory(at:Fixture.root,withIntermediateDirectories:true)
            let journalURL=Fixture.root.appendingPathComponent("fixture-journal.plist")
            let backupURL=Fixture.root.appendingPathComponent("fixture-original.backup")
            let targetURL=Fixture.root.appendingPathComponent("fixture-target.data")
            let packageURL=Fixture.root.appendingPathComponent(item.identity+".3105")
            try Data("fixture journal requiring recovery".utf8).write(to:journalURL)
            try Data("fixture retained original bytes".utf8).write(to:backupURL)
            try Data("fixture possibly patched target".utf8).write(to:targetURL)
            try Data("fixture retained catalog package".utf8).write(to:packageURL)
            Fixture.receipt=PatchTransactionReceipt(id:receiptID,projectID:projectID,journalURL:journalURL)
            Fixture.journal = .recoveryRequired
            let record=PatchEngineApplicationRecord(projectID:projectID,engine:.worseQuery,
                baseline:.capturedPriorState,targetKeys:targets,journalID:receiptID,phase:.recoveryRequired)
            try Fixture.store.save(record)
            service.catalogApplications.associate(projectID,with:item.identity)
            service.catalogApplications.markApplied(item.identity)
            service.catalogApplications.markRecoveryRequired(item.identity)
            let recordURL=Fixture.root.appendingPathComponent(".engine-applications/\(projectID.uuidString).plist")
            let snapshots=try Dictionary(uniqueKeysWithValues:[journalURL,backupURL,recordURL,targetURL,packageURL].map { ($0,try Data(contentsOf:$0)) })
            return (service,auth,item,projectID,snapshots)
        }
        func unchanged(_ snapshots:[URL:Data]) throws -> Bool {
            try snapshots.allSatisfy { try Data(contentsOf:$0.key)==$0.value }
        }
        for reason in ["invalid-record","missing-receipt","airlift-no-backup","provider-unavailable","restore-io"] {
            let (service,auth,item,projectID,initial)=try disableFixture(reason)
            var snapshots=initial
            if reason=="invalid-record" {
                let recordURL=Fixture.root.appendingPathComponent(".engine-applications/\(projectID.uuidString).plist")
                try Data("unreadable provenance fixture".utf8).write(to:recordURL)
                snapshots[recordURL]=try Data(contentsOf:recordURL)
            } else if reason=="missing-receipt" {
                // An old ON/recovery preference can survive without a project
                // association; force OFF must retain that unresolved evidence.
                service.catalogApplications.clear(item.identity)
                service.catalogApplications.markRecoveryRequired(item.identity)
            } else if reason=="airlift-no-backup" {
                let record=PatchEngineApplicationRecord(projectID:projectID,engine:.airLift,baseline:.unavailable,
                    targetKeys:targets,phase:.recoveryRequired,totalBatches:1)
                try Fixture.store.save(record)
                let recordURL=Fixture.root.appendingPathComponent(".engine-applications/\(projectID.uuidString).plist")
                snapshots[recordURL]=try Data(contentsOf:recordURL)
                UserDefaults.standard.set(true,forKey:"airlift.applied.\(projectID.uuidString)")
            } else if reason=="provider-unavailable" {
                ExploitSupportPolicy.currentStorageMode = .airLift
            } else {
                Fixture.restoreError=NSError(domain:NSPOSIXErrorDomain,code:13)
            }
            let canonical=service.patchApplicationState(item)
            let association=service.catalogApplications.projectID(for:item.identity)
            let legacy=UserDefaults.standard.bool(forKey:"airlift.applied.\(projectID.uuidString)")
            let outcome=try await service.disablePatch(item,auth:auth)
            try check(outcome == .disabledWithoutRestore,"OFF remains available when restore fails: \(reason)")
            try check(service.patchApplicationState(item)==canonical && canonical.requiresRestore,"force OFF retains canonical recovery state: \(reason)")
            try check(service.catalogApplications.projectID(for:item.identity)==association,"force OFF retains project association: \(reason)")
            try check(try unchanged(snapshots),"force OFF changes no target, journal, backup, package or provenance bytes: \(reason)")
            try check(UserDefaults.standard.bool(forKey:"airlift.applied.\(projectID.uuidString)")==legacy,"force OFF retains legacy AirLift evidence: \(reason)")
            try check(!service.isPatchToggleOn(item) && service.isPatchDisabledPendingRestore(item),"desired OFF still exposes recovery obligation: \(reason)")
            let rebuilt=FeaturePatchService()
            try check(!rebuilt.isPatchToggleOn(item) && rebuilt.isPatchDisabledPendingRestore(item),"OFF persists through service reconstruction: \(reason)")
            do { try rebuilt.attemptEnable(item,newProjectID:UUID());throw FixtureError.failed("pending OFF allowed a new association") }
            catch PatchRestoreError.disabledPendingRestore {}
            try check(Fixture.enableAssociations==0 && rebuilt.catalogApplications.projectID(for:item.identity)==association,"enable guard runs before replacing the old association: \(reason)")
            try check(Fixture.restores==0,"failed restore did not report restored: \(reason)")
        }

        do {
            let (service,auth,item,projectID,_)=try disableFixture("retry")
            Fixture.restoreError=NSError(domain:NSPOSIXErrorDomain,code:13)
            _ = try await service.disablePatch(item,auth:auth)
            let renamed=PatchItem(identity:"fixture_disable_renamed_"+UUID().uuidString)
            service.catalogApplications.migrateIdentity(from:item.identity,to:renamed.identity)
            let rebuilt=FeaturePatchService()
            try check(!rebuilt.isPatchToggleOn(renamed) && rebuilt.isPatchDisabledPendingRestore(renamed),"stable identity migration retains detached OFF and its binding")
            try check(!rebuilt.catalogApplications.hasPendingDisable(item.identity),"legacy detached marker does not survive identity migration")
            Fixture.restoreError=nil
            try await rebuilt.restorePatch(renamed,auth:auth)
            try check(Fixture.restores==1 && rebuilt.patchApplicationState(renamed) == .off,"strict restore retry resolves the canonical obligation")
            try check(!rebuilt.catalogApplications.hasPendingDisable(renamed.identity) && rebuilt.catalogApplications.projectID(for:renamed.identity)==nil,"successful retry clears only the completed catalog metadata")
            let record=try Fixture.store.read(projectID)
            try check(record?.phase == .restored,"successful retry records actual restoration")
            let newProject=UUID()
            try rebuilt.attemptEnable(renamed,newProjectID:newProject)
            try check(Fixture.enableAssociations==1 && rebuilt.catalogApplications.projectID(for:renamed.identity)==newProject,"enable is allowed once canonical recovery is OFF")
        }

        do {
            let (service,auth,item,projectID,_)=try disableFixture("successful-disable")
            let outcome=try await service.disablePatch(item,auth:auth)
            try check(outcome == .restored && Fixture.restores==1,"successful OFF reports actual restoration separately")
            try check(service.patchApplicationState(item) == .off && !service.isPatchToggleOn(item),"successful restore publishes normal OFF")
            try check(!service.catalogApplications.hasPendingDisable(item.identity),"successful OFF does not leave detached-recovery metadata")
            try check(try Fixture.store.read(projectID)?.phase == .restored,"successful OFF retains the completed transaction record")
        }

        do {
            let (service,auth,item,_,_)=try disableFixture("completed-elsewhere")
            Fixture.restoreError=FixtureError.nativeFailure
            _ = try await service.disablePatch(item,auth:auth)
            Fixture.journal = .off
            let replacement=UUID()
            try service.attemptEnable(item,newProjectID:replacement)
            try check(Fixture.enableAssociations==1,"canonical restored state permits enable despite stale detached metadata")
        }

        for changed in ["receipt","operation"] {
            let (service,auth,item,projectID,_)=try disableFixture("binding-"+changed)
            if changed=="operation" {
                Fixture.receipt=nil
                let record=PatchEngineApplicationRecord(projectID:projectID,engine:.airLift,baseline:.unavailable,
                    targetKeys:targets,phase:.recoveryRequired,totalBatches:1)
                try Fixture.store.save(record)
            }
            Fixture.restoreError=FixtureError.nativeFailure
            _ = try await service.disablePatch(item,auth:auth)
            if changed=="receipt",let old=Fixture.receipt {
                Fixture.receipt=PatchTransactionReceipt(id:UUID(),projectID:projectID,journalURL:old.journalURL)
            } else if let old=try Fixture.store.read(projectID) {
                var replacement=PatchEngineApplicationRecord(projectID:old.projectID,operationID:UUID(),engine:old.engine,
                    baseline:old.baseline,targetKeys:old.targetKeys,journalID:old.journalID,phase:old.phase,totalBatches:old.totalBatches)
                replacement.completedBatches=old.completedBatches
                try Fixture.store.save(replacement)
            }
            try check(!service.isPatchDisabledPendingRestore(item) && service.isPatchToggleOn(item),"old detached marker cannot hide a different \(changed)")
            do { try service.attemptEnable(item,newProjectID:UUID());throw FixtureError.failed("stale binding bypassed unresolved obligation") }
            catch PatchRestoreError.disabledPendingRestore {}
            try check(Fixture.enableAssociations==0,"stale marker still blocks unsafe overwrite until canonical OFF")
        }

        do {
            let (service,auth,item,projectID,_)=try disableFixture("sidecar-repair")
            let path=Fixture.root.appendingPathComponent(".engine-applications/\(projectID.uuidString).plist")
            let saved=try Data(contentsOf:path)
            try Data("invalid sidecar".utf8).write(to:path)
            _ = try await service.disablePatch(item,auth:auth)
            try saved.write(to:path)
            try check(service.isPatchDisabledPendingRestore(item) && !service.isPatchToggleOn(item),"repairing a direct sidecar cannot undo OFF for the same journal")
            if let old=try Fixture.store.read(projectID) {
                let replacement=PatchEngineApplicationRecord(projectID:old.projectID,operationID:UUID(),engine:old.engine,
                    baseline:old.baseline,targetKeys:old.targetKeys,journalID:old.journalID,phase:old.phase,totalBatches:old.totalBatches)
                try Fixture.store.save(replacement)
            }
            try check(service.isPatchDisabledPendingRestore(item) && !service.isPatchToggleOn(item),"direct metadata operation ID changes retain OFF while the journal is unchanged")
        }

        for failure in ["unauthenticated","revision","restore-auth","cancelled-error","url-cancelled","cancelled-task"] {
            for wasOff in [false,true] {
                let (service,auth,item,projectID,snapshots)=try disableFixture(failure)
                if wasOff {
                    Fixture.restoreError=FixtureError.nativeFailure
                    _ = try await service.disablePatch(item,auth:auth)
                    Fixture.restoreError=nil
                }
                let beforeToggle=service.isPatchToggleOn(item)
                let beforePending=service.catalogApplications.hasPendingDisable(item.identity)
                if failure=="unauthenticated" { auth.authState = .idle }
                else if failure=="revision" {
                    Fixture.onPrepareReceipt = { auth.authenticationRevision &+= 1 }
                } else if failure=="restore-auth" { Fixture.restoreError=FeaturePatchError.notAuthenticated }
                else if failure=="cancelled-error" { Fixture.restoreError=CancellationError() }
                else if failure=="url-cancelled" { Fixture.restoreError=URLError(.cancelled) }
                let operation=Task { @MainActor in
                    if failure=="cancelled-task" { withUnsafeCurrentTask { $0?.cancel() } }
                    return try await service.disablePatch(item,auth:auth)
                }
                do { _ = try await operation.value;throw FixtureError.failed("auth/cancel was acknowledged as disabled") }
                catch FeaturePatchError.notAuthenticated {} catch is CancellationError {}
                catch let error as URLError where error.code == .cancelled {}
                try check(service.isPatchToggleOn(item)==beforeToggle && service.catalogApplications.hasPendingDisable(item.identity)==beforePending,"auth/cancellation preserves the previous desired state: \(failure)/\(wasOff)")
                try check(try unchanged(snapshots),"auth/cancellation preserves all filesystem evidence")
                try check(service.catalogApplications.projectID(for:item.identity)==projectID,"auth/cancellation preserves the original project association")
            }
        }

        do {
            let (service,auth,item,_,_)=try disableFixture("gate")
            Fixture.restoreError=FixtureError.nativeFailure
            let owner=try await PatchFilesystemGate.shared.acquire()
            var completed=false
            let disable=Task { @MainActor in
                let outcome=try await service.disablePatch(item,auth:auth)
                completed=true
                return outcome
            }
            try await Task.sleep(nanoseconds:10_000_000)
            try check(!completed && !service.catalogApplications.hasPendingDisable(item.identity),"OFF waits for the active filesystem owner before changing catalog desire")
            await PatchFilesystemGate.shared.release(owner)
            let result=try await disable.value
            try check(result == .disabledWithoutRestore && completed,"OFF proceeds after exclusive ownership is released")
        }

        do {
            let (service,auth,item,_,snapshots)=try disableFixture("queued-cancel")
            let owner=try await PatchFilesystemGate.shared.acquire()
            let disable=Task { @MainActor in try await service.disablePatch(item,auth:auth) }
            try await Task.sleep(nanoseconds:10_000_000)
            disable.cancel()
            do { _ = try await disable.value;throw FixtureError.failed("cancelled queued OFF changed desire") }
            catch is CancellationError {}
            await PatchFilesystemGate.shared.release(owner)
            try check(service.isPatchToggleOn(item) && !service.catalogApplications.hasPendingDisable(item.identity),"queued cancellation leaves the user's original ON request intact")
            try check(try unchanged(snapshots),"cancelled queued OFF never changes filesystem recovery evidence")
        }
        print("Actual coordinator/provenance/gate: \(checks) checks passed")
    }
}
