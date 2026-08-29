import Foundation
import UIKit
import CryptoKit

@MainActor
final class FeaturePatchService: ObservableObject {
    @Published var categories: [PatchCategory] = []
    @Published var patches: [PatchItem] = []
    @Published var isLoading = false

    private let baseURL = "https://plexus-auth-api-o01h.onrender.com"

    private let pinnedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config,
                          delegate: CertPinningDelegate.shared,
                          delegateQueue: nil)
    }()

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FeaturePatches", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let patchProjectsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let defaults = UserDefaults.standard
    private let appliedPrefix = "patch_applied_"

    // MARK: - Auth Headers

    private func authHeaders(_ auth: AuthManager) -> [String: String] {
        [
            "X-Auth-Key": auth.licenseKey,
            "X-Auth-HWID": auth.hwid
        ]
    }

    private func authorizedRequest(_ url: URL, auth: AuthManager) -> URLRequest {
        var request = URLRequest(url: url)
        for (key, value) in authHeaders(auth) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    // MARK: - Slug Safety

    private func safeSlug(_ slug: String) -> String {
        slug.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\0", with: "_")
    }

    // MARK: - Sync

    func syncFromServer(auth: AuthManager) async {
        guard auth.authState == .verified else {
            print("[FeaturePatch] sync blocked: not authenticated")
            return
        }

        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/ff/sync") else { return }
        print("[FeaturePatch] syncing from: \(url.absoluteString)")
        do {
            let request = authorizedRequest(url, auth: auth)
            let (data, _) = try await pinnedSession.data(for: request)
            let response = try JSONDecoder().decode(PatchSyncResponse.self, from: data)
            guard response.success else {
                print("[FeaturePatch] sync: server returned success=false")
                return
            }
            
            // HMAC Verification
            guard let serverHmac = response.hmac, !serverHmac.isEmpty else {
                print("[FeaturePatch] sync: missing HMAC signature")
                return
            }
            
            let expectedMessage = "\(response.success)|\(response.categories.count)|\(response.patches.count)"
            let computedHmac = HMACUtils.compute(key: auth.licenseKey, message: expectedMessage)
            
            guard serverHmac == computedHmac else {
                print("[FeaturePatch] sync: HMAC mismatch! Possible MITM attack.")
                return
            }

            categories = response.categories
            patches = response.patches
            print("[FeaturePatch] sync OK: \(categories.count) categories, \(patches.count) patches")

            for patch in patches {
                await downloadImageIfNeeded(patch)
            }
        } catch {
            print("[FeaturePatch] sync error: \(error)")
        }
    }

    // MARK: - Download

    func downloadPatch(_ patch: PatchItem, auth: AuthManager) async throws -> URL {
        guard auth.authState == .verified else {
            throw FeaturePatchError.notAuthenticated
        }

        let localURL = localPatchURL(patch)

        if FileManager.default.fileExists(atPath: localURL.path) {
            let localHash = sha256File(at: localURL)
            if localHash == patch.fileHash { return localURL }
        }

        guard !patch.fileUrl.isEmpty else {
            print("[FeaturePatch] fileUrl is empty for patch: \(patch.name)")
            throw FeaturePatchError.invalidURL
        }

        guard let remoteURL = URL(string: patch.fileUrl) else {
            print("[FeaturePatch] invalid URL: \(patch.fileUrl)")
            throw FeaturePatchError.invalidURL
        }

        print("[FeaturePatch] downloading patch from: \(remoteURL.absoluteString)")

        let request = authorizedRequest(remoteURL, auth: auth)
        let (tempURL, response) = try await pinnedSession.download(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw FeaturePatchError.downloadFailed
        }

        print("[FeaturePatch] download response: HTTP \(httpResp.statusCode)")

        guard (200..<300).contains(httpResp.statusCode) else {
            throw FeaturePatchError.httpError(statusCode: httpResp.statusCode)
        }

        let dir = cachePath(for: patch)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)

        if !patch.fileHash.isEmpty {
            let downloadedHash = sha256File(at: localURL)
            if downloadedHash != patch.fileHash {
                try? FileManager.default.removeItem(at: localURL)
                print("[FeaturePatch] hash mismatch: expected \(patch.fileHash), got \(downloadedHash)")
                throw FeaturePatchError.hashMismatch(expected: patch.fileHash, got: downloadedHash)
            }
        }

        return localURL
    }

    // MARK: - Apply / Restore

    func applyPatch(_ patch: PatchItem, auth: AuthManager) async throws {
        guard auth.authState == .verified else {
            throw FeaturePatchError.notAuthenticated
        }

        print("[FeaturePatch] applying patch: \(patch.name) (slug: \(patch.slug))")
        let cachedURL = try await downloadPatch(patch, auth: auth)
        print("[FeaturePatch] download OK, cached at: \(cachedURL.path)")

        let slug = safeSlug(patch.slug)
        let destURL = patchProjectsDir.appendingPathComponent("\(slug).3105")
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: cachedURL, to: destURL)

        let data = try Data(contentsOf: cachedURL)
        let summary = try PatchPackageCodec.inspect(data)
        let decoded: DecodedPatchPackage
        if let contentKey = try PatchKeyStore.load(for: summary) {
            decoded = try PatchPackageCodec.decode(data, contentKey: contentKey)
        } else if summary.isPasswordProtected {
            throw FeaturePatchError.invalidURL
        } else {
            decoded = try PatchPackageCodec.decode(data, password: nil)
        }
        let project = decoded.project

        _ = try DevicePatchService.apply(project: project)

        defaults.set(project.id.uuidString, forKey: appliedPrefix + slug + "_projectID")
        defaults.set(true, forKey: appliedPrefix + slug)
        print("[FeaturePatch] applied successfully: \(destURL.path)")
    }

    func restorePatch(_ patch: PatchItem, auth: AuthManager) async {
        guard auth.authState == .verified else { return }

        let slug = safeSlug(patch.slug)
        if let projectIDString = defaults.string(forKey: appliedPrefix + slug + "_projectID"),
           let projectID = UUID(uuidString: projectIDString),
           let receipt = DevicePatchService.latestReceipt(projectID: projectID) {
            try? DevicePatchService.restore(receipt: receipt)
            print("[FeaturePatch] restored via DevicePatchService for \(patch.name)")
        }

        let destURL = patchProjectsDir.appendingPathComponent("\(slug).3105")
        try? FileManager.default.removeItem(at: destURL)
        defaults.removeObject(forKey: appliedPrefix + slug)
        defaults.removeObject(forKey: appliedPrefix + slug + "_projectID")
        print("[FeaturePatch] restored patch: \(patch.name)")
    }

    func isPatchApplied(_ patch: PatchItem) -> Bool {
        let fileURL = patchProjectsDir.appendingPathComponent("\(safeSlug(patch.slug)).3105")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func isPatchDownloaded(_ patch: PatchItem) -> Bool {
        FileManager.default.fileExists(atPath: localPatchURL(patch).path)
    }

    // MARK: - Cache Paths

    private func cachePath(for patch: PatchItem) -> URL {
        cacheDir.appendingPathComponent(safeSlug(patch.slug), isDirectory: true)
    }

    private func localPatchURL(_ patch: PatchItem) -> URL {
        cachePath(for: patch).appendingPathComponent("patch.3105")
    }

    private func localImageURL(_ patch: PatchItem) -> URL {
        cachePath(for: patch).appendingPathComponent("image.jpg")
    }

    // MARK: - Image Download

    private func downloadImageIfNeeded(_ patch: PatchItem) async {
        guard !patch.imageUrl.isEmpty else { return }
        let localURL = localImageURL(patch)
        guard !FileManager.default.fileExists(atPath: localURL.path) else { return }

        guard let remoteURL = URL(string: patch.imageUrl) else { return }
        do {
            let (data, _) = try await pinnedSession.data(from: remoteURL)
            let dir = cachePath(for: patch)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: localURL)
        } catch {
            print("[FeaturePatch] image download error: \(error)")
        }
    }

    func cachedImage(for patch: PatchItem) -> UIImage? {
        let url = localImageURL(patch)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Hash

    private func sha256File(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum FeaturePatchError: LocalizedError {
    case invalidURL
    case downloadFailed
    case httpError(statusCode: Int)
    case hashMismatch(expected: String, got: String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Liên kết file không hợp lệ"
        case .downloadFailed: return "Tải file thất bại từ máy chủ"
        case .httpError(let code): return "Máy chủ trả lỗi HTTP \(code)"
        case .hashMismatch(let expected, let got): return "File không khớp (mong đợi: \(expected.prefix(16))..., nhận: \(got.prefix(16))...)"
        case .notAuthenticated: return "Vui lòng đăng nhập để sử dụng chức năng này"
        }
    }
}
