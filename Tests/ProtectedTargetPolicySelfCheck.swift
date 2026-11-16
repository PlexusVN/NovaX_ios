import Foundation

enum TargetPolicyCheckError: Error { case failed(String) }

@main
struct ProtectedTargetPolicySelfCheck {
    static func main() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let cases = fixture["cases"] as! [[String: Any]]
        var checks = 0
        func require(_ value: Bool, _ detail: String) throws {
            guard value else { throw TargetPolicyCheckError.failed(detail) }
            checks += 1
        }
        for item in cases {
            let variant = item["variant"] as! String, kind = item["kind"] as! String
            let expected = item["expectedBundleID"] as? String
            try require(AppSecurityConfiguration.protectedBundleID(forVariant: variant) == expected,
                        "Bundle-ID parser differs from server for \(variant.debugDescription)")
            try require(AppSecurityConfiguration.permitsProtectedArtifact(variant: variant, kind: kind)
                        == (item["expectedAllowed"] as! Bool),
                        "Artifact target policy differs for \(variant.debugDescription)/\(kind)")
            try require(!AppSecurityConfiguration.permitsProtectedPackage(variant: variant, bundleIDs: []),
                        "Empty target scope accepted")
            if let expected {
                try require(AppSecurityConfiguration.permitsProtectedPackage(variant: variant, bundleIDs: [expected]),
                            "Matching package target rejected")
                try require(!AppSecurityConfiguration.permitsProtectedPackage(variant: variant,
                    bundleIDs: [expected, "com.fixture.unrelated"]), "Mixed application package accepted")
            } else {
                try require(!AppSecurityConfiguration.permitsProtectedPackage(variant: variant,
                    bundleIDs: ["com.fixture.unrelated"]), "Invalid variant matched a target")
            }
        }
        print("[PASS] \(checks) production package target checks across \(cases.count) server-generated cases")
    }
}
