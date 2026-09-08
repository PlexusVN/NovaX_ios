import Foundation
import Darwin

// MARK: - Wallpaper Lab Models & Scanner

enum WallpaperLabError: Error, Equatable {
    case unsafeContainerRoot
    case posterStoreUnavailable
    case unsupportedPosterLayout
    case unsupportedPackage
    case unsafeArchive
    case symbolicLinkUnsupported
    case packageTooLarge
    case noDescriptors
    case accessDenied
    case backupFailed
    case installFailed
    case restoreFailed
}

extension WallpaperLabError: LocalizedError {
    var localizationKey: String {
        switch self {
        case .unsafeContainerRoot: return "wallpaper.error.unsafe_container"
        case .posterStoreUnavailable: return "wallpaper.error.store_unavailable"
        case .unsupportedPosterLayout: return "wallpaper.error.layout"
        case .unsupportedPackage: return "wallpaper.error.package"
        case .unsafeArchive: return "wallpaper.error.archive"
        case .symbolicLinkUnsupported: return "wallpaper.error.symlink"
        case .packageTooLarge: return "wallpaper.error.size"
        case .noDescriptors: return "wallpaper.error.no_descriptors"
        case .accessDenied: return "wallpaper.error.access"
        case .backupFailed: return "wallpaper.error.backup"
        case .installFailed: return "wallpaper.error.install"
        case .restoreFailed: return "wallpaper.error.restore"
        }
    }

    var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

enum WallpaperLabLimits {
    static let maximumArchiveBytes: Int64 = 512 * 1_024 * 1_024
    static let maximumExpandedBytes: Int64 = 768 * 1_024 * 1_024
    static let maximumEntryBytes: Int64 = 256 * 1_024 * 1_024
    static let maximumEntryCount = 20_000
    static let maximumDescriptorCount = 64
    static let maximumPathBytes = 4_096
}

struct WallpaperPosterLayout: Equatable {
    static let collectionsExtension = "com.apple.WallpaperKit.CollectionsPoster"
    static let photosExtension = "com.apple.PhotosUIPrivate.PhotosPosterProvider"
    static let mercuryExtension = "com.apple.MercuryPoster"

    let generation: String
    let storeURL: URL
    let extensionDescriptorDirectories: [String: URL]

    var supportsCollections: Bool {
        extensionDescriptorDirectories[Self.collectionsExtension] != nil
    }

    var supportsVideo: Bool {
        extensionDescriptorDirectories[Self.photosExtension] != nil
    }
}

struct WallpaperDescriptorSource: Equatable, Identifiable {
    let extensionIdentifier: String
    let directoryURL: URL
    let byteCount: Int64
    let fileCount: Int
    let isOrdered: Bool

    var id: String { "\(extensionIdentifier):\(directoryURL.path)" }
}

struct TendiesPayload: Equatable {
    let descriptors: [WallpaperDescriptorSource]
    let totalBytes: Int64
    let fileCount: Int
}

enum WallpaperLayoutScanner {
    static let storeRelativePath = "Library/Application Support/PRBPosterExtensionDataStore"

    typealias RootValidator = (URL) -> Bool

    static func scan(
        containerURL rawContainerURL: URL,
        rootValidator: RootValidator,
        fileManager: FileManager = .default
    ) throws -> WallpaperPosterLayout {
        let containerURL = rawContainerURL.standardizedFileURL
        guard containerURL.isFileURL,
              containerURL.path.hasPrefix("/"),
              containerURL.path != "/",
              rootValidator(containerURL) else {
            throw WallpaperLabError.unsafeContainerRoot
        }
        try validateDirectory(containerURL, fileManager: fileManager)

        let storeURL = containerURL.appendingPathComponent(
            storeRelativePath,
            isDirectory: true
        )
        guard isContained(storeURL, in: containerURL),
              fileManager.fileExists(atPath: storeURL.path) else {
            throw WallpaperLabError.posterStoreUnavailable
        }
        try validatePathComponents(
            relativePath: storeRelativePath,
            root: containerURL,
            fileManager: fileManager
        )

        let generationURLs = try fileManager.contentsOfDirectory(
            at: storeURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard Int(url.lastPathComponent) != nil else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }.sorted {
            (Int($0.lastPathComponent) ?? -1) > (Int($1.lastPathComponent) ?? -1)
        }

        guard !generationURLs.isEmpty else {
            throw WallpaperLabError.unsupportedPosterLayout
        }

        for generationURL in generationURLs {
            let extensionsURL = generationURL.appendingPathComponent("Extensions", isDirectory: true)
            guard fileManager.fileExists(atPath: extensionsURL.path) else { continue }
            try validateDirectory(extensionsURL, fileManager: fileManager)

            var descriptorDirectories: [String: URL] = [:]
            let extensions = try fileManager.contentsOfDirectory(
                at: extensionsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for extensionURL in extensions {
                let values = try extensionURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                guard validExtensionIdentifier(extensionURL.lastPathComponent) else { continue }
                let descriptorsURL = extensionURL.appendingPathComponent(
                    "descriptors",
                    isDirectory: true
                )
                guard fileManager.fileExists(atPath: descriptorsURL.path) else { continue }
                try validateDirectory(descriptorsURL, fileManager: fileManager)
                descriptorDirectories[extensionURL.lastPathComponent] = descriptorsURL
            }

            if !descriptorDirectories.isEmpty {
                return WallpaperPosterLayout(
                    generation: generationURL.lastPathComponent,
                    storeURL: storeURL,
                    extensionDescriptorDirectories: descriptorDirectories
                )
            }
        }
        throw WallpaperLabError.unsupportedPosterLayout
    }

    static func validExtensionIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255, value.contains(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func validateDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw WallpaperLabError.posterStoreUnavailable
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw WallpaperLabError.symbolicLinkUnsupported
        }
        guard values.isDirectory == true else {
            throw WallpaperLabError.unsupportedPosterLayout
        }
    }

