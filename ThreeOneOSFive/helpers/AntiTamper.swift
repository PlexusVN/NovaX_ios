import Foundation
import UIKit
import Darwin
import MachO

// MARK: - Active Anti-Crack & Permanent Machine Ban Service

public enum AntiTamper {

    private static var hasReportedViolation = false
    public static var isPermanentlyLocked = false

    // MARK: - 1. Debugger Detection (P_TRACED via sysctl)

    public static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard junk == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - 2. Injected Dylibs (Frida, Cycript, Substrate, Hookers)

    public static var detectedInjectedDylib: String? {
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

    public static var isFridaPortOpen: Bool {
        for port in [27042, 27043] {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { continue }
            defer { Darwin.close(socket) }

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
        }
        return false
    }

    // MARK: - 4. Active Anti-Crack Report & Machine Locking

    public static func reportCrackAndLockMachine(reason: String, details: [String: Any]) {
        guard !hasReportedViolation else { return }
        hasReportedViolation = true
        isPermanentlyLocked = true

        let hwid = DeviceUtils.hwid
        let deviceName = DeviceUtils.deviceModel
        let iosVersion = UIDevice.current.systemVersion
        let savedKey = KeychainUtils.read(key: "novax_saved_license_key") ?? ""

        // Xóa license local ngay lập tức
        KeychainUtils.delete(key: "novax_saved_license_key")

        // Gửi báo cáo lên server để khóa vĩnh viễn UID máy trên toàn bộ sản phẩm
        Task(priority: .high) {
            guard let url = URL(string: "https://zynox.click/api/security/report-crack") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(hwid, forHTTPHeaderField: "X-Client-HWID")
            request.timeoutInterval = 8

            let payload: [String: Any] = [
                "hwid": hwid,
                "device_name": deviceName,
                "ios_version": iosVersion,
                "reason": reason,
                "key": savedKey,
                "details": details
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - Public Checkpoints

    public static func checkAtLaunch() -> SecurityCheckResult {
        var reasons: [String] = []
        var details: [String: Any] = [:]

        if isDebuggerAttached {
            reasons.append("Debugger attached (P_TRACED)")
            details["debugger"] = true
        }

        if let dylib = detectedInjectedDylib {
            reasons.append("Injected instrumentation dylib: \(dylib)")
            details["injected_dylib"] = dylib
        }

        if isFridaPortOpen {
            reasons.append("Frida server port active (27042/27043)")
            details["frida_port"] = true
        }

        if !reasons.isEmpty {
            let combinedReason = reasons.joined(separator: " | ")
            reportCrackAndLockMachine(reason: combinedReason, details: details)
            return SecurityCheckResult(isCompromised: true, reasons: reasons)
        }

        return SecurityCheckResult(isCompromised: false, reasons: [])
    }

    public static func checkAfterLogin() -> SecurityCheckResult {
        return checkAtLaunch()
    }

    public static func checkBeforePatch() -> Bool {
        if isPermanentlyLocked { return false }
        let result = checkAtLaunch()
        return !result.isCompromised
    }

    @discardableResult
    public static func periodicCheck() -> SecurityCheckResult {
        return checkAtLaunch()
    }
}

public struct SecurityCheckResult {
    public let isCompromised: Bool
    public let compromisedReasons: [String]

    public init(isCompromised: Bool = false, reasons: [String] = []) {
        self.isCompromised = isCompromised
        self.compromisedReasons = reasons
    }
}
