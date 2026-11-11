import Foundation
import CryptoKit

private enum ResumeCheckError: Error { case failed(String), writeFailure }
private final class ResumeMemory {
    var values: [String: Data] = [:]
    var failTag: String?
    lazy var storage = DeviceIdentityStorage(read: { [self] in values[$0] },
        write: { [self] tag, value in
            if tag == failTag { throw ResumeCheckError.writeFailure }
            values[tag] = value
        }, remove: { [self] in values.removeValue(forKey: $0) })
}
@MainActor private final class ResumeTransport {
    let binding: String
    let deviceID = UUID().uuidString.lowercased()
    let installID: String
    var corrupt: String?
    var resumeFailure: ProtectedDownloadError?
    var syncFailures: [ProtectedDownloadError] = []
    var onResume: (() -> Void)?
    var calls: [String] = []
    init(binding: String, installID: String) { self.binding=binding; self.installID=installID }
    func send(_ route: String, _ body: [String: Any]) async throws -> [String: Any] {
        calls.append(route)
        if route == "/api/v2/device/challenge" {
            guard body["key"] as? String == "RESUME-FIXTURE", body["hwid"] as? String == "hardware-A",
                  body["recover_installation"] == nil else { throw ResumeCheckError.failed("resume requested a replacement ticket") }
            return ["success":true,"challenge_id":UUID().uuidString.lowercased(),
                "challenge":Data(repeating:6,count:32).base64EncodedString(),"key_id":7,
                "license_binding":binding,"recovery_authorized":false]
        }
        if route == "/api/v2/artifacts/sync" {
            if !syncFailures.isEmpty { throw syncFailures.removeFirst() }
            return ["success":true,"categories":[],"patches":[]]
        }
        guard route == "/api/v2/device/resume" else { throw ResumeCheckError.failed("unexpected endpoint") }
        if let resumeFailure { throw resumeFailure }
        let fields = ["ASTRA-ENROLL-V2-RECIPIENT", body["challenge_id"] as! String,
            body["challenge"] as! String, "RESUME-FIXTURE", "hardware-A", body["install_id"] as! String,
            body["public_key_x963"] as! String, body["assurance_level"] as! String,
            body["agreement_public_key_x963"] as! String]
        let publicKey = try P256.Signing.PublicKey(x963Representation:Data(base64Encoded:fields[6])!)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation:Data(base64Encoded:body["signature"] as! String)!)
        guard publicKey.isValidSignature(signature,for:Data(fields.joined(separator:"\n").utf8)) else {
            throw ResumeCheckError.failed("resume did not prove the original signing key")
        }
        func fingerprint(_ value: String) -> String { SHA256.hash(data:Data(base64Encoded:value)!).map{String(format:"%02x",$0)}.joined() }
        var response: [String: Any] = ["success":true,"license_binding":binding,"key_id":7,
            "device_key_id":deviceID,"install_id":installID,"enrollment_revision":2,
            "public_key_fingerprint":fingerprint(fields[6]),"agreement_public_key_fingerprint":fingerprint(fields[8])]
        if let corrupt {
            if corrupt == "key_id" || corrupt == "enrollment_revision" { response[corrupt]=99 }
            else { response[corrupt] = String(repeating:"a",count:64) }
        }
        onResume?()
        return response
    }
}
@main struct ProtectedIdentityResumeSelfCheck {
    static var checks=0
    static func require(_ condition: @autoclosure () throws -> Bool,_ name: String) throws {
        guard try condition() else { throw ResumeCheckError.failed(name) }; checks += 1
    }
    @MainActor private static func fixture() throws -> (ResumeMemory,DeviceIdentityService,AuthManager,ResumeTransport,IdentityResumeHarness) {
        let memory=ResumeMemory(),auth=AuthManager(),binding=DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
        let identity=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
        let install=try identity.installationID()
        _=try identity.getOrCreateKey();_=try identity.getOrCreateAgreementKey()
        try identity.persistServerKeyID(7);try identity.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
        let transport=ResumeTransport(binding:binding,installID:install)
        let flow=IdentityResumeHarness(auth:auth,identity:identity,transport:transport.send)
        return(memory,identity,auth,transport,flow)
    }
    @MainActor static func main() async throws {
        do {
            let memory=ResumeMemory(), original=UUID().uuidString
            memory.values["deviceHwid"]=Data(original.utf8)
            let before=memory.values
            try require(try StableDeviceHWID.resolve(storage:memory.storage,vendorID:UUID().uuidString)==original,
                        "a changed vendor ID never overwrites the registered HWID")
            try require(try StableDeviceHWID.resolve(storage:memory.storage,vendorID:nil)==original,
                        "saved HWID remains available before IDFV is ready")
            try require(memory.values==before,"reading an established HWID never rewrites Keychain")
        }
        do {
            let memory=ResumeMemory()
            do { _=try StableDeviceHWID.resolve(storage:memory.storage,vendorID:nil);throw ResumeCheckError.failed("temporary nil IDFV created random HWID") }
            catch DeviceIdentityError.identityMissing {}
            try require(memory.values.isEmpty,"nil IDFV does not allocate a new license identity")
            let vendor=UUID().uuidString;memory.failTag="deviceHwid"
            do { _=try StableDeviceHWID.resolve(storage:memory.storage,vendorID:vendor);throw ResumeCheckError.failed("failed HWID persistence ignored") }
            catch ResumeCheckError.writeFailure {}
            memory.failTag=nil
            try require(try StableDeviceHWID.resolve(storage:memory.storage,vendorID:vendor)==vendor,
                        "first HWID is published only after storage succeeds")
        }
        do {
            let storage=DeviceIdentityStorage(read:{_ in throw DeviceIdentityError.keychain(-25308)},
                write:{_,_ in throw ResumeCheckError.failed("locked Keychain was overwritten")},remove:{_ in})
            do { _=try StableDeviceHWID.resolve(storage:storage,vendorID:UUID().uuidString);throw ResumeCheckError.failed("Keychain error treated as a new device") }
            catch DeviceIdentityError.keychain(-25308) {}
            try require(true,"temporary Keychain failure never rotates HWID")
        }
        for code in ["device_key_invalid","device_signature_invalid"] {
            let(memory,identity,_,transport,flow)=try fixture();let before=memory.values
            flow.openFailures=[ProtectedDownloadError.rejected(code)]
            try await flow.session()
            try require(try identity.persistedEnrollmentID()==transport.deviceID,"correct signed device reference restored")
            try require(flow.recoveryCount==0,"same keys never request a replacement")
            try require(flow.openCount==2,"session reopened once after same-key resume")
            for(tag,data)in before where !tag.hasSuffix("novax_device_key_id") {
                try require(memory.values[tag]==data,"existing keys and installation preserved")
            }
        }
        do {
            let(memory,identity,_,transport,flow)=try fixture()
            let tag=memory.values.keys.first{$0.hasSuffix("novax_device_install_id")}!
            memory.values.removeValue(forKey:tag)
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            try await flow.session()
            try require(try identity.existingInstallationID()==transport.installID,"lost installation metadata restored without rotating keys")
        }
        for suffix in ["novax_device_install_id", "novax_device_key_id"] {
            let(memory,identity,_,transport,flow)=try fixture()
            let originalKeys=memory.values.filter { $0.key.contains("p256_key") }
            memory.failTag=memory.values.keys.first{$0.hasSuffix(suffix)}!
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            do { try await flow.session();throw ResumeCheckError.failed("injected metadata write ignored") }
            catch ResumeCheckError.writeFailure {}
            memory.failTag=nil
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            try await flow.session()
            try require(try identity.persistedEnrollmentID()==transport.deviceID,"interrupted metadata write can resume again")
            for(tag,data)in originalKeys { try require(memory.values[tag]==data,"interrupted resume preserves private keys") }
        }
        for corrupt in ["license_binding","key_id","enrollment_revision","public_key_fingerprint","agreement_public_key_fingerprint","device_key_id","install_id"] {
            let(memory,_,_,transport,flow)=try fixture();let before=memory.values;transport.corrupt=corrupt
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            do { try await flow.session();throw ResumeCheckError.failed("corrupt scope accepted: "+corrupt) }
            catch is ProtectedDownloadError {} catch is DeviceIdentityError {}
            try require(memory.values==before,"mismatched signed scope leaves storage intact: "+corrupt)
        }
        do {
            let(memory,_,_,transport,flow)=try fixture();let before=memory.values
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            transport.onResume={flow.invalidate()}
            do { try await flow.session();throw ResumeCheckError.failed("stale resume accepted") } catch is CancellationError {}
            try require(memory.values==before,"late response cannot modify a newer context")
        }
        for code in ["device_key_revoked","key_banned","hwid_mismatch","replay_detected","HTTP_401"] {
            let(memory,_,_,transport,flow)=try fixture();let before=memory.values
            flow.openFailures=[ProtectedDownloadError.rejected(code)]
            do { try await flow.session();throw ResumeCheckError.failed("restriction retried") } catch is ProtectedDownloadError {}
            try require(transport.calls.isEmpty && memory.values==before,"no resume/rotation for "+code)
        }
        do {
            let(_,_,_,transport,flow)=try fixture();transport.resumeFailure = .rejected("HTTP_404")
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            do { try await flow.session();throw ResumeCheckError.failed("old server silently accepted") }
            catch ProtectedDownloadError.rejected("identity_resume_unavailable") {}
            try require(flow.recoveryCount==0,"missing server route does not rotate identity")
        }
        do {
            let(memory,_,auth,transport,flow)=try fixture();let before=memory.values
            transport.resumeFailure = .rejected("device_recovery_required")
            flow.openFailures=[ProtectedDownloadError.rejected("device_key_invalid")]
            do { _=try await flow.sync(auth:auth);throw ResumeCheckError.failed("unauthorized replacement accepted") }
            catch { try require(flow.accessNotice==error.localizedDescription,"category notice equals the final catalog error") }
            try require(flow.recoveryCount==1 && memory.values==before,"actual missing keys still require authorized recovery")
        }
        do {
            let(memory,_,_,transport,flow)=try fixture()
            let signingTag=memory.values.keys.first{$0.hasSuffix("novax_software_p256_key")}!
            memory.values.removeValue(forKey:signingTag);let before=memory.values
            flow.openFailures=[DeviceIdentityError.identityMissing]
            do { try await flow.session();throw ResumeCheckError.failed("missing private key recreated") } catch is ProtectedDownloadError {}
            try require(transport.calls.isEmpty && memory.values==before,"resume never recreates a missing private key")
        }
        do {
            let(_,_,auth,transport,flow)=try fixture();transport.syncFailures=[.rejected("session_expired")]
            _=try await flow.sync(auth:auth)
            try require(transport.calls==["/api/v2/artifacts/sync","/api/v2/artifacts/sync"],"only read-only catalog is retried")
            try require(flow.openCount==2 && flow.recoveryCount==0,"expired session reopens without identity recovery")
        }
        do {
            let(_,_,auth,transport,flow)=try fixture();transport.syncFailures=[.rejected("session_expired"),.rejected("session_expired")]
            do { _=try await flow.sync(auth:auth);throw ResumeCheckError.failed("unbounded session retry") } catch is ProtectedDownloadError {}
            try require(transport.calls.count==2,"catalog retries stop after one rejection")
        }
        print("Identity resume/session regression: \(checks) checks passed")
    }
}
