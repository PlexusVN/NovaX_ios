import Foundation

@main struct EngineTransactionSelfCheck {
    static var checks = 0

    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw FixtureError.failed(message) }
        checks += 1
    }

    static func project() -> PatchProject {
        PatchProject(name: "fixture", rules: [
            PatchRule(bundleID: "com.fixture.app", relativePath: "a/file",
                      replacementFilename: "file", replacementData: Data([1])),
            PatchRule(bundleID: "com.fixture.app", relativePath: "b/file",
                      replacementFilename: "file", replacementData: Data([2]))
        ])
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("itech-engine-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func setup() { Fixture.reset(root.appendingPathComponent(UUID().uuidString)) }

        setup()
        let id = UUID()
        let journalID = UUID()
        let targets = ["com.fixture.app\0a/file"]
        var direct = PatchEngineApplicationRecord(
            projectID: id,
            engine: .worseQuery,
            baseline: .capturedPriorState,
            targetKeys: targets,
            journalID: journalID,
            phase: .applied
        )
        try check(
            PatchEngineApplicationStore.reconcile(
                record: direct, journal: .applied, legacyAirLift: true
            ) == .applied,
            "bound direct provenance outranks historical preference"
        )
        try check(
            PatchEngineApplicationStore.reconcile(
                record: nil, journal: .applied, legacyAirLift: true
            ) == .recoveryRequired,
            "legacy direct/AirLift conflict is ambiguous"
        )
        do {
            try PatchEngineApplicationStore.requireDirectRestore(
                record: nil,
                receiptID: journalID,
                journal: .applied,
                legacyAirLift: true
            )
            throw FixtureError.failed("legacy ambiguity accepted")
        } catch PatchEngineStateError.legacyAmbiguous {}
        try PatchEngineApplicationStore.requireDirectRestore(
            record: direct,
            receiptID: journalID,
            journal: .applied,
            legacyAirLift: true
        )
        try check(
            PatchEngineApplicationStore.reconcile(
                record: direct, journal: .off, legacyAirLift: true
            ) == .off,
            "restored journal is not resurrected by AirLift boolean"
        )
        do {
            try PatchEngineApplicationStore.requireDirectRestore(
                record: direct,
                receiptID: UUID(),
                journal: .applied,
                legacyAirLift: false
            )
            throw FixtureError.failed("wrong receipt accepted")
        } catch PatchEngineStateError.invalidRecord {}
        direct.phase = .writing
        try Fixture.store.save(direct)
        try check(try Fixture.store.read(id) == direct, "provenance survives persistence")

        let coordinator = StorageEngineCoordinator()
        do {
            let unknownID = UUID()
            let unknownKey = "airlift.applied.\(UUID().uuidString)"
            UserDefaults.standard.set(true, forKey: unknownKey)
            do {
                try await coordinator.applyPatchProject(project())
                throw FixtureError.failed("different project bypassed unknown legacy history")
            } catch PatchEngineStateError.legacyTargetsUnknown {}
            try check(
                Fixture.writes == 0 && UserDefaults.standard.bool(forKey: unknownKey),
                "unknown legacy targets block new baselines without deleting history"
            )
            UserDefaults.standard.removeObject(forKey: unknownKey)

            let knownKey = "airlift.applied.\(unknownID.uuidString)"
            UserDefaults.standard.set(true, forKey: knownKey)
            let known = PatchEngineApplicationRecord(
                projectID: unknownID,
                engine: .airLift,
                baseline: .unavailable,
                targetKeys: ["com.other.app\0unrelated"],
                phase: .applied,
                totalBatches: 1
            )
            try Fixture.store.save(known)
            try Fixture.store.requireResolvedLegacyHistory()
            try Fixture.store.requireNoUnbackedOverlap(projectID: UUID(), targetKeys: targets)
            try check(
                UserDefaults.standard.bool(forKey: knownKey),
                "known unrelated AirLift history uses target overlap without global denial"
            )
            UserDefaults.standard.removeObject(forKey: knownKey)
        }

        do {
            var patch = project()
            patch.rules[0].relativePath = "a/file"
            do {
                try await coordinator.applyPatchProject(patch)
                throw FixtureError.failed("AirLift overwrote direct transaction")
            } catch PatchEngineStateError.recoveryRequired {}
            try check(Fixture.writes == 0, "AirLift cannot overwrite a backed direct transaction")
        }

        for failed in [1, 2] {
            setup()
            let patch = project()
            Fixture.failBatch = failed
            do {
                try await coordinator.applyPatchProject(patch)
                throw FixtureError.failed("native failure ignored")
            } catch is FixtureError {
            } catch is AirLiftError {}
            let record = try Fixture.store.read(patch.id)!
            try check(
                record.phase == .recoveryRequired && record.completedBatches == failed - 1,
                "partial or unknown first batch remains recovery-required"
            )
            try check(
                Fixture.observed.allSatisfy { $0.phase == .writing },
                "writing record exists before every dispatch"
            )
            try check(
                coordinator.projectApplicationState(patch.id) == .recoveryRequired,
                "partial AirLift never displays OFF"
            )
            let writes = Fixture.writes
            do {
                try await coordinator.applyPatchProject(patch)
                throw FixtureError.failed("unbacked reapply permitted")
            } catch PatchEngineStateError.recoveryRequired {}
            try check(Fixture.writes == writes, "unresolved AirLift cannot be reapplied")
        }

        setup()
        let success = project()
        try await coordinator.applyPatchProject(success)
        let successful = try Fixture.store.read(success.id)!
        try check(
            successful.phase == .applied && successful.completedBatches == 2,
            "success records all acknowledged batches"
        )
        do {
            try PatchEngineApplicationStore.requireDirectRestore(
                record: successful,
                receiptID: nil,
                journal: nil,
                legacyAirLift: false
            )
            throw FixtureError.failed("AirLift invented original bytes")
        } catch PatchEngineStateError.airLiftNoBackup {}
        do {
            try Fixture.store.requireNoUnbackedOverlap(
                projectID: UUID(),
                targetKeys: successful.targetKeys
            )
            throw FixtureError.failed("new project overwrote AirLift baseline")
        } catch PatchEngineStateError.recoveryRequired {}

        for onlyDirectory in [false, true] {
            setup()
            var patch = project()
            patch.directories = [
                PatchDirectory(bundleID: "com.fixture.app", relativePath: "empty")
            ]
            if onlyDirectory { patch.rules = [] }
            do {
                try await coordinator.applyPatchProject(patch)
                throw FixtureError.failed("empty directory silently ignored")
            } catch PatchEngineStateError.unsupportedAirLiftDirectory {}
            try check(
                Fixture.writes == 0 && !FileManager.default.fileExists(atPath: Fixture.root.path),
                "capability failure precedes storage/native effects"
            )
        }

        setup()
        var parent = project()
        parent.directories = [PatchDirectory(bundleID: "com.fixture.app", relativePath: "a")]
        try await coordinator.applyPatchProject(parent)
        try check(Fixture.writes == 2, "AirLift accepts directories represented by payload parents")

        setup()
        ExploitSupportPolicy.currentStorageMode = .direct
        try await coordinator.applyPatchProject(project())
        try check(Fixture.directWrites == 1 && Fixture.writes == 0,
                  "direct dispatch never enters AirLift")

        ExploitSupportPolicy.currentStorageMode = .airLift
        setup()
        let first = project()
        var second = project()
        second.rules[0].relativePath = "c/file"
        second.rules[1].relativePath = "d/file"
        Fixture.onWrite = { try await Task.sleep(nanoseconds: 10_000_000) }
        async let one: Void = coordinator.applyPatchProject(first)
        let secondProject = second
        async let two: Void = coordinator.applyPatchProject(secondProject)
        _ = try await (one, two)
        try check(
            Fixture.events == [
                "native-start", "native-end", "native-start", "native-end",
                "native-start", "native-end", "native-start", "native-end"
            ],
            "filesystem operations serialize across native awaits"
        )

        let held = try await PatchFilesystemGate.shared.acquire()
        let waiting = Task { @MainActor in
            try await coordinator.applyPatchProject(project())
        }
        await Task.yield()
        waiting.cancel()
        do {
            try await waiting.value
            throw FixtureError.failed("cancelled waiter entered filesystem")
        } catch is CancellationError {}
        await PatchFilesystemGate.shared.release(held)
        try check(Fixture.writes == 4, "cancelled waiter never dispatches")

        setup()
        let service = FeaturePatchService()
        let item = PatchItem(identity: "fixture_disable_astra")
        let auth = AuthManager()
        let transition = try service.catalogModes.prepare(identity: item.identity, isRestoration: false, candidates: [])
        try service.catalogModes.commit(transition)
        let receiptID = UUID()
        Fixture.receipt = PatchTransactionReceipt(id: receiptID, projectID: transition.projectID,
            journalURL: root.appendingPathComponent("journal.plist"))
        Fixture.journal = .applied
        try Fixture.store.save(PatchEngineApplicationRecord(projectID: transition.projectID,
            engine: .worseQuery, baseline: .capturedPriorState, targetKeys: targets,
            journalID: receiptID, phase: .applied))
        try check(service.isPatchToggleOn(item), "original Astra toggle reads durable mode association")
        Fixture.restoreError = FixtureError.nativeFailure
        let failedDisable = try await service.disablePatch(item, auth: auth)
        try check(failedDisable == .disabledWithoutRestore, "failed restore records explicit OFF without claiming file restoration")
        try check(service.isPatchDisabledPendingRestore(item) && !service.isPatchToggleOn(item),
            "original UI exposes pending recovery for durable mode project")
        try check(service.patchApplicationState(item) == .applied && Fixture.receipt?.id == receiptID,
            "OFF adapter retains actual state and original receipt")
        do {
            try service.assertCanEnable(item)
            throw FixtureError.failed("pending recovery allowed a new activation")
        } catch PatchRestoreError.disabledPendingRestore {}
        let freshService = FeaturePatchService()
        freshService.defaults.set(service.defaults.dictionaryRepresentation()["astra_catalog_feature_modes_v1"],
            forKey: "astra_catalog_feature_modes_v1")
        freshService.catalogApplications.markDisabledWithoutRestore(item.identity,
            binding: transition.projectID.uuidString + ":journal:" + receiptID.uuidString)
        try check(freshService.isPatchDisabledPendingRestore(item), "durable mode association wins when preference association is absent")
        Fixture.restoreError = CancellationError()
        do {
            _ = try await service.disablePatch(item, auth: auth)
            throw FixtureError.failed("cancelled restore became successful OFF")
        } catch is CancellationError {}
        Fixture.restoreError = nil
        let restored = try await service.disablePatch(item, auth: auth)
        try check(restored == .restored && !service.isPatchToggleOn(item) && !service.isPatchDisabledPendingRestore(item),
            "successful strict restore clears pending OFF and keeps UI off")
        try service.assertCanEnable(item)

        print("Actual coordinator/provenance/gate and original Astra toggle: \(checks) checks passed")
    }
}
