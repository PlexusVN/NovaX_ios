import Foundation

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
    let categories: [PatchCategory]
    let patches: [PatchItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        categories = try container.decodeIfPresent([PatchCategory].self, forKey: .categories) ?? []
        patches = try container.decodeIfPresent([PatchItem].self, forKey: .patches) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case success, categories, patches
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
