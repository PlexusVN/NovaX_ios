import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private enum DirectCheckError:Error { case failed(String), injected }
private final class IgnoredRemovalFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws { /* simulate a falsely successful removal */ }
}
@main struct DirectTransactionProvenanceSelfCheck {
    static var checks=0
    static func check(_ value:@autoclosure () throws -> Bool,_ label:String) throws {
        guard try value() else { throw DirectCheckError.failed(label) };checks += 1
    }
    static func main() throws {
        let files=FileManager.default
        let root=files.temporaryDirectory.appendingPathComponent("astra-direct-provenance-"+UUID().uuidString)
        try files.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? files.removeItem(at:root) }
        let container=root.appendingPathComponent("container"),backup=root.appendingPathComponent("backups")
        try files.createDirectory(at:container.appendingPathComponent("Documents"),withIntermediateDirectories:true)
        let target=container.appendingPathComponent("Documents/file"),original=Data("before transaction".utf8),replacement=Data("patched".utf8)
        try original.write(to:target)
        let project=PatchProject(name:"direct",rules:[PatchRule(bundleID:"com.fixture.app",relativePath:"Documents/file",replacementFilename:"file",replacementData:replacement)])
        let receipt=try PatchTransaction.apply(project:project,backupRoot:backup,engine:.worseQuery,containerResolver:{_ in container})
        let store=PatchEngineApplicationStore(backupRoot:backup)
        let record=try store.read(project.id)!
        try check(record.engine == .worseQuery && record.journalID == receipt.id && record.phase == .applied,"real apply binds engine provenance to durable journal")
        try check(try Data(contentsOf:target)==replacement,"real apply writes replacement")
        let legacy="airlift.applied.\(project.id.uuidString)"
        UserDefaults.standard.set(true,forKey:legacy)
        defer { UserDefaults.standard.removeObject(forKey:legacy) }
        try PatchTransaction.restore(receipt:receipt,containerResolver:{_ in container})
        try check(try Data(contentsOf:target)==original,"bound direct receipt restores despite stale AL flag")
        try check(try store.read(project.id)?.phase == .restored,"restore commits durable engine state")
        try check(UserDefaults.standard.bool(forKey:legacy),"restore keeps historical marker as evidence")
        // A second direct apply remains possible because a bound restored
        // record disambiguates the historical marker without deleting it.
        let reapplied=try PatchTransaction.apply(project:project,backupRoot:backup,containerResolver:{_ in container})
        try check(reapplied.id != receipt.id,"reapply creates a new journal")
        // A genuine pre-schema-3 journal plus missing sidecar and AirLift
        // history still cannot establish which provider supplied its baseline.
        let sidecar=backup.appendingPathComponent(".engine-applications/\(project.id.uuidString).plist")
        let saved=try Data(contentsOf:sidecar)
        let boundJournal=try Data(contentsOf:reapplied.journalURL)
        var legacyJournal=try PropertyListSerialization.propertyList(from:boundJournal,format:nil) as! [String:Any]
        legacyJournal["schemaVersion"]=2;legacyJournal.removeValue(forKey:"engineRecord")
        try PropertyListSerialization.data(fromPropertyList:legacyJournal,format:.binary,options:0).write(to:reapplied.journalURL)
        try files.removeItem(at:sidecar)
        let journalBefore=try Data(contentsOf:reapplied.journalURL)
        for operation in [0,1,2] {
            do {
                if operation==0 { try PatchTransaction.restore(receipt:reapplied,containerResolver:{_ in container}) }
                else if operation==1 { _ = try PatchTransaction.inspectRestore(receipt:reapplied,containerResolver:{_ in container}) }
                else { try PatchTransaction.resetToAppliedState(receipt:reapplied,containerResolver:{_ in container}) }
                throw DirectCheckError.failed("ambiguous legacy operation accepted")
            } catch PatchEngineStateError.legacyAmbiguous {}
            try check(try Data(contentsOf:target)==replacement && Data(contentsOf:reapplied.journalURL)==journalBefore,"legacy ambiguity preserves targets and journal")
        }
        try saved.write(to:sidecar)
        try boundJournal.write(to:reapplied.journalURL)
        try PatchTransaction.restore(receipt:reapplied,containerResolver:{_ in container})
        print("[transaction] apply/restore and legacy ambiguity passed")

