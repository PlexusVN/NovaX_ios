import Foundation
import Darwin
import UIKit

// MARK: - Models

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let containerPath: String
    let version: String
    let icon: UIImage?

    var id: String { bundleID }
    var displayName: String {
        AppDisplayNamePolicy.resolve(bundleID: bundleID, candidates: [name])
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct FileEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64

    var id: String { path }
    var sizeText: String {
        if isDirectory { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// BEGIN CONTAINER IDENTITY EVIDENCE
struct ContainerIdentityEvidence {
    let identifier: String?
    let diagnostics: [String]
}

enum ContainerIdentityEvidenceResolver {
    static func resolve(xattr: Data?, metadata: Data?) -> ContainerIdentityEvidence {
        var diagnostics: [String] = []
        func canonical(_ raw: String, source: String) -> String? {
            guard let value = try? PatchPathValidator.canonicalBundleIdentifier(raw), value == raw else {
                diagnostics.append("\(source)=invalid_identifier")
                return nil
            }
            diagnostics.append("\(source)=\(value)")
            return value
        }
        var attributeID: String?
        if let xattr {
            var bytes = xattr
            if bytes.last == 0 { bytes.removeLast() }
            if !bytes.isEmpty, bytes.count <= 255, !bytes.contains(0),
               let value = String(data: bytes, encoding: .utf8) {
                attributeID = canonical(value, source: "xattr")
            } else { diagnostics.append("xattr=invalid_encoding_or_length") }
        } else { diagnostics.append("xattr=unavailable") }
        var metadataID: String?
        if let metadata {
            do {
                let plist = try PropertyListSerialization.propertyList(from: metadata, options: [], format: nil)
                if let object = plist as? [String: Any], let value = object["MCMMetadataIdentifier"] as? String {
                    metadataID = canonical(value, source: "metadata")
                } else { diagnostics.append("metadata=identifier_missing") }
            } catch { diagnostics.append("metadata=invalid_plist") }
        } else { diagnostics.append("metadata=unavailable") }
        if let attributeID, let metadataID, attributeID != metadataID {
            diagnostics.append("identity=conflict")
            return ContainerIdentityEvidence(identifier: nil, diagnostics: diagnostics)
        }
        let identifier = attributeID ?? metadataID
        if identifier == nil { diagnostics.append("identity=unresolved") }
        return ContainerIdentityEvidence(identifier: identifier, diagnostics: diagnostics)
    }
}
// END CONTAINER IDENTITY EVIDENCE

// MARK: - Store

enum ContainerStore {
    private static let discoveryLock = NSLock()
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let systemDataRoot = "/var/mobile/Containers/Data/System"
    private static var shouldUseBadQuery: Bool {
        ExploitSupportPolicy.currentAccessProvider == .legacy3105
            && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }
    private static let applicationBundleRoots: [(path: String, nested: Bool)] = [
        ("/var/containers/Bundle/Application", true),
        ("/Applications", false),
        ("/System/Applications", false)
    ]
    static let researchAppIdentifiers = [
        "com.apple.mobilesafari", "com.apple.mobilenotes", "com.apple.Maps",
        "com.apple.facetime", "com.apple.iBooks", "com.apple.podcasts",
        "com.apple.PosterBoard", "com.apple.mobilemail", "com.apple.weather",
        "com.apple.camera", "com.apple.Health", "com.apple.Fitness",
        "com.apple.tips", "com.apple.Passbook", "com.apple.reminders",
        "com.apple.stocks", "com.apple.news", "com.apple.Home", "com.apple.tv",
        "com.apple.shortcuts", "com.apple.freeform", "com.apple.calculator",
        "com.apple.MobileSMS", "com.apple.InCallService", "com.apple.Preferences",
        "com.apple.springboard", "com.apple.Photos", "com.apple.AppStore",
        "com.apple.Music", "com.apple.Bridge", "com.apple.Clock",
        "com.apple.VoiceMemos", "com.apple.Translate", "com.apple.measure",
        "com.apple.compass", "com.apple.Magnifier", "com.apple.DocumentsApp"
    ]

    static func resolveAppContainerPath(bundleID: String, allowMetadataScan: Bool = true,
                                        retainAccess: Bool = true) -> String? {
        guard (try? PatchPathValidator.canonicalBundleIdentifier(bundleID)) == bundleID else {
            return nil
        }

        // All worse_query lookup/grant/read work belongs to the worker preparation
        // gate. Rendering a view must not perform a native path lookup.
        if ExploitSupportPolicy.currentRequiresWorseQueryPreparation {
            return IOS27ContainerSession.path(for: bundleID)
        }
        guard ExploitSupportPolicy.currentAccessProvider == .legacy3105 else { return nil }

        let cacheKey = "astra.resolved_container.\(bundleID)"

        // MHA-C2 retains a lease in this process. A persisted UUID is only a
        // path hint: metadata can remain visible after the old process lease
        // is gone, especially on iOS 16 where bad_query is not selected.
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError) {
            let cleanMCM = ContainerDiscoveryMerger.canonicalPath(path)
            if isApplicationContainerPath(cleanMCM) {
                log("patch: MHA-C2 resolved \(bundleID) -> \(cleanMCM)")
                UserDefaults.standard.set(cleanMCM, forKey: cacheKey)
                if retainAccess { _ = grantContainerAccess(cleanMCM) }
                return cleanMCM
            }
        }
        let detail = lookupError.map(String.init) ?? "unavailable"
        log("patch: MHA-C2 could not resolve \(bundleID), detail=\(detail)")

        // Existing direct/kernel access may still use a cached path after MCM
        // fails. Existence here does not claim a new sandbox grant or writability.
        if let cached = UserDefaults.standard.string(forKey: cacheKey) {
            let cleanCached = ContainerDiscoveryMerger.canonicalPath(cached)
            var exists = false
            if isApplicationContainerPath(cleanCached) {
                if WorseQueryHelper.isAvailable {
                    exists = (try? WorseQueryHelper.withSandboxAccess(for: cleanCached) {
                        FileManager.default.fileExists(atPath: cleanCached)
                    }) ?? false
                } else {
                    exists = FileManager.default.fileExists(atPath: cleanCached)
                }
            }
            if exists {
                log("patch: container resolved from persistent cache for \(bundleID) -> \(cleanCached)")
                if retainAccess { _ = grantContainerAccess(cleanCached) }
                return cleanCached
            }
        }

        // 3. Safe typed-ARC LaunchServices fallback.
        if let lsPath = containerPathForBundleID(bundleID) {
            let cleanLS = ContainerDiscoveryMerger.canonicalPath(lsPath)
            if isApplicationContainerPath(cleanLS) {
                log("patch: LaunchServices resolved \(bundleID) -> \(cleanLS)")
                UserDefaults.standard.set(cleanLS, forKey: cacheKey)
                if retainAccess { _ = grantContainerAccess(lsPath) }
                return cleanLS
            }
        }

        guard allowMetadataScan else { return nil }

        // 4. Fallback quét metadata hệ thống qua pathleak / worse_query / bad_query
        if let scanned = resolveAppContainerPathByMetadataScan(bundleID: bundleID) {
            let cleanScanned = ContainerDiscoveryMerger.canonicalPath(scanned)
            if isApplicationContainerPath(cleanScanned) {
                log("patch: filesystem metadata scan resolved \(bundleID) -> \(cleanScanned)")
                UserDefaults.standard.set(cleanScanned, forKey: cacheKey)
                if retainAccess { _ = grantContainerAccess(cleanScanned) }
                return cleanScanned
            }
        }
        return nil
    }

    /// Patch callers must retain discovery errors rather than turn every failed
    /// query or filesystem setup into the same "app unavailable" message.
    static func resolveAppContainerForPatch(bundleID: String) throws -> String {
        _ = try PatchPathValidator.canonicalBundleIdentifier(bundleID)
        if ExploitSupportPolicy.currentRequiresWorseQueryPreparation {
            guard let path = IOS27ContainerSession.path(for: bundleID) else {
                throw WorseQueryError.preparationRequired
            }
            return path
        }
        guard ExploitSupportPolicy.currentAccessProvider == .legacy3105 else {
            throw WorseQueryError.unsupportedOS(AppInfo.osBuild)
        }
        if let path = resolveAppContainerPath(bundleID: bundleID, allowMetadataScan: false, retainAccess: false) {
            return path
        }
        if WorseQueryHelper.isAvailable {
            return try resolveContainerWithWorseQuery(bundleID: bundleID)
        }
        if let path = resolveAppContainerPath(bundleID: bundleID, retainAccess: false) { return path }
        throw PatchPackageError.targetAppUnavailable(bundleID)
    }

    private static var worseQueryResume: [String: (next: UInt64, maximum: UInt64)] = [:]

    static func prepareIOS27Access(bundleIDs: [String], forceScan: Bool = false) throws -> [String: String] {
        let targets = Set(try bundleIDs.map { try PatchPathValidator.canonicalBundleIdentifier($0) })
        guard !targets.isEmpty else { throw WorseQueryError.preparationRequired }
        guard discoveryLock.try() else { throw WorseQueryError.discoveryInProgress }
        defer { discoveryLock.unlock() }
        return try ContainerScanProgress.shared.track(bundleID: targets.sorted().joined(separator: ", "),
            successMessage: "Đã xác minh thư mục ứng dụng có thể đọc. Quyền ghi được kiểm tra khi thực hiện thao tác.") { sessionID in
            guard WorseQueryHelper.isOSSupported else { throw WorseQueryError.unsupportedOS(AppInfo.osBuild) }
            ContainerScanProgress.shared.checkpoint(sessionID, message: "Kiểm tra App Group của bản ký hiện tại…")
            WorseQueryHelper.invalidateActiveAppGroup()
            ContainerScanProgress.shared.checkpoint(sessionID, message: WorseQueryHelper.preparationContext)
            guard WorseQueryHelper.isAppGroupConfigured else { throw WorseQueryError.appGroupUnavailable }
            ContainerScanProgress.shared.checkpoint(sessionID, message: try WorseQueryHelper.preparationDiagnostics())
            var found: [String: String] = [:]
            var conflictingTargets = Set<String>()
            var seen = Set<String>()
            var inspectedEvidence = Set<String>()
            var candidates = 0, grants = 0, readable = 0, identified = 0
            var lastGrantError: Error?

            func inspect(_ path: String, boundBundleID: String? = nil, source: String = "scan") throws {
                try ContainerScanProgress.shared.checkCancellation(sessionID)
                let clean = ContainerDiscoveryMerger.canonicalPath(path)
                guard isApplicationContainerPath(clean),
                      inspectedEvidence.insert(clean + "\0" + (boundBundleID ?? "")).inserted else { return }
                if seen.insert(clean).inserted { candidates += 1 }
                ContainerScanProgress.shared.checkpoint(sessionID, message: "worse_query: yêu cầu handle cho \(clean)", candidates: candidates, grants: grants)
                let handle: Int64
                do { handle = try WorseQueryHelper.acquireAccess(for: clean) }
                catch {
                    lastGrantError = error
                    ContainerScanProgress.shared.checkpoint(sessionID, message: WorseQueryHelper.nativeDiagnostics)
                    throw error
                }
                defer { WorseQueryHelper.releaseAccess(handle: handle) }
                grants += 1
                let evidence = readWorseQueryIdentity(clean)
                if evidence.readable { readable += 1 }
                if evidence.identifier != nil { identified += 1 }
                let detail = evidence.diagnostics.joined(separator: "; ")
                ContainerScanProgress.shared.checkpoint(sessionID,
                    message: "IDENTITY path=\(clean) \(detail)", candidates: candidates, grants: grants,
                    readable: readable, identified: identified, matched: found.count)
                guard evidence.readable else { return }
                let identifier: String
                if let boundBundleID {
                    // A path returned by an exact Bundle-ID system lookup has
                    // different evidence from an anonymous inode candidate.
                    // Missing xattr/metadata must not discard that binding, but
                    // a conflicting valid identity always rejects the path.
                    guard targets.contains(boundBundleID),
                          !evidence.diagnostics.contains("identity=conflict"),
                          evidence.identifier == nil || evidence.identifier == boundBundleID else {
                        ContainerScanProgress.shared.checkpoint(sessionID,
                            message: "IDENTITY lookup conflict source=\(source); đã từ chối kết quả.")
                        return
                    }
                    identifier = boundBundleID
                    if evidence.identifier == nil { identified += 1 }
                    ContainerScanProgress.shared.checkpoint(sessionID,
                        message: "IDENTITY source=\(source) binding=\(identifier) grant=ok directory_read=ok")
                } else {
                    guard let observed = evidence.identifier else { return }
                    identifier = observed
                }
                guard targets.contains(identifier) else { return }
                guard !conflictingTargets.contains(identifier) else { return }
                if let other = found.first(where: { $0.key != identifier && $0.value == clean })?.key {
                    found.removeValue(forKey: other)
                    conflictingTargets.formUnion([other, identifier])
                    for target in [other, identifier] {
                        UserDefaults.standard.removeObject(forKey: "astra.resolved_container.\(target)")
                    }
                    ContainerScanProgress.shared.checkpoint(sessionID,
                        message: "IDENTITY conflict: một UUID được gán cho nhiều Bundle ID; không chọn thư mục để ghi.")
                    return
                }
                if let previous = found[identifier], previous != clean {
                    found.removeValue(forKey: identifier)
                    conflictingTargets.insert(identifier)
                    UserDefaults.standard.removeObject(forKey: "astra.resolved_container.\(identifier)")
                    ContainerScanProgress.shared.checkpoint(sessionID,
                        message: "IDENTITY conflict: nhiều UUID cùng định danh \(identifier); không chọn thư mục để ghi.", matched: found.count)
                    return
                }
                found[identifier] = clean
                UserDefaults.standard.set(clean, forKey: "astra.resolved_container.\(identifier)")
                ContainerScanProgress.shared.checkpoint(sessionID, message: "Đã đọc và xác minh \(identifier).", matched: found.count)
            }

            // A remembered UUID is only a candidate: re-read its identity with a
            // fresh grant. A stale UUID cannot remain published after a failed check.
            for bundleID in targets.sorted() {
                if let cached = UserDefaults.standard.string(forKey: "astra.resolved_container.\(bundleID)") {
                    do { try inspect(cached) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        if (error as? WorseQueryError)?.blocksContainerPreparation == true { throw error }
                        ContainerScanProgress.shared.checkpoint(sessionID, message: "Cache không dùng được: \(error.localizedDescription)")
                    }
                    if found[bundleID] == nil { UserDefaults.standard.removeObject(forKey: "astra.resolved_container.\(bundleID)") }
                }
            }
            ContainerScanProgress.shared.report(sessionID, scanned: 0, total: 0, candidates: candidates, grants: grants,
                readable: readable, identified: identified, matched: found.count,
                message: "Cache: \(found.count)/\(targets.count) ứng dụng đã được đọc và xác minh.")
            if found.count == targets.count || (!forceScan && !found.isEmpty) { return found }

            // IPA 3105 2.2 resolves known identifiers before its anonymous scan.
            // This path never calls MCMActivateContainerPath or bad_query.
            for bundleID in targets.sorted() where found[bundleID] == nil {
                try ContainerScanProgress.shared.checkCancellation(sessionID)
                ContainerScanProgress.shared.checkpoint(sessionID,
                    message: "Tra đường dẫn theo Bundle ID \(bundleID) bằng MCM (chưa cấp quyền).")
                var lookupError: NSString?
                if let path = MCMContainerPathForWorseQuery(2, bundleID, false, &lookupError) {
                    try ContainerScanProgress.shared.checkCancellation(sessionID)
                    do { try inspect(path, boundBundleID: bundleID, source: "mcm_bundle_id") }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        if (error as? WorseQueryError)?.blocksContainerPreparation == true { throw error }
                        ContainerScanProgress.shared.checkpoint(sessionID, message: "MCM: chưa cấp được quyền worse_query.")
                    }
                }
                if found[bundleID] == nil {
                    try ContainerScanProgress.shared.checkCancellation(sessionID)
                    if let path = containerPathForBundleID(bundleID) {
                        try ContainerScanProgress.shared.checkCancellation(sessionID)
                        do { try inspect(path, boundBundleID: bundleID, source: "launch_services_bundle_id") }
                        catch is CancellationError { throw CancellationError() }
                        catch {
                            if (error as? WorseQueryError)?.blocksContainerPreparation == true { throw error }
                            ContainerScanProgress.shared.checkpoint(sessionID, message: "LaunchServices: chưa cấp được quyền worse_query.")
                        }
                    }
                }
            }
            ContainerScanProgress.shared.report(sessionID, scanned: 0, total: 0, candidates: candidates, grants: grants,
                readable: readable, identified: identified, matched: found.count,
                message: "Tra theo Bundle ID: \(found.count)/\(targets.count) ứng dụng đã được cấp quyền và đọc.")
            if found.count == targets.count || (!forceScan && !found.isEmpty) { return found }

            let group = WorseQueryHelper.resolveActiveAppGroup() ?? ""
            let resumeKey = AppInfo.osBuild + "|" + group + "|" + targets.sorted().joined(separator: ",")
            if forceScan { worseQueryResume.removeValue(forKey: resumeKey) }
            let prior = worseQueryResume[resumeKey]
            let maximum = try prior?.maximum ?? WorseQueryHelper.currentFilesystemMaxInode()
            let chunkSize: UInt64 = 50_000
            var first: UInt64 = prior?.next ?? 1
            var exhaustedWindow = false
            ContainerScanProgress.shared.report(sessionID, scanned: first - 1, total: maximum, candidates: candidates, grants: grants,
                readable: readable, identified: identified, matched: found.count,
                message: "Dò dự phòng phạm vi ước lượng \(first)…\(maximum) inode bằng pathleak. Đây không phải giới hạn toàn filesystem.")
            while first <= maximum {
                try ContainerScanProgress.shared.checkCancellation(sessionID)
                // Resume a cancelled chunk from its beginning; no unseen child
                // is skipped after cancellation between enumeration and inspection.
                worseQueryResume[resumeKey] = (first, maximum)
                let last = first + min(chunkSize - 1, maximum - first)
                let paths = try WorseQueryHelper.enumeratePaths(in: appDataRoot, from: first, through: last)
                for path in paths {
                    do { try inspect(path) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        if (error as? WorseQueryError)?.blocksContainerPreparation == true { throw error }
                        ContainerScanProgress.shared.checkpoint(sessionID, message: "Không nhận được handle: \(error.localizedDescription)")
                    }
                }
                ContainerScanProgress.shared.report(sessionID, scanned: last, total: maximum, candidates: candidates, grants: grants,
                    readable: readable, identified: identified, matched: found.count,
                    message: "Phạm vi hiện tại \(last)/\(maximum) inode; \(candidates) thư mục, \(grants) handle, \(readable) đọc được, \(identified) định danh hợp lệ, \(found.count) đúng mục tiêu.")
                exhaustedWindow = last == maximum
                if found.count == targets.count || (!forceScan && !found.isEmpty) || exhaustedWindow { break }
                first = last + 1
            }
            worseQueryResume.removeValue(forKey: resumeKey)
            if found.count < targets.count {
                ContainerScanProgress.shared.checkpoint(sessionID,
                    message: "\(exhaustedWindow ? "Đã hết phạm vi inode ước lượng" : "Đã xác minh ứng dụng có thể dùng; các mục tùy chọn còn lại sẽ được dò khi cần"); chưa xác minh: \(targets.subtracting(found.keys).sorted().joined(separator: ", ")). Không kết luận ứng dụng chưa cài.")
            }
            guard !found.isEmpty else {
                if grants == 0, let lastGrantError { throw lastGrantError }
                throw WorseQueryError.containerDiscoveryFailed(targets.sorted().joined(separator: ", "))
            }
            return found
        }
    }

    /// All reads happen while the caller owns the container grant. Receiving a
    /// handle alone never establishes directory readability or game identity.
    static func readWorseQueryIdentity(_ path: String) -> (identifier: String?, readable: Bool, diagnostics: [String]) {
        var diagnostics: [String] = []
        var readable = false
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            readable = true
            diagnostics.append("directory_read=ok")
        } catch {
            let failure = error as NSError
            diagnostics.append("directory_read=failed domain=\(failure.domain) code=\(failure.code)")
        }
        var xattr: Data?
        let size = getxattr(path, "com.apple.containermanager.identifier", nil, 0, 0, 0)
        if size > 0 && size <= 4096 {
            var bytes = [UInt8](repeating: 0, count: size)
            let count = getxattr(path, "com.apple.containermanager.identifier", &bytes, bytes.count, 0, 0)
            if count > 0 && count <= bytes.count {
                xattr = Data(bytes.prefix(count))
                diagnostics.append("xattr_bytes=\(count)")
            } else { diagnostics.append("xattr_read=failed errno=\(errno)") }
        } else if size < 0 { diagnostics.append("xattr_size=failed errno=\(errno)") }
        else { diagnostics.append("xattr_size=invalid bytes=\(size)") }
        var metadata: Data?
        do {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: metadataPath(for: path)))
            if bytes.count <= 1_048_576 { metadata = bytes }
            else { diagnostics.append("metadata_read=oversized") }
        } catch {
            let failure = error as NSError
            diagnostics.append("metadata_read=failed domain=\(failure.domain) code=\(failure.code)")
        }
        let evidence = ContainerIdentityEvidenceResolver.resolve(xattr: xattr, metadata: metadata)
        diagnostics.append(contentsOf: evidence.diagnostics)
        return (evidence.identifier, readable, diagnostics)
    }

    private static func resolveContainerWithWorseQuery(bundleID: String) throws -> String {
        let found = try prepareIOS27Access(bundleIDs: [bundleID])
        guard let path = found[bundleID] else { throw WorseQueryError.containerDiscoveryFailed(bundleID) }
        return path
    }

    static func resolveAppContainerPathByMetadataScan(bundleID: String) -> String? {
        if ExploitSupportPolicy.currentRequiresWorseQueryPreparation {
            return IOS27ContainerSession.path(for: bundleID)
        }
        guard ExploitSupportPolicy.currentAccessProvider == .legacy3105 else { return nil }
        if WorseQueryHelper.isAvailable {
            do { return try resolveContainerWithWorseQuery(bundleID: bundleID) }
            catch { log("worse_query discovery failed: \(error.localizedDescription)"); return nil }
        }
        guard !KernelExploit.requiresSandboxEscape || KernelExploit.hasSandboxAccess() || shouldUseBadQuery else {
            return nil
        }

        // 1. Quét nhanh các container thông qua pathleak (fsgetpath)
        let maxInode = (try? WorseQueryHelper.currentFilesystemMaxInode()) ?? 2_000_000
        let leakDirs = (pathleak(appDataRoot, maxInode) as? [String]) ?? []

        let candidateDirs: [String]
        if !leakDirs.isEmpty {
            candidateDirs = leakDirs
            log("patch: pathleak enumerated \(candidateDirs.count) candidate containers")
        } else {
            let dirs = enumerateDirectoriesWithTraversalGrant(path: appDataRoot)
            candidateDirs = dirs.isEmpty ? enumerateDirectories(path: appDataRoot, maxInode: Int64(maxInode)) : dirs
        }

        guard !candidateDirs.isEmpty else {
            log("patch: metadata scan unavailable — no containers enumerated")
            return nil
        }

        for dir in candidateDirs {
            let cleanDir = ContainerDiscoveryMerger.canonicalPath(dir)
            guard UUID(uuidString: (cleanDir as NSString).lastPathComponent) != nil else { continue }
            let handle = grantContainerAccess(cleanDir)
            defer { if handle >= 0 { sandbox_extension_release_handle(handle) } }

            var matched = false
            if WorseQueryHelper.isAvailable {
                var buf = [CChar](repeating: 0, count: 512)
                let len = getxattr(cleanDir, "com.apple.containermanager.identifier", &buf, 511, 0, 0)
                if len > 0 {
                    let id = String(cString: buf)
                    if id == bundleID {
                        matched = true
                    }
                }
            }

            if !matched, let metadata = readContainerMetadata(containerPath: cleanDir), metadata.bundleID == bundleID {
                matched = true
            }

            if matched {
                let canonical = ContainerDiscoveryMerger.canonicalPath(cleanDir)
                if isApplicationContainerPath(canonical) {
                    return canonical
                }
            }

        }
        return nil
    }

    // MARK: Primary — MobileInstallation / LSApplicationWorkspace

    static func installedAppsFromAPI() -> [InstalledApp] {
        let raw = installedAppInfo() as? [String: [String: Any]] ?? [:]
        var apps: [InstalledApp] = []
        var missingContainer = 0
        for (bundleID, info) in raw {
            var containerPath = info["container"] as? String ?? ""
            if containerPath.isEmpty {
                var lookupError: NSString?
                if let resolved = MCMActivateContainerPath(2, bundleID, false, &lookupError),
                   isApplicationContainerPath(resolved) {
                    containerPath = resolved
                } else {
                    missingContainer += 1
                }
            }
            // Skip entries we cannot browse — empty path is dropped by mergers anyway.
            guard !containerPath.isEmpty else { continue }
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: info["name"] as? String ?? "",
                containerPath: containerPath,
                version: info["version"] as? String ?? "",
                icon: info["icon"] as? UIImage
            ))
        }
        log("browser: LS/API apps=\(apps.count) raw=\(raw.count) missingContainer=\(missingContainer)")
        return apps
    }

    static func applicationBundleMetadataCatalog() -> [String: ApplicationBundleMetadata] {
        var catalog: [String: ApplicationBundleMetadata] = [:]
        for root in applicationBundleRoots {
            for metadata in applicationBundleMetadata(at: root.path, nested: root.nested) {
                catalog[metadata.bundleID] = metadata
            }
        }
        log("browser: app-bundle metadata resolved \(catalog.count) names")
        return catalog
    }

    static func applyingBundleMetadata(
        to apps: [InstalledApp],
        catalog: [String: ApplicationBundleMetadata]
    ) -> [InstalledApp] {
        apps.map { app in
            guard let metadata = catalog[app.bundleID] else { return app }
            return InstalledApp(
                bundleID: app.bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: app.bundleID,
                    candidates: [metadata.displayName, app.name]
                ),
                containerPath: app.containerPath,
                version: app.version.isEmpty ? metadata.version : app.version,
                icon: app.icon
            )
        }
    }

    static func dynamicAppIdentifiers() -> [String] {
        var enumerationError: NSString?
        let identifiers = MCMEnumerateIdentifiersForClass(2, 1_024, &enumerationError)
        let enumerationDetail = enumerationError.map { String($0) } ?? "none"
        log("browser: MCM class-2 identifiers=\(identifiers.count) detail=\(enumerationDetail)")
        return identifiers
    }

    static func installedAppsFromMCM(
        identifiers: [String]? = nil,
        bundleMetadata: [String: ApplicationBundleMetadata] = [:]
    ) -> [InstalledApp] {
        let identifiers = identifiers ?? dynamicAppIdentifiers()

        var apps: [InstalledApp] = []
        for (index, bundleID) in identifiers.enumerated() {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(2, bundleID, false, &lookupError) else {
                let lookupDetail = lookupError.map { String($0) } ?? "no path"
                if index < 3 { log("mcm[\(index)]: \(bundleID) -> \(lookupDetail)") }
                continue
            }
            if index < 3 { log("mcm[\(index)]: \(bundleID) -> \(containerPath)") }

            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let metadata = bundleMetadata[bundleID]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: bundleID,
                    candidates: [metadata?.displayName, rawInfo["name"] as? String]
                ),
                containerPath: containerPath,
                version: rawInfo["version"] as? String ?? metadata?.version ?? "",
                icon: rawInfo["icon"] as? UIImage
            ))
        }
        log("browser: MCM resolved \(apps.count)/\(identifiers.count) app paths")
        return apps
    }

    // MARK: LaunchServices store discovery

    static func installedAppsFromMHACandidates(
        identifiers: [String],
        bundleMetadata: [String: ApplicationBundleMetadata] = [:],
        progress: (([InstalledApp]) -> Void)? = nil
    ) -> [InstalledApp] {
        guard !identifiers.isEmpty else {
            log("browser: MHA catalog returned no bundle candidates")
            return []
        }

        var apps: [InstalledApp] = []
        for (index, bundleID) in identifiers.enumerated() {
            var lookupError: NSString?
            guard let containerPath = MCMActivateContainerPath(
                2,
                bundleID,
                false,
                &lookupError
            ),
                  isApplicationContainerPath(containerPath) else {
                if index < 3 {
                    let detail = lookupError.map { String($0) } ?? "invalid app-data path"
                    log("mha-candidate[\(index)]: \(bundleID) -> \(detail)")
                }
                continue
            }

            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let metadata = bundleMetadata[bundleID]
            apps.append(InstalledApp(
                bundleID: bundleID,
                name: AppDisplayNamePolicy.resolve(
                    bundleID: bundleID,
                    candidates: [metadata?.displayName, rawInfo["name"] as? String]
                ),
                containerPath: containerPath,
                version: rawInfo["version"] as? String ?? metadata?.version ?? "",
                icon: rawInfo["icon"] as? UIImage
            ))
            if apps.count <= 5 {
                log("browser: MHA-C2 resolved \(bundleID) -> \(containerPath)")
            }
            if apps.count.isMultiple(of: 8) {
                progress?(apps)
            }
        }

        progress?(apps)
        log("browser: MHA-C2 resolved \(apps.count)/\(identifiers.count) bundle candidates")
        return apps
    }

    private static func applicationBundleMetadata(
        at rootPath: String,
        nested: Bool
    ) -> [ApplicationBundleMetadata] {
        let handle = grantContainerAccess(rootPath)
        defer {
            if handle >= 0 { bad_query_release(handle) }
        }

        let fileManager = FileManager.default
        guard let rootEntries = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            log("browser: app-bundle metadata unavailable root=\(rootPath) grant=\(handle)")
            return []
        }

        let bundlePaths: [String]
        if nested {
            bundlePaths = rootEntries.prefix(2_048).flatMap { entry -> [String] in
                guard UUID(uuidString: entry) != nil else { return [] }
                let containerPath = (rootPath as NSString).appendingPathComponent(entry)
                let children = (try? fileManager.contentsOfDirectory(atPath: containerPath)) ?? []
                return children.prefix(16).compactMap { child in
                    guard child.hasSuffix(".app") else { return nil }
                    return (containerPath as NSString).appendingPathComponent(child)
                }
            }
        } else {
            bundlePaths = rootEntries.prefix(2_048).compactMap { entry in
                guard entry.hasSuffix(".app") else { return nil }
                return (rootPath as NSString).appendingPathComponent(entry)
            }
        }

        return bundlePaths.compactMap { bundlePath in
            let infoPath = (bundlePath as NSString).appendingPathComponent("Info.plist")
            let infoSize = (try? fileManager.attributesOfItem(atPath: infoPath)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard infoSize > 0, infoSize <= 2 * 1_024 * 1_024 else { return nil }
            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPath)) else {
                return nil
            }
            return ApplicationBundleMetadataReader.metadata(
                from: plistData,
                localizedInfo: Bundle(path: bundlePath)?.localizedInfoDictionary
            )
        }
    }

    static func launchServicesStoreIdentifiers() -> [String] {
        var cachePaths: [String] = []
        var seenCachePaths = Set<String>()

        func addCachePath(_ rawPath: String) {
            let path = ContainerDiscoveryMerger.canonicalPath(rawPath)
            guard !path.isEmpty, seenCachePaths.insert(path).inserted else { return }
            cachePaths.append(path)
        }

        var leasedCachePaths = Set<String>()
        var serviceLookupError: NSString?
        if let servicePath = MCMActivateContainerPath(
            10,
            "com.apple.lsd",
            false,
            &serviceLookupError
        ) {
            let cachePath = (servicePath as NSString).appendingPathComponent("Library/Caches")
            addCachePath(cachePath)
            leasedCachePaths.insert(ContainerDiscoveryMerger.canonicalPath(cachePath))
        } else if shouldUseBadQuery {
            let detail = serviceLookupError.map { String($0) } ?? "no path"
            log("browser: MCM com.apple.lsd activation unavailable detail=\(detail)")
        }

        let traversedSystemDirectories = enumerateDirectoriesWithTraversalGrant(path: systemDataRoot)
        let systemDirectories = traversedSystemDirectories.isEmpty
            ? enumerateDirectories(path: systemDataRoot)
            : traversedSystemDirectories
        for directory in systemDirectories {
            // Attempt the raw metadata read even without a traversal grant:
            // it succeeds when the sandbox escape is active, which is the
            // only path left when MCM/bad_query grants are denied.
            guard readContainerMetadata(containerPath: directory)?.bundleID == "com.apple.lsd" else {
                continue
            }
            addCachePath((directory as NSString).appendingPathComponent("Library/Caches"))
        }

        // Older and Simulator layouts keep the same store outside the MCM
        // service-container layout. They are harmless fallbacks on device.
        addCachePath("/var/db/lsd")
        addCachePath("/var/mobile/Library/Caches")

        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()
        let maximumCandidateCount = 65_536

        for cachePath in cachePaths where identifiers.count < maximumCandidateCount {
            let hasLease = leasedCachePaths.contains(
                ContainerDiscoveryMerger.canonicalPath(cachePath)
            )
            let handle: Int64
            if hasLease || !shouldUseBadQuery {
                handle = -1
            } else {
                handle = grantContainerAccess(cachePath)
                if handle < 0 {
                    log("browser: LaunchServices traversal grant failed \(cachePath) -> \(handle)")
                    continue
                }
            }
            defer {
                if handle >= 0 { bad_query_release(handle) }
            }

            let names = (try? FileManager.default.contentsOfDirectory(atPath: cachePath)) ?? []
            for name in names where identifiers.count < maximumCandidateCount {
                guard name.hasPrefix("com.apple.LaunchServices-"),
                      name.hasSuffix("-v2.csstore") else {
                    continue
                }
                let storePath = (cachePath as NSString).appendingPathComponent(name)
                guard let size = (try? FileManager.default.attributesOfItem(atPath: storePath)[.size]) as? NSNumber,
                      size.uint64Value > 0,
                      size.uint64Value <= 64 * 1_024 * 1_024,
                      let data = try? Data(contentsOf: URL(fileURLWithPath: storePath), options: .mappedIfSafe) else {
                    continue
                }
                let remaining = maximumCandidateCount - identifiers.count
                let extracted = LaunchServicesCandidateExtractor.identifiers(from: data, limit: remaining)
                for identifier in extracted where seenIdentifiers.insert(identifier).inserted {
                    identifiers.append(identifier)
                }
                log("browser: LaunchServices store \(name) bytes=\(data.count) candidates=\(identifiers.count)")
            }
        }

        log("browser: LaunchServices store total candidates=\(identifiers.count)")
        return identifiers
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        var clean = ContainerDiscoveryMerger.canonicalPath(path)
        while clean.count > 1 && clean.hasSuffix("/") {
            clean.removeLast()
        }
        let canonicalRoot = ContainerDiscoveryMerger.canonicalPath(appDataRoot)
        guard clean.hasPrefix(canonicalRoot + "/") else { return false }
        let uuid = String(clean.dropFirst(canonicalRoot.count + 1))
        return !uuid.contains("/") && UUID(uuidString: uuid) != nil
    }

    // MARK: Filesystem discovery

    static func enumerateDirectories(path: String, maxInode: Int64 = 2_000_000) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard clean.hasPrefix("/") else { return [] }

        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }

        guard ExploitSupportPolicy.currentAccessProvider == .legacy3105 else {
            return []
        }

        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, maxInode) else {
            log("enumerate: NULL for \(clean)")
            return []
        }
        defer { free(result) }
        let list = String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
        if !list.isEmpty {
            log("enumerate: inode fallback for \(clean) -> \(list.count) entries")
        } else {
            log("enumerate: FileManager+inode unavailable for \(clean)")
        }
        return list
    }

    static func enumerateDirectoriesWithTraversalGrant(path: String) -> [String] {
        if !shouldUseBadQuery {
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty {
                return names.map { (path as NSString).appendingPathComponent($0) }
            }
            return enumerateDirectories(path: path)
        }

        let handle = grantContainerAccess(path)
        if handle >= 0 {
            defer { bad_query_release(handle) }
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path), !names.isEmpty {
                return names.map { (path as NSString).appendingPathComponent($0) }
            }
        } else {
            log("browser: root traversal grant failed \(path) -> \(handle)")
        }

        return enumerateDirectories(path: path)
    }

    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? {
        let metadataPath = metadataPath(for: containerPath)

        var data: Data?
        if WorseQueryHelper.isAvailable && WorseQueryHelper.isScopeSupported(for: containerPath) {
            data = try? WorseQueryHelper.readFile(at: metadataPath)
        }
        if data == nil {
            if let fd = fopen(metadataPath, "r") {
                var buffer = [UInt8](repeating: 0, count: 65536)
                var bytes: [UInt8] = []
                while true {
                    let n = fread(&buffer, 1, buffer.count, fd)
                    if n <= 0 { break }
                    bytes.append(contentsOf: buffer[0..<n])
                }
                fclose(fd)
                if !bytes.isEmpty { data = Data(bytes) }
            }
        }
        if data == nil { data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)) }

        guard let validData = data,
              let plist = try? PropertyListSerialization.propertyList(from: validData, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let bundleID = plist["MCMMetadataIdentifier"] as? String ?? ""
        var displayName = ""
        if let info = plist["MCMMetadataInfo"] as? [String: Any] {
            displayName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ""
        }
        return ContainerMetadata(bundleID: bundleID, displayName: displayName)
    }

    static func metadataPath(for containerPath: String) -> String {
        (containerPath as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
    }

    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        let clean = containerPath.hasSuffix("/") ? String(containerPath.dropLast()) : containerPath
        if WorseQueryHelper.isAvailable && WorseQueryHelper.isScopeSupported(for: clean) {
            do {
                return try WorseQueryHelper.acquireAccess(for: clean)
            } catch {
                log("worse_query: container grant failed: \(error.localizedDescription)")
            }
        }
        guard shouldUseBadQuery else { return -1 }
        var pathC = clean.utf8CString.map { Int8($0) }
        return bad_query(&pathC, true, nil, false)
    }

    static func containersFromFilesystem() -> [InstalledApp] {
        let grantedDirectories = enumerateDirectoriesWithTraversalGrant(path: appDataRoot)
        let dirs: [String]
        if grantedDirectories.isEmpty {
            dirs = enumerateDirectories(path: appDataRoot)
            log("browser: filesystem root=\(appDataRoot) inode fallback enumerated \(dirs.count) containers")
        } else {
            dirs = grantedDirectories
            log("browser: filesystem root=\(appDataRoot) traversal enumerated \(dirs.count) containers")
        }
        let apps = dirs.compactMap { dir -> InstalledApp? in
            let uuid = (dir as NSString).lastPathComponent
            guard UUID(uuidString: uuid) != nil else { return nil }
            let fallback = ContainerIdentityResolver.fallbackIdentity(containerPath: dir)
            return InstalledApp(
                bundleID: fallback.bundleID,
                name: fallback.displayName,
                containerPath: dir,
                version: "",
                icon: nil
            )
        }
        log("browser: filesystem accepted \(apps.count)/\(dirs.count) app containers")
        return apps
    }

    static func inferredApp(
        for fallback: InstalledApp,
        knownAppsByBundleID: [String: InstalledApp],
        launchServicesIdentifiers: Set<String>
    ) -> InstalledApp? {
        guard UUID(uuidString: fallback.bundleID) != nil else { return fallback }

        // Read the MCM metadata plist directly. With the sandbox escape
        // active the raw read succeeds even when every MCM/bad_query grant
        // is denied; without it the read simply fails and we fall through.
        if let metadata = readContainerMetadata(containerPath: fallback.containerPath) {
            let bundleID = metadata.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if ContainerBundleCandidateResolver.isValidBundleIdentifier(bundleID),
               !bundleID.hasPrefix("systemgroup.") {
                let info = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
                let resolvedName = metadata.displayName.isEmpty
                    ? (info["name"] as? String ?? bundleID)
                    : metadata.displayName
                return InstalledApp(
                    bundleID: bundleID,
                    name: resolvedName,
                    containerPath: fallback.containerPath,
                    version: info["version"] as? String ?? "",
                    icon: info["icon"] as? UIImage
                )
            }
        }

        let handle = grantContainerAccess(fallback.containerPath)
        defer {
            if handle >= 0 { bad_query_release(handle) }
        }

        let libraryPath = (fallback.containerPath as NSString).appendingPathComponent("Library")
        let savedStatePath = (libraryPath as NSString).appendingPathComponent("Saved Application State")
        let preferencesPath = (libraryPath as NSString).appendingPathComponent("Preferences")
        let savedStates = (try? FileManager.default.contentsOfDirectory(atPath: savedStatePath)) ?? []
        let preferences = (try? FileManager.default.contentsOfDirectory(atPath: preferencesPath)) ?? []
        let strongCandidates = ContainerBundleCandidateResolver.candidates(
            savedStateNames: savedStates,
            preferenceFileNames: []
        )
        let candidates = ContainerBundleCandidateResolver.candidates(
            savedStateNames: savedStates,
            preferenceFileNames: preferences
        )

        func resolvedApp(from candidates: [String], source: String) -> InstalledApp? {
            for bundleID in candidates {
                if let known = knownAppsByBundleID[bundleID] {
                    return InstalledApp(
                        bundleID: bundleID,
                        name: known.name,
                        containerPath: fallback.containerPath,
                        version: known.version,
                        icon: known.icon
                    )
                }

                let info = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
                guard info["found"] as? Bool == true else { continue }
                return InstalledApp(
                    bundleID: bundleID,
                    name: info["name"] as? String ?? bundleID,
                    containerPath: fallback.containerPath,
                    version: info["version"] as? String ?? "",
                    icon: info["icon"] as? UIImage
                )
            }

            guard let bundleID = ContainerBundleCandidateResolver.confirmedCandidate(
                candidates: candidates,
                launchServicesIdentifiers: launchServicesIdentifiers
            ) else {
                return nil
            }
            let uuid = (fallback.containerPath as NSString).lastPathComponent
            log("browser: content+LaunchServices confirmed \(uuid) -> \(bundleID) source=\(source)")
            return InstalledApp(
                bundleID: bundleID,
                name: bundleID,
                containerPath: fallback.containerPath,
                version: "",
                icon: nil
            )
        }

        if let app = resolvedApp(from: candidates, source: "state/preferences") {
            return app
        }
        if let bundleID = strongCandidates.first {
            return InstalledApp(
                bundleID: bundleID,
                name: bundleID,
                containerPath: fallback.containerPath,
                version: "",
                icon: nil
            )
        }

        let artifactPaths = [
            (libraryPath as NSString).appendingPathComponent("SplashBoard/Snapshots"),
            (libraryPath as NSString).appendingPathComponent("Caches/Snapshots"),
            (libraryPath as NSString).appendingPathComponent("Cookies"),
            (libraryPath as NSString).appendingPathComponent("WebKit")
        ]
        let artifactNames = artifactPaths.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? []
        }
        let artifactCandidates = ContainerBundleCandidateResolver.candidates(
            savedStateNames: [],
            preferenceFileNames: [],
            artifactNames: artifactNames
        )
        if let app = resolvedApp(from: artifactCandidates, source: "artifacts") {
            return app
        }

        let uuid = (fallback.containerPath as NSString).lastPathComponent
        let preview = (candidates + artifactCandidates).prefix(6).joined(separator: ",")
        log("browser: unresolved \(uuid) metadata=unavailable savedStates=\(savedStates.count) preferences=\(preferences.count) artifacts=\(artifactNames.count) candidates=[\(preview)]")
        return nil
    }

    static func inferUnidentifiedApps(
        in apps: [InstalledApp],
        knownApps: [InstalledApp],
        launchServicesIdentifiers: Set<String> = []
    ) -> [InstalledApp] {
        let knownByBundleID = Dictionary(knownApps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        var inferredCount = 0
        let result = apps.enumerated().map { index, app -> InstalledApp in
            guard UUID(uuidString: app.bundleID) != nil,
                  let inferred = autoreleasepool(invoking: {
                      inferredApp(
                        for: app,
                        knownAppsByBundleID: knownByBundleID,
                        launchServicesIdentifiers: launchServicesIdentifiers
                      )
                  }) else {
                return app
            }
            inferredCount += 1
            if inferredCount <= 5 {
                log("browser: inferred \((app.containerPath as NSString).lastPathComponent) -> \(inferred.bundleID)")
            }
            return inferred
        }
        let unresolvedCount = result.filter { UUID(uuidString: $0.bundleID) != nil }.count
        log("browser: inferred identities for \(inferredCount)/\(apps.count) merged containers; unresolved=\(unresolvedCount)")
        return result
    }

    // MARK: File browsing

    static func listFiles(at path: String) -> [FileEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            log("listFiles: FAILED for \(path) errno=\(errno)")
            return []
        }
        var entries: [FileEntry] = []
        for item in items {
            if item.hasPrefix(".") { continue }
            let full = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let size = isDir.boolValue ? 0 : ((try? fm.attributesOfItem(atPath: full)[.size] as? Int64) ?? 0)
            entries.append(FileEntry(name: item, path: full, isDirectory: isDir.boolValue, size: size))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func readTextFile(at path: String, limit: Int = 200_000) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return "Unable to read file."
        }
        let truncated = data.prefix(limit)
        if let text = String(data: truncated, encoding: .utf8) {
            return data.count > limit ? text + "\n… [truncated]" : text
        }
        if let text = String(data: truncated, encoding: .utf16) {
            return data.count > limit ? text + "\n… [truncated]" : text
        }
        return "Binary data (\(data.count) bytes) — not text."
    }
}

