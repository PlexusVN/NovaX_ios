import Foundation

// MARK: - Light Anti-Tamper (Log-Only, No Crash)

enum AntiTamper {

    // MARK: - Jailbreak Detection (Filesystem — log only)

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
            "/usr/bin/cycript",
            "/usr/libexec/cydia",
            "/var/cache/apt",
            "/var/lib/cydia",
            "/bin/bash",
            "/bin/sh",
            "/etc/apt"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return false
        #endif
    }

    // MARK: - Frida Detection (Port Probe — log only)

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

    // MARK: - Combined (log only, never block)

    static var isJailbroken: Bool { isJailbrokenByFilesystem }

    // MARK: - Public API (non-blocking)

    static func checkAtLaunch() -> SecurityCheckResult {
        let jailbreak = isJailbroken
        let frida = isFridaDetected
        if jailbreak || frida {
            var reasons: [String] = []
            if jailbreak { reasons.append("Jailbreak") }
            if frida { reasons.append("Frida") }
            log("security: detected \(reasons.joined(separator: ", ")) — continuing anyway")
        }
        return SecurityCheckResult(jailbroken: jailbreak, fridaDetected: frida)
    }

    static func checkAfterLogin() -> SecurityCheckResult { checkAtLaunch() }
    static func checkBeforePatch() -> Bool { true }

    @discardableResult
    static func periodicCheck() -> SecurityCheckResult { checkAtLaunch() }
}

struct SecurityCheckResult {
    let jailbroken: Bool
    let fridaDetected: Bool

    var isCompromised: Bool { false }
    var compromisedReasons: [String] {
        var r: [String] = []
        if jailbroken { r.append("Jailbreak") }
        if fridaDetected { r.append("Frida") }
        return r
    }

    init(jailbroken: Bool = false, fridaDetected: Bool = false) {
        self.jailbroken = jailbroken
        self.fridaDetected = fridaDetected
    }
}
