//
//  WorseQueryHelper.swift
//  ThreeOneOSFive / Astra
//
//  Created for Astra No-Pairing Container Access Integration.
//  Provides high-level Swift APIs for on-device sandbox escape via worse_query.
//

import Foundation
import UIKit

public enum WorseQueryError: LocalizedError {
    case appGroupUnavailable
    case targetNotFound(String)
    case dlopenOrSymbolsFailed
    case queryCreationFailed
    case symlinkCreationFailed
    case queryRejected
    case kernelRefusedExtension
    case unknownError(Int64)
    case unsupportedOS(String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Không tìm thấy App Group hợp lệ trong provisioning profile hoặc chứng chỉ ký."
        case .targetNotFound(let path):
            return "Đường dẫn mục tiêu không tồn tại trên thiết bị: \(path)"
        case .dlopenOrSymbolsFailed:
            return "Không thể nạp thư viện containermanager hoặc hàm hệ thống không tương thích."
        case .queryCreationFailed:
            return "Khởi tạo container query thất bại."
        case .symlinkCreationFailed:
            return "Không thể tạo liên kết symlink trong App Group Caches."
        case .queryRejected:
            return "containermanagerd đã từ chối query."
        case .kernelRefusedExtension:
            return "Kernel từ chối cấp phát Sandbox Token Extension."
        case .unknownError(let code):
            return "Lỗi worse_query không xác định (mã lỗi: \(code))."
        case .unsupportedOS(let version):
            return "Phiên bản hệ điều hành \(version) không nằm trong phạm vi hỗ trợ của worse_query."
        case .invalidPath(let path):
            return "Đường dẫn không hợp lệ cho container sandbox escape: \(path)"
        }
    }
}

public final class WorseQueryHelper {
    public static let shared = WorseQueryHelper()

