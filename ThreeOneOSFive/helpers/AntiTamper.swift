import Foundation
import UIKit
import Darwin
import MachO

@_silgen_name("ptrace")
private func astra_ptrace(_ request: Int32, _ pid: pid_t,
                          _ address: UnsafeMutableRawPointer?, _ data: Int32) -> Int32

@_silgen_name("csops")
private func astra_csops(_ pid: pid_t, _ operation: UInt32,
                         _ userAddress: UnsafeMutableRawPointer?, _ userSize: size_t) -> Int32

// MARK: - Jailbreak detection

/// Sanitized evidence only. Raw paths and user-controlled identifiers are never
/// sent to the API; the authenticated device key remains the server authority.
struct JailbreakDetectionResult {
    let isJailbroken: Bool
    let score: Int
    let evidenceCodes: [String]

    static let clean = JailbreakDetectionResult(isJailbroken: false, score: 0, evidenceCodes: [])
}

enum JailbreakDetector {
    private static let cacheLock = NSLock()
    private static var cachedResult: JailbreakDetectionResult?

    static func evaluate() -> JailbreakDetectionResult {
#if targetEnvironment(simulator)
        // Simulator hosts legitimately contain shell/tooling paths and must not
        // be used to validate physical-device jailbreak heuristics.
        return .clean
#else
        cacheLock.lock()
        if let cachedResult {
            cacheLock.unlock()
            return cachedResult
        }
        cacheLock.unlock()

        var scores: [String: Int] = [:]
        func record(_ code: String, _ score: Int) {
            scores[code] = max(scores[code] ?? 0, score)
        }

        // Strong runtime signals. These are not normal App Store/enterprise app
        // conditions and therefore independently cross the decision threshold.
        if let value = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"], !value.isEmpty {
            record("dyld_injection_environment", 100)
        }
        if AntiTamper.detectedInjectedDylib != nil {
            record("injected_jailbreak_dylib", 100)
        }
        if AntiTamper.isFridaPortOpen {
            record("frida_server_port", 100)
        }
        if canWriteOutsideSandbox() {
            record("sandbox_escape_write", 100)
        }

        // Rootless jailbreaks commonly expose /var/jb or a bootstrap beneath
        // /private/preboot. Rootful package managers and hook frameworks retain
        // their classic locations. Exact jailbreak-specific paths avoid generic
        // Unix paths that may also exist on stock iOS.
        if pathExists("/var/jb") || pathExists("/private/var/jb") {
            record("rootless_jb_root", 100)
        }
        if prebootContainsBootstrap() {
            record("preboot_jailbreak_bootstrap", 100)
        }
        if anyPathExists([
            "/Applications/Cydia.app", "/Applications/Sileo.app",
            "/Applications/Zebra.app", "/Applications/Installer.app",
            "/var/jb/Applications/Sileo.app", "/var/jb/Applications/Zebra.app"
        ]) {
            record("jailbreak_package_manager", 100)
        }
        if anyPathExists([
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/substrate/SubstrateLoader.dylib",
            "/usr/lib/libhooker.dylib", "/usr/lib/libsubstitute.dylib",
            "/var/jb/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/var/jb/usr/lib/libhooker.dylib", "/var/jb/usr/lib/libsubstitute.dylib"
        ]) {
            record("jailbreak_hook_framework", 100)
        }
        if anyPathExists([
            "/var/lib/dpkg/status", "/private/var/lib/dpkg/status",
            "/etc/apt/sources.list.d", "/private/etc/apt/sources.list.d",
            "/var/jb/var/lib/dpkg/status", "/var/jb/etc/apt/sources.list.d"
        ]) {
            record("jailbreak_package_database", 60)
        }
        if anyPathExists([
            "/usr/sbin/sshd", "/usr/bin/ssh", "/usr/libexec/ssh-keysign",
            "/var/jb/usr/sbin/sshd", "/var/jb/usr/bin/ssh"
        ]) {
            record("jailbreak_remote_shell", 45)
        }
        if anyPathExists([
            "/var/mobile/Library/Preferences/com.saurik.Cydia.plist",
            "/var/mobile/Library/Preferences/org.coolstar.SileoStore.plist",
            "/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"
        ]) {
            record("jailbreak_preference_artifact", 45)
        }

