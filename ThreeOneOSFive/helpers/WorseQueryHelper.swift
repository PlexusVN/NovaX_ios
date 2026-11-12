//
//  WorseQueryHelper.swift
//  ThreeOneOSFive / Astra
//
//  Created for Astra No-Pairing Container Access Integration.
//  Provides high-level Swift APIs for on-device sandbox escape via worse_query.
//

import Foundation
import Darwin

public enum WorseQueryError: LocalizedError {
    case appGroupUnavailable
    case targetNotFound(String)
    case dlopenOrSymbolsFailed
    case queryCreationFailed
    case symlinkCreationFailed
    case localFilesystemFailure(String)
    case queryRejected
    case kernelRefusedExtension
    case extensionConsumptionFailed
    case containerDiscoveryFailed(String)
    case discoveryInProgress
    case preparationRequired
    case nativeException
    case mainThreadAccess
    case unknownError(Int64)
    case unsupportedOS(String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Bản ký Astra hiện tại không có App Group truy cập được nên chưa thể dùng worse_query không cần VPN/pairing. Hãy ký lại bằng profile có App Group hợp lệ và giữ quyền App Group khi ký ESign."
        case .targetNotFound(let path):
            return "Đường dẫn mục tiêu không tồn tại trên thiết bị: \(path)"
        case .dlopenOrSymbolsFailed:
            return "Không thể nạp thư viện containermanager hoặc hàm hệ thống không tương thích."
        case .queryCreationFailed:
            return "Khởi tạo container query thất bại."
        case .symlinkCreationFailed:
            return "Không thể tạo liên kết symlink trong App Group Caches."
        case .localFilesystemFailure(let detail):
            return "Không thể chuẩn bị App Group Caches (WQ04).\n\(detail)"
        case .queryRejected:
            return "containermanagerd đã từ chối query."
        case .kernelRefusedExtension:
            return "Kernel từ chối cấp phát Sandbox Token Extension."
        case .extensionConsumptionFailed:
            return "worse_query nhận được token nhưng hệ thống không cho sử dụng quyền truy cập."
        case .containerDiscoveryFailed(let bundleID):
            return "Chưa tìm được thư mục dữ liệu của ứng dụng \(bundleID) bằng worse_query. Hãy mở ứng dụng đích một lần rồi thử lại (WQ02)."
        case .discoveryInProgress:
            return "Astra đang dò thư mục dữ liệu cho một thao tác khác. Hãy chờ thao tác đó hoàn tất rồi thử lại."
        case .preparationRequired:
            return "Chưa chuẩn bị xong quyền truy cập ứng dụng. Hãy hoàn tất màn hình chuẩn bị trước khi bật chức năng."
        case .nativeException:
            return "Hệ thống phát sinh exception khi cấp quyền worse_query (WQ08). Xem dòng log cuối của phiên chuẩn bị."
        case .mainThreadAccess:
            return "Đã chặn truy cập native trên luồng giao diện (WQ09). Hãy chạy lại bước chuẩn bị quyền truy cập."
        case .unknownError(let code):
            return "Lỗi worse_query không xác định (mã lỗi: \(code))."
        case .unsupportedOS(let version):
            return "Phiên bản hệ điều hành \(version) không nằm trong phạm vi hỗ trợ của worse_query."
        case .invalidPath(let path):
            return "Đường dẫn không hợp lệ cho container sandbox escape: \(path)"
        }
    }

    var blocksContainerPreparation: Bool {
        switch self {
        case .localFilesystemFailure, .symlinkCreationFailed, .appGroupUnavailable: return true
        default: return false
        }
    }
}

public final class WorseQueryHelper {
    public static let shared = WorseQueryHelper()
    private static let groupStateLock = NSLock()
    private static var groupProbeCompleted = false
    private static var verifiedGroup: String?

