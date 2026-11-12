import Foundation

enum DeviceIdentityError: Error {
    case keychain(Int32), invalidIdentity, identityMissing, ambiguousIdentity, invalidInput
}
struct DeviceIdentityStorage {
    let read: (String) throws -> Data?
    let write: (String, Data) throws -> Void
    let remove: (String) throws -> Void
}
enum CheckError: Error { case failed(String), diskUnavailable }
final class HWIDMemory: @unchecked Sendable {
    var data: Data?
    var readError: Error?
    var writeError: Error?
    var winnerOnWrite: Data?
    var writes = 0
    init(_ value: String? = nil) { data = value.map { Data($0.utf8) } }
    var storage: DeviceIdentityStorage { DeviceIdentityStorage(read: { _ in
        if let error = self.readError { throw error }; return self.data
    }, write: { _, data in
        self.writes += 1
        if let winner = self.winnerOnWrite { self.data = winner }
        if let error = self.writeError { throw error }; self.data = data
    }, remove: { _ in preconditionFailure("HWID must never delete an identity") }) }
}
@MainActor enum UIApplication {
    struct App { var isProtectedDataAvailable = true }
    static var shared = App()
}
@MainActor enum DeviceUtils {
    static var operation: () throws -> String = { throw DeviceIdentityError.identityMissing }
    static func resolveHWID() throws -> String { try operation() }
}