        let score = scores.values.reduce(0, +)
        let result = JailbreakDetectionResult(
            isJailbroken: score >= 100,
            score: min(score, 999),
            evidenceCodes: scores.keys.sorted()
        )
        cacheLock.lock()
        cachedResult = result
        cacheLock.unlock()
        return result
#endif
    }

    private static func anyPathExists(_ paths: [String]) -> Bool {
        paths.contains(where: { pathExists($0) })
    }

    private static func pathExists(_ path: String) -> Bool {
        if FileManager.default.fileExists(atPath: path) { return true }
        var info = stat()
        return path.withCString { lstat($0, &info) == 0 }
    }

    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/.astra_guard_\(UUID().uuidString)"
        let descriptor = path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { return false }
        Darwin.close(descriptor)
        path.withCString { _ = Darwin.unlink($0) }
        return true
    }

    private static func prebootContainsBootstrap() -> Bool {
        guard let roots = try? FileManager.default.contentsOfDirectory(atPath: "/private/preboot") else {
            return false
        }
        let markers = ["jb", "procursus", "bootstrap", "dopamine", "palera1n"]
        for root in roots.prefix(64) {
            let lower = root.lowercased()
            if markers.contains(where: { lower.contains($0) }) { return true }
            let base = "/private/preboot/\(root)"
            for suffix in ["/jb", "/procursus", "/bootstrap"] where pathExists(base + suffix) {
                return true
            }
        }
        return false
    }
}

// MARK: - Local integrity signals (not authority to ban a license)

enum AntiTamper {

    private static let signalLock = NSLock()
    private static var hasLocalSignal = false
    static var hasPendingSecuritySignal: Bool {
        signalLock.lock(); defer { signalLock.unlock() }
        return hasLocalSignal
    }
    // Compatibility for callers of the old API; local heuristics never create
    // a permanent account decision. The server controls license entitlement.
    static var isPermanentlyLocked: Bool { false }

    // MARK: - 1. Debugger Detection (P_TRACED via sysctl)

    static var isDebuggerAttached: Bool {
#if DEBUG || targetEnvironment(simulator)
        return false
#else
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard junk == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
#endif
    }