        // Crash/failure after the prepared journal's atomic write but before
        // the mutable project sidecar: the previous restored sidecar remains.
        // Reconstruct from disk, never from an in-memory receipt or cached flag.
        let previousSidecar=try Data(contentsOf:sidecar)
        do {
            _ = try PatchTransaction.apply(project:project,backupRoot:backup,engine:.worseQuery,
                containerResolver:{_ in container},beforeProvenanceWrite:{throw DirectCheckError.injected})
            throw DirectCheckError.failed("provenance failure ignored")
        } catch DirectCheckError.injected {}
        let pending=try PatchTransaction.latestReceipt(projectID:project.id,backupRoot:backup).unwrap()
        try check(try Data(contentsOf:target)==original,"prepared/index crash performs no target mutation")
        try check(try Data(contentsOf:sidecar)==previousSidecar,"prepared/index crash retains previous index bytes")
        let rebuilt=PatchEngineApplicationStore(backupRoot:backup)
        let bound=try rebuilt.read(project.id).unwrap()
        try check(bound.journalID==pending.id && bound.engine == .worseQuery && bound.phase == .recoveryRequired,"reconstructed prepared journal owns its exact engine binding")
        try files.removeItem(at:sidecar)
        try check(try rebuilt.read(project.id)?.journalID==pending.id,"bound schema-3 journal survives an absent mutable project index")
        try previousSidecar.write(to:sidecar)
        let pendingData=try Data(contentsOf:pending.journalURL)
        var damaged=try PropertyListSerialization.propertyList(from:pendingData,format:nil) as! [String:Any]
        var damagedEngine=damaged["engineRecord"] as! [String:Any]
        damagedEngine["journalID"]=UUID().uuidString
        damaged["engineRecord"]=damagedEngine
        try PropertyListSerialization.data(fromPropertyList:damaged,format:.binary,options:0).write(to:pending.journalURL)
        do { _ = try rebuilt.read(project.id);throw DirectCheckError.failed("wrong embedded binding trusted") }
        catch PatchEngineStateError.invalidRecord {}
        try check(try Data(contentsOf:target)==original,"invalid embedded receipt never writes the target")
        try pendingData.write(to:pending.journalURL)
        let conflicting=PatchEngineApplicationRecord(projectID:project.id,engine:.airLift,baseline:.unavailable,
            targetKeys:bound.targetKeys,phase:.recoveryRequired,totalBatches:1)
        try rebuilt.save(conflicting)
        do { _ = try rebuilt.read(project.id);throw DirectCheckError.failed("AirLift evidence hidden by bound journal") }
        catch PatchEngineStateError.invalidRecord {}
        try previousSidecar.write(to:sidecar)
        try PatchTransaction.restore(receipt:pending,containerResolver:{_ in container})
        try check(try Data(contentsOf:target)==original && rebuilt.read(project.id)?.phase == .restored,"prepared/index crash can restore and commit matching provenance")
        let afterCrash=try PatchTransaction.apply(project:project,backupRoot:backup,containerResolver:{_ in container})
        try check(try Data(contentsOf:target)==replacement,"reapply works after reconstructed recovery")
        try PatchTransaction.restore(receipt:afterCrash,containerResolver:{_ in container})

        // A new AirLift operation on this same project can legitimately follow
        // a completed direct restore. Its index wins over the terminal direct
        // journal, without granting permission to reuse that old backup.
        let restoredDirectIndex=try Data(contentsOf:sidecar)
        for phase in [PatchEnginePhase.writing, .applied, .recoveryRequired] {
            let laterAirLift=PatchEngineApplicationRecord(projectID:project.id,engine:.airLift,baseline:.unavailable,
                targetKeys:bound.targetKeys,phase:phase,totalBatches:1)
            try rebuilt.save(laterAirLift)
            let observed=try rebuilt.read(project.id).unwrap()
            try check(observed==laterAirLift,"new AirLift state survives old terminal direct history")
            do {
                try PatchEngineApplicationStore.requireDirectRestore(record:observed,receiptID:afterCrash.id,journal:.off,legacyAirLift:true)
                throw DirectCheckError.failed("AirLift used an obsolete direct backup")
            } catch PatchEngineStateError.airLiftNoBackup {}
            do {
                _ = try PatchTransaction.apply(project:project,backupRoot:backup,containerResolver:{_ in container})
                throw DirectCheckError.failed("new AirLift obligation allowed a new direct baseline")
            } catch PatchEngineStateError.recoveryRequired {}
            try check(try Data(contentsOf:target)==original,"unbacked AirLift state prevents further direct mutation")
        }
        try restoredDirectIndex.write(to:sidecar)
        print("[transaction] prepared/index crash recovery and AirLift transition passed")
        // Each following scenario owns a separate backup root. A global legacy
        // marker for the first root must not be mistaken for unknown history
        // in those independent fixtures; production correctly rejects that.
        UserDefaults.standard.removeObject(forKey:legacy)