    static func validatePathComponents(
        relativePath: String,
        root: URL,
        fileManager: FileManager = .default
    ) throws {
        var cursor = root
        for component in relativePath.split(separator: "/").map(String.init) {
            cursor.appendPathComponent(component, isDirectory: true)
            guard isContained(cursor, in: root) else {
                throw WallpaperLabError.unsafeContainerRoot
            }
            try validateDirectory(cursor, fileManager: fileManager)
        }
    }

    static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

enum TendiesPackageInspector {
    static func inspectExtractedPackage(
        at packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> TendiesPayload {
        try WallpaperLayoutScanner.validateDirectory(packageURL, fileManager: fileManager)
        let descriptors = try collectDescriptorSources(
            in: packageURL,
            packageRoot: packageURL,
            fileManager: fileManager
        )

        guard !descriptors.isEmpty else { throw WallpaperLabError.noDescriptors }
        guard descriptors.count <= WallpaperLabLimits.maximumDescriptorCount else {
            throw WallpaperLabError.packageTooLarge
        }
        let totalBytes = descriptors.reduce(Int64(0)) { $0 + $1.byteCount }
        let fileCount = descriptors.reduce(0) { $0 + $1.fileCount }
        guard totalBytes <= WallpaperLabLimits.maximumExpandedBytes,
              fileCount <= WallpaperLabLimits.maximumEntryCount else {
            throw WallpaperLabError.packageTooLarge
        }
        return TendiesPayload(
            descriptors: descriptors,
            totalBytes: totalBytes,
            fileCount: fileCount
        )
    }

    private static func collectDescriptorSources(
        in directory: URL,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> [WallpaperDescriptorSource] {
        guard WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WallpaperDescriptorSource] = []

        for child in children where child.lastPathComponent != "__MACOSX" {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else { continue }

            let name = child.lastPathComponent.lowercased()
            if name == "container" {
                let layout = try WallpaperLayoutScanner.scan(
                    containerURL: child,
                    rootValidator: { $0.standardizedFileURL == child.standardizedFileURL },
                    fileManager: fileManager
                )
                for (identifier, descriptorDirectory) in layout.extensionDescriptorDirectories
                    .sorted(by: { $0.key < $1.key }) {
                    result += try descriptorSources(
                        in: descriptorDirectory,
                        extensionIdentifier: identifier,
                        isOrdered: false,
                        packageRoot: packageRoot,
                        fileManager: fileManager
                    )
                }
            } else if name.contains("descriptor") {
                let extensionIdentifier: String
                if name.contains("video") || name.contains("photos") {
                    extensionIdentifier = WallpaperPosterLayout.photosExtension
                } else if name.contains("mercury") {
                    extensionIdentifier = WallpaperPosterLayout.mercuryExtension
                } else {
                    extensionIdentifier = WallpaperPosterLayout.collectionsExtension
                }
                result += try descriptorSources(
                    in: child,
                    extensionIdentifier: extensionIdentifier,
                    isOrdered: name.contains("ordered"),
                    packageRoot: packageRoot,
                    fileManager: fileManager
                )
            } else {
                result += try collectDescriptorSources(
                    in: child,
                    packageRoot: packageRoot,
                    fileManager: fileManager
                )
            }
        }
        return result
    }

    private static func descriptorSources(
        in directory: URL,
        extensionIdentifier: String,
        isOrdered: Bool,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> [WallpaperDescriptorSource] {
        guard WallpaperLayoutScanner.validExtensionIdentifier(extensionIdentifier),
              WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WallpaperDescriptorSource] = []
        for child in children where child.lastPathComponent != "__MACOSX" {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else { continue }
            let summary = try validateTree(
                at: child,
                packageRoot: packageRoot,
                fileManager: fileManager
            )
            result.append(
                WallpaperDescriptorSource(
                    extensionIdentifier: extensionIdentifier,
                    directoryURL: child,
                    byteCount: summary.bytes,
                    fileCount: summary.files,
                    isOrdered: isOrdered
                )
            )
        }
        return result
    }

    private static func validateTree(
        at directory: URL,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> (bytes: Int64, files: Int) {
        guard WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        var bytes: Int64 = 0
        var files = 0
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw WallpaperLabError.unsupportedPackage
        }
        for case let itemURL as URL in enumerator {
            guard WallpaperLayoutScanner.isContained(itemURL, in: packageRoot),
                  itemURL.path.utf8.count <= WallpaperLabLimits.maximumPathBytes else {
                throw WallpaperLabError.unsafeArchive
            }
            let values = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ])
            if values.isSymbolicLink == true {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size >= 0, size <= WallpaperLabLimits.maximumEntryBytes else {
                    throw WallpaperLabError.packageTooLarge
                }
                bytes += size
                files += 1
                guard bytes <= WallpaperLabLimits.maximumExpandedBytes,
                      files <= WallpaperLabLimits.maximumEntryCount else {
                    throw WallpaperLabError.packageTooLarge
                }
            } else if values.isDirectory != true {
                throw WallpaperLabError.unsupportedPackage
            }
        }
        return (bytes, files)
    }
}

// MARK: - Wallpaper Access Probe & Service

struct WallpaperAccessReport: Equatable {
    let layout: WallpaperPosterLayout
    let descriptorCount: Int
    let canInstall: Bool
    let deniedExtensionIdentifiers: [String]
}

enum WallpaperAccessProbe {
    static func probe(
        containerURL: URL,
        rootValidator: WallpaperLayoutScanner.RootValidator,
        requiredExtensionIdentifiers: Set<String>? = nil,
        fileManager: FileManager = .default
    ) throws -> WallpaperAccessReport {
        let layout = try WallpaperLayoutScanner.scan(
            containerURL: containerURL,
            rootValidator: rootValidator,
            fileManager: fileManager
        )
        var descriptorCount = 0
        for descriptorDirectory in layout.extensionDescriptorDirectories.values {
            let names = (try? fileManager.contentsOfDirectory(atPath: descriptorDirectory.path)) ?? []
            descriptorCount += names.filter { !$0.hasPrefix(".") }.count
        }

        let requiredIdentifiers: [String]
        if let requiredExtensionIdentifiers {
            requiredIdentifiers = requiredExtensionIdentifiers.sorted()
        } else if layout.supportsCollections {
            requiredIdentifiers = [WallpaperPosterLayout.collectionsExtension]
        } else {
            requiredIdentifiers = layout.extensionDescriptorDirectories.keys.sorted()
        }
        var deniedIdentifiers = requiredIdentifiers.filter {
            layout.extensionDescriptorDirectories[$0] == nil
        }

        for identifier in requiredIdentifiers where !deniedIdentifiers.contains(identifier) {
            guard let descriptorDirectory = layout.extensionDescriptorDirectories[identifier] else {
                continue
            }

            let probeURL = descriptorDirectory.appendingPathComponent(
                ".3105-wallpaper-probe-\(UUID().uuidString)",
                isDirectory: true
            )
            let created = mkdir(probeURL.path, 0o700) == 0
            if created {
                let descriptor = open(
                    probeURL.path,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
                if descriptor >= 0 { close(descriptor) }
                if rmdir(probeURL.path) != 0 || descriptor < 0 {
                    deniedIdentifiers.append(identifier)
                    try? fileManager.removeItem(at: probeURL)
                }
            } else {
                deniedIdentifiers.append(identifier)
            }
        }

        return WallpaperAccessReport(
            layout: layout,
            descriptorCount: descriptorCount,
            canInstall: !requiredIdentifiers.isEmpty
                && deniedIdentifiers.isEmpty,
            deniedExtensionIdentifiers: deniedIdentifiers
        )
    }
}

struct WallpaperStagedPackage: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let packageDirectoryURL: URL
    let archiveURL: URL
    let extractedURL: URL
    let payload: TendiesPayload
    let importedAt: Date
}

enum WallpaperPackageStore {
    private static let archiveName = "wallpaper.tendies"
    private static let extractedName = "Extracted"
    private static let metadataName = "metadata.plist"