    /// CS_DEBUGGED is independent of P_TRACED and catches additional debug
    /// runtime states. It does not inspect the signing certificate, so ESign or
    /// KSign re-signing alone is not treated as a violation.
    static var isCodeSignatureDebugged: Bool {
#if DEBUG || targetEnvironment(simulator)
        return false
#else
        let csOpsStatus: UInt32 = 0
        let csDebugged: UInt32 = 0x10000000
        var flags: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &flags) { pointer in
            astra_csops(getpid(), csOpsStatus, UnsafeMutableRawPointer(pointer),
                        MemoryLayout<UInt32>.size)
        }
        return result == 0 && (flags & csDebugged) != 0
#endif
    }

    /// Prevents a debugger attaching after the clean launch assessment. If a
    /// debugger was already present, App.swift first enters the signed incident
    /// flow instead of calling PT_DENY_ATTACH and losing the report instantly.
    static func activateDebuggerDenial() {
#if !DEBUG && !targetEnvironment(simulator)
        let ptDenyAttach: Int32 = 31
        _ = astra_ptrace(ptDenyAttach, 0, nil, 0)
#endif
    }

    // MARK: - 2. Injected Dylibs (Frida, Cycript, Substrate, Hookers)

    static var detectedInjectedDylib: String? {
        let suspiciousDylibs = [
            "FridaGadget", "frida-agent", "cycript", "cynject",
            "libhooker", "substitute", "substrate", "ellekit",
            "sslkillswitch", "shadow", "Liberty", "ABypass"
        ]
        let count = _dyld_image_count()
        for i in 0..<count {
            if let imageNameC = _dyld_get_image_name(i) {
                let imageName = String(cString: imageNameC).lowercased()
                for sus in suspiciousDylibs {
                    if imageName.contains(sus.lowercased()) {
                        return sus
                    }
                }
            }
        }
        return nil
    }

    // MARK: - 3. Frida Port Probe (27042 & 27043)

    static var isFridaPortOpen: Bool {
        for port in [27042, 27043] {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { continue }
            defer { Darwin.close(socket) }
            // A localhost probe must never hold the app's launch/UI thread
            // while a listener is overloaded. A pending connection is not
            // evidence of instrumentation.
            let flags = fcntl(socket, F_GETFL, 0)
            guard flags >= 0, fcntl(socket, F_SETFL, flags | O_NONBLOCK) == 0 else { continue }

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if connectResult == 0 { return true }
            if errno == EINPROGRESS {
                var descriptor = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
                if Darwin.poll(&descriptor, 1, 30) > 0 {
                    var error: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    if getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - 4. Record a signal for authenticated, minimal telemetry

    static func reportCrackAndLockMachine(reason: String, details: [String: Any]) {
        signalLock.lock(); defer { signalLock.unlock() }
        hasLocalSignal = true
        // Deliberately do not delete the saved license, send arbitrary details
        // or claim another HWID. Reports use the signed download session later.
    }

    // MARK: - Public Checkpoints

    static func checkAtLaunch() -> SecurityCheckResult {
        var reasons: [String] = []
        var details: [String: Any] = [:]
        var evidenceCodes: [String] = []

        let jailbreak = JailbreakDetector.evaluate()
        if jailbreak.isJailbroken {
            reasons.append("Jailbreak environment detected")
            details["jailbreak_evidence"] = jailbreak.evidenceCodes
            evidenceCodes.append(contentsOf: jailbreak.evidenceCodes)
        }

        if isDebuggerAttached {
            reasons.append("Debugger attached (P_TRACED)")
            details["debugger"] = true
            evidenceCodes.append("debugger_attached")
        }

        if isCodeSignatureDebugged {
            reasons.append("Debugged code-sign state detected")
            details["codesign_debugged"] = true
            evidenceCodes.append("codesign_debugged")
        }

        if let dylib = detectedInjectedDylib {
            reasons.append("Injected instrumentation dylib: \(dylib)")
            details["injected_dylib"] = dylib
            evidenceCodes.append("injected_jailbreak_dylib")
        }

        if isFridaPortOpen {
            reasons.append("Frida server port active (27042/27043)")
            details["frida_port"] = true
            evidenceCodes.append("frida_server_port")
        }

        evidenceCodes = Array(Set(evidenceCodes)).sorted()

        if !reasons.isEmpty {
            let combinedReason = reasons.joined(separator: " | ")
            reportCrackAndLockMachine(reason: combinedReason, details: details)
            return SecurityCheckResult(isCompromised: true, reasons: reasons,
                                       jailbreakDetection: jailbreak,
                                       evidenceCodes: evidenceCodes)
        }

        return SecurityCheckResult(isCompromised: false, reasons: [],
                                   jailbreakDetection: jailbreak,
                                   evidenceCodes: [])
    }

    static func checkAfterLogin() -> SecurityCheckResult {
        return checkAtLaunch()
    }

    static func checkBeforePatch() -> Bool {
        if isPermanentlyLocked { return false }
        let result = checkAtLaunch()
        return !result.isCompromised
    }

    @discardableResult
    static func periodicCheck() -> SecurityCheckResult {
        return checkAtLaunch()
    }
}

struct SecurityCheckResult {
    let isCompromised: Bool
    let compromisedReasons: [String]
    let jailbreakDetection: JailbreakDetectionResult
    let evidenceCodes: [String]

    init(isCompromised: Bool = false, reasons: [String] = [],
         jailbreakDetection: JailbreakDetectionResult = .clean,
         evidenceCodes: [String] = []) {
        self.isCompromised = isCompromised
        self.compromisedReasons = reasons
        self.jailbreakDetection = jailbreakDetection
        self.evidenceCodes = evidenceCodes
    }
}
