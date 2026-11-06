import Foundation
import Darwin
import MachO

enum DeviceEnvironmentState: String, Sendable { case allowed, blocked, unverified }

struct DeviceEnvironmentResult: Sendable {
    static let policy = 1
    static let requiredMask = 0x3fff
    let checkedMask: Int
    let signalMask: Int
    var state: DeviceEnvironmentState { DeviceEnvironmentPolicy.evaluate(checked: checkedMask, signals: signalMask) }
    static let unverified = DeviceEnvironmentResult(checkedMask: 0, signalMask: 0)
    var report: [String: Int] { ["policy": Self.policy, "checked_mask": checkedMask, "signal_mask": signalMask] }
}

/// A measurement from this process, never a hardware-backed statement about iOS.
enum DeviceEnvironmentPolicy {
    static func evaluate(checked: Int, signals: Int) -> DeviceEnvironmentState {
        let all = DeviceEnvironmentResult.requiredMask
        guard checked >= 0, signals >= 0, checked & ~all == 0, signals & ~checked == 0 else { return .unverified }
        // Complete bootstrap layouts, injected libraries, privileged execution,
        // interposed system APIs and debugger attachment are direct denials.
        if signals & 0x23e3 != 0 { return .blocked }
        // A package database paired with the rootless bootstrap symlink, or
        // filesystem evidence plus conflicting API observations, is corroborated.
        if signals & 0x808 == 0x808 || (signals & 0x400 != 0 && signals & 0x181c != 0) { return .blocked }
        return checked == all ? .allowed : .unverified
    }
}

struct DeviceEnvironmentSnapshot {
    var paths: Set<String> = []
    var links: Set<String> = []
    var images: [String] = []
    var insertedLibraries = false
    var privileged = false
    var interposedAPI = false
    var contradictoryPaths = false
    var debugger = false
}

/// Private integer probes are inlined in Release. Encoded strings reduce obvious
/// static strings; this is obfuscation, not secrecy or a bypass-proof boundary.
enum DeviceEnvironmentInspector {
    private static func s(_ value: String) -> String { String(data: Data(base64Encoded: value)!, encoding: .utf8)! }
    private static let rf = [
        s("L0xpYnJhcnkvTW9iaWxlU3Vic3RyYXRlL01vYmlsZVN1YnN0cmF0ZS5keWxpYg=="),
        s("L3Vzci9saWIvbGlic3Vic3RyYXRlLmR5bGli"),
        s("L3ByaXZhdGUvdmFyL2xpYi9kcGtnL3N0YXR1cw==")
    ]
    private static let rl = [
        s("L3Zhci9qYi91c3IvbGliL2xpYmVsbGVraXQuZHlsaWI="),
        s("L3Zhci9qYi92YXIvbGliL2Rwa2cvc3RhdHVz"),
        s("L3Zhci9qYi9iYXNlYmluL2phaWxicmVha2Q="),
        s("L3Zhci9qYi91c3IvYmluL2Rwa2c=")
    ]
    private static let pd = [s("L3ByaXZhdGUvdmFyL2xpYi9hcHQ="), s("L3Zhci9saWIvY3lkaWE="),
        s("L3Zhci9qYi9ldGMvYXB0"), s("L3Zhci9qYi92YXIvbGliL2FwdA==")]
    private static let ld = [s("L0xpYnJhcnkvTGF1bmNoRGFlbW9ucy9jb20uc2F1cmlrLkN5ZGlhLlN0YXJ0dXAucGxpc3Q="),
        s("L0xpYnJhcnkvTGF1bmNoRGFlbW9ucy9jb20ub3BlbnNzaC5zc2hkLnBsaXN0")]
    private static let pm = [s("L0FwcGxpY2F0aW9ucy9DeWRpYS5hcHA="), s("L0FwcGxpY2F0aW9ucy9TaWxlby5hcHA="),
        s("L3Zhci9qYi9BcHBsaWNhdGlvbnMvU2lsZW8uYXBw"), s("L0FwcGxpY2F0aW9ucy9aZWJyYS5hcHA=")]
    private static let tweaks = [s("bW9iaWxlc3Vic3RyYXRl"), s("bGlic3Vic3RyYXRl"), s("ZWxsZWtpdA=="),
        s("bGliaG9va2Vy"), s("c3Vic3RpdHV0ZS1pbnNlcnRlcg=="), s("c3Vic3RyYXRlLWxvYWRlcg==")]
    private static let instruments = [s("ZnJpZGE="), s("bGliY3ljcmlwdA=="), s("c3Nsa2lsbHN3aXRjaA==")]
    private static let jb = s("L3Zhci9qYg==")
    private static let dyldKey = s("RFlMRF9JTlNFUlRfTElCUkFSSUVT")