    static func stagingRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try applicationSupportURL(fileManager: fileManager)
        let url = base.appendingPathComponent("WallpaperLab/Packages", isDirectory: true)
        try createApprovedDirectory(url, fileManager: fileManager)
        return url
    }

    static func backupRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try applicationSupportURL(fileManager: fileManager)
        let url = base.appendingPathComponent("WallpaperLab/Backups", isDirectory: true)
        try createApprovedDirectory(url, fileManager: fileManager)
        return url
    }

    static func importPackage(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> WallpaperStagedPackage {
        guard sourceURL.pathExtension.lowercased() == "tendies" else {
            throw WallpaperLabError.unsupportedPackage
        }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw WallpaperLabError.symbolicLinkUnsupported
        }
        let size = Int64(values.fileSize ?? 0)
        guard size > 0, size <= WallpaperLabLimits.maximumArchiveBytes else {
            throw WallpaperLabError.packageTooLarge
        }

        let root = try stagingRoot(fileManager: fileManager)
        let id = UUID()
        let importingURL = root.appendingPathComponent(
            ".importing-\(id.uuidString)",
            isDirectory: true
        )
        let finalURL = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: importingURL,
                withIntermediateDirectories: false
            )
            let archiveURL = importingURL.appendingPathComponent(archiveName)
            try fileManager.copyItem(at: sourceURL, to: archiveURL)
            let extractedURL = importingURL.appendingPathComponent(
                extractedName,
                isDirectory: true
            )
            _ = try SecureZIPArchive.extract(
                archiveURL: archiveURL,
                destinationURL: extractedURL,
                fileManager: fileManager
            )
            _ = try TendiesPackageInspector.inspectExtractedPackage(
                at: extractedURL,
                fileManager: fileManager
            )
            let metadata = PackageMetadata(
                id: id,
                displayName: sourceURL.deletingPathExtension().lastPathComponent,
                importedAt: Date()
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(metadata).write(
                to: importingURL.appendingPathComponent(metadataName),
                options: .atomic
            )
            guard rename(importingURL.path, finalURL.path) == 0 else {
                throw WallpaperLabError.unsafeArchive
            }
            return try loadPackage(at: finalURL, fileManager: fileManager)
        } catch let error as WallpaperLabError {
            try? fileManager.removeItem(at: importingURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: importingURL)
            throw WallpaperLabError.unsupportedPackage
        }
    }

    static func packages(fileManager: FileManager = .default) -> [WallpaperStagedPackage] {
        guard let root = try? stagingRoot(fileManager: fileManager),
              let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return directories.compactMap { directory in
            guard UUID(uuidString: directory.lastPathComponent) != nil else { return nil }
            return try? loadPackage(at: directory, fileManager: fileManager)
        }.sorted { $0.importedAt > $1.importedAt }
    }

    static func delete(
        _ package: WallpaperStagedPackage,
        fileManager: FileManager = .default
    ) throws {
        let root = try stagingRoot(fileManager: fileManager)
        guard package.packageDirectoryURL.deletingLastPathComponent().standardizedFileURL
                == root.standardizedFileURL,
              package.packageDirectoryURL.lastPathComponent == package.id.uuidString else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(
            package.packageDirectoryURL,
            fileManager: fileManager
        )
        try fileManager.removeItem(at: package.packageDirectoryURL)
    }

    private static func loadPackage(
        at directory: URL,
        fileManager: FileManager
    ) throws -> WallpaperStagedPackage {
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let metadataData = try Data(contentsOf: directory.appendingPathComponent(metadataName))
        let metadata = try PropertyListDecoder().decode(PackageMetadata.self, from: metadataData)
        guard directory.lastPathComponent == metadata.id.uuidString,
              !metadata.displayName.isEmpty,
              metadata.displayName.utf8.count <= 255 else {
            throw WallpaperLabError.unsupportedPackage
        }
        let archiveURL = directory.appendingPathComponent(archiveName)
        let extractedURL = directory.appendingPathComponent(extractedName, isDirectory: true)
        let payload = try TendiesPackageInspector.inspectExtractedPackage(
            at: extractedURL,
            fileManager: fileManager
        )
        return WallpaperStagedPackage(
            id: metadata.id,
            displayName: metadata.displayName,
            packageDirectoryURL: directory,
            archiveURL: archiveURL,
            extractedURL: extractedURL,
            payload: payload,
            importedAt: metadata.importedAt
        )
    }

    private static func applicationSupportURL(fileManager: FileManager) throws -> URL {
        guard let url = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw WallpaperLabError.accessDenied
        }
        try createApprovedDirectory(url, fileManager: fileManager)
        return url
    }

    private static func createApprovedDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            try WallpaperLayoutScanner.validateDirectory(url, fileManager: fileManager)
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private struct PackageMetadata: Codable {
    let id: UUID
    let displayName: String
    let importedAt: Date
}
