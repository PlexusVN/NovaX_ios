import Foundation

@main struct ContainerIdentityEvidenceSelfCheck {
    static var checks = 0
    static func require(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); checks += 1
    }
    static func main() throws {
        let first = "com.fixture.first", second = "com.fixture.second"
        func plist(_ identifier: Any) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": identifier], format: .binary, options: 0)
        }
        let valid = try plist(first)
        for attribute in [Data(first.utf8), Data(first.utf8) + Data([0])] {
            require(ContainerIdentityEvidenceResolver.resolve(xattr: attribute, metadata: nil).identifier == first, "valid bounded UTF8 attribute")
            require(ContainerIdentityEvidenceResolver.resolve(xattr: attribute, metadata: valid).identifier == first, "sources agree")
            let conflict = ContainerIdentityEvidenceResolver.resolve(xattr: attribute, metadata: try plist(second))
            require(conflict.identifier == nil && conflict.diagnostics.contains("identity=conflict"), "valid conflicting evidence cannot choose the requested game")
        }
        for attribute in [Data(), Data([0]), Data([0xff, 0xfe]), Data("com.fixture. first".utf8),
                          Data(" com.fixture.first".utf8), Data("com.fixture.first\n".utf8),
                          Data("com.fixture\0.first".utf8), Data(repeating: 65, count: 256),
                          Data("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA".utf8)] {
            let fallback = ContainerIdentityEvidenceResolver.resolve(xattr: attribute, metadata: valid)
            require(fallback.identifier == first, "invalid attribute permits valid metadata fallback")
            require(fallback.diagnostics.contains(where: { $0.hasPrefix("xattr=invalid") }), "attribute rejection is explained")
        }
        require(ContainerIdentityEvidenceResolver.resolve(xattr: nil, metadata: valid).identifier == first, "missing attribute falls back")
        for metadata in [Data("not a plist".utf8), try plist(7), try plist(" bad.identifier"),
                         try PropertyListSerialization.data(fromPropertyList: ["unrelated": first], format: .binary, options: 0)] {
            require(ContainerIdentityEvidenceResolver.resolve(xattr: nil, metadata: metadata).identifier == nil, "bad metadata never identifies container")
            require(ContainerIdentityEvidenceResolver.resolve(xattr: Data(first.utf8), metadata: metadata).identifier == first, "independent valid attribute survives unavailable invalid metadata")
        }
        let absent = ContainerIdentityEvidenceResolver.resolve(xattr: nil, metadata: nil)
        require(absent.identifier == nil && absent.diagnostics.contains("identity=unresolved"), "all reads unavailable remains unresolved")
        print("[PASS] Actual container identity evidence: \(checks) assertions")
    }
}
