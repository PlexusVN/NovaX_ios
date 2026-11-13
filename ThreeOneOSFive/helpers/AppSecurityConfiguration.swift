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
    /// Preparation targets derive from the same catalog capability map.
    static var protectedBundleIDs: [String] {
        ["ffth", "ffmax", "capcut"].compactMap { protectedBundleID(forVariant: $0) }.sorted()
    }
    static func protectedBundleID(forVariant variant: String) -> String? {
        switch variant {
        case "ffth": return "com.dts.freefireth"
        case "ffmax": return "com.dts.freefiremax"
        case "capcut": return "com.lemon.lvoverseas"
        default: return nil
        }
    }
}
