import Foundation
import UIKit
import CryptoKit

@MainActor
final class FeaturePatchService: ObservableObject {
    @Published var categories: [PatchCategory] = []
    @Published var patches: [PatchItem] = []
    @Published var isLoading = false

    private let baseURL = "https://plexus-auth-api-o01h.onrender.com"

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FeaturePatches", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let patchProjectsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let defaults = UserDefaults.standard
    private let appliedPrefix = "patch_applied_"

    // MARK: - Sync

    func syncFromServer() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/ff/sync") else { return }
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: config)
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(PatchSyncResponse.self, from: data)
            guard response.success else { return }

            categories = response.categories
            patches = response.patches

            for patch in patches {
                await downloadImageIfNeeded(patch)
            }
        } catch {
            print("[FeaturePatch] sync error: \(error)")
        }
    }

    // MARK: - Download

    func downloadPatch(_ patch: PatchItem) async throws -> URL {
        let localURL = localPatchURL(patch)

        if FileManager.default.fileExists(atPath: localURL.path) {
            let localHash = sha256File(at: localURL)
            if localHash == patch.fileHash { return localURL }
        }

        guard let remoteURL = URL(string: patch.fileUrl) else {
            throw FeaturePatchError.invalidURL
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)

        let (tempURL, response) = try await session.download(from: remoteURL)
        guard let httpResp = response as? HTTPURLResponse, (200..<300).contains(httpResp.statusCode) else {
            throw FeaturePatchError.downloadFailed
        }

        let dir = cachePath(for: patch)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)

        return localURL
    }

    // MARK: - Apply / Restore

    func applyPatch(_ patch: PatchItem) async throws {
        let cachedURL = try await downloadPatch(patch)

        let destURL = patchProjectsDir.appendingPathComponent("\(patch.slug).3105")
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: cachedURL, to: destURL)

        defaults.set(true, forKey: appliedPrefix + patch.slug)
    }

    func restorePatch(_ patch: PatchItem) {
        let destURL = patchProjectsDir.appendingPathComponent("\(patch.slug).3105")
        try? FileManager.default.removeItem(at: destURL)
        defaults.removeObject(forKey: appliedPrefix + patch.slug)
    }

    func isPatchApplied(_ patch: PatchItem) -> Bool {
        let fileURL = patchProjectsDir.appendingPathComponent("\(patch.slug).3105")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func isPatchDownloaded(_ patch: PatchItem) -> Bool {
        FileManager.default.fileExists(atPath: localPatchURL(patch).path)
    }

    // MARK: - Cache Paths

    private func cachePath(for patch: PatchItem) -> URL {
        cacheDir.appendingPathComponent(patch.slug, isDirectory: true)
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
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: config)
            let (data, _) = try await session.data(from: remoteURL)
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
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum FeaturePatchError: LocalizedError {
    case invalidURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Liên kết không hợp lệ"
        case .downloadFailed: return "Tải file thất bại"
        }
    }
}
