import Foundation
import UIKit
import MachO
import CommonCrypto

// MARK: - Anti-Tamper Protection (Professional Grade)

enum AntiTamper {

    // MARK: - Jailbreak Detection (Filesystem)

    static var isJailbrokenByFilesystem: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Filza.app",
            "/usr/sbin/sshd",
            "/usr/bin/sshd",
            "/usr/bin/cycript",
            "/usr/local/bin/cycript",
            "/usr/libexec/cydia",
            "/usr/libexec/sftp-server",
            "/var/cache/apt",
            "/var/lib/apt",
            "/var/lib/cydia",
            "/var/mobile/Library/SBSettings/Themes",
            "/var/log/syslog",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/tmp/cydia.log",
            "/bin/bash",
            "/bin/sh",
            "/etc/apt",
            "/etc/apt/sources.list.d",
            "/private/etc/apt",
            "/private/etc/apt/sources.list.d",
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return false
        #endif
    }

    // MARK: - Jailbreak Detection (Sandbox Write Test)

    static var isJailbrokenBySandbox: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let testPath = "/private/var/tmp/.novax_jb_test"
        let testData = "test".data(using: .utf8)!
        do {
            try testData.write(to: URL(fileURLWithPath: testPath))
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #endif
    }

    // MARK: - Jailbreak Detection (URL Scheme)

    static var isJailbrokenByURLScheme: Bool {
        let schemes = ["cydia://", "sileo://", "zbra://", "filza://", "undecimus://"]
        for scheme in schemes {
            if let url = URL(string: scheme),
               UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        return false
    }

    // MARK: - Combined Jailbreak Detection

    static var isJailbroken: Bool {
        return isJailbrokenByFilesystem ||
               isJailbrokenBySandbox ||
               isJailbrokenByURLScheme
    }

    // MARK: - Debugger Detection (sysctl)

    static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - Frida Detection (Port Probe)

    static var isFridaDetected: Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { Darwin.close(socket) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(27042).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connectResult == 0
    }

    // MARK: - Dylib Scan (Frida/Substrate/Flex Detection)

    static func scanForSuspiciousDylibs() -> [String] {
        var suspicious: [String] = []
        let blacklist = ["frida", "substrate", "gadget", "sslkill", "flex", "cedar",
                         "cycript", "substitute", "liberty", "a-bypass", "shadow"]
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let name = _dyld_get_image_name(i) else { continue }
            let nameStr = String(cString: name).lowercased()
            for keyword in blacklist {
                if nameStr.contains(keyword) {
                    suspicious.append(nameStr)
                    break
                }
            }
        }
        return suspicious
    }

    static var hasSuspiciousDylibs: Bool {
        !scanForSuspiciousDylibs().isEmpty
    }

    // MARK: - Environment Variable Check

    static var hasInjectionEnv: Bool {
        if let _ = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] {
            return true
        }
        if let _ = ProcessInfo.processInfo.environment["_MSSafeMode"] {
            return true
        }
        return false
    }

    // MARK: - Code Signature Validation

    static var isCodeSignatureValid: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        // Use csops to verify code signature integrity
        var codeRef: SecCode?
        var status = SecCodeCopySelf(SecCSFlags(rawValue: kSecCSDefaultFlags), &codeRef)
        guard status == errSecSuccess, let codeRef = codeRef else { return false }

        var cfError: Unmanaged<CFError>?
        status = SecCodeCheckValidity(codeRef, SecCSFlags(rawValue: kSecCSStrictValidate), &cfError)
        if status != errSecSuccess {
            log("security: code signature invalid — status \(status)")
            return false
        }
        return true
        #endif
    }

    // MARK: - Bundle Hash Integrity

    private static var storedBundleHash: String? {
        UserDefaults.standard.string(forKey: "novax_bundle_hash")
    }

    static func calculateBundleHash() -> String {
        guard let executablePath = Bundle.main.executablePath,
              let data = FileManager.default.contents(atPath: executablePath) else {
            return ""
        }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Verify bundle hash — first run stores hash, subsequent runs compare
    static var isBundleIntact: Bool {
        let current = calculateBundleHash()
        guard !current.isEmpty else { return false }
        if let stored = storedBundleHash, !stored.isEmpty {
            if current != stored {
                log("security: bundle hash MISMATCH — possible binary patch")
                return false
            }
            return true
        }
        // First run: store hash
        UserDefaults.standard.set(current, forKey: "novax_bundle_hash")
        log("security: bundle hash stored: \(current.prefix(16))...")
        return true
    }

    // MARK: - Critical Classes Verification

    static func verifyCriticalClasses() -> Bool {
        let criticalClasses = [
            "AuthManager",
            "FeaturePatchService",
            "PatchPackageCodec",
            "DevicePatchService"
        ]
        for className in criticalClasses {
            if NSClassFromString(className) == nil { return false }
        }
        return true
    }

    // MARK: - Method Swizzle Detection

    static func detectSwizzling() -> Bool {
        guard let cls = NSClassFromString("AppInfo") as? NSObject.Type else { return false }
        let selector = NSSelectorFromString("machineName")
        guard let method = class_getInstanceMethod(cls, selector) else { return false }
        let imp = method_getImplementation(method)
        let impAddr = unsafeBitCast(imp, to: uintptr_t.self)
        return impAddr < 0x100000
    }

    // MARK: - Run Scattered Checks (Called from different places)

    /// Call at App launch — check 1
    static func checkAtLaunch() -> SecurityCheckResult {
        return SecurityCheckResult(
            jailbroken: isJailbroken,
            debuggerAttached: isDebuggerAttached,
            fridaDetected: isFridaDetected,
            suspiciousDylibs: hasSuspiciousDylibs,
            injectionEnv: hasInjectionEnv,
            classesValid: verifyCriticalClasses(),
            swizzlingDetected: detectSwizzling(),
            codeSignatureValid: isCodeSignatureValid,
            bundleIntact: isBundleIntact
        )
    }

    /// Call after login — check 2
    static func checkAfterLogin() -> SecurityCheckResult {
        return checkAtLaunch()
    }

    /// Call before patch apply — check 3
    static func checkBeforePatch() -> Bool {
        return !checkAtLaunch().isCompromised
    }

    /// Periodic check — check 4 (actionable, not just logging)
    @discardableResult
    static func periodicCheck() -> SecurityCheckResult {
        let result = checkAtLaunch()
        if result.isCompromised {
            log("security: COMPROMISED at runtime — \(result.compromisedReasons.joined(separator: ", "))")
        }
        return result
    }
}

// MARK: - Security Check Result

struct SecurityCheckResult {
    let jailbroken: Bool
    let debuggerAttached: Bool
    let fridaDetected: Bool
    let suspiciousDylibs: Bool
    let injectionEnv: Bool
    let classesValid: Bool
    let swizzlingDetected: Bool
    let codeSignatureValid: Bool
    let bundleIntact: Bool

    var isCompromised: Bool {
        return jailbroken || debuggerAttached || fridaDetected ||
               suspiciousDylibs || injectionEnv || !classesValid ||
               swizzlingDetected || !codeSignatureValid || !bundleIntact
    }

    var compromisedReasons: [String] {
        var reasons: [String] = []
        if jailbroken { reasons.append("Jailbreak") }
        if debuggerAttached { reasons.append("Debugger") }
        if fridaDetected { reasons.append("Frida") }
        if suspiciousDylibs { reasons.append("Hook library") }
        if injectionEnv { reasons.append("DYLD injection") }
        if !classesValid { reasons.append("Missing class") }
        if swizzlingDetected { reasons.append("Swizzle") }
        if !codeSignatureValid { reasons.append("Code signature") }
        if !bundleIntact { reasons.append("Binary patched") }
        return reasons
    }
}
