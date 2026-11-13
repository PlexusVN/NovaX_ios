import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private enum DirectCheckError:Error { case failed(String), injected }
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
        // Removing only the new sidecar reproduces pre-migration legacy state:
        // direct journal plus AirLift history cannot establish original bytes.
        let sidecar=backup.appendingPathComponent(".engine-applications/\(project.id.uuidString).plist")
        let saved=try Data(contentsOf:sidecar)
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
        try PatchTransaction.restore(receipt:reapplied,containerResolver:{_ in container})
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

        UserDefaults.standard.removeObject(forKey:legacy)
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
