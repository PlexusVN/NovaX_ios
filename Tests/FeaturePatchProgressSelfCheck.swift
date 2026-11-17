import Foundation

enum ProgressCheckFailure:Error { case failed(String) }
@MainActor final class WorkerBoundary {
    var continuation:CheckedContinuation<Void,Never>?
    var isWaiting:Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { let pending=continuation;continuation=nil;pending?.resume() }
}

@main struct FeaturePatchProgressSelfCheck {
    @MainActor static func main() async throws {
        var checks=0
        func check(_ value:Bool,_ message:String) throws {
            checks += 1
            if !value { throw ProgressCheckFailure.failed(message) }
        }
        func waitFor(_ condition:() -> Bool) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                await Task.yield()
            }
            throw ProgressCheckFailure.failed("fixture did not reach its boundary")
        }
        let service=FeaturePatchService()
        let patch=PatchItem(downloadIdentity:"catalog-fixture")
        let worker=WorkerBoundary()
        let operation=Task { @MainActor in
            try await service.withCatalogOperation(patch) {
                service.updatePatchOperation(.download)
                await worker.wait()
                try Task.checkCancellation()
            }
        }
        try await waitFor { worker.isWaiting }
        try check(service.patchOperation?.identity==patch.downloadIdentity,"active task lost its identity")
        try check(service.patchOperation?.stage == .download,"real download phase missing")
        try check(service.patchOperation?.canCancel == true,"precommit cancellation must be available")
        let firstID=service.patchOperation!.id
        do {
            try await service.withCatalogOperation(PatchItem(downloadIdentity:"other")) {}
            throw ProgressCheckFailure.failed("second card queued behind live worker")
        } catch FeaturePatchError.operationInProgress {}
        try check(service.patchOperation?.id==firstID,"rejected second operation replaced first task")
        service.cancelPatchOperation(identity:"other")
        try check(service.patchOperation?.cancellationPending == false,"another card canceled task")
        service.cancelPatchOperation(identity:patch.downloadIdentity)
        try check(service.patchOperation?.cancellationPending == true,"cancellation was not published")
        try check(service.patchOperation?.canCancel == false,"repeated cancel remains enabled")
        try check(service.patchOperation?.id==firstID,"cancel discarded active worker before completion")
        for _ in 0..<20 { await Task.yield() }
        try check(worker.isWaiting && service.patchOperation != nil,"busy released while worker still owns payload")
        worker.release()
        do { try await operation.value; throw ProgressCheckFailure.failed("canceled task reported success") }
        catch is CancellationError {}
        try check(service.patchOperation == nil,"completed canceled worker left spinner active")
        try check(service.cancelCatalogOperation == nil,"completed task retained cancellation closure")

        for stage in [FeaturePatchOperationProgress.Stage.write,.restore] {
            let boundary=WorkerBoundary()
            let writing=Task { @MainActor in
                try await service.withCatalogOperation(patch) {
                    service.updatePatchOperation(stage)
                    await boundary.wait()
                    try Task.checkCancellation()
                }
            }
            try await waitFor { boundary.isWaiting }
            try check(service.patchOperation?.canCancel == false,"commit UI allows cancellation")
            service.cancelPatchOperation(identity:patch.downloadIdentity)
            try check(service.patchOperation?.cancellationPending == false,"UI canceled admitted commit")
            try check(service.patchOperation?.stage==stage,"commit phase discarded")
            boundary.release()
            try await writing.value
            try check(service.patchOperation == nil,"finished commit left spinner active")
        }

        do {
            try await service.withCatalogOperation(patch) { throw ProgressCheckFailure.failed("injected download failure") }
            throw ProgressCheckFailure.failed("failure swallowed")
        } catch ProgressCheckFailure.failed(let text) {
            try check(text=="injected download failure","wrong error propagated")
        }
        try check(service.patchOperation == nil,"failed task left spinner active")

        let externallyCancelled=Task { @MainActor in
            try await service.withCatalogOperation(patch) {
                service.updatePatchOperation(.target)
                await worker.wait()
                try Task.checkCancellation()
            }
        }
        try await waitFor { worker.isWaiting }
        externallyCancelled.cancel()
        for _ in 0..<20 { await Task.yield() }
        try check(service.patchOperation != nil,"caller cancellation released live worker")
        worker.release()
        do { try await externallyCancelled.value; throw ProgressCheckFailure.failed("caller cancel not forwarded") }
        catch is CancellationError {}
        try check(service.patchOperation == nil,"caller-canceled completed task left spinner")
        print("[PASS] \(checks) production feature task/progress/cancellation checks")
    }
}
