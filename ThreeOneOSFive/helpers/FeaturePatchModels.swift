import Foundation

struct PatchCategory: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let icon: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, icon
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
    let categories: [PatchCategory]
    let patches: [PatchItem]
}

struct PatchCategoriesResponse: Codable {
    let success: Bool
    let data: [PatchCategory]
}

struct PatchListResponse: Codable {
    let success: Bool
    let data: [PatchItem]
}
