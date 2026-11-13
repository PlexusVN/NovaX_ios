import Foundation
import Combine

enum IOS27ContainerSession {
    private static let lock = NSLock()
    private static var roots: [String: String] = [:]
    static func path(for bundleID: String) -> String? {
        lock.lock(); defer { lock.unlock() }; return roots[bundleID]
    }
    static func install(_ verified: [String: String], merging: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if merging { roots.merge(verified) { _, new in new } } else { roots = verified }
    }
    static func invalidate(bundleIDs: [String]) {
        lock.lock(); defer { lock.unlock() }
        for bundleID in bundleIDs { roots.removeValue(forKey: bundleID) }
    }
    static func reset() { install([:]) }
}

@MainActor
final class IOS27ContainerPreparation: ObservableObject {
    static let shared = IOS27ContainerPreparation()
    enum State: Equatable { case idle, preparing, ready, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var didContinue = false
    @Published private(set) var failure: String?
    private var work: Task<[String: String], Error>?
    private var generation: UInt64 = 0
    private let progress: ContainerScanProgress
    private let operation: @Sendable ([String], Bool) throws -> [String: String]
    private var targetBundleIDs: [String] = []
    private var forceNextScan = false

    init(progress: ContainerScanProgress = .shared,
         operation: @escaping @Sendable ([String], Bool) throws -> [String: String] = {
             try ContainerStore.prepareIOS27Access(bundleIDs: $0, forceScan: $1)
         }) {
        self.progress = progress
        self.operation = operation
    }

    /// The application supplies its known capabilities before displaying the
    /// mandatory preparation gate. The discovery engine contains no game list.
    func configureTargets(bundleIDs: [String]) {
        do {
            let requested = try validatedTargets(bundleIDs)
            guard requested != targetBundleIDs else { return }
            reset()
            targetBundleIDs = requested
        } catch {
            reset()
            targetBundleIDs = []
            state = .failed
            failure = error.localizedDescription
        }
    }

    func prepareIfNeeded(bundleIDs: [String], force: Bool = false) async {
        configureTargets(bundleIDs: bundleIDs)
        await prepareIfNeeded(force: force)
    }

    func prepareIfNeeded(force: Bool = false) async {
        guard work == nil, state != .ready || force else { return }
        guard !targetBundleIDs.isEmpty else {
            state = .failed; failure = "Chưa có ứng dụng hợp lệ để chuẩn bị quyền truy cập."
            return
        }
        if !force && !forceNextScan && progress.snapshot.phase == .interrupted {
            state = .failed
            failure = "Phiên chuẩn bị trước bị gián đoạn. Xem dòng log cuối rồi chọn Thử lại để tiếp tục."
            return
        }
        generation &+= 1
        let revision = generation
        state = .preparing; failure = nil; didContinue = false
        IOS27ContainerSession.reset()
        let operation = self.operation
        let targets = targetBundleIDs
        let forceScan = force || forceNextScan
        forceNextScan = false
        let task = Task.detached(priority: .userInitiated) { try operation(targets, forceScan) }
        work = task
        do {
            let roots = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard revision == generation else { return }
            let verified = try validatedRoots(roots, requested: targets)
            guard !verified.isEmpty else { throw WorseQueryError.preparationRequired }
            IOS27ContainerSession.install(verified)
            state = .ready
        } catch {
            guard revision == generation else { return }
            state = .failed
            failure = error is CancellationError ? "Đã dừng chuẩn bị. Chọn Thử lại để dò tiếp phạm vi hiện tại trước khi vào ứng dụng." : error.localizedDescription
        }
        if revision == generation { work = nil }
    }

    /// Additional authenticated patch targets use the same engine after the
    /// initial gate. Re-identify requested roots; retain other verified targets.
    func prepareAdditionalTargets(bundleIDs: [String]) async throws {
        let requested = try validatedTargets(bundleIDs)
        guard state == .ready, didContinue else { throw WorseQueryError.preparationRequired }
        while let pending = work {
            _ = try await pending.value
            // The owner publishes/clears its completed operation on this actor.
            await Task.yield()
        }
        try Task.checkCancellation()
        guard state == .ready, didContinue else { throw WorseQueryError.preparationRequired }
        let revision = generation
        IOS27ContainerSession.invalidate(bundleIDs: requested)
        let operation = self.operation
        let task = Task.detached(priority: .userInitiated) {
            var resolved: [String: String] = [:]
            // Initial preparation permits any installed optional target. A
            // patch requires EACH requested app, so a cache hit for A must not
            // short-circuit discovery of B in the same patch.
            for target in requested {
                try Task.checkCancellation()
                do {
                    let roots = try operation([target], false)
                    guard roots.keys.allSatisfy({ $0 == target }) else {
                        throw WorseQueryError.invalidPath("additional container scope")
                    }
                    resolved.merge(roots) { _, new in new }
                } catch WorseQueryError.containerDiscoveryFailed {
                    // Publish other independently verified targets before the
                    // caller receives the missing-target error below.
                }
            }
            return resolved
        }
        work = task
        do {
            let roots = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard revision == generation, didContinue else { throw CancellationError() }
            let verified = try validatedRoots(roots, requested: requested)
            IOS27ContainerSession.install(verified, merging: true)
            guard requested.allSatisfy({ verified[$0] != nil }) else {
                throw WorseQueryError.containerDiscoveryFailed(requested.filter { verified[$0] == nil }.joined(separator: ", "))
            }
            if revision == generation { work = nil }
        } catch {
            if revision == generation { work = nil }
            throw error
        }
    }

    private func validatedTargets(_ bundleIDs: [String]) throws -> [String] {
        let targets = Set(try bundleIDs.map { try PatchPathValidator.canonicalBundleIdentifier($0) })
        guard !targets.isEmpty else { throw WorseQueryError.preparationRequired }
        return targets.sorted()
    }

    private func validatedRoots(_ roots: [String: String], requested: [String]) throws -> [String: String] {
        let allowed = Set(requested)
        guard roots.allSatisfy({ allowed.contains($0.key) && ContainerStore.isApplicationContainerPath($0.value) }) else {
            throw WorseQueryError.invalidPath("prepared container scope")
        }
        return roots
    }

    func enterApplication() {
        guard state == .ready else { return }
        progress.dismiss()
        didContinue = true
    }

    func reset(forceScan: Bool = false) {
        generation &+= 1
        work?.cancel(); work = nil
        IOS27ContainerSession.reset()
        state = .idle; failure = nil; didContinue = false
        forceNextScan = forceScan
    }
}
