import Foundation
import Combine

enum IOS27ContainerSession {
    private static let lock = NSLock()
    private static var roots: [String: String] = [:]
    static func path(for bundleID: String) -> String? {
        lock.lock(); defer { lock.unlock() }; return roots[bundleID]
    }
    static func install(_ verified: [String: String]) {
        lock.lock(); roots = verified; lock.unlock()
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
    @Published private(set) var canUseAirLift = false
    private var work: Task<[String: String], Error>?
    private var generation: UInt64 = 0
    private let progress: ContainerScanProgress
    private let operation: () throws -> [String: String]

    init(progress: ContainerScanProgress = .shared,
         operation: @escaping () throws -> [String: String] = { try ContainerStore.prepareIOS27Access() }) {
        self.progress = progress
        self.operation = operation
    }

    func prepareIfNeeded(force: Bool = false) async {
        guard work == nil, state != .ready || force else { return }
        if !force && progress.snapshot.phase == .interrupted {
            state = .failed
            failure = "Phiên chuẩn bị trước bị gián đoạn. Xem dòng log cuối rồi chọn Thử lại để tiếp tục."
            return
        }
        generation &+= 1
        let revision = generation
        state = .preparing; failure = nil; canUseAirLift = false; didContinue = false
        IOS27ContainerSession.reset()
        let operation = self.operation
        let task = Task.detached(priority: .userInitiated) { try operation() }
        work = task
        do {
            let roots = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard revision == generation else { return }
            guard !roots.isEmpty else { throw WorseQueryError.preparationRequired }
            IOS27ContainerSession.install(roots)
            state = .ready
        } catch {
            guard revision == generation else { return }
            state = .failed
            failure = error is CancellationError ? "Đã dừng chuẩn bị. Chọn Thử lại để quét tiếp trước khi vào ứng dụng." : error.localizedDescription
            if case WorseQueryError.appGroupUnavailable = error { canUseAirLift = true }
        }
        if revision == generation { work = nil }
    }

    func enterApplication() {
        guard state == .ready else { return }
        progress.dismiss()
        didContinue = true
    }

    func chooseAirLift() {
        guard state == .failed, canUseAirLift else { return }
        progress.dismiss()
        didContinue = true
    }

    func reset() {
        generation &+= 1
        work?.cancel(); work = nil
        IOS27ContainerSession.reset()
        state = .idle; failure = nil; didContinue = false; canUseAirLift = false
    }
}
