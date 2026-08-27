import UIKit
import CryptoKit

struct DeviceUtils {

    /// HWID = hardware-derived (identifierForVendor + model + bundleID)
    /// Each device produces a unique, non-spoofable HWID.
    /// Cracker cannot predict HWID of other devices.
    static var hwid: String {
        if let cached = KeychainUtils.read(key: "deviceHwid") {
            return cached
        }
        let vendorID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let model = deviceModel
        let bundleID = Bundle.main.bundleIdentifier ?? "com.novax"
        let combined = "\(vendorID)|\(model)|\(bundleID)"
        let newHwid = sha256Hex(combined).prefix(16).lowercased()
        if KeychainUtils.save(key: "deviceHwid", value: newHwid) {
            return newHwid
        }
        return sha256Hex(combined).prefix(16).lowercased()
    }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }
        guard !bytes.isEmpty else { return "Unknown" }
        return String(cString: bytes).trimmingCharacters(in: .whitespaces)
    }

    static var osVersion: String { UIDevice.current.systemVersion }

    static var chipName: String {
        let model = deviceModel
        if model.contains("iPhone17") || model.contains("iPhone16,6") { return "A18 / A18 Pro" }
        if model.contains("iPhone15") { return "A17 Pro" }
        if model.contains("iPhone14,7") || model.contains("iPhone14,8") { return "A15 Bionic" }
        if model.contains("iPhone14") { return "A15 Bionic" }
        if model.contains("iPhone13") { return "A15 / A14 Bionic" }
        if model.contains("iPhone12") { return "A14 / A13 Bionic" }
        if model.contains("iPhone11") { return "A13 Bionic" }
        return "Apple Silicon"
    }

    static var totalRAM: String {
        let mem = ProcessInfo.processInfo.physicalMemory
        return "\(mem / 1_073_741_824) GB"
    }

    static var cpuCores: Int { ProcessInfo.processInfo.processorCount }

    static var screenResolution: String {
        let s = UIScreen.main.nativeBounds
        return "\(Int(s.width))x\(Int(s.height))"
    }

    static var refreshRate: Int {
        Int(UIScreen.main.maximumFramesPerSecond)
    }

    static var batteryPercent: Int {
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        return Int(UIDevice.current.batteryLevel * 100)
    }

    private static func sha256Hex(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