    /// Danh sách các App Group định danh dự phòng
    public static let candidateAppGroups: [String] = {
        var groups = AstraSignedApplicationGroups()
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            groups.append("group.\(bundleID)")
        }
        groups.append(contentsOf: [
            "group.com.novax.app",
            "group.cc.forcequit.worse-query",
            "group.com.astra.app"
        ])
        return Array(NSOrderedSet(array: groups)) as? [String] ?? groups
    }()

    private init() {}

    /// Tự động phát hiện App Group đang hoạt động được hệ thống cấp phép
    public static func resolveActiveAppGroup() -> String? {
        groupStateLock.lock()
        let completed = groupProbeCompleted
        let cached = verifiedGroup
        groupStateLock.unlock()
        if completed { return cached }
        // Runtime routing is read during SwiftUI rendering. Never perform the
        // Foundation/containermanager lookup there on iOS 27, even while a
        // worker is already waiting for containermanagerd.
        if (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            || ExploitSupportPolicy.currentRequiresWorseQueryPreparation) && Thread.isMainThread { return nil }
        var resolved: String?
        for group in candidateAppGroups {
            // Foundation may raise an Objective-C exception for a group removed
            // by re-signing. Swift do/catch cannot catch that exception.
            if worse_query_group_path(group) != nil { resolved = group; break }
        }
        groupStateLock.lock()
        verifiedGroup = resolved
        groupProbeCompleted = true
        groupStateLock.unlock()
        return resolved
    }

    static func invalidateActiveAppGroup() {
        groupStateLock.lock()
        verifiedGroup = nil
        groupProbeCompleted = false
        groupStateLock.unlock()
    }

    /// Kiểm tra App Group có sẵn sàng hay không
    public static var isAppGroupConfigured: Bool {
        resolveActiveAppGroup() != nil
    }

    /// Kiểm tra xem phiên bản iOS hiện tại có hỗ trợ worse_query hay không
    public static var isOSSupported: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return ExploitSupportPolicy.supportsWorseQuery(
            major: version.majorVersion, minor: version.minorVersion,
            patch: version.patchVersion, build: AppInfo.osBuild
        )
    }

    /// Preconditions only; the daemon may still reject a real access request.
    public static var isAvailable: Bool {
        isOSSupported && isAppGroupConfigured
    }

    static var preparationContext: String {
        "OS build=\(AppInfo.osBuild)\nSigned App Groups=\(AstraSignedApplicationGroups().joined(separator: ", "))\nCandidates=\(candidateAppGroups.joined(separator: ", "))"
    }

    static func preparationDiagnostics() throws -> String {
        guard !Thread.isMainThread else { throw WorseQueryError.mainThreadAccess }
        var reports = [preparationContext]
        // A Foundation group URL can exist even when the sandbox denies writes.
        // Do not pin the first readable directory or expose a half-tested group
        // to runtime routing while the worker checks the remaining candidates.
        groupStateLock.lock()
        verifiedGroup = nil
        groupProbeCompleted = true
        groupStateLock.unlock()
        for group in candidateAppGroups {
            guard let path = worse_query_group_path(group) else {
                reports.append("SKIP group=\(group) stage=resolve_group; không có thư mục truy cập được.")
                continue
            }
            reports.append("CHECK group=\(group) root=\(path)")
            let ready = worse_query_preflight(group)
            reports.append(worse_query_diagnostics() ?? "Không có chẩn đoán native.")
            guard ready else { continue }
            groupStateLock.lock()
            verifiedGroup = group
            groupProbeCompleted = true
            groupStateLock.unlock()
            reports.append("SELECTED writable_group=\(group)")
            return reports.joined(separator: "\n")
        }
        reports.append("Không có App Group nào vượt qua kiểm tra ghi/symlink. Hãy ký lại Astra bằng profile cấp App Group tương ứng; chỉ thêm tên group vào IPA không tự cấp quyền truy cập.")
        throw WorseQueryError.localFilesystemFailure(reports.joined(separator: "\n"))
    }

    static var nativeDiagnostics: String { worse_query_diagnostics() ?? "Không có chẩn đoán native." }

    /// Kiểm tra xem đường dẫn có thuộc phạm vi cho phép của worse_query hay không
    public static func isScopeSupported(for path: String) -> Bool {
        let clean = ContainerDiscoveryMerger.canonicalPath(path)
        return supportedRoots.contains { clean == $0 || clean.hasPrefix($0 + "/") }
    }

    private static let supportedRoots = [
        "/var/mobile/Containers/Data/Application",
        "/var/mobile/Containers/Data/InternalDaemon",
        "/var/mobile/Containers/Data/PluginKitPlugin",
        "/var/mobile/Containers/Shared/AppGroup",
        "/var/containers/Data/System",
        "/var/containers/Shared/SystemGroup"
    ].map { ContainerDiscoveryMerger.canonicalPath($0) }

    /// Trích xuất thư mục gốc của container từ đường dẫn bất kỳ (Data/Application, AppGroup, System)
    public static func containerRoot(for path: String) -> String? {
        let clean = ContainerDiscoveryMerger.canonicalPath(path)
        let prefixes = supportedRoots.map { $0 + "/" }

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
    public static func currentFilesystemMaxInode() throws -> UInt64 {
        let probeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe_inode_\(UUID().uuidString)")
        try Data("probe".utf8).write(to: probeURL)
        defer { try? FileManager.default.removeItem(at: probeURL) }
        var st = stat()
        guard stat(probeURL.path, &st) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return try enumerationUpperBound(probeInode: UInt64(st.st_ino))
    }

    static func enumerationUpperBound(probeInode: UInt64) throws -> UInt64 {
        let (maximum, overflow) = probeInode.addingReportingOverflow(2_048)
        guard probeInode > 0, !overflow else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EOVERFLOW))
        }
        return maximum
    }

    static func enumeratePaths(in path: String, from first: UInt64, through last: UInt64) throws -> [String] {
        var errorCode: Int32 = 0
        guard let paths = pathleak_range(path, first, last, &errorCode) as? [String] else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode == 0 ? EIO : errorCode))
        }
        return paths
    }

    /// Cấp phát quyền Sandbox Extension cho đường dẫn mục tiêu
    public static func acquireAccess(for targetPath: String, createDir: Bool = false) throws -> Int64 {
        guard isOSSupported else {
            let v = "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
            throw WorseQueryError.unsupportedOS(v)
        }


        if (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            || ExploitSupportPolicy.currentRequiresWorseQueryPreparation) && Thread.isMainThread {
            throw WorseQueryError.mainThreadAccess
        }
        guard !targetPath.isEmpty else {
            throw WorseQueryError.invalidPath(targetPath)
        }

        // Tự động chuẩn hóa mục tiêu về thư mục gốc container nếu là đường dẫn con
        let canonical = ContainerDiscoveryMerger.canonicalPath(targetPath)
        guard isScopeSupported(for: canonical) else { throw WorseQueryError.invalidPath(targetPath) }
        let effectiveTarget = containerRoot(for: canonical) ?? canonical


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
            invalidateActiveAppGroup()
            throw WorseQueryError.appGroupUnavailable
        case -2:
            throw WorseQueryError.dlopenOrSymbolsFailed
        case -3:
            throw WorseQueryError.queryCreationFailed
        case -4:
            throw WorseQueryError.localFilesystemFailure(nativeDiagnostics)
        case -5:
            throw WorseQueryError.queryRejected
        case -6:
            throw WorseQueryError.kernelRefusedExtension
        case -7:
            throw WorseQueryError.extensionConsumptionFailed
        case -8:
            throw WorseQueryError.nativeException
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