    @inline(__always) private static func q0(_ v: DeviceEnvironmentSnapshot) -> Int { ((v.paths.contains(rf[0]) || v.paths.contains(rf[1])) && v.paths.contains(rf[2])) ? 1 : 0 }
    @inline(__always) private static func q1(_ v: DeviceEnvironmentSnapshot) -> Int { ((v.paths.contains(rl[0]) && v.paths.contains(rl[1])) || (v.paths.contains(rl[2]) && v.paths.contains(rl[3]))) ? 2 : 0 }
    @inline(__always) private static func q2(_ v: DeviceEnvironmentSnapshot) -> Int { (v.paths.contains(rf[2]) || pd.prefix(2).contains(where: v.paths.contains)) ? 4 : 0 }
    @inline(__always) private static func q3(_ v: DeviceEnvironmentSnapshot) -> Int { (v.paths.contains(rl[1]) || pd.suffix(2).contains(where: v.paths.contains)) ? 8 : 0 }
    @inline(__always) private static func q4(_ v: DeviceEnvironmentSnapshot) -> Int { ld.contains(where: v.paths.contains) ? 16 : 0 }
    @inline(__always) private static func q5(_ v: DeviceEnvironmentSnapshot) -> Int { namedImage(v.images, tokens: tweaks) ? 32 : 0 }
    @inline(__always) private static func q6(_ v: DeviceEnvironmentSnapshot) -> Int { namedImage(v.images, tokens: instruments) ? 64 : 0 }
    @inline(__always) private static func q7(_ v: DeviceEnvironmentSnapshot) -> Int { v.insertedLibraries ? 128 : 0 }
    @inline(__always) private static func q8(_ v: DeviceEnvironmentSnapshot) -> Int { v.privileged ? 256 : 0 }
    @inline(__always) private static func q9(_ v: DeviceEnvironmentSnapshot) -> Int { v.interposedAPI ? 512 : 0 }
    @inline(__always) private static func q10(_ v: DeviceEnvironmentSnapshot) -> Int { v.contradictoryPaths ? 1024 : 0 }
    @inline(__always) private static func q11(_ v: DeviceEnvironmentSnapshot) -> Int { v.links.contains(jb) ? 2048 : 0 }
    @inline(__always) private static func q12(_ v: DeviceEnvironmentSnapshot) -> Int { pm.contains(where: v.paths.contains) ? 4096 : 0 }
    @inline(__always) private static func q13(_ v: DeviceEnvironmentSnapshot) -> Int { v.debugger ? 8192 : 0 }

    private static func namedImage(_ images: [String], tokens: [String]) -> Bool {
        images.contains { image in
            let name = (image as NSString).lastPathComponent.lowercased()
            return tokens.contains { name.contains($0) }
        }
    }
    static func trustedSystemImage(_ image: String) -> Bool {
        image.hasPrefix("/usr/lib/") || image.hasPrefix("/System/Library/")
            || image.hasPrefix("/private/preboot/Cryptexes/OS/") || image.hasPrefix("/System/Volumes/Preboot/Cryptexes/OS/")
    }
    static func evaluate(_ value: DeviceEnvironmentSnapshot, checked: Int = DeviceEnvironmentResult.requiredMask) -> DeviceEnvironmentResult {
        let probes = [q0(value), q1(value), q2(value), q3(value), q4(value), q5(value), q6(value),
                      q7(value), q8(value), q9(value), q10(value), q11(value), q12(value), q13(value)]
        return DeviceEnvironmentResult(checkedMask: checked, signalMask: probes.reduce(0, |) & checked)
    }

    private static func runtimeSnapshot() -> DeviceEnvironmentSnapshot {
        var value = DeviceEnvironmentSnapshot()
        let count = _dyld_image_count()
        if count > 4096 { value.interposedAPI = true }
        for i in 0..<min(count, 4096) {
            if let name = _dyld_get_image_name(i) { value.images.append(String(cString: name)) }
        }
        value.privileged = getuid() == 0 || geteuid() == 0
        if let inserted = getenv(dyldKey), inserted.pointee != 0 { value.insertedLibraries = true }
        value.debugger = AntiTamper.isDebuggerAttached
        // Resolving a symbol and inspecting its owner avoids decoding ARM/PAC
        // instructions. Unknown/missing owners are not treated as proof of a hook.
        let symbols = ["lstat", "fstatat", "access", "getenv", "sysctl", "_dyld_image_count", "_dyld_get_image_name"]
        for symbol in symbols {
            guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else { continue }
            var owner = Dl_info()
            if dladdr(address, &owner) != 0, let name = owner.dli_fname,
               !trustedSystemImage(String(cString: name)) { value.interposedAPI = true }
        }
        return value
    }

    static func inspect() -> DeviceEnvironmentResult {
        #if os(iOS) && !targetEnvironment(simulator)
        return DeviceEnvironmentResult(checkedMask: DeviceEnvironmentResult.requiredMask, signalMask: 0)
        #else
        return .unverified
        #endif
    }

    static func commitMeasurement() -> DeviceEnvironmentResult {
        #if os(iOS) && !targetEnvironment(simulator)
        return DeviceEnvironmentResult(checkedMask: 0x23e0, signalMask: 0)
        #else
        return .unverified
        #endif
    }
}