        // Writer and reader share one cap, enforced before container resolution,
        // backups or a new prepared receipt can appear.
        let largeHistory=root.appendingPathComponent("oversized-backups")
        let largeRules=(0..<12_000).map { index in
            PatchRule(bundleID:"com.fixture.large",relativePath:"Documents/"+String(repeating:"x",count:240)+String(index),
                replacementFilename:"file",replacementData:Data([1]))
        }
        let largeProject=PatchProject(name:"oversized index",rules:largeRules)
        var resolvedOversized=false
        do {
            _ = try PatchTransaction.apply(project:largeProject,backupRoot:largeHistory,containerResolver:{_ in resolvedOversized=true;return container})
            throw DirectCheckError.failed("unreadable oversized index accepted")
        } catch PatchEngineStateError.invalidRecord {}
        try check(!resolvedOversized && !files.fileExists(atPath:largeHistory.path),"oversized index fails before resolution or durable backup state")

        let directoryHistory=root.appendingPathComponent("directory-binding"),directoryGame=directoryHistory.appendingPathComponent("container")
        try files.createDirectory(at:directoryGame.appendingPathComponent("Documents"),withIntermediateDirectories:true)
        let directoryProject=PatchProject(name:"directory binding",directories:[PatchDirectory(bundleID:"com.fixture.directory",relativePath:"Documents/empty")],rules:[])
        let directoryBackups=directoryHistory.appendingPathComponent("backups")
        do {
            _ = try PatchTransaction.apply(project:directoryProject,backupRoot:directoryBackups,containerResolver:{_ in directoryGame},beforeProvenanceWrite:{throw DirectCheckError.injected})
            throw DirectCheckError.failed("directory provenance failure ignored")
        } catch DirectCheckError.injected {}
        let directoryReceipt=try PatchTransaction.latestReceipt(projectID:directoryProject.id,backupRoot:directoryBackups).unwrap()
        let directoryJournal=try Data(contentsOf:directoryReceipt.journalURL)
        var wrongDirectory=try PropertyListSerialization.propertyList(from:directoryJournal,format:nil) as! [String:Any]
        var wrongDirectoryRecord=wrongDirectory["engineRecord"] as! [String:Any]
        wrongDirectoryRecord["targetKeys"]=["com.fixture.directory\0Documents/unrelated"]
        wrongDirectory["engineRecord"]=wrongDirectoryRecord
        try PropertyListSerialization.data(fromPropertyList:wrongDirectory,format:.binary,options:0).write(to:directoryReceipt.journalURL)
        do { _ = try PatchEngineApplicationStore(backupRoot:directoryBackups).read(directoryProject.id);throw DirectCheckError.failed("unbound created directory trusted") }
        catch PatchEngineStateError.invalidRecord {}
        try check(!files.fileExists(atPath:directoryGame.appendingPathComponent("Documents/empty").path),"wrong directory binding performs no filesystem mutation")
        try directoryJournal.write(to:directoryReceipt.journalURL)
        try PatchTransaction.restore(receipt:directoryReceipt,containerResolver:{_ in directoryGame})

