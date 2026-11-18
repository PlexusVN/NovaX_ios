import Foundation

@main struct CatalogCompatibilitySelfCheck {
    static func main() throws {
        func item(requirement: String? = nil) throws -> PatchItem {
            var row: [String: Any] = ["id": 9, "category_id": 18,
                "name": "Fixture", "slug": "fixture", "artifact_variant": "ffth"]
            if let requirement { row["required_key_type"] = requirement }
            return try JSONDecoder().decode(PatchItem.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let legacy = try item()
        precondition(legacy.requiredKeyType == "any")
        for license in ["basic", "pro", "vip", "admin"] {
            precondition(CatalogFeatureAccess.allows(licenseType: license, requiredKeyType: legacy.requiredKeyType),
                         "legacy server catalog acquired an unrelated VIP requirement")
        }
        precondition(!CatalogFeatureAccess.allows(licenseType: "unknown", requiredKeyType: "any"))
        let vip = try item(requirement: "vip")
        precondition(!CatalogFeatureAccess.allows(licenseType: "pro", requiredKeyType: vip.requiredKeyType))
        precondition(CatalogFeatureAccess.allows(licenseType: "vip", requiredKeyType: "pro"))
        precondition(!CatalogFeatureAccess.allows(licenseType: "vip", requiredKeyType: "invalid"))
        precondition(legacy.downloadIdentity == "9:ffth")
        precondition(CatalogGameGrouping.patches([legacy], for: .ffth).count == 1)
        precondition(CatalogGameGrouping.patches([legacy], for: .ffmax).isEmpty)
        print("[PASS] Astra catalog compatibility: legacy access, explicit tier restrictions and signed variant identity")
    }
}
