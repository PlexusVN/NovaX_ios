import Foundation
import SwiftUI

// MARK: - Guide Models

struct GuideItem: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let content: String
    let mediaType: String // "video", "image", "none"
    let mediaUrl: String?
    let thumbnailUrl: String?
    var likesCount: Int
    let sortOrder: Int
    let isActive: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content
        case mediaType = "media_type"
        case mediaUrl = "media_url"
        case thumbnailUrl = "thumbnail_url"
        case likesCount = "likes_count"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "none"
        mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount) ?? 0
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encode(likesCount, forKey: .likesCount)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

private struct GuidesResponse: Codable {
    let success: Bool
    let data: [GuideItem]
}

private struct GuideLikeResponse: Codable {
    let success: Bool
    let likes_count: Int?
}

// MARK: - Guide Service

@MainActor
final class GuideService: ObservableObject {
    static let shared = GuideService()

    @Published var guides: [GuideItem] = []
    @Published var isLoading: Bool = false
    @Published var likedGuideIDs: Set<Int> = []

    private let baseURL = "https://zynox.click"
    private let likedStorageKey = "novax_liked_guide_ids_v1"

    init() {
        loadLikedState()
    }

    // MARK: - Local Liked State Persistence

    private func loadLikedState() {
        if let array = UserDefaults.standard.array(forKey: likedStorageKey) as? [Int] {
            likedGuideIDs = Set(array)
        }
    }

    private func saveLikedState() {
        UserDefaults.standard.set(Array(likedGuideIDs), forKey: likedStorageKey)
    }

    func isLiked(_ guideID: Int) -> Bool {
        likedGuideIDs.contains(guideID)
    }

    // MARK: - Fetch Guides

    func fetchGuides() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/client/guides") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
            let decoded = try JSONDecoder().decode(GuidesResponse.self, from: data)
            if decoded.success {
                self.guides = decoded.data
            }
        } catch {
            print("[GuideService] fetchGuides error: \(error)")
        }
    }

    // MARK: - Toggle Like

    func toggleLike(for guideID: Int) {
        guard let index = guides.firstIndex(where: { $0.id == guideID }) else { return }

        let alreadyLiked = likedGuideIDs.contains(guideID)

        if alreadyLiked {
            // Un-like cục bộ
            likedGuideIDs.remove(guideID)
            guides[index].likesCount = max(0, guides[index].likesCount - 1)
            saveLikedState()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            // Like (Optimistic Update)
            likedGuideIDs.insert(guideID)
            guides[index].likesCount += 1
            saveLikedState()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Gửi like lên máy chủ
            Task {
                await sendLikeToServer(guideID: guideID, targetIndex: index)
            }
        }
    }

    private func sendLikeToServer(guideID: Int, targetIndex: Int) async {
        guard let url = URL(string: "\(baseURL)/api/client/guides/\(guideID)/like") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let decoded = try JSONDecoder().decode(GuideLikeResponse.self, from: data)
            if decoded.success, let newCount = decoded.likes_count {
                if targetIndex < self.guides.count && self.guides[targetIndex].id == guideID {
                    self.guides[targetIndex].likesCount = newCount
                }
            }
        } catch {
            print("[GuideService] sendLike error: \(error)")
        }
    }
}
