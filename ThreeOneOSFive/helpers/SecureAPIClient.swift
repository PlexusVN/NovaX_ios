import Foundation

enum SecureAPIError: LocalizedError {
    case invalidEndpoint
    case redirectRejected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Địa chỉ máy chủ không được phép."
        case .redirectRejected: return "Máy chủ yêu cầu chuyển hướng không được phép."
        case .invalidResponse: return "Phản hồi máy chủ không hợp lệ."
        }
    }
}

/// Cancellation can arrive before the URLSession operation exists. Installing
/// its cancellation closure afterwards must still cancel exactly that operation.
final class APIRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (() -> Void)?
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func install(_ action: @escaping () -> Void) {
        lock.lock()
        if cancelled { lock.unlock(); action() }
        else { self.action = action; lock.unlock() }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
    func clear() { lock.lock(); action = nil; lock.unlock() }
}

/// Snapshot synchronously when the gate revokes access. A delayed cancellation
/// can never enumerate or cancel requests created after a successful recovery.
final class APIRequestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var active: [UUID: APIRequestCancellation] = [:]
    var epoch: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return revision
    }
    func register(_ request: APIRequestCancellation, id: UUID, expectedEpoch: UInt64) throws {
        lock.lock()
        guard revision == expectedEpoch else { lock.unlock(); throw CancellationError() }
        active[id] = request
        lock.unlock()
    }
    func remove(_ id: UUID) {
        lock.lock(); active.removeValue(forKey: id); lock.unlock()
    }
    func cancelActive() {
        lock.lock()
        revision &+= 1
        let snapshot = Array(active.values)
        active.removeAll()
        lock.unlock()
        snapshot.forEach { $0.cancel() }
    }
}

/// All authenticated API traffic stays on this origin. Public media and the
/// LocalDevVPN device transport are separate and must never receive API secrets.
enum SecureAPIEndpointPolicy {
    static let host = AstraServerTrust.protectedHost

    static func permits(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == host,
              components.port == nil || components.port == 443,
              components.user == nil, components.password == nil,
              components.fragment == nil else { return false }

        // No encoded separators, repeated separators, dot segments or double
        // decoding: the client and server must agree on the signed route.
        let path = components.percentEncodedPath
        guard path == components.path, path.hasPrefix("/"),
              !path.contains("//"), !path.contains("\\"),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              path.utf8.allSatisfy({ $0 >= 0x21 && $0 < 0x7f }) else { return false }

        let exactPaths: Set<String> = [
            "/Nova-logo.png", "/api/verify", "/api/client/config",
            "/api/client/guides", "/api/client/mod-items",
            "/api/ff/categories", "/api/ff/patches", "/api/ff/sync",
            "/api/novax/login", "/api/novax/commands",
            "/api/security/report-crack", "/api/v2/security/report-crack",
            "/api/v2/security/jailbreak-quarantine",
            "/api/v2/security/integrity",
            "/api/v2/security/policy", "/api/v2/device/challenge",
            "/api/v2/device/context",
            "/api/v2/device/enroll", "/api/v2/novax/login",
            "/api/v2/novax/logout", "/api/v2/novax/session/renew",
            "/api/v2/novax/session/open",
            "/api/v2/ff/sync", "/api/v2/artifacts/sync", "/api/v2/artifacts/resolve"
        ]
        if exactPaths.contains(path) { return true }

        let patterns = [
            #"^/api/v2/artifacts/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/(grants|content)$"#,
            #"^/api/client/guides/[1-9][0-9]*/like$"#,
            #"^/api/(v2/)?ff/download/[A-Za-z0-9_-]+$"#,
            #"^/api/(v2/)?novax/(menu|state)/(ffth|ffmax)$"#,
            #"^/api/(v2/)?novax/patches/[1-9][0-9]*/download$"#
        ]
        return patterns.contains { path.range(of: $0, options: .regularExpression) != nil }
    }
}

/// Validate before attaching credentials, and again before every network call.
/// Redirects are rejected by CertPinningDelegate, including same-origin redirects:
/// a proof signs one exact resource and cannot be silently moved to another one.
final class SecureAPIClient {
    static let shared = SecureAPIClient()

    private let session: URLSession
    private let requests = APIRequestRegistry()
    private var invalidationObserver: NSObjectProtocol?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 180
        let apiSession = URLSession(configuration: configuration,
                                    delegate: CertPinningDelegate.shared, delegateQueue: nil)
        session = apiSession
        let requests = self.requests
        invalidationObserver = NotificationCenter.default.addObserver(
            forName: .astraNetworkAccessInvalidated, object: nil, queue: nil
        ) { _ in requests.cancelActive() }
    }

    deinit {
        if let invalidationObserver { NotificationCenter.default.removeObserver(invalidationObserver) }
        session.invalidateAndCancel()
    }

    static func validateURL(_ url: URL) throws {
        guard SecureAPIEndpointPolicy.permits(url) else { throw SecureAPIError.invalidEndpoint }
    }

    static func validate(_ request: URLRequest) throws {
        guard let url = request.url else { throw SecureAPIError.invalidEndpoint }
        try validateURL(url)
        guard ["GET", "POST", "PUT", "DELETE", "HEAD"].contains(request.httpMethod ?? "GET") else {
            throw SecureAPIError.invalidEndpoint
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Self.validate(request)
        let generation = try await NetworkAccessGate.shared.requireAllowed()
        let epoch = requests.epoch
        try await NetworkAccessGate.shared.validateGeneration(generation)
        let id = UUID()
        let cancellation = APIRequestCancellation()
        try requests.register(cancellation, id: id, expectedEpoch: epoch)
        defer { requests.remove(id); cancellation.clear() }
        try Task.checkCancellation()
        let operation = Task { [session] in
            try Task.checkCancellation()
            guard !cancellation.isCancelled else { throw CancellationError() }
            return try await session.data(for: request)
        }
        cancellation.install { operation.cancel() }
        let (data, response) = try await withTaskCancellationHandler(operation: {
            try await operation.value
        }, onCancel: { cancellation.cancel() })
        try Task.checkCancellation()
        try await NetworkAccessGate.shared.validateGeneration(generation)
        return (data, try checkedResponse(response))
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        try Self.validate(request)
        let generation = try await NetworkAccessGate.shared.requireAllowed()
        let epoch = requests.epoch
        try await NetworkAccessGate.shared.validateGeneration(generation)
        let id = UUID()
        let cancellation = APIRequestCancellation()
        try requests.register(cancellation, id: id, expectedEpoch: epoch)
        defer { requests.remove(id); cancellation.clear() }
        try Task.checkCancellation()
        let operation = Task { [session] in
            try Task.checkCancellation()
            guard !cancellation.isCancelled else { throw CancellationError() }
            return try await session.download(for: request)
        }
        cancellation.install { operation.cancel() }
        let (file, response) = try await withTaskCancellationHandler(operation: {
            try await operation.value
        }, onCancel: { cancellation.cancel() })
        do {
            try Task.checkCancellation()
            try await NetworkAccessGate.shared.validateGeneration(generation)
            return (file, try checkedResponse(response))
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    private func checkedResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw SecureAPIError.invalidResponse
        }
        try Self.validateURL(url)
        guard !(300..<400).contains(http.statusCode) else { throw SecureAPIError.redirectRejected }
        return http
    }
}
