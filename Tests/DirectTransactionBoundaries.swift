// macOS filesystem regression boundaries. Production transaction, path models,
// digests, journals, atomic I/O and rollback compile without substitution.
import Foundation

enum ExploitSupportPolicy {
    enum Provider { case legacy3105, worseQuery }
    static let currentAccessProvider = Provider.legacy3105
}
enum ContainerStore {
    static func isApplicationContainerPath(_ path: String) -> Bool { true }
    static func resolveAppContainerForPatch(bundleID: String) throws -> String {
        fatalError("device resolution is not used by filesystem fixtures")
    }
    static func grantContainerAccess(_ path: String) -> Int64 {
        fatalError("device grants are not used by filesystem fixtures")
    }
}
enum WorseQueryError: Error { case appGroupUnavailable }
enum WorseQueryHelper {
    static let isAvailable = false
    static func acquireAccess(for path: String) throws -> Int64 {
        fatalError("native access is not used by filesystem fixtures")
    }
}
@MainActor final class IOS27ContainerPreparation {
    static let shared = IOS27ContainerPreparation()
    func prepareAdditionalTargets(bundleIDs: [String]) async throws {
        fatalError("device preparation is not used by filesystem fixtures")
    }
}
enum PatchProjectLibrary {
    static func backupRootURL() throws -> URL {
        fatalError("device storage is not used by filesystem fixtures")
    }
}
func sandbox_extension_release_handle(_ handle: Int64) {}
