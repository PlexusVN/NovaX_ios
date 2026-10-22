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
    let password: String?

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
        password = try container.decodeIfPresent(String.self, forKey: .password)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(name, forKey: .name)
        try container.encode(slug, forKey: .slug)
        try container.encode(description, forKey: .description)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encode(fileUrl, forKey: .fileUrl)
        try container.encode(fileHash, forKey: .fileHash)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(password, forKey: .password)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, version, password
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

// MARK: - NovaX Native Patch Menu Models

enum GamePatchVariant: String, CaseIterable, Identifiable, Codable {
    case ffth
    case ffmax

    var id: String { rawValue }
    var title: String { self == .ffth ? "Free Fire TH" : "Free Fire MAX" }
    var shortTitle: String { self == .ffth ? "FFTH" : "FFMAX" }
}

struct NovaXFeatureOption: Codable, Identifiable, Equatable {
    let value: Int
    let title: String
    var id: Int { value }
}

struct NovaXFeatureDefinition: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let section: String
    let type: String
    let min: Int
    let max: Int
    let `default`: Int
    let options: [NovaXFeatureOption]

    init(
        id: String,
        title: String,
        section: String,
        type: String = "toggle",
        min: Int = 0,
        max: Int = 1,
        default: Int = 0,
        options: [NovaXFeatureOption] = []
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.type = type
        self.min = min
        self.max = max
        self.default = `default`
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? id
        section = try container.decodeIfPresent(String.self, forKey: .section) ?? "Khác"
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "toggle"
        min = try container.decodeIfPresent(Int.self, forKey: .min) ?? 0
        max = try container.decodeIfPresent(Int.self, forKey: .max) ?? 1
        `default` = try container.decodeIfPresent(Int.self, forKey: .default) ?? 0
        options = try container.decodeIfPresent([NovaXFeatureOption].self, forKey: .options) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, title, section, type, min, max, `default`, options
    }
}

struct NovaXPatchRelease: Codable, Identifiable, Equatable {
    let id: Int
    let version: Int
    let gameBuild: String
    let packageId: String
    let fileSHA256: String
    let fileSize: Int
    let changelog: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, version, changelog
        case gameBuild = "game_build"
        case packageId = "package_id"
        case fileSHA256 = "file_sha256"
        case fileSize = "file_size"
        case createdAt = "created_at"
    }
}

struct NovaXRemoteFeatureState: Codable, Equatable {
    let enabled: Bool
    let value: Int
    let revision: Int64?
}

struct NovaXMenuResponse: Codable {
    let success: Bool
    let variant: String
    let release: NovaXPatchRelease?
    let desiredState: [String: NovaXRemoteFeatureState]
    let actualState: [String: NovaXRemoteFeatureState]
    let desiredRevision: Int64
    let appliedRevision: Int64
    let assemblyOnline: Bool
    let assemblyLastSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case success, variant, release
        case desiredState = "desired_state"
        case actualState = "actual_state"
        case desiredRevision = "desired_revision"
        case appliedRevision = "applied_revision"
        case assemblyOnline = "assembly_online"
        case assemblyLastSeenAt = "assembly_last_seen_at"
    }
}

struct NovaXCommandResponse: Codable {
    let success: Bool
    let code: String
    let revision: Int64?
    let assemblyOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case success, code, revision
        case assemblyOnline = "assembly_online"
    }
}

// MARK: - Feature Patch Service

@MainActor
final class FeaturePatchService: ObservableObject {
    @Published var categories: [PatchCategory] = []
    @Published var patches: [PatchItem] = []
    @Published var isLoading = false

    static let colorOptions: [NovaXFeatureOption] = [
        NovaXFeatureOption(value: 0, title: "Cầu vồng"),
        NovaXFeatureOption(value: 1, title: "Mặc định"),
        NovaXFeatureOption(value: 2, title: "Đỏ"),
        NovaXFeatureOption(value: 3, title: "Xanh lá"),
        NovaXFeatureOption(value: 4, title: "Xanh dương"),
        NovaXFeatureOption(value: 5, title: "Vàng"),
        NovaXFeatureOption(value: 6, title: "Xanh ngọc"),
        NovaXFeatureOption(value: 7, title: "Hồng"),
        NovaXFeatureOption(value: 8, title: "Cam"),
        NovaXFeatureOption(value: 9, title: "Tím"),
        NovaXFeatureOption(value: 10, title: "Trắng")
    ]

