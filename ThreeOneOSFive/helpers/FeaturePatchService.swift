import Foundation
import UIKit
import CryptoKit

// MARK: - Feature Patch Models

struct PatchCategory: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let icon: String
    let imageUrl: String
    let sortOrder: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl) ?? ""
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
    }
}

struct PatchItem: Identifiable, Codable, Equatable {
    let id: Int
    let categoryId: Int
    let name: String
    let slug: String
    let description: String
    let imageUrl: String
    let fileUrl: String
    let fileHash: String
    let fileSize: Int
    let version: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        categoryId = try container.decode(Int.self, forKey: .categoryId)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl) ?? ""
        fileUrl = try container.decodeIfPresent(String.self, forKey: .fileUrl) ?? ""
        fileHash = try container.decodeIfPresent(String.self, forKey: .fileHash) ?? ""
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize) ?? 0
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, version
        case categoryId = "category_id"
        case imageUrl = "image_url"
        case fileUrl = "file_url"
        case fileHash = "file_hash"
        case fileSize = "file_size"
    }
}

struct PatchSyncResponse: Codable {
    let success: Bool
    let hmac: String?
    let categories: [PatchCategory]
    let patches: [PatchItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        hmac = try container.decodeIfPresent(String.self, forKey: .hmac)
        categories = try container.decodeIfPresent([PatchCategory].self, forKey: .categories) ?? []
        patches = try container.decodeIfPresent([PatchItem].self, forKey: .patches) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case success, hmac, categories, patches
    }
}

struct PatchCategoriesResponse: Codable {
    let success: Bool
    let data: [PatchCategory]
}

struct PatchListResponse: Codable {
    let success: Bool
    let data: [PatchItem]
}

// MARK: - Feature Patch Service

@MainActor
final class FeaturePatchService: ObservableObject {
    @Published var categories: [PatchCategory] = []
    @Published var patches: [PatchItem] = []
    @Published var isLoading = false

    private let baseURL = "https://zynox.click"

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

    // MARK: - Category Image Memory & Disk Cache
    @Published private(set) var categoryImageCache: [Int: UIImage] = [:]

    private let categoryImagesDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("CategoryImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let metadataCacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FeaturePatches_metadata.json")
    }()

    init() {
        loadCachedMetadata()
    }

    private func loadCachedMetadata() {
        guard FileManager.default.fileExists(atPath: metadataCacheURL.path),
              let data = try? Data(contentsOf: metadataCacheURL) else { return }
        do {
            struct CachedPayload: Codable {
                let categories: [PatchCategory]
                let patches: [PatchItem]
            }
            let payload = try JSONDecoder().decode(CachedPayload.self, from: data)
            self.categories = payload.categories
            self.patches = payload.patches
            preloadCategoryImages()
        } catch {
            print("[FeaturePatch] error loading cached metadata: \(error)")
        }
    }

    private func saveCachedMetadata() {
        struct CachedPayload: Codable {
            let categories: [PatchCategory]
            let patches: [PatchItem]
        }
        let payload = CachedPayload(categories: categories, patches: patches)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: metadataCacheURL)
        }
    }

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
            saveCachedMetadata()
            preloadCategoryImages()
            print("[FeaturePatch] sync OK: \(categories.count) categories, \(patches.count) patches")

            // Tải ảnh danh mục (chỉ vài danh mục thay vì hàng chục patch)
            for category in categories {
                await downloadCategoryImageIfNeeded(category)
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

    // MARK: - Category Image Caching & Retrieval

    private func fullImageURL(for urlString: String) -> URL? {
        guard !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(cleanBase)/\(cleanPath)")
    }

    private func localCategoryImageURL(for categoryId: Int) -> URL {
        categoryImagesDir.appendingPathComponent("cat_\(categoryId).jpg")
    }

    func categoryImage(for categoryId: Int) -> UIImage? {
        if let memoryImage = categoryImageCache[categoryId] {
            return memoryImage
        }
        let localURL = localCategoryImageURL(for: categoryId)
        if FileManager.default.fileExists(atPath: localURL.path),
           let diskImage = UIImage(contentsOfFile: localURL.path) {
            categoryImageCache[categoryId] = diskImage
            return diskImage
        }
        return nil
    }

    func preloadCategoryImages() {
        for cat in categories {
            _ = categoryImage(for: cat.id)
        }
    }

    func downloadCategoryImageIfNeeded(_ category: PatchCategory, force: Bool = false) async {
        guard !category.imageUrl.isEmpty else { return }
        let localURL = localCategoryImageURL(for: category.id)
        let lastURL = defaults.string(forKey: "cat_img_url_\(category.id)")

        if !force && lastURL == category.imageUrl {
            if categoryImageCache[category.id] != nil {
                return
            }
            if FileManager.default.fileExists(atPath: localURL.path),
               let diskImage = UIImage(contentsOfFile: localURL.path) {
                categoryImageCache[category.id] = diskImage
                return
            }
        }

        guard let remoteURL = fullImageURL(for: category.imageUrl) else { return }
        do {
            let (data, response) = try await pinnedSession.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let image = UIImage(data: data) {
                try? data.write(to: localURL)
                defaults.set(category.imageUrl, forKey: "cat_img_url_\(category.id)")
                categoryImageCache[category.id] = image
                print("[FeaturePatch] category image downloaded & cached: \(category.name) (ID: \(category.id))")
            }
        } catch {
            print("[FeaturePatch] category image download error for \(category.name): \(error)")
        }
    }

    // MARK: - Patch Image Retrieval

    func cachedImage(for patch: PatchItem) -> UIImage? {
        // 1. Tối ưu theo yêu cầu: Dùng chính ảnh của danh mục cho chức năng
        if let catImage = categoryImage(for: patch.categoryId) {
            return catImage
        }
        // 2. Dự phòng: ảnh riêng của patch nếu có lưu trước đó
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