// MARK: - Container Identity Resolver

struct ContainerMetadata: Equatable {
    let bundleID: String
    let displayName: String
}

enum ContainerResolution: Equatable {
    case resolved(ContainerMetadata)
    case accessFailed(Int64)
    case metadataUnavailable
    case unsupportedIdentifier(String)

    var logDescription: String {
        switch self {
        case .resolved(let metadata):
            return "resolved \(metadata.bundleID)"
        case .accessFailed(let code):
            return "access failed (\(code))"
        case .metadataUnavailable:
            return "metadata unavailable"
        case .unsupportedIdentifier(let identifier):
            return "identifier '\(identifier)' skipped"
        }
    }
}

enum ContainerIdentityResolver {
    static func fallbackIdentity(containerPath: String) -> ContainerMetadata {
        let identifier = (containerPath as NSString).lastPathComponent
        let shortIdentifier = String(identifier.prefix(8))
        return ContainerMetadata(
            bundleID: identifier,
            displayName: "Container \(shortIdentifier)"
        )
    }

    static func resolve(
        containerPath: String,
        grantAccess: (String) -> Int64,
        releaseAccess: (Int64) -> Void,
        loadMetadata: (String) -> ContainerMetadata?
    ) -> ContainerResolution {
        let handle = grantAccess(containerPath)
        guard handle >= 0 else { return .accessFailed(handle) }
        defer { releaseAccess(handle) }

        guard let metadata = loadMetadata(containerPath) else {
            return .metadataUnavailable
        }

        let bundleID = metadata.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return .metadataUnavailable }
        guard !bundleID.hasPrefix("systemgroup.") else {
            return .unsupportedIdentifier(bundleID)
        }

        return .resolved(ContainerMetadata(bundleID: bundleID, displayName: metadata.displayName))
    }
}
