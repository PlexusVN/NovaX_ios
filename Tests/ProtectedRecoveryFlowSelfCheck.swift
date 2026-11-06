// Tests the extracted ACTUAL recoverInstallation body with real identity storage.
// Transport fixtures represent signature-verified server payloads, never real APIs.
import Foundation
import CryptoKit

private enum FlowCheckError: Error { case failed(String) }
private final class RecoveryMemoryStore {
    var values: [String: Data] = [:]
    var storage: DeviceIdentityStorage {
        DeviceIdentityStorage(read: { [self] in values[$0] },
            write: { [self] tag, value in values[tag]=value },
            remove: { [self] in values.removeValue(forKey:$0) })
    }
}
@MainActor private final class RecoveryTransport {
    let binding: String
    var authorized = true
    var changedBinding: String?
    var changedKeyID: Int?
    var failFirstEnrollment = false
    var wrongRecipient = false
    var onEnroll: (() -> Void)?
    var enrollments: [[String: Any]] = []
    let deviceID=UUID().uuidString.lowercased()
    init(binding: String) { self.binding=binding }
    func send(_ route:String,_ body:[String:Any]) async throws -> [String:Any] {
        if route=="/api/v2/device/challenge" {
            guard body["recover_installation"] as? Bool == true,
                  body["key"] as? String == "RECOVERY-FIXTURE",
                  body["hwid"] as? String == "hardware-A",
                  UUID(uuidString:body["install_id"] as? String ?? "") != nil else {
                throw FlowCheckError.failed("challenge request lost its immutable scope")
            }
            return ["success":true,"challenge_id":UUID().uuidString.lowercased(),
                "challenge":Data(repeating:4,count:32).base64EncodedString(),
                "license_binding":changedBinding ?? binding,"key_id":changedKeyID ?? 7,
                "recovery_authorized":authorized]
        }
        guard route=="/api/v2/device/enroll" else { throw FlowCheckError.failed("unexpected route") }
        enrollments.append(body)
        onEnroll?()
        if failFirstEnrollment && enrollments.count==1 { throw URLError(.networkConnectionLost) }
        let recipient=Data(base64Encoded:body["agreement_public_key_x963"] as? String ?? "")!
        let fingerprint=SHA256.hash(data:recipient).map { String(format:"%02x",$0) }.joined()
        return ["success":true,"device_key_id":deviceID,"enrollment_revision":2,
            "agreement_public_key_fingerprint":wrongRecipient ? String(repeating:"0",count:64) : fingerprint]
    }
}

@main struct ProtectedRecoveryFlowSelfCheck {
    static var checks=0
    static func require(_ condition:@autoclosure () throws -> Bool,_ name:String) throws {
        guard try condition() else { throw FlowCheckError.failed(name) };checks += 1
    }
    @MainActor private static func fixture() throws -> (RecoveryMemoryStore,DeviceIdentityService,AuthManager,RecoveryTransport,ProtectedRecoveryFlowHarness) {
        let memory=RecoveryMemoryStore(),auth=AuthManager(licenseKey:"RECOVERY-FIXTURE",hwid:"hardware-A")
        let binding=DeviceIdentityService.binding(forLicense:auth.licenseKey)
        let old=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
        _=try old.installationID();_=try old.getOrCreateKey();_=try old.getOrCreateAgreementKey()
        try old.persistServerKeyID(7);try old.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
        let transport=RecoveryTransport(binding:binding)
        let flow=ProtectedRecoveryFlowHarness(auth:auth,identity:old,transport:transport.send)
        return(memory,old,auth,transport,flow)
    }
    @MainActor static func main() async throws {
        do {
            let(memory,old,_,transport,flow)=try fixture();let before=memory.values
            transport.authorized=false
            do { try await flow.recover();throw FlowCheckError.failed("false ticket accepted") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(memory.values==before,"false ticket does not create or replace keys")
            try require(transport.enrollments.isEmpty,"false ticket sends no enrollment")
            try require(flow.currentIdentity === old,"false ticket preserves old identity")
        }
        for wrongBinding in [true,false] {
            let(memory,old,_,transport,flow)=try fixture();let before=memory.values
            if wrongBinding { transport.changedBinding=String(repeating:"b",count:64) }
            else { transport.changedKeyID=8 }
            do { try await flow.recover();throw FlowCheckError.failed("wrong recovery scope accepted") }
            catch ProtectedDownloadError.invalidResponse {}
            try require(memory.values==before,"mismatched binding/keyID causes no key changes")
            try require(flow.currentIdentity === old,"mismatched scope preserves active identity")
        }
        do {
            let(memory,old,auth,transport,flow)=try fixture()
            let oldSigning=try old.getOrCreateKey().publicKeyX963Base64
            let oldRecipient=try old.getOrCreateAgreementKey().publicKeyX963Base64
            let oldInstall=try old.installationID(),oldEnrollment=try old.persistedEnrollmentID()
            let oldValues=memory.values;transport.failFirstEnrollment=true
            do { try await flow.recover();throw FlowCheckError.failed("simulated lost response was ignored") }
            catch let error as URLError { try require(error.code == .networkConnectionLost,"lost response propagates") }
            try require(flow.currentIdentity === old,"lost response leaves active pointer unchanged")
            try require(try old.persistedEnrollmentID()==oldEnrollment,"lost response preserves old enrollment")
            for(tag,value)in oldValues { try require(memory.values[tag]==value,"old key material preserved") }
            let first=transport.enrollments[0]
            try require(first["install_id"] as? String != oldInstall,"recovery uses fresh installation")
            try require(first["public_key_x963"] as? String != oldSigning,"recovery uses fresh signing key")
            try require(first["agreement_public_key_x963"] as? String != oldRecipient,"recovery uses fresh recipient")
            transport.authorized=false
            try await flow.recover()
            let second=transport.enrollments[1]
            for field in ["install_id","public_key_x963","agreement_public_key_x963"] {
                try require(first[field] as? String == second[field] as? String,"retry reuses exact "+field)
            }
            try require(flow.currentIdentity !== old,"only accepted enrollment promotes replacement")
            try require(try flow.currentIdentity.persistedEnrollmentID()==transport.deviceID,"promoted enrollment matches signed response")
            let reloaded=try DeviceIdentityService.scoped(to:DeviceIdentityService.binding(forLicense:auth.licenseKey),storage:memory.storage,useSecureEnclave:false)
            try require(try reloaded.persistedEnrollmentID()==transport.deviceID,"promotion survives reconstruction")
            try require(flow.clearedSessionCount==1,"old transient session discarded only after promotion")
        }
        do {
            let(_,old,_,transport,flow)=try fixture()
            transport.onEnroll={flow.invalidate()}
            do { try await flow.recover();throw FlowCheckError.failed("stale context promoted") }
            catch is CancellationError {}
            try require(flow.currentIdentity === old,"context invalidation prevents promotion")
            try require(flow.clearedSessionCount==0,"stale reply cannot clear a newer session")
        }
        do {
            let(_,old,_,transport,flow)=try fixture();transport.wrongRecipient=true
            do { try await flow.recover();throw FlowCheckError.failed("wrong recipient promoted") }
            catch ProtectedDownloadError.invalidResponse {}
            try require(flow.currentIdentity === old,"wrong signed recipient fingerprint prevents promotion")
        }
        print("Protected recovery flow self-check: \(checks) checks passed")
    }
}
