import Foundation
import Combine

enum ContainerScanPhase: String, Codable {
    case idle, scanning, resolved, failed, cancelled, interrupted
}

struct ContainerScanSnapshot: Codable {
    var id: UUID?
    var bundleID = ""
    var phase: ContainerScanPhase = .idle
    var startedAt = Date()
    var scanned: UInt64 = 0
    var total: UInt64 = 0
    var candidates = 0
    var grants = 0
    var logs: [String] = []
    var detail = ""

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(scanned) / Double(total)))
    }
}

/// Workers report progress; published state is changed only on the main queue.
/// This object never starts a scan or invokes a private OS API at initialization.
final class ContainerScanProgress: ObservableObject {
    static let shared = ContainerScanProgress()
    @Published private(set) var snapshot = ContainerScanSnapshot()
    @Published private(set) var isPresented = false
    @Published private(set) var cancelPending = false
    private let lock = NSLock()
    private var activeID: UUID?
    private var requestedCancellation = false
    private let historyURL: URL?
    private let historyQueue = DispatchQueue(label: "astra.container-scan.history", qos: .utility)
    private var lastSavedAt = Date.distantPast // main queue only

    init(historyURL: URL? = ContainerScanProgress.defaultHistoryURL) {
        self.historyURL = historyURL
        if let historyURL,
           let size = try? historyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= 256 * 1024,
           let data = try? Data(contentsOf: historyURL),
           var previous = try? JSONDecoder().decode(ContainerScanSnapshot.self, from: data) {
            previous.logs = Array(previous.logs.suffix(200))
            if previous.phase == .scanning {
                previous.phase = .interrupted
                previous.detail = "Phiên quét trước chưa hoàn tất. Astra sẽ không tự chạy lại khi mở app."
                previous.logs.append(previous.detail)
            }
            snapshot = previous
        }
    }

    static var defaultHistoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Astra", isDirectory: true).appendingPathComponent("ContainerScanHistory.json")
    }

    func track(bundleID: String, operation: (UUID) throws -> String) throws -> String {
        let id = UUID()
        lock.lock()
        activeID = id
        requestedCancellation = false
        lock.unlock()
        onMain {
            self.snapshot = ContainerScanSnapshot(id: id, bundleID: bundleID, phase: .scanning)
            self.cancelPending = false
            self.isPresented = true
            self.append("Bắt đầu tìm thư mục dữ liệu: \(bundleID)")
            self.saveHistory(force: true)
        }
        do {
            try checkCancellation(id)
            let path = try operation(id)
            try checkCancellation(id)
            finish(id, phase: .resolved, detail: "Đã tìm thấy thư mục dữ liệu. Astra tiếp tục thao tác bạn đã chọn.")
            return path
        } catch {
            finish(id, phase: error is CancellationError ? .cancelled : .failed,
                   detail: error is CancellationError ? "Đã dừng quét; chưa bắt đầu ghi file trong bước dò này." : error.localizedDescription)
            throw error
        }
    }

    func report(_ id: UUID, scanned: UInt64, total: UInt64, candidates: Int, grants: Int, message: String) {
        onMain {
            guard self.snapshot.id == id, self.snapshot.phase == .scanning else { return }
            self.snapshot.scanned = scanned
            self.snapshot.total = total
            self.snapshot.candidates = candidates
            self.snapshot.grants = grants
            self.append(message)
            self.saveHistory(force: false)
        }
    }

    func checkCancellation(_ id: UUID) throws {
        try Task.checkCancellation()
        lock.lock()
        let cancelled = activeID == id && requestedCancellation
        lock.unlock()
        if cancelled { throw CancellationError() }
    }

    func requestCancellation() {
        lock.lock()
        if activeID != nil { requestedCancellation = true }
        lock.unlock()
        onMain {
            guard self.snapshot.phase == .scanning else { return }
            self.cancelPending = true
            self.append("Đã yêu cầu dừng. Đang chờ lượt dò hiện tại hoàn tất…")
        }
    }

    func showHistory() { onMain { self.isPresented = true } }
    func dismiss() {
        onMain {
            guard self.snapshot.phase != .scanning else { return }
            self.isPresented = false
        }
    }

    var shareText: String {
        (["Astra · Nhật ký quét thư mục", "Ứng dụng: \(snapshot.bundleID)",
          "Trạng thái: \(snapshot.phase.rawValue)",
          "Đã dò: \(snapshot.scanned)/\(snapshot.total); thư mục: \(snapshot.candidates); truy cập được: \(snapshot.grants)", ""]
         + snapshot.logs).joined(separator: "\n")
    }

    private func finish(_ id: UUID, phase: ContainerScanPhase, detail: String) {
        lock.lock()
        if activeID == id { activeID = nil; requestedCancellation = false }
        lock.unlock()
        onMain {
            guard self.snapshot.id == id else { return }
            self.snapshot.phase = phase
            self.snapshot.detail = detail
            self.cancelPending = false
            self.append(detail)
            self.saveHistory(force: true)
        }
    }

    private func append(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        snapshot.logs.append("[\(formatter.string(from: Date()))] \(message)")
        if snapshot.logs.count > 200 { snapshot.logs.removeFirst(snapshot.logs.count - 200) }
    }

    private func saveHistory(force: Bool) {
        guard let historyURL, force || Date().timeIntervalSince(lastSavedAt) >= 3,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        lastSavedAt = Date()
        historyQueue.async {
            try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func onMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread { operation() } else { DispatchQueue.main.async(execute: operation) }
    }
}