    static let defaultFeatures: [NovaXFeatureDefinition] = [
        // ESP (12)
        NovaXFeatureDefinition(id: "esp.master", title: "ESP tổng", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.box", title: "Khung ESP", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.tracer", title: "Đường kẻ", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.health", title: "Máu", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.name", title: "Tên", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.distance", title: "Khoảng cách", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.fov", title: "Vòng FOV", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.skeleton", title: "Skeleton", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.enemy", title: "Đếm địch", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.arrows", title: "Mũi tên 360°", section: "ESP", type: "toggle"),
        NovaXFeatureDefinition(id: "esp.fovRadius", title: "Bán kính FOV", section: "ESP", type: "range", min: 0, max: 31, default: 0),
        NovaXFeatureDefinition(id: "esp.lineOrigin", title: "Gốc đường kẻ", section: "ESP", type: "select", min: 0, max: 2, default: 0, options: [
            NovaXFeatureOption(value: 0, title: "Trên"),
            NovaXFeatureOption(value: 1, title: "Giữa"),
            NovaXFeatureOption(value: 2, title: "Dưới")
        ]),

        // Aim (7)
        NovaXFeatureDefinition(id: "aim.silent", title: "Silent Aim", section: "Aim", type: "toggle"),
        NovaXFeatureDefinition(id: "aim.system", title: "Aim System", section: "Aim", type: "toggle"),
        NovaXFeatureDefinition(id: "aim.systemHead", title: "Vị trí Aim System", section: "Aim", type: "select", min: 0, max: 1, default: 0, options: [
            NovaXFeatureOption(value: 0, title: "Ngực"),
            NovaXFeatureOption(value: 1, title: "Đầu")
        ]),
        NovaXFeatureDefinition(id: "aim.target", title: "Mục tiêu", section: "Aim", type: "select", min: 0, max: 2, default: 0, options: [
            NovaXFeatureOption(value: 0, title: "Gần tâm"),
            NovaXFeatureOption(value: 1, title: "Gần người"),
            NovaXFeatureOption(value: 2, title: "Máu thấp")
        ]),
        NovaXFeatureDefinition(id: "aim.headRate", title: "Tỉ lệ Head", section: "Aim", type: "select", min: 0, max: 4, default: 0, options: [
            NovaXFeatureOption(value: 0, title: "0%"),
            NovaXFeatureOption(value: 1, title: "25%"),
            NovaXFeatureOption(value: 2, title: "50%"),
            NovaXFeatureOption(value: 3, title: "75%"),
            NovaXFeatureOption(value: 4, title: "100%")
        ]),
        NovaXFeatureDefinition(id: "aim.legit", title: "Legit Aim", section: "Aim", type: "toggle"),
        NovaXFeatureDefinition(id: "aim.sniper", title: "Sniper Scope", section: "Aim", type: "toggle"),

        // Khác (14)
        NovaXFeatureDefinition(id: "misc.backJump", title: "Back Jump", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.fastSwitch", title: "Đổi súng nhanh", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.speed", title: "Tốc độ", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.speedLevel", title: "Mức tốc độ", section: "Khác", type: "range", min: 0, max: 19, default: 5),
        NovaXFeatureDefinition(id: "misc.vision", title: "Tầm nhìn", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.visionLevel", title: "Mức tầm nhìn", section: "Khác", type: "range", min: 1, max: 20, default: 10),
        NovaXFeatureDefinition(id: "misc.spin", title: "Xoay nhân vật", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.spinLevel", title: "Tốc độ xoay", section: "Khác", type: "range", min: 1, max: 15, default: 5),
        NovaXFeatureDefinition(id: "misc.buff", title: "Buff Damage", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.sensitivity", title: "Độ nhạy cao", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.fps", title: "Mở khóa FPS", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.skill", title: "Không hồi chiêu", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.ammo", title: "Tăng đạn", section: "Khác", type: "toggle"),
        NovaXFeatureDefinition(id: "misc.damage", title: "Màu sát thương", section: "Khác", type: "toggle"),

        // Màu sắc (7)
        NovaXFeatureDefinition(id: "damage.criticalColor", title: "Màu damage chí mạng", section: "Màu sắc", type: "color", min: 0, max: 10, default: 2, options: colorOptions),
        NovaXFeatureDefinition(id: "damage.normalColor", title: "Màu damage thường", section: "Màu sắc", type: "color", min: 0, max: 10, default: 10, options: colorOptions),
        NovaXFeatureDefinition(id: "damage.iconColor", title: "Màu icon damage", section: "Màu sắc", type: "color", min: 0, max: 10, default: 6, options: colorOptions),
        NovaXFeatureDefinition(id: "colors.fov", title: "Màu FOV", section: "Màu sắc", type: "color", min: 0, max: 10, default: 1, options: colorOptions),
        NovaXFeatureDefinition(id: "colors.line", title: "Màu đường kẻ", section: "Màu sắc", type: "color", min: 0, max: 10, default: 1, options: colorOptions),
        NovaXFeatureDefinition(id: "colors.box", title: "Màu khung", section: "Màu sắc", type: "color", min: 0, max: 10, default: 1, options: colorOptions),
        NovaXFeatureDefinition(id: "colors.skeleton", title: "Màu skeleton", section: "Màu sắc", type: "color", min: 0, max: 10, default: 1, options: colorOptions),

        // Hệ thống (1)
        NovaXFeatureDefinition(id: "settings.restore", title: "Khôi phục tất cả", section: "Hệ thống", type: "toggle")
    ]

    @Published private(set) var nativeRelease: NovaXPatchRelease?
    @Published private(set) var nativeFeatures: [NovaXFeatureDefinition] = FeaturePatchService.defaultFeatures
    @Published private(set) var nativeDesiredState: [String: NovaXRemoteFeatureState] = [:]
    @Published private(set) var nativeActualState: [String: NovaXRemoteFeatureState] = [:]
    @Published private(set) var nativeAssemblyOnline = false
    @Published private(set) var nativeStatusMessage = "Cheat đã sẵn sàng"
    @Published private(set) var isNativeLoading = false
    @Published private(set) var isNativeInjecting = false

    /// Per-variant (cả 2 game: ffth và ffmax)
    @Published private(set) var nativeReleaseByVariant: [GamePatchVariant: NovaXPatchRelease] = [:]
    @Published private(set) var nativeDesiredStateByVariant: [GamePatchVariant: [String: NovaXRemoteFeatureState]] = [:]
    @Published private(set) var nativeActualStateByVariant: [GamePatchVariant: [String: NovaXRemoteFeatureState]] = [:]
    @Published private(set) var nativeAssemblyOnlineByVariant: [GamePatchVariant: Bool] = [:]
    @Published private(set) var codepatchModAvailable: [GamePatchVariant: Bool] = [:]
    @Published private(set) var codepatchOriginalAvailable: [GamePatchVariant: Bool] = [:]

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
    private var nativeSessionToken = ""
    private var nativeSessionExpiresAt: Date?
    private var nativeSessionKey = ""
    private var loadedNativeVariant: GamePatchVariant?

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
        if let contentKey = try? PatchKeyStore.load(for: summary),
           let cachedDecoded = try? PatchPackageCodec.decode(data, contentKey: contentKey) {
            decoded = cachedDecoded
        } else if summary.isPasswordProtected {
            guard let password = patch.password, !password.isEmpty else {
                print("[FeaturePatch] patch '\(patch.name)' is password-protected but no password was provided by server")
                throw PatchPackageError.invalidPasswordOrCorruptedPackage
            }
            decoded = try PatchPackageCodec.decode(data, password: password)
            // Cache contentKey in iOS Keychain via PatchKeyStore so future toggles are instantaneous
            try? PatchKeyStore.store(decoded.contentKey, for: summary)
        } else {
            decoded = try PatchPackageCodec.decode(data, password: nil)
        }
        let project = decoded.project

        if StorageEngineCoordinator.shared.isAirLiftActive {
            try await StorageEngineCoordinator.shared.applyPatchProject(project)
        } else {
            _ = try DevicePatchService.apply(project: project)
        }

        defaults.set(project.id.uuidString, forKey: appliedPrefix + slug + "_projectID")
        defaults.set(true, forKey: appliedPrefix + slug)
        print("[FeaturePatch] applied successfully: \(destURL.path)")
    }

    func restorePatch(_ patch: PatchItem, auth: AuthManager) async throws {
        guard auth.authState == .verified else { throw FeaturePatchError.notAuthenticated }

        let slug = safeSlug(patch.slug)
        if let projectIDString = defaults.string(forKey: appliedPrefix + slug + "_projectID"),
           let projectID = UUID(uuidString: projectIDString) {
            if StorageEngineCoordinator.shared.isProjectAppliedThroughAirLift(projectID) {
                throw AirLiftError.executionFailed(
                    "Bản AirLift không thể khôi phục file gốc vì upstream chưa cung cấp API đọc file tùy ý. Astra giữ trạng thái đã áp dụng thay vì báo khôi phục giả."
                )
            }
            if let receipt = DevicePatchService.latestReceipt(projectID: projectID) {
                try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
                print("[FeaturePatch] restored via DevicePatchService for \(patch.name)")
            }
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

    // MARK: - NovaX Native Patch Menu

    private var novaProductSecret: String {
        Obf.s([254, 223, 198, 209, 232, 157, 209, 197, 196, 216, 157, 219, 213, 201], 0xB0)
    }

    private func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func serverMessage(from data: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fallback }
        if let message = object["message"] as? String, !message.isEmpty {
            let lower = message.lowercased()
            if lower.contains("/") || lower.contains("\\") || lower.contains("assembly") ||
               lower.contains("codepatch") || lower.contains("patch") || lower.contains("file") ||
               lower.contains("dir") || lower.contains("container") || lower.contains("documents") {
                return fallback
            }
            return message
        }
        if let code = object["code"] as? String, !code.isEmpty {
            let lower = code.lowercased()
            if lower.contains("/") || lower.contains("\\") || lower.contains("assembly") ||
               lower.contains("codepatch") || lower.contains("patch") || lower.contains("file") ||
               lower.contains("dir") || lower.contains("container") || lower.contains("documents") {
                return fallback
            }
            return code
        }
        return fallback
    }

    private func ensureNativeSession(auth: AuthManager, force: Bool = false) async throws {
        guard auth.authState == .verified, !auth.licenseKey.isEmpty else {
            throw NovaXControlError.message("Vui lòng đăng nhập Astra trước")
        }
        if !force,
           !nativeSessionToken.isEmpty,
           nativeSessionKey.caseInsensitiveCompare(auth.licenseKey) == .orderedSame,
           let expires = nativeSessionExpiresAt,
           expires.timeIntervalSinceNow > 30 {
            return
        }

        guard let url = URL(string: "\(baseURL)/api/novax/login") else {
            throw NovaXControlError.message("URL máy chủ không hợp lệ")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": auth.licenseKey,
            "product": novaProductSecret
        ])

        let (data, response) = try await pinnedSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NovaXControlError.message("Phản hồi đăng nhập phiên không hợp lệ")
        }
        guard (200..<300).contains(http.statusCode), json["success"] as? Bool == true else {
            throw NovaXControlError.message(serverMessage(from: data, fallback: "Không thể tạo phiên Astra"))
        }

        let code = json["code"] as? String ?? ""
        let responseKey = json["key"] as? String ?? ""
        let type = json["type"] as? String ?? ""
        let expiresAt = json["expires_at"] as? String ?? ""
        let sessionToken = json["app_session_token"] as? String ?? ""
        let sessionExpires = json["session_expires_at"] as? String ?? ""
        let serverTime = json["server_time"] as? String ?? ""
        let receivedHMAC = json["hmac"] as? String ?? ""
        let message = "true|\(code)|\(responseKey)|\(type)|\(expiresAt)|\(sessionToken)|\(sessionExpires)|\(serverTime)"
        let expectedHMAC = HMACUtils.compute(key: novaProductSecret, message: message)
        guard !sessionToken.isEmpty, !receivedHMAC.isEmpty, receivedHMAC == expectedHMAC else {
            throw NovaXControlError.message("Chữ ký phiên Astra không hợp lệ")
        }

        nativeSessionToken = sessionToken
        nativeSessionExpiresAt = parseISODate(sessionExpires)
        nativeSessionKey = auth.licenseKey
    }

    private func nativeRequest(_ url: URL, auth: AuthManager, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(nativeSessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.licenseKey, forHTTPHeaderField: "X-Auth-Key")
        return request
    }

    func loadNativeMenu(variant: GamePatchVariant, auth: AuthManager, showLoading: Bool = true) async throws {
        if loadedNativeVariant != variant {
            loadedNativeVariant = variant
            nativeRelease = nil
            nativeFeatures = FeaturePatchService.defaultFeatures
            nativeDesiredState = [:]
            nativeActualState = [:]
            nativeAssemblyOnline = false
            nativeStatusMessage = "Đang tải \(variant.shortTitle)..."
        }
        if showLoading { isNativeLoading = true }
        defer { if showLoading { isNativeLoading = false } }
        try await ensureNativeSession(auth: auth)
        guard let url = URL(string: "\(baseURL)/api/novax/menu/\(variant.rawValue)") else {
            throw NovaXControlError.message("URL menu không hợp lệ")
        }
        var request = nativeRequest(url, auth: auth)
        var (data, response) = try await pinnedSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await ensureNativeSession(auth: auth, force: true)
            request = nativeRequest(url, auth: auth)
            (data, response) = try await pinnedSession.data(for: request)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NovaXControlError.message(serverMessage(from: data, fallback: "Không thể đồng bộ trạng thái máy chủ"))
        }
        let menu = try JSONDecoder().decode(NovaXMenuResponse.self, from: data)
        guard menu.success else { throw NovaXControlError.message("Máy chủ từ chối yêu cầu") }
        nativeRelease = menu.release
        nativeFeatures = FeaturePatchService.defaultFeatures
        nativeDesiredState = menu.desiredState
        nativeActualState = menu.actualState
        nativeAssemblyOnline = menu.assemblyOnline
        nativeStatusMessage = menu.assemblyOnline ? "Cheat đang hoạt động trong game" : "Chưa vào game"
    }

    func refreshNativeState(variant: GamePatchVariant, auth: AuthManager) async {
        guard loadedNativeVariant == variant,
              let url = URL(string: "\(baseURL)/api/novax/state/\(variant.rawValue)") else { return }
        do {
            try await ensureNativeSession(auth: auth)
            var (data, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                try await ensureNativeSession(auth: auth, force: true)
                (data, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let state = try JSONDecoder().decode(NovaXMenuResponse.self, from: data)
            nativeDesiredState = state.desiredState
            nativeActualState = state.actualState
            nativeAssemblyOnline = state.assemblyOnline
            nativeStatusMessage = state.assemblyOnline ? "Cheat đang hoạt động trong game" : "Chưa vào game"
        } catch {
            nativeStatusMessage = "Mất kết nối trạng thái"
        }
    }

    // MARK: - Cả 2 variant cùng lúc (FeaturesView dùng)
    func loadNativeMenuForBothVariants(auth: AuthManager, showLoading: Bool = true) async throws {
        if showLoading { isNativeLoading = true }
        defer { if showLoading { isNativeLoading = false } }
        try await ensureNativeSession(auth: auth)
        // Load song song cả 2 variant
        let variants: [GamePatchVariant] = [.ffth, .ffmax]
        var firstError: Error?
        for v in variants {
            do {
                let menu = try await fetchNativeMenu(variant: v, auth: auth)
                nativeReleaseByVariant[v] = menu.release
                nativeDesiredStateByVariant[v] = menu.desiredState
                nativeActualStateByVariant[v] = menu.actualState
                nativeAssemblyOnlineByVariant[v] = menu.assemblyOnline
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        // Trạng thái server của Assembly đang online là nguồn hiển thị chính.
        // Nếu chưa có Assembly, dùng release đầu tiên chỉ để hiển thị metadata.
        let displayedVariant = variants.first(where: { nativeAssemblyOnlineByVariant[$0] == true })
            ?? variants.first(where: { nativeReleaseByVariant[$0] != nil })
        if let displayedVariant {
            nativeRelease = nativeReleaseByVariant[displayedVariant]
            nativeFeatures = FeaturePatchService.defaultFeatures
            nativeDesiredState = nativeDesiredStateByVariant[displayedVariant] ?? [:]
            nativeActualState = nativeActualStateByVariant[displayedVariant] ?? [:]
            nativeAssemblyOnline = nativeAssemblyOnlineByVariant[displayedVariant] ?? false
            nativeStatusMessage = nativeAssemblyOnline ? "Cheat đang hoạt động trong game" : "Chưa vào game"
        } else {
            nativeFeatures = FeaturePatchService.defaultFeatures
        }
        // Check codepatch availability
        await loadCodePatchAvailability(auth: auth)
        if let firstError = firstError, nativeReleaseByVariant.isEmpty { throw firstError }
    }

    func refreshNativeStateForBothVariants(auth: AuthManager) async {
        try? await ensureNativeSession(auth: auth)
        for v in [GamePatchVariant.ffth, .ffmax] {
            guard let url = URL(string: "\(baseURL)/api/novax/state/\(v.rawValue)") else { continue }
            do {
                var (data, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    try await ensureNativeSession(auth: auth, force: true)
                    (data, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let state = try JSONDecoder().decode(NovaXMenuResponse.self, from: data)
                nativeDesiredStateByVariant[v] = state.desiredState
                nativeActualStateByVariant[v] = state.actualState
                nativeAssemblyOnlineByVariant[v] = state.assemblyOnline
            } catch {}
        }
        let activeVariant: GamePatchVariant = [GamePatchVariant.ffth, .ffmax].first(where: { nativeAssemblyOnlineByVariant[$0] == true })
            ?? (nativeActualStateByVariant[.ffmax]?.isEmpty == false ? .ffmax : .ffth)
        self.nativeActualState = nativeActualStateByVariant[activeVariant] ?? [:]
        self.nativeDesiredState = nativeDesiredStateByVariant[activeVariant] ?? [:]
        self.nativeAssemblyOnline = nativeAssemblyOnlineByVariant.values.contains(true)
        self.nativeStatusMessage = self.nativeAssemblyOnline ? "Cheat đang hoạt động trong game" : "Chưa vào game"
    }

    func loadCodePatchAvailability(auth: AuthManager) async {
        for v in [GamePatchVariant.ffth, .ffmax] {
            for kind in [CodePatchKind.mod, .original] {
                let key = "codepatch_avail_\(v.rawValue)_\(kind.rawValue)"
                do {
                    try await ensureNativeSession(auth: auth)
                    guard let url = URL(string: "\(baseURL)/api/novax/codepatch/\(v.rawValue)/\(kind.rawValue)/download") else { continue }
                    // Dùng GET thử — nếu file có, server trả 200 + binary (bỏ qua body); nếu không, 404.
                    // (URLSession.data(for:) chỉ hỗ trợ GET/POST, nên không dùng HEAD được ở đây.)
                    let (_, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        defaults.set(true, forKey: key)
                    } else {
                        defaults.set(false, forKey: key)
                    }
                } catch {
                    defaults.set(false, forKey: key)
                }
            }
        }
        codepatchModAvailable[.ffth] = defaults.bool(forKey: "codepatch_avail_ffth_mod")
        codepatchModAvailable[.ffmax] = defaults.bool(forKey: "codepatch_avail_ffmax_mod")
        codepatchOriginalAvailable[.ffth] = defaults.bool(forKey: "codepatch_avail_ffth_original")
        codepatchOriginalAvailable[.ffmax] = defaults.bool(forKey: "codepatch_avail_ffmax_original")
    }

    private func fetchNativeMenu(variant: GamePatchVariant, auth: AuthManager) async throws -> NovaXMenuResponse {
        guard let url = URL(string: "\(baseURL)/api/novax/menu/\(variant.rawValue)") else {
            throw NovaXControlError.message("URL menu không hợp lệ")
        }
        var (data, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await ensureNativeSession(auth: auth, force: true)
            (data, response) = try await pinnedSession.data(for: nativeRequest(url, auth: auth))
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NovaXControlError.message(serverMessage(from: data, fallback: "Không thể tải Patch Menu \(variant.title)"))
        }
        return try JSONDecoder().decode(NovaXMenuResponse.self, from: data)
    }

    func sendNativeCommand(
        feature: NovaXFeatureDefinition,
        enabled: Bool,
        value: Int,
        auth: AuthManager
    ) async throws {
        var acceptedCount = 0
        var lastError: Error?
        let releasedVariants = [GamePatchVariant.ffth, .ffmax].filter { nativeReleaseByVariant[$0] != nil }
        let targetVariants = releasedVariants.isEmpty ? [GamePatchVariant.ffth, .ffmax] : releasedVariants
        for v in targetVariants {
            do {
                try await sendNativeCommand(
                    feature: feature,
                    enabled: enabled,
                    value: value,
                    variant: v,
                    auth: auth
                )
                acceptedCount += 1
            } catch {
                lastError = error
            }
        }
        guard acceptedCount > 0 else {
            throw lastError ?? NovaXControlError.message("Máy chủ không lưu được trạng thái chức năng")
        }
        // Re-read the authoritative snapshot. Nothing is persisted locally.
        await refreshNativeStateForBothVariants(auth: auth)
        if let lastError { throw lastError }
    }

    func sendNativeCommand(
        feature: NovaXFeatureDefinition,
        enabled: Bool,
        value: Int,
        variant: GamePatchVariant,
        auth: AuthManager
    ) async throws {
        try await ensureNativeSession(auth: auth)
        guard let url = URL(string: "\(baseURL)/api/novax/commands") else {
            throw NovaXControlError.message("URL gửi lệnh không hợp lệ")
        }
        var request = nativeRequest(url, auth: auth, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "variant": variant.rawValue,
            "feature": feature.id,
            "enabled": enabled,
            "value": value,
            "client_command_id": UUID().uuidString
        ])
        let (data, response) = try await pinnedSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NovaXControlError.message(serverMessage(from: data, fallback: "Không thể gửi lệnh"))
        }
        let result = try JSONDecoder().decode(NovaXCommandResponse.self, from: data)
        guard result.success else { throw NovaXControlError.message(result.code) }
        nativeAssemblyOnline = result.assemblyOnline ?? false
        nativeAssemblyOnlineByVariant[variant] = result.assemblyOnline ?? false
        nativeStatusMessage = nativeAssemblyOnline ? "Đã áp dụng cheat vào game" : "Đã lưu cài đặt (chờ vào game)"
    }

    func injectNativePatch(variant: GamePatchVariant, auth: AuthManager) async throws {
        guard let release = nativeReleaseByVariant[variant] else {
            throw NovaXControlError.message("Chưa có cheat \(variant.shortTitle) đang phát hành")
        }
        try await ensureNativeSession(auth: auth)
        guard let url = URL(string: "\(baseURL)/api/novax/patches/\(release.id)/download") else {
            throw NovaXControlError.message("URL tải cheat không hợp lệ")
        }
        isNativeInjecting = true
        defer { isNativeInjecting = false }

        let (temporaryURL, response) = try await pinnedSession.download(for: nativeRequest(url, auth: auth))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? Data(contentsOf: temporaryURL)) ?? Data()
            throw NovaXControlError.message(serverMessage(from: body, fallback: "Tải cheat thất bại"))
        }
        let downloadedHash = sha256File(at: temporaryURL)
        guard downloadedHash.caseInsensitiveCompare(release.fileSHA256) == .orderedSame else {
            throw FeaturePatchError.hashMismatch(expected: release.fileSHA256, got: downloadedHash)
        }

        let destination = patchProjectsDir.appendingPathComponent("native-\(variant.rawValue)-v\(release.version).3105")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        let data = try Data(contentsOf: destination)
        let summary = try PatchPackageCodec.inspect(data)
        let decoded: DecodedPatchPackage
        if let contentKey = try? PatchKeyStore.load(for: summary),
           let cached = try? PatchPackageCodec.decode(data, contentKey: contentKey) {
            decoded = cached
        } else {
            decoded = try PatchPackageCodec.decode(data, password: nil)
        }

        if StorageEngineCoordinator.shared.isAirLiftActive {
            try await StorageEngineCoordinator.shared.applyPatchProject(decoded.project)
        } else {
            _ = try DevicePatchService.apply(project: decoded.project)
        }
        defaults.set(release.id, forKey: "native_patch_release_\(variant.rawValue)")
        defaults.set(decoded.project.id.uuidString, forKey: "native_patch_project_\(variant.rawValue)")
        nativeStatusMessage = "Đã kích hoạt cheat \(variant.shortTitle) v\(release.version)"
    }

    func isNativePatchInjected(variant: GamePatchVariant) -> Bool {
        guard let release = nativeReleaseByVariant[variant] else { return false }
        return defaults.integer(forKey: "native_patch_release_\(variant.rawValue)") == release.id
    }

    // MARK: - CodePatch
    // Tải file mod/original từ server và ghi đè vào thư mục codepatch
    // bên trong container Free Fire (com.dts.freefireth / com.dts.freefiremax):
    //   Documents/contentcache/Compulsory/ios/gameassetbundles/codepatch/

    private static let legacyCodePatchFileName = "assembly-csharp-patch.q3QzMLimIntmNHG7~2BbafinWQ1mU~3D"

    private struct DownloadedCodePatch {
        let temporaryURL: URL
        let fileName: String
    }

    private static func validCodePatchFileName(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value.utf8.count <= 255,
              value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"),
              value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
            return nil
        }
        return value
    }

    /// Đường dẫn tuyệt đối tới file codepatch trong container Free Fire
    static func codePatchURL(variant: GamePatchVariant) -> URL? {
        let bundleID: String
        let baseDir: String
        switch variant {
        case .ffth:
            bundleID = "com.dts.freefireth"
        case .ffmax:
            bundleID = "com.dts.freefiremax"
        }
        // Ưu tiên container path từ ContainerStore (hỗ trợ cả AirLift và direct)
        if let container = ContainerStore.resolveAppContainerPath(bundleID: bundleID) {
            baseDir = container
        } else {
            #if targetEnvironment(simulator)
            baseDir = NSHomeDirectory()
            #else
            return nil
            #endif
        }
        let dirPath = (baseDir as NSString)
            .appendingPathComponent("Documents/contentcache/Compulsory/ios/gameassetbundles/codepatch")
        let storedName = UserDefaults.standard.string(forKey: "codepatch_file_name_\(variant.rawValue)")
        let fileName = validCodePatchFileName(storedName) ?? legacyCodePatchFileName
        return URL(fileURLWithPath: (dirPath as NSString).appendingPathComponent(fileName))
    }

    /// Trả về thư mục chứa file codepatch (tạo nếu chưa có)
    static func codePatchDirectory(variant: GamePatchVariant) -> URL? {
        let bundleID: String
        switch variant {
        case .ffth: bundleID = "com.dts.freefireth"
        case .ffmax: bundleID = "com.dts.freefiremax"
        }
        let baseDir: String
        if let container = ContainerStore.resolveAppContainerPath(bundleID: bundleID) {
            baseDir = container
        } else {
            #if targetEnvironment(simulator)
            baseDir = NSHomeDirectory()
            #else
            return nil
            #endif
        }
        let dirPath = (baseDir as NSString)
            .appendingPathComponent("Documents/contentcache/Compulsory/ios/gameassetbundles/codepatch")
        let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }

    /// Kiểm tra file codepatch hiện tại trong thiết bị đã được ghi chưa
    static func isCodePatchWritten(variant: GamePatchVariant) -> Bool {
        guard let url = codePatchURL(variant: variant) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    enum CodePatchKind: String {
        case mod
        case original
    }

    /// Tải file codepatch (mod hoặc original) từ server về thư mục tạm
    private func downloadCodePatchFile(
        variant: GamePatchVariant,
        kind: CodePatchKind,
        auth: AuthManager
    ) async throws -> DownloadedCodePatch {
        try await ensureNativeSession(auth: auth)
        guard let url = URL(string: "\(baseURL)/api/novax/codepatch/\(variant.rawValue)/\(kind.rawValue)/download") else {
            throw NovaXControlError.message("Không thể kết nối đến máy chủ")
        }
        var request = nativeRequest(url, auth: auth)
        request.timeoutInterval = 60
        do {
            let (tempURL, response) = try await pinnedSession.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = (try? Data(contentsOf: tempURL)) ?? Data()
                throw NovaXControlError.message(serverMessage(from: body, fallback: "Tải dữ liệu thất bại"))
            }
            let encodedName = http.value(forHTTPHeaderField: "X-CodePatch-File-Name")
            let decodedName = encodedName?.removingPercentEncoding
            let fileName = FeaturePatchService.validCodePatchFileName(decodedName)
                ?? FeaturePatchService.legacyCodePatchFileName
            return DownloadedCodePatch(temporaryURL: tempURL, fileName: fileName)
        } catch let err as NovaXControlError {
            throw err
        } catch {
            throw NovaXControlError.message("Lỗi kết nối khi tải dữ liệu. Vui lòng thử lại sau.")
        }
    }

    /// Inject: tải file MOD từ server và ghi đè vào container Free Fire
    func injectCodePatch(variant: GamePatchVariant, auth: AuthManager) async throws {
        guard let destDir = FeaturePatchService.codePatchDirectory(variant: variant) else {
            throw NovaXControlError.message("Không thể truy cập dữ liệu game \(variant.title). Vui lòng kiểm tra quyền ứng dụng.")
        }
        let downloaded = try await downloadCodePatchFile(variant: variant, kind: .mod, auth: auth)
        let destURL = destDir.appendingPathComponent(downloaded.fileName)
        defer { try? FileManager.default.removeItem(at: downloaded.temporaryURL) }

        do {
            let fileData = try Data(contentsOf: downloaded.temporaryURL)
            if StorageEngineCoordinator.shared.isAirLiftActive {
                try await StorageEngineCoordinator.shared.writeFile(data: fileData, toPath: destURL.path)
            } else if FileManager.default.fileExists(atPath: destURL.path) {
                do {
                    _ = try FileReplacementService.replace(target: destURL, with: downloaded.temporaryURL)
                } catch {
                    try fileData.write(to: destURL, options: .atomic)
                }
            } else {
                try fileData.write(to: destURL, options: .atomic)
            }
        } catch {
            throw NovaXControlError.message("Không thể kích hoạt cheat cho \(variant.title). Vui lòng kiểm tra lại quyền ứng dụng.")
        }
        defaults.set(downloaded.fileName, forKey: "codepatch_file_name_\(variant.rawValue)")
        defaults.set(true, forKey: "codepatch_mod_written_\(variant.rawValue)")
        defaults.set(Date().timeIntervalSince1970, forKey: "codepatch_mod_time_\(variant.rawValue)")
        nativeStatusMessage = "Đã kích hoạt cheat \(variant.shortTitle)"
    }

    /// Unject: tải file GỐC từ server và ghi đè vào container Free Fire
    func unjectCodePatch(variant: GamePatchVariant, auth: AuthManager) async throws {
        guard let destDir = FeaturePatchService.codePatchDirectory(variant: variant) else {
            throw NovaXControlError.message("Không thể truy cập dữ liệu game \(variant.title). Vui lòng kiểm tra quyền ứng dụng.")
        }
        let downloaded = try await downloadCodePatchFile(variant: variant, kind: .original, auth: auth)
        let destURL = destDir.appendingPathComponent(downloaded.fileName)
        defer { try? FileManager.default.removeItem(at: downloaded.temporaryURL) }

        do {
            let fileData = try Data(contentsOf: downloaded.temporaryURL)
            if StorageEngineCoordinator.shared.isAirLiftActive {
                try await StorageEngineCoordinator.shared.writeFile(data: fileData, toPath: destURL.path)
            } else if FileManager.default.fileExists(atPath: destURL.path) {
                do {
                    _ = try FileReplacementService.replace(target: destURL, with: downloaded.temporaryURL)
                } catch {
                    try fileData.write(to: destURL, options: .atomic)
                }
            } else {
                try fileData.write(to: destURL, options: .atomic)
            }
        } catch {
            throw NovaXControlError.message("Không thể khôi phục game \(variant.title). Vui lòng kiểm tra lại quyền ứng dụng.")
        }
        defaults.set(downloaded.fileName, forKey: "codepatch_file_name_\(variant.rawValue)")
        defaults.set(false, forKey: "codepatch_mod_written_\(variant.rawValue)")
        defaults.set(Date().timeIntervalSince1970, forKey: "codepatch_original_time_\(variant.rawValue)")
        nativeStatusMessage = "Đã khôi phục gốc \(variant.shortTitle)"
    }

    func isCodePatchInjected(variant: GamePatchVariant) -> Bool {
        return defaults.bool(forKey: "codepatch_mod_written_\(variant.rawValue)")
    }

    // MARK: - Hash

    private func sha256File(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum NovaXControlError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
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
        case .invalidURL: return "Liên kết không hợp lệ"
        case .downloadFailed: return "Tải dữ liệu thất bại từ máy chủ"
        case .httpError(let code): return "Máy chủ phản hồi mã lỗi \(code)"
        case .hashMismatch: return "Dữ liệu không toàn vẹn. Vui lòng thử lại"
        case .notAuthenticated: return "Vui lòng đăng nhập để sử dụng chức năng này"
        }
    }
}
