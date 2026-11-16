import Foundation

/// Production public configuration. Private signing/master keys stay on the server.
enum AppSecurityConfiguration {
    // Owner-selected network-only client policy. ESign/KSign installs need no
    // release seal, App Store receipt, Team ID, debugger or jailbreak checks.
    // Server key/session/proof authorization and encrypted delivery stay on.
    static let localIntegrityEnforced = false
    static let apiOrigin = "https://zynox.click"
    static let apiHost = "zynox.click"
    static let tlsLeafPin = "7NfgIVpP+fdJQCMiloG7ljIWxP5OZEiAGfsc6+jgcQA="
    // Leaf plus the currently deployed WE1 intermediate: ordinary leaf renewal
    // remains possible, without trusting an arbitrary user-installed proxy CA.
    // Verified against the live, normally validated TLS chain on 2026-11-07.
    static let tlsCertificatePins: Set<String> = [
        tlsLeafPin,
        "IdQUF8E+9XNz3x4jmjWBYdYAZvahNfxagxuz9wc77wA=",
        "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="
    ]
    static func permitsCertificatePins(_ pins: [String]) -> Bool {
        !tlsCertificatePins.isDisjoint(with: pins)
    }
    static let signingKeyId = "astra-rsa-2026-01"
    static let signingPublicKeyPKCS1Base64 = "MIIBCgKCAQEA1SwdZU9s51D/5e+2ktR3IAergpRnQ9idTn2ENrUk2Hr7njStvyoPXeF/mVz+vwtXrMMF2gknnHhle7fAJE5X8So2gI4L2z20mZQB6qkXIEj2V/N7qEDRe1JvmZwmoWWg58KLmrnNfSIIYopUIRnF8zVEu8OhjBuDRHAIaNJ1Gdw9gNbHA2GIk4LAfX1KrlG6IM7qCEa7RlZJJODr8h5s8NoYAK6UKaHY/1wGWLKtQFaJX/PL01LLDR8pgbBwuflT8ze/XIh6rV4uTqFW6Mw7RXI5mEtrO95O8z9DUFkuPBxmAlMRGcp5Zg3BeDwBtdHZgm/Klg/wkb8SOVTc69pXWQIDAQAB"
    static let productSecret = "NovaX-auth-key"
    static var isConfigured: Bool { true }
    /// Legacy aliases remain available for compatibility; preparation loads its
    /// actual targets from the current authenticated catalog.
    static var protectedBundleIDs: [String] {
        ["ffth", "ffmax", "capcut"].compactMap { protectedBundleID(forVariant: $0) }.sorted()
    }
    static func protectedBundleID(forVariant variant: String) -> String? {
        switch variant {
        case "ffth": return "com.dts.freefireth"
        case "ffmax": return "com.dts.freefiremax"
        case "capcut": return "com.lemon.lvoverseas"
        default:
            let prefix = "bundle:"
            guard variant.hasPrefix(prefix) else { return nil }
            let bundleID = String(variant.dropFirst(prefix.count))
            return isValidProtectedBundleID(bundleID) ? bundleID : nil
        }
    }

    /// Matches the server package-target grammar without normalizing identity.
    /// Every component is ASCII alphanumeric with optional interior hyphens.
    static func isValidProtectedBundleID(_ bundleID: String) -> Bool {
        let bytes = Array(bundleID.utf8)
        guard !bytes.isEmpty, bytes.count <= 255 else { return false }
        var componentLength = 0
        var lastWasHyphen = false
        var dots = 0
        for byte in bytes {
            switch byte {
            case 48...57, 65...90, 97...122:
                componentLength += 1
                lastWasHyphen = false
            case 45:
                guard componentLength > 0 else { return false }
                componentLength += 1
                lastWasHyphen = true
            case 46:
                guard componentLength > 0, !lastWasHyphen else { return false }
                dots += 1
                componentLength = 0
                lastWasHyphen = false
            default:
                return false
            }
        }
        return dots >= 1 && componentLength > 0 && !lastWasHyphen
    }

    /// Arbitrary application targets apply only to packages. Native payloads
    /// keep their existing game-specific destination and restore contracts.
    static func permitsProtectedArtifact(variant: String, kind: String) -> Bool {
        switch kind {
        case "package": return protectedBundleID(forVariant: variant) != nil
        case "mod", "original": return variant == "ffth" || variant == "ffmax"
        default: return false
        }
    }

    /// The authenticated artifact target must bind every declared package target.
    /// A valid identifier alone never authorizes a package for another app.
    static func permitsProtectedPackage(variant: String, bundleIDs: [String]) -> Bool {
        guard let expected = protectedBundleID(forVariant: variant), !bundleIDs.isEmpty else { return false }
        return bundleIDs.allSatisfy { $0 == expected }
    }
}
