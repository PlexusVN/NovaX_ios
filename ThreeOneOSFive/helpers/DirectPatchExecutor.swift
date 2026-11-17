import Foundation

fileprivate final class DirectPatchPermit: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var revoked = false

    func revoke() {
        lock.lock()
        revoked = true
        lock.unlock()
    }

    func check() throws {
        try Task.checkCancellation()
        lock.lock()
        let invalid = revoked
        lock.unlock()
        if invalid { throw CancellationError() }
    }
}

enum DirectPatchExecutionContext {
    fileprivate static let key = "itech.direct-patch.permit"

    static func check() throws {
        try Task.checkCancellation()
        try (Thread.current.threadDictionary[key] as? DirectPatchPermit)?.check()
    }

    fileprivate static func execute<T>(
        _ permit: DirectPatchPermit,
        operation: () throws -> T
    ) throws -> T {
        try permit.check()
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        dictionary[key] = permit
        defer {
            if let previous {
                dictionary[key] = previous
            } else {
                dictionary.removeObject(forKey: key)
            }
        }
        return try operation()
    }
}

/// Native lookup, backup/write/verify and rollback never occupy MainActor.
/// Revocation is checked before forward writes; rollback stays uninterrupted.
enum DirectPatchExecutor {
    static func run<T: Sendable>(
        validation: @escaping @MainActor @Sendable () throws -> Void,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let permit = DirectPatchPermit()
        let notificationCenter = NotificationCenter.default
        let observers = ["AstraNetworkAccessInvalidated", "AstraAuthenticationInvalidated"].map { name in
            notificationCenter.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: nil
            ) { _ in
                permit.revoke()
            }
        }
        defer { observers.forEach { notificationCenter.removeObserver($0) } }

        let task = Task.detached(priority: .userInitiated) {
            try permit.check()
            try await validation()
            try permit.check()
            return try DirectPatchExecutionContext.execute(permit, operation: operation)
        }
        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: {
                permit.revoke()
                task.cancel()
            }
        )
    }
}