    /// Danh sách các App Group định danh dự phòng
    public static let candidateAppGroups: [String] = {
        var groups: [String] = []
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            groups.append("group.\(bundleID)")
        }
        groups.append(contentsOf: [
            "group.com.novax.app",
            "group.cc.forcequit.worse-query",
            "group.com.astra.app"
        ])
        return groups
    }()

    /// Các build iOS 27.2 được xác minh hỗ trợ
    private static let supported272Builds: Set<String> = [
        "24B5084k", // iOS 27.2 Beta 1
        "24B5089g"  // iOS 27.2 Beta 2
    ]

    private init() {}

    /// Tự động phát hiện App Group đang hoạt động được hệ thống cấp phép
    public static func resolveActiveAppGroup() -> String? {
        let fileManager = FileManager.default
        for group in candidateAppGroups {
            if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: group) {
                // Kiểm tra xem thư mục có thật sự truy cập được không
                if fileManager.fileExists(atPath: url.path) {
                    return group
                }
                // Thử tạo thư mục nếu chưa tồn tại
                if (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil {
                    return group
                }
            }
        }
        return nil
    }

    /// Kiểm tra App Group có sẵn sàng hay không
    public static var isAppGroupConfigured: Bool {
        resolveActiveAppGroup() != nil
    }

    /// Kiểm tra xem phiên bản iOS hiện tại có hỗ trợ worse_query hay không
    public static var isOSSupported: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let major = version.majorVersion
        let minor = version.minorVersion
        let build = AppInfo.osBuild

        if major == 26 {
            // iOS 26.0 đến 26.7.2
            if minor < 7 { return true }
            if minor == 7 { return version.patchVersion <= 2 }
            return false
        }

        if major == 27 {
            // iOS 27.0 - 27.1
            if minor < 2 { return true }
            // iOS 27.2 beta 1 & beta 2
            if minor == 2 {
                if supported272Builds.contains(build) { return true }
                // Fallback kiểm tra ký tự cuối build nếu là build beta trước beta 3
                return build <= "24B5089g" && !build.isEmpty
            }
            return false
        }

        return false
    }

    /// worse_query có thể hoạt động ngay lập tức (OS hỗ trợ + Có App Group)
    public static var isAvailable: Bool {
        isOSSupported && isAppGroupConfigured
    }

    /// Kiểm tra xem đường dẫn có thuộc phạm vi cho phép của worse_query hay không
    public static func isScopeSupported(for path: String) -> Bool {
        let clean = ContainerDiscoveryMerger.canonicalPath(path)
        return clean.hasPrefix("/var/mobile/Containers/Data/Application") ||
               clean.hasPrefix("/private/var/mobile/Containers/Data/Application") ||
               clean.hasPrefix("/var/mobile/Containers/Shared/AppGroup") ||
               clean.hasPrefix("/private/var/mobile/Containers/Shared/AppGroup") ||
               clean.hasPrefix("/var/containers/Data/System") ||
               clean.hasPrefix("/private/var/containers/Data/System")
    }

    /// Trích xuất thư mục gốc của container từ đường dẫn bất kỳ (Data/Application, AppGroup, System)
    public static func containerRoot(for path: String) -> String? {
        let clean = ContainerDiscoveryMerger.canonicalPath(path)
        let prefixes = [
            "/var/mobile/Containers/Data/Application/",
            "/private/var/mobile/Containers/Data/Application/",
            "/var/mobile/Containers/Shared/AppGroup/",
            "/private/var/mobile/Containers/Shared/AppGroup/",
            "/var/containers/Data/System/",
            "/private/var/containers/Data/System/"
        ]

        for prefix in prefixes {
            if clean.hasPrefix(prefix) {
                let remainder = String(clean.dropFirst(prefix.count))
                let parts = remainder.split(separator: "/")
                if let first = parts.first, !first.isEmpty {
                    return prefix + String(first)
                }
            }
        }
        return nil
    }

    /// Ước tính số Inode tối đa hiện tại trên phân vùng /private/var thông qua tệp thăm dò tạm thời
    public static func currentFilesystemMaxInode() -> UInt64 {
        let probeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe_inode_\(UUID().uuidString)")
        try? "probe".data(using: .utf8)?.write(to: probeURL)
        var st = stat()
        var current: UInt64 = 200_000
        if stat(probeURL.path, &st) == 0 {
            current = UInt64(st.st_ino) + 2_000
        }
        try? FileManager.default.removeItem(at: probeURL)
        return max(current, 100_000)
    }

    /// Cấp phát quyền Sandbox Extension cho đường dẫn mục tiêu
    public static func acquireAccess(for targetPath: String, createDir: Bool = false) throws -> Int64 {
        guard !targetPath.isEmpty else {
            throw WorseQueryError.invalidPath(targetPath)
        }

        // Tự động chuẩn hóa mục tiêu về thư mục gốc container nếu là đường dẫn con
        let canonical = ContainerDiscoveryMerger.canonicalPath(targetPath)
        let effectiveTarget = containerRoot(for: canonical) ?? canonical

        guard isOSSupported else {
            let v = "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
            throw WorseQueryError.unsupportedOS(v)
        }

        guard let group = resolveActiveAppGroup() else {
            throw WorseQueryError.appGroupUnavailable
        }

        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let altFlags = (major == 26 && effectiveTarget.contains("/var/mobile/Containers/Shared/AppGroup"))

        let handle = worse_query(effectiveTarget, group, altFlags, createDir)
        if handle >= 0 {
            return handle
        }

        switch handle {
        case -1:
            throw WorseQueryError.appGroupUnavailable
        case -2:
            throw WorseQueryError.dlopenOrSymbolsFailed
        case -3:
            throw WorseQueryError.queryCreationFailed
        case -4:
            throw WorseQueryError.symlinkCreationFailed
        case -5:
            throw WorseQueryError.queryRejected
        case -6:
            throw WorseQueryError.kernelRefusedExtension
        case -255:
            throw WorseQueryError.targetNotFound(effectiveTarget)
        default:
            throw WorseQueryError.unknownError(handle)
        }
    }

    /// Giải phóng handle Sandbox Extension
    public static func releaseAccess(handle: Int64) {
        if handle >= 0 {
            worse_query_release(handle)
        }
    }

    /// Thực thi khối mã lệnh đồng bộ với quyền Sandbox Extension tự động giải phóng
    public static func withSandboxAccess<T>(for path: String, createDir: Bool = false, _ operation: () throws -> T) throws -> T {
        // Tìm thư mục cha thích hợp nếu path là file chưa tồn tại
        var resolvedTarget = path
        let fm = FileManager.default
        if !createDir && !fm.fileExists(atPath: path) {
            let parent = (path as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: parent) {
                resolvedTarget = parent
            }
        }

        let handle = try acquireAccess(for: resolvedTarget, createDir: createDir)
        defer { releaseAccess(handle: handle) }
        return try operation()
    }

    /// Thực thi khối mã lệnh bất đồng bộ với quyền Sandbox Extension tự động giải phóng
    public static func withSandboxAccessAsync<T>(for path: String, createDir: Bool = false, _ operation: () async throws -> T) async throws -> T {
        var resolvedTarget = path
        let fm = FileManager.default
        if !createDir && !fm.fileExists(atPath: path) {
            let parent = (path as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: parent) {
                resolvedTarget = parent
            }
        }

        let handle = try acquireAccess(for: resolvedTarget, createDir: createDir)
        defer { releaseAccess(handle: handle) }
        return try await operation()
    }

    // MARK: - Direct File Operations via Sandbox Extension

    /// Đọc dữ liệu từ tệp container trực tiếp
    public static func readFile(at path: String) throws -> Data {
        try withSandboxAccess(for: path) {
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    }

    /// Ghi dữ liệu vào tệp container trực tiếp (tự động tạo thư mục con nếu cần)
    public static func writeFile(data: Data, to path: String) throws {
        let parentDir = (path as NSString).deletingLastPathComponent
        let targetAccessPath = FileManager.default.fileExists(atPath: parentDir) ? parentDir : path

        try withSandboxAccess(for: targetAccessPath, createDir: true) {
            let fileURL = URL(fileURLWithPath: path)
            let parentURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentURL.path) {
                try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
            }
            try data.write(to: fileURL, options: .atomic)
        }
    }

    /// Khôi phục file gốc từ tệp sao lưu hoặc ghi đè
    public static func restoreFile(from backupURL: URL, to destinationPath: String) throws {
        let backupData = try Data(contentsOf: backupURL)
        try writeFile(data: backupData, to: destinationPath)
    }

    /// Xóa tệp hoặc thư mục trong container
    public static func removeItem(at path: String) throws {
        let parentDir = (path as NSString).deletingLastPathComponent
        try withSandboxAccess(for: parentDir) {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// Liệt kê danh sách thư mục trong container
    public static func contentsOfDirectory(at path: String) throws -> [String] {
        try withSandboxAccess(for: path) {
            try FileManager.default.contentsOfDirectory(atPath: path)
        }
    }

    /// Dò tìm inode nhanh bằng pathleak
    public static func fastEnumeratePaths(in basePath: String, maxInode: UInt64) -> [String] {
        guard let list = pathleak(basePath, maxInode) as? [String] else {
            return []
        }
        return list
    }
}

