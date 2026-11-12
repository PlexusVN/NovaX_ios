import Foundation
import CryptoKit

private enum ResumeCheckError: Error { case failed(String), writeFailure }
private final class ResumeMemory {
    var values: [String: Data] = [:]
    var failTag: String?
    lazy var storage = DeviceIdentityStorage(read: { [self] in values[$0] },
        write: { [self] tag, value in
            if tag == failTag { throw ResumeCheckError.writeFailure }; values[tag] = value
        }, remove: { [self] in values.removeValue(forKey: $0) })
}
@MainActor private final class ResumeTransport {
    let binding: String
    let deviceID = UUID().uuidString.lowercased()
    let installID = UUID().uuidString.lowercased()
    var corrupt: String?
    var challengeFailure: ProtectedDownloadError?
    var openFailures: [ProtectedDownloadError] = [], syncFailures: [ProtectedDownloadError] = []
    var onEnrollment: (() -> Void)?
    var rejectTLS = false
    var calls: [String] = []
    var statusOverride: Int?
    var corruptRSAEnvelope = false
    init(binding: String) { self.binding = binding }
    func send(_ request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        if rejectTLS { throw FixtureNetworkError.untrustedTLS }
        let route = request.url!.path
        calls.append(route)
        guard request.value(forHTTPHeaderField:"X-Astra-Response-Mode") == "tls-pinned-v1" else {
            throw ResumeCheckError.failed("client still requires RSA response mode")
        }
        let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        let payload: [String:Any]
        var status = 200
        do {
            if route == "/api/v2/device/challenge" {
                if let challengeFailure { throw challengeFailure }
                guard body["key"] as? String == "RESUME-FIXTURE", body["hwid"] as? String == "hardware-A",
                      body["recover_installation"] == nil else { throw ResumeCheckError.failed("replacement recovery requested") }
                payload = ["success":true,"challenge_id":UUID().uuidString.lowercased(),
                    "challenge":Data(repeating:6,count:32).base64EncodedString(),"key_id":7,
                    "license_binding":binding,"recovery_authorized":false]
            } else if route == "/api/v2/device/enroll" {
                guard body["canonical_enrollment"] as? Bool == true else { throw ResumeCheckError.failed("normal enrollment not canonical") }
                let fields = ["ASTRA-ENROLL-V2-RECIPIENT", body["challenge_id"] as! String,
                    body["challenge"] as! String, "RESUME-FIXTURE", "hardware-A", body["install_id"] as! String,
                    body["public_key_x963"] as! String, body["assurance_level"] as! String,
                    body["agreement_public_key_x963"] as! String]
                let publicKey = try P256.Signing.PublicKey(x963Representation:Data(base64Encoded:fields[6])!)
                let signature = try P256.Signing.ECDSASignature(rawRepresentation:Data(base64Encoded:body["signature"] as! String)!)
                guard publicKey.isValidSignature(signature,for:Data(fields.joined(separator:"\n").utf8)) else {
                    throw ResumeCheckError.failed("enrollment did not prove existing private key")
                }
                func fp(_ text:String) -> String { SHA256.hash(data:Data(base64Encoded:text)!).map{String(format:"%02x",$0)}.joined() }
                var response: [String:Any] = ["success":true,"license_binding":binding,"key_id":7,
                    "device_key_id":deviceID,"install_id":installID,"enrollment_revision":2,
                    "public_key_fingerprint":fp(fields[6]),"agreement_public_key_fingerprint":fp(fields[8])]
                if let corrupt {
                    if corrupt == "key_id" || corrupt == "enrollment_revision" { response[corrupt] = 99 }
                    else { response[corrupt] = String(repeating:"a",count:64) }
                }
                onEnrollment?()
                payload = response
            } else if route == "/api/v2/novax/session/open" {
                if !openFailures.isEmpty { throw openFailures.removeFirst() }
                guard request.value(forHTTPHeaderField:"X-Astra-Device-Key") == deviceID else {
                    throw ResumeCheckError.failed("session used stale device reference")
                }
                payload = ["success":true,"license_binding":binding,"key_id":7,"app_session_id":UUID().uuidString.lowercased(),
                    "app_session_token":"fixture-token","session_expires_at":ISO8601DateFormatter().string(from:Date().addingTimeInterval(3600))]
            } else if route == "/api/v2/artifacts/sync" {
                if !syncFailures.isEmpty { throw syncFailures.removeFirst() }
                guard request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token" else { throw ResumeCheckError.failed("catalog was anonymous") }
                payload = ["success":true,"categories":[],"patches":[]]
            } else { throw ResumeCheckError.failed("unexpected endpoint: " + route) }
        } catch ProtectedDownloadError.rejected(let code) {
            status = code == "key_banned" ? 403 : 401
            return (try JSONSerialization.data(withJSONObject:["success":false,"code":code]),
                    HTTPURLResponse(url:request.url!,statusCode:statusOverride ?? status,httpVersion:nil,headerFields:nil)!)
        }
        var result = payload
        if corruptRSAEnvelope { result["astra_v2"] = ["signature":"not-an-rsa-signature"] }
        return (try JSONSerialization.data(withJSONObject:result),
                HTTPURLResponse(url:request.url!,statusCode:statusOverride ?? status,httpVersion:nil,headerFields:nil)!)
    }
    var openCount: Int { calls.filter{$0 == "/api/v2/novax/session/open"}.count }
}
@main struct ProtectedIdentityResumeSelfCheck {
    static var checks = 0
    static func require(_ condition: @autoclosure () throws -> Bool,_ name: String) throws {
        guard try condition() else { throw ResumeCheckError.failed(name) }; checks += 1
    }
    @MainActor private static func fixture(enrolled: Bool = true) throws -> (ResumeMemory,DeviceIdentityService,AuthManager,ResumeTransport,IdentityResumeHarness) {
        let memory = ResumeMemory(), auth = AuthManager(), binding = DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
        let identity = try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
        if enrolled {
            _ = try identity.installationID(); _ = try identity.getOrCreateKey(); _ = try identity.getOrCreateAgreementKey()
            try identity.persistServerKeyID(7); try identity.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
        }
        let transport = ResumeTransport(binding:binding)
        SecureAPIClient.handler = transport.send
        let flow = IdentityResumeHarness(auth:auth,identity:identity)
        return (memory,identity,auth,transport,flow)
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
        for enrolled in [false,true] {
            let (memory,identity,_,transport,flow) = try fixture(enrolled:enrolled)
            let keys = memory.values.filter{$0.key.contains("p256_key")}
            try await flow.session()
            try require(try identity.persistedEnrollmentID() == transport.deviceID,"canonical device reference stored")
            try require(try identity.existingInstallationID() == transport.installID,"canonical installation reference stored")
            try require(transport.calls == ["/api/v2/device/challenge","/api/v2/device/enroll","/api/v2/novax/session/open"],"only normal bootstrap endpoints used")
            for (tag,data) in keys { try require(memory.values[tag] == data,"existing private keys remain intact") }
            try await flow.session()
            try require(transport.calls.count == 3,"valid in-memory session does not reenroll")
        }
        for code in ["device_key_invalid","device_signature_invalid","session_expired"] {
            let (_,_,_,transport,flow) = try fixture(); transport.openFailures = [.rejected(code)]
            try await flow.session()
            try require(transport.openCount == 2,"one fresh bootstrap retry")
            try require(!transport.calls.contains("/api/v2/device/resume"),"removed route never called")
        }
        do {
            let (_,_,_,transport,flow) = try fixture(); transport.openFailures = [.rejected("device_key_invalid"),.rejected("device_key_invalid")]
            do { try await flow.session(); throw ResumeCheckError.failed("unbounded bootstrap") } catch is ProtectedDownloadError {}
            try require(transport.openCount == 2,"bootstrap retry bounded")
        }
        for code in ["device_key_revoked","key_banned","hwid_mismatch","replay_detected"] {
            let (_,_,_,transport,flow) = try fixture(); transport.openFailures = [.rejected(code)]
            do { try await flow.session(); throw ResumeCheckError.failed("server denial ignored") } catch is ProtectedDownloadError {}
            try require(transport.openCount == 1,"policy not bypassed: " + code)
        }
        for corrupt in ["license_binding","key_id","enrollment_revision","public_key_fingerprint","agreement_public_key_fingerprint","device_key_id","install_id"] {
            let (memory,_,_,transport,flow) = try fixture(); let before = memory.values; transport.corrupt = corrupt
            do { try await flow.session(); throw ResumeCheckError.failed("corrupt enrollment accepted") }
            catch is ProtectedDownloadError {} catch is DeviceIdentityError {}
            try require(memory.values == before,"mismatched scope cannot rewrite metadata: " + corrupt)
        }
        do {
            let (memory,_,_,transport,flow) = try fixture(); let before = memory.values
            transport.onEnrollment = { flow.invalidate() }
            do { try await flow.session(); throw ResumeCheckError.failed("late enrollment accepted") } catch is CancellationError {}
            try require(memory.values == before,"cancelled context preserves metadata")
        }
        do {
            let (memory,identity,_,_,flow) = try fixture()
            let tag = memory.values.keys.first{$0.hasSuffix("novax_device_install_id")}!
            memory.values.removeValue(forKey:tag)
            try await flow.session()
            try require(try identity.existingInstallationID() != nil,"lost metadata accepted with same proven keys")
        }
        for suffix in ["novax_device_install_id","novax_device_key_id"] {
            let (memory,_,_,transport,flow) = try fixture(); let keys = memory.values.filter{$0.key.contains("p256_key")}
            memory.failTag = memory.values.keys.first{$0.hasSuffix(suffix)}!
            do { try await flow.session(); throw ResumeCheckError.failed("write interruption ignored") } catch ResumeCheckError.writeFailure {}
            memory.failTag = nil
            try await flow.session()
            try require(transport.openCount == 1,"interrupted enrollment can bootstrap again")
            for (tag,data) in keys { try require(memory.values[tag] == data,"interruption keeps private keys") }
        }
        do {
            let (memory,_,_,transport,flow) = try fixture()
            let tag = memory.values.keys.first{$0.hasSuffix("novax_software_p256_key")}!
            memory.values.removeValue(forKey:tag); let before = memory.values
            do { try await flow.session(); throw ResumeCheckError.failed("lost private key regenerated") } catch DeviceIdentityError.identityMissing {}
            try require(memory.values == before && !transport.calls.contains("/api/v2/device/enroll"),"lost private keys need explicit authorization")
        }
        do {
            let (memory,_,_,transport,flow) = try fixture(enrolled:false); transport.challengeFailure = .rejected("key_expired")
            do { try await flow.session(); throw ResumeCheckError.failed("expired license created keys") } catch is ProtectedDownloadError {}
            try require(memory.values.isEmpty,"invalid license cannot allocate a recipient")
        }
        do {
            let (_,_,auth,transport,flow) = try fixture(); transport.syncFailures = [.rejected("session_expired")]
            _ = try await flow.sync(auth:auth)
            try require(transport.calls.filter{$0 == "/api/v2/artifacts/sync"}.count == 2 && transport.openCount == 2,"only catalog gets one session retry")
        }
        do {
            let (_,_,auth,transport,flow) = try fixture(); transport.syncFailures = [.rejected("session_expired"),.rejected("session_expired")]
            do { _ = try await flow.sync(auth:auth); throw ResumeCheckError.failed("unbounded catalog retry") } catch is ProtectedDownloadError {}
            try require(transport.calls.filter{$0 == "/api/v2/artifacts/sync"}.count == 2,"catalog retry bounded")
        }
        do {
            let (_,_,auth,transport,flow) = try fixture(); transport.openFailures = [.rejected("key_banned")]
            do { _ = try await flow.sync(auth:auth); throw ResumeCheckError.failed("denied catalog accepted") }
            catch { try require(flow.accessNotice == error.localizedDescription,"UI shows final authoritative error") }
        }
        do {
            let (_,_,_,transport,flow) = try fixture(); transport.corruptRSAEnvelope = true
            try await flow.session()
            try require(transport.openCount == 1,"invalid legacy RSA API envelope cannot block pinned TLS metadata")
        }
        do {
            let (memory,_,_,transport,flow) = try fixture(); let before = memory.values; transport.rejectTLS = true
            do { try await flow.session(); throw ResumeCheckError.failed("untrusted transport accepted") } catch FixtureNetworkError.untrustedTLS {}
            try require(memory.values == before && transport.calls.isEmpty,"TLS failure never yields an API payload")
        }
        print("Pinned-TLS enrollment/session regression: \(checks) checks passed")
    }
}