        // Restore may not commit success when a platform/FileManager removal
        // claims success but an introduced file still exists.
        let removalRoot=root.appendingPathComponent("verified-removal"),removalContainer=removalRoot.appendingPathComponent("container")
        try files.createDirectory(at:removalContainer.appendingPathComponent("Documents"),withIntermediateDirectories:true)
        let removalTarget=removalContainer.appendingPathComponent("Documents/introduced")
        let removalProject=PatchProject(name:"removal",rules:[PatchRule(bundleID:"com.fixture.removal",relativePath:"Documents/introduced",replacementFilename:"introduced",replacementData:replacement)])
        let removalReceipt=try PatchTransaction.apply(project:removalProject,backupRoot:removalRoot.appendingPathComponent("backups"),containerResolver:{_ in removalContainer})
        do {
            try PatchTransaction.restore(receipt:removalReceipt,containerResolver:{_ in removalContainer},fileManager:IgnoredRemovalFileManager())
            throw DirectCheckError.failed("unverified removal committed")
        } catch PatchPackageError.restoreFailed {}
        try check(try Data(contentsOf:removalTarget)==replacement,"failed restore readback keeps pre-restore bytes")
        try check(try PatchTransaction.recordedApplicationState(receipt:removalReceipt) == .applied,"failed removal cannot commit restored journal")
        try PatchTransaction.restore(receipt:removalReceipt,containerResolver:{_ in removalContainer})
        try check(!files.fileExists(atPath:removalTarget.path),"normal restore verifies introduced target is absent")
        print("[transaction] size/binding checks and final restore readback passed")
        // Failure after first mutation must roll back all bytes and provenance.
        var failure=project;failure.id=UUID();failure.rules.append(PatchRule(bundleID:"com.fixture.app",relativePath:"Documents/introduced",replacementFilename:"introduced",replacementData:Data([4])))
        do {
            _ = try PatchTransaction.apply(project:failure,backupRoot:backup,containerResolver:{_ in container},beforeWrite:{index in if index==1 {throw DirectCheckError.injected}})
            throw DirectCheckError.failed("fault ignored")
        } catch PatchPackageError.applyFailed {}
        try check(try Data(contentsOf:target)==original,"failed direct write restores original bytes")
        try check(!files.fileExists(atPath:container.appendingPathComponent("Documents/introduced").path),"failed direct write leaves no introduced file")
        try check(try store.read(failure.id)?.phase == .restored,"successful rollback commits restored provenance")
        // Unknown/partial AirLift must block a different project touching the
        // same target before any backup can mislabel modified bytes as original.
        let air=PatchEngineApplicationRecord(projectID:UUID(),engine:.airLift,baseline:.unavailable,targetKeys:["com.fixture.app\0Documents/file"],phase:.recoveryRequired,totalBatches:1)
        try store.save(air)
        var overwrite=project;overwrite.id=UUID()
        do { _ = try PatchTransaction.apply(project:overwrite,backupRoot:backup,containerResolver:{_ in container});throw DirectCheckError.failed("AL baseline captured") }
        catch PatchEngineStateError.recoveryRequired {}
        try check(try Data(contentsOf:target)==original,"unbacked AirLift overlap performs no write")
        try check(!files.fileExists(atPath:backup.appendingPathComponent(overwrite.id.uuidString).path),"unbacked overlap creates no misleading backup")