@main struct StableHWIDSelfCheck {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckError.failed(message) }; checks += 1
    }
    @MainActor static func main() async throws {
        let original = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let changed = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        do {
            let primary = HWIDMemory(original), mirror = HWIDMemory()
            try expect(try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage) == original, "IDFV overwrote registered HWID")
            try expect(primary.writes == 0 && mirror.data == primary.data, "existing HWID not mirrored without rewriting Keychain")
            primary.readError = DeviceIdentityError.keychain(-25308)
            try expect(try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage) == original, "temporary Keychain outage discarded known HWID")
            try expect(primary.writes == 0, "read failure wrote over inaccessible Keychain")
        }
        do {
            let primary = HWIDMemory(), mirror = HWIDMemory(original)
            primary.writeError = DeviceIdentityError.keychain(-34018)
            try expect(try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage) == original, "re-signing changed HWID despite a saved backup")
            try expect(mirror.data == Data(original.utf8), "restore destroyed backup")
        }
        do {
            let primary = HWIDMemory(), mirror = HWIDMemory()
            primary.writeError = DeviceIdentityError.keychain(-25308)
            try expect(try StableDeviceHWID.resolve(storage:primary.storage,vendorID:original,mirror:mirror.storage) == original, "confirmed-new public HWID could not use durable backup")
            primary.readError = DeviceIdentityError.keychain(-34018)
            try expect(try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage) == original, "backup did not survive a later signing/Keychain failure")
        }
        do {
            let primary = HWIDMemory(), mirror = HWIDMemory()
            primary.readError = DeviceIdentityError.keychain(-34018)
            do { _ = try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage); throw CheckError.failed("unknown inaccessible identity was replaced with IDFV") }
            catch DeviceIdentityError.keychain(-34018) {}
            try expect(primary.writes == 0 && mirror.writes == 0, "unknown identity was silently allocated")
        }
        do {
            let primary = HWIDMemory(), mirror = HWIDMemory()
            primary.writeError = DeviceIdentityError.keychain(-25308); mirror.writeError = CheckError.diskUnavailable
            do { _ = try StableDeviceHWID.resolve(storage:primary.storage,vendorID:original,mirror:mirror.storage); throw CheckError.failed("HWID published without any successful persistence") }
            catch CheckError.diskUnavailable {}
            try expect(primary.data == nil && mirror.data == nil, "failed persistence changed identity")
        }
        do {
            let primary = HWIDMemory(), mirror = HWIDMemory()
            primary.winnerOnWrite = Data(original.utf8); primary.writeError = DeviceIdentityError.keychain(-25299)
            try expect(try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage) == original, "SecItemAdd race overwrote winning ID")
            try expect(mirror.data == Data(original.utf8) && primary.writes == 1, "race winner not preserved")
        }
        do {
            let primary = HWIDMemory(original), mirror = HWIDMemory(changed)
            do { _ = try StableDeviceHWID.resolve(storage:primary.storage,vendorID:nil,mirror:mirror.storage); throw CheckError.failed("conflicting identities were silently accepted") }
            catch DeviceIdentityError.ambiguousIdentity {}
            try expect(primary.writes == 0 && mirror.writes == 0, "conflict overwrote identity evidence")
        }
        for corruptPrimary in [false,true] {
            let primary = HWIDMemory(corruptPrimary ? "corrupted" : nil)
            let mirror = HWIDMemory(corruptPrimary ? original : "corrupted")
            do { _ = try StableDeviceHWID.resolve(storage:primary.storage,vendorID:changed,mirror:mirror.storage); throw CheckError.failed("corrupt saved identity was replaced") }
            catch DeviceIdentityError.invalidIdentity {}
            try expect(primary.writes == 0 && mirror.writes == 0, "corrupt data was overwritten")
        }
        do {
            let primary = HWIDMemory(), mirror = HWIDMemory()
            do { _ = try StableDeviceHWID.resolve(storage:primary.storage,vendorID:nil,mirror:mirror.storage); throw CheckError.failed("nil IDFV invented an identity") }
            catch DeviceIdentityError.identityMissing {}
            try expect(primary.writes == 0 && mirror.writes == 0, "nil IDFV persisted a random HWID")
        }
        do {
            let primary = HWIDMemory()
            primary.writeError = DeviceIdentityError.keychain(-25308)
            do { _ = try StableDeviceHWID.resolve(storage:primary.storage,vendorID:original); throw CheckError.failed("legacy no-mirror API ignored failed persistence") }
            catch DeviceIdentityError.keychain(-25308) {}
            try expect(primary.data == nil, "old secure contract changed")
        }
        do {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:path) }
            let disk = DeviceIdentityStorage(read: { _ in
                if !FileManager.default.fileExists(atPath:path.path) { return nil }
                return try Data(contentsOf:path)
            }, write: { _, data in try data.write(to:path,options:.atomic) }, remove: { _ in })
            let first = HWIDMemory(original)
            _ = try StableDeviceHWID.resolve(storage:first.storage,vendorID:nil,mirror:disk)
            let restarted = HWIDMemory(); restarted.readError = DeviceIdentityError.keychain(-34018)
            try expect(try StableDeviceHWID.resolve(storage:restarted.storage,vendorID:changed,mirror:disk) == original, "real on-disk backup failed after process-like restart")
        }
        for (error,protected,code) in [(DeviceIdentityError.keychain(-34018),true,"HW02"),
            (.keychain(-25308),false,"HW01"),(.keychain(-25308),true,"HW03"),
            (.identityMissing,true,"HW04"),(.invalidIdentity,true,"HW05")] {
            let text = StableDeviceHWID.failureMessage(error,protectedDataAvailable:protected)
            try expect(text.contains(code), "error presentation lost its cause")
            if protected { try expect(!text.contains("mở khóa"), "unlocked phone incorrectly told to unlock") }
        }
        try expect(StableDeviceHWID.isRetryable(DeviceIdentityError.identityMissing), "nil IDFV is not retried")
        try expect(StableDeviceHWID.isRetryable(DeviceIdentityError.keychain(-25308)), "temporary Keychain failure is not retried")
        try expect(!StableDeviceHWID.isRetryable(DeviceIdentityError.keychain(-34018)), "permanent signing error retried forever")
        try expect(!StableDeviceHWID.isRetryable(DeviceIdentityError.invalidIdentity), "corrupt identity retried forever")

        DeviceUtils.operation = { throw DeviceIdentityError.identityMissing }
        let login = HWIDLoginHarness()
        login.attemptLogin()
        try expect(login.networkRequests == 0 && login.hwid.isEmpty, "login sent an empty HWID to the server")
        DeviceUtils.operation = { original }
        try await Task.sleep(nanoseconds:400_000_000)
        try expect(login.hwid == original && login.authState == .idle, "bounded retry did not recover the login screen")
        login.attemptLogin()
        try expect(login.networkRequests == 1, "recovered HWID still blocked login")
        DeviceUtils.operation = { throw DeviceIdentityError.keychain(-34018) }
        let signing = HWIDLoginHarness(); signing.attemptLogin()
        try expect(signing.networkRequests == 0 && signing.hwidFailure?.contains("HW02") == true, "signing error collapsed into empty/unlock message")
        DeviceUtils.operation = { changed }
        signing.foregroundOrUnlock()
        try expect(signing.hwid == changed && signing.authState == .idle, "foreground/unlock did not re-read HWID")
        DeviceUtils.operation = { throw DeviceIdentityError.keychain(-34018) }
        let replaced = HWIDLoginHarness(); replaced.attemptLogin()
        replaced.authState = .error("key_invalid")
        DeviceUtils.operation = { changed }
        replaced.foregroundOrUnlock()
        try expect(replaced.authState == .error("key_invalid"), "HWID recovery cleared an error which replaced the original HWID error")
        let unrelated = HWIDLoginHarness(); unrelated.authState = .error("key_invalid")
        unrelated.foregroundOrUnlock()
        try expect(unrelated.authState == .error("key_invalid"), "identity refresh cleared unrelated authentication errors")
        print("[PASS] \(checks) actual Swift HWID persistence/recovery, race, corruption, diagnostics and login retry checks")
    }
}