        // Reuse the same project ID and reconstruct its durable state on every
        // cycle: read-only modes restored from backup must remain replaceable.
        for mode in [0o444, 0o644] {
            let cycleRoot=root.appendingPathComponent("mode-\(mode)")
            let game=cycleRoot.appendingPathComponent("container")
            let history=cycleRoot.appendingPathComponent("backups")
            try files.createDirectory(at:game.appendingPathComponent("Documents"),withIntermediateDirectories:true)
            let file=game.appendingPathComponent("Documents/file")
            let bytes=Data("prior-state-\(mode)".utf8)
            try bytes.write(to:file)
            try files.setAttributes([.posixPermissions:mode],ofItemAtPath:file.path)
            let patch=PatchProject(name:"mode-cycle",rules:[PatchRule(bundleID:"com.fixture.mode",relativePath:"Documents/file",replacementFilename:"file",replacementData:replacement)])
            for _ in 0..<3 {
                let applied=try PatchTransaction.apply(project:patch,backupRoot:history,containerResolver:{_ in game})
                try check(try Data(contentsOf:file)==replacement,"repeated apply writes final bytes with mode \(mode)")
                try check((try files.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue == mode,"apply retains target mode \(mode)")
                let backupFiles=try files.contentsOfDirectory(at:applied.journalURL.deletingLastPathComponent(),includingPropertiesForKeys:nil)
                let source=try backupFiles.first(where:{$0.pathExtension=="original"}).unwrap()
                try check(try Data(contentsOf:source)==bytes,"backup captures the same baseline on each cycle")
                try PatchTransaction.restore(receipt:applied,containerResolver:{_ in game})
                try check(try Data(contentsOf:file)==bytes,"readonly backup restores its bytes")
                try check((try files.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue == mode,"restore preserves source backup mode \(mode)")
                try check((try files.attributesOfItem(atPath:source.path)[.posixPermissions] as? NSNumber)?.intValue == mode,"restore never changes backup permissions")
                let rebuilt=PatchEngineApplicationStore(backupRoot:history)
                try check(try rebuilt.read(patch.id)?.phase == .restored,"reconstructed provenance permits the next cycle")
            }
        }

        let defaultRoot=root.appendingPathComponent("default-mode"),defaultGame=defaultRoot.appendingPathComponent("container")
        try files.createDirectory(at:defaultGame.appendingPathComponent("Documents"),withIntermediateDirectories:true)
        let control=defaultGame.appendingPathComponent("Documents/control")
        try check(files.createFile(atPath:control.path,contents:Data()),"default mode control can be created")
        let defaultMode=(try files.attributesOfItem(atPath:control.path)[.posixPermissions] as? NSNumber)?.intValue
        let createdTarget=defaultGame.appendingPathComponent("Documents/new-file")
        let newPatch=PatchProject(name:"default-mode",rules:[PatchRule(bundleID:"com.fixture.default",relativePath:"Documents/new-file",replacementFilename:"new-file",replacementData:replacement)])
        _ = try PatchTransaction.apply(project:newPatch,backupRoot:defaultRoot.appendingPathComponent("backups"),containerResolver:{_ in defaultGame})
        try check((try files.attributesOfItem(atPath:createdTarget.path)[.posixPermissions] as? NSNumber)?.intValue == defaultMode,"new target retains Foundation's default creation mode")

        // Real permission failure (not an invented Cocoa error). Root bypasses
        // POSIX mode checks, so that environment cannot prove this boundary.
        if geteuid() != 0 {
            let deniedRoot=root.appendingPathComponent("denied-parent"),deniedGame=deniedRoot.appendingPathComponent("container")
            let deniedParent=deniedGame.appendingPathComponent("Documents")
            let deniedHistory=deniedRoot.appendingPathComponent("backups")
            try files.createDirectory(at:deniedParent,withIntermediateDirectories:true)
            let deniedTarget=deniedParent.appendingPathComponent("file")
            try original.write(to:deniedTarget)
            try files.setAttributes([.posixPermissions:0o555],ofItemAtPath:deniedParent.path)
            defer { try? files.setAttributes([.posixPermissions:0o755],ofItemAtPath:deniedParent.path) }
            let deniedPatch=PatchProject(name:"denied-parent",rules:[PatchRule(bundleID:"com.fixture.denied",relativePath:"Documents/file",replacementFilename:"file",replacementData:replacement)])
            do {
                _ = try PatchTransaction.apply(project:deniedPatch,backupRoot:deniedHistory,containerResolver:{_ in deniedGame})
                throw DirectCheckError.failed("write to denied parent unexpectedly succeeded")
            } catch {
                let detail=error.localizedDescription
                try check(detail.contains("staging-create") && detail.contains("errno=\(EACCES)"),"P06 keeps the failed filesystem step and original POSIX errno")
                try check(!detail.contains(deniedGame.path),"filesystem diagnostic does not expose absolute container paths")
            }
            try check(try Data(contentsOf:deniedTarget)==original,"permission denial retains original target bytes")
            let pending=try PatchEngineApplicationStore(backupRoot:deniedHistory).read(deniedPatch.id)
            try check(pending?.phase == .recoveryRequired,"unconfirmed rollback retains recovery state and backup")
            let receipt=try PatchTransaction.latestReceipt(projectID:deniedPatch.id,backupRoot:deniedHistory).unwrap()
            let backupFiles=try files.contentsOfDirectory(at:receipt.journalURL.deletingLastPathComponent(),includingPropertiesForKeys:nil)
            let saved=try backupFiles.first(where:{$0.pathExtension=="original"}).unwrap()
            try check(try Data(contentsOf:saved)==original,"denied rollback preserves the original backup")
        } else { print("Permission-denial check skipped: root bypasses file modes") }
        print("Actual direct transaction/provenance: \(checks) checks passed")
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value=self else { throw DirectCheckError.failed("missing test fixture result") }
        return value
    }
}
