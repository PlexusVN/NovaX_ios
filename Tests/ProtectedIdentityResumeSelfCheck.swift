import Foundation
import CryptoKit

private enum ResumeCheckError: Error { case failed(String), writeFailure }
private final class ResumeMemory {
    var values: [String: Data] = [:]
    var failTag: String?
    var readFailureTag: String?
    var readFailure: Error?
    lazy var storage = DeviceIdentityStorage(read: { [self] tag in
            if tag == readFailureTag, let readFailure { throw readFailure }; return values[tag]
        },
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
    var onLegacyContext: (() -> Void)?
    var legacyContextBinding: String?
    var rejectTLS = false
    var calls: [String] = []
    var statusOverride: Int?
    var corruptRSAEnvelope = false
    var fractionalExpiry = false
    var recoveryAuthorized = false
    var normalEnrollmentFailures: [ProtectedDownloadError] = []
    var recoveryInstallations = Set<String>()
    var enrollments: [[String:Any]] = []
    var dropRecoveryResponse = false
    private var acceptedDeviceID: String?
    private var acceptedInstallID: String?
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
            if route == "/api/v2/device/context" {
                onLegacyContext?()
                payload = ["success":true,"license_binding":legacyContextBinding ?? binding,
                    "key_id":7,"device_key_id":request.value(forHTTPHeaderField:"X-Astra-Device-Key")!]
            } else if route == "/api/v2/device/challenge" {
                if let challengeFailure { throw challengeFailure }
                guard body["key"] as? String == "RESUME-FIXTURE", body["hwid"] as? String == "hardware-A" else {
                    throw ResumeCheckError.failed("challenge lost scope")
                }
                if body["recover_installation"] as? Bool == true {
                    recoveryInstallations.insert(body["install_id"] as! String)
                }
                payload = ["success":true,"challenge_id":UUID().uuidString.lowercased(),
                    "challenge":Data(repeating:6,count:32).base64EncodedString(),"key_id":7,
                    "license_binding":binding,"recovery_authorized":recoveryAuthorized]
            } else if route == "/api/v2/device/enroll" {
                enrollments.append(body)
                let recovering=recoveryInstallations.contains(body["install_id"] as! String)
                if !recovering && !normalEnrollmentFailures.isEmpty { throw normalEnrollmentFailures.removeFirst() }
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
                if recovering {
                    if acceptedInstallID == nil {
                        acceptedInstallID=body["install_id"] as? String
                        acceptedDeviceID=UUID().uuidString.lowercased()
                    }
                    guard acceptedInstallID == body["install_id"] as? String else { throw ResumeCheckError.failed("pending candidate was replaced") }
                }
                var response: [String:Any] = ["success":true,"license_binding":binding,"key_id":7,
                    "device_key_id":acceptedDeviceID ?? deviceID,"install_id":acceptedInstallID ?? installID,"enrollment_revision":2,
                    "public_key_fingerprint":fp(fields[6]),"agreement_public_key_fingerprint":fp(fields[8])]
                if let corrupt {
                    if corrupt == "key_id" || corrupt == "enrollment_revision" { response[corrupt] = 99 }
                    else { response[corrupt] = String(repeating:"a",count:64) }
                }
                if recovering && dropRecoveryResponse {
                    dropRecoveryResponse=false
                    throw URLError(.networkConnectionLost)
                }
                onEnrollment?()
                payload = response
            } else if route == "/api/v2/novax/session/open" {
                if !openFailures.isEmpty { throw openFailures.removeFirst() }
                guard request.value(forHTTPHeaderField:"X-Astra-Device-Key") == acceptedDeviceID ?? deviceID else {
                    throw ResumeCheckError.failed("session used stale device reference")
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = fractionalExpiry ? [.withInternetDateTime,.withFractionalSeconds] : [.withInternetDateTime]
                payload = ["success":true,"license_binding":binding,"key_id":7,"app_session_id":UUID().uuidString.lowercased(),
                    "app_session_token":"fixture-token","session_expires_at":formatter.string(from:Date().addingTimeInterval(3600))]
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
            let (memory,identity,auth,transport,flow)=try fixture()
            _ = try await flow.sync(auth:auth)
            let before=memory.values
            flow.artifactOperation={
                let _: Void = try identity.withStoredSecureEnclaveKey {
                    throw NSError(domain:"CryptoTokenKit",code:-3)
                }
            }
            do { _ = try await flow.download(PatchItem(),auth:auth);throw ResumeCheckError.failed("corrupted decrypt key accepted") }
            catch DeviceIdentityError.invalidIdentity {}
            try require(flow.consumedFixtureGrants.count==1,"failed local decrypt never replays one-use content automatically")
            try require(memory.values==before,"failed key use preserves the complete enrolled archive")
            try require(flow.accessNotice != nil,"local key failure records a recovery notice")
            flow.artifactOperation=nil
            do { _ = try await flow.download(PatchItem(),auth:auth);throw ResumeCheckError.failed("bad cached private key bypassed recovery") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(flow.consumedFixtureGrants.count==1 && memory.values==before,
                        "next explicit download requires recovery permission before a new grant or archive write")
            transport.recoveryAuthorized=true
            _ = try await flow.download(PatchItem(),auth:auth)
            try require(flow.consumedFixtureGrants.count==2 && flow.consumedFixtureGrants[0] != flow.consumedFixtureGrants[1],
                        "authorized explicit retry obtains a fresh grant after replacement")
            try require(before.allSatisfy{memory.values[$0.key]==$0.value},"authorized recovery retains original key bytes")
        }
        // Cold-start preparation uses actual production migration/session bodies
        // with only the Keychain factories and HTTP transport isolated.
        for scopedEnrolled in [false,true] {
            let memory=ResumeMemory(),auth=AuthManager()
            let binding=DeviceIdentityService.binding(forLicense:auth.licenseKey)
            let legacy=DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false)
            _ = try legacy.installationID(); _ = try legacy.getOrCreateKey(); _ = try legacy.getOrCreateAgreementKey()
            try legacy.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
            memory.values["novax_software_p256_key"]=Data([0])
            let archived=memory.values
            var scopedKeys: (String,String)?
            if scopedEnrolled {
                let selected=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
                _ = try selected.installationID()
                scopedKeys=(try selected.getOrCreateKey().publicKeyX963Base64,try selected.getOrCreateAgreementKey().publicKeyX963Base64)
                try selected.persistServerKeyID(7)
                try selected.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
            }
            let transport=ResumeTransport(binding:binding);SecureAPIClient.handler=transport.send
            let coldLegacy=DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false)
            let flow=IdentityResumeHarness(auth:auth,identity:nil,coldStorage:memory.storage,legacyIdentity:coldLegacy)
            _ = try await flow.sync(auth:auth)
            try require(transport.openCount==1,"cold scoped namespace opens despite damaged global archive")
            try require(!transport.calls.contains("/api/v2/device/context"),"damaged global signer cannot send a migration proof")
            try require(archived.allSatisfy{memory.values[$0.key]==$0.value},"cold-start keeps the global archive byte for byte")
            if let scopedKeys {
                let selected=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
                try require(try selected.getOrCreateKey().publicKeyX963Base64==scopedKeys.0 &&
                    selected.getOrCreateAgreementKey().publicKeyX963Base64==scopedKeys.1,"enrolled scoped identity is never replaced by legacy handling")
            }
        }
        do {
            let memory=ResumeMemory(),auth=AuthManager(),binding=DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
            memory.values["novax_device_key_id"]=Data("damaged-legacy-reference".utf8)
            let selected=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
            _ = try selected.installationID()
            let signer=try selected.getOrCreateKey().publicKeyX963Base64
            let recipient=try selected.getOrCreateAgreementKey().publicKeyX963Base64
            let before=memory.values,transport=ResumeTransport(binding:binding);SecureAPIClient.handler=transport.send
            let flow=IdentityResumeHarness(auth:auth,identity:nil,coldStorage:memory.storage,
                legacyIdentity:DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false))
            _ = try await flow.sync(auth:auth)
            let resumed=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
            try require(try resumed.getOrCreateKey().publicKeyX963Base64==signer &&
                resumed.getOrCreateAgreementKey().publicKeyX963Base64==recipient,
                "damaged legacy reference cannot replace scoped keys waiting for canonical resume")
            let savedKeys=before.filter { $0.key == "novax_device_key_id" ||
                $0.key.hasSuffix("novax_software_p256_key") || $0.key.hasSuffix("novax_agreement_software_p256_v2") ||
                $0.key.hasSuffix("novax_signing_backend_v2") || $0.key.hasSuffix("novax_agreement_backend_v2") }
            try require(savedKeys.allSatisfy{memory.values[$0.key]==$0.value},"metadata-less scoped resume preserves key bytes and the broken legacy archive")
        }
        do {
            let memory=ResumeMemory(),auth=AuthManager(),binding=DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
            let legacy=DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false)
            _ = try legacy.installationID()
            let signer=try legacy.getOrCreateKey().publicKeyX963Base64
            _ = try legacy.getOrCreateAgreementKey()
            try legacy.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
            let before=memory.values,transport=ResumeTransport(binding:binding)
            let unrelated=String(repeating:"a",count:64);transport.legacyContextBinding=unrelated
            SecureAPIClient.handler=transport.send
            let flow=IdentityResumeHarness(auth:auth,identity:nil,coldStorage:memory.storage,legacyIdentity:legacy)
            _ = try await flow.sync(auth:auth)
            let migrated=try DeviceIdentityService.scoped(to:unrelated,storage:memory.storage,useSecureEnclave:false)
            let selected=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
            try require(try migrated.getOrCreateKey().publicKeyX963Base64==signer,
                        "healthy legacy migration still follows the verified original license binding")
            try require(try selected.getOrCreateKey().publicKeyX963Base64 != signer,
                        "new selected license never inherits an unrelated global signing key")
            try require(before.allSatisfy{memory.values[$0.key]==$0.value},"healthy migration retains legacy archive")
        }
        do {
            let memory=ResumeMemory(),auth=AuthManager(),binding=DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
            let legacy=DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false)
            _ = try legacy.installationID(); _ = try legacy.getOrCreateKey(); _ = try legacy.getOrCreateAgreementKey()
            try legacy.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
            memory.values["novax_software_p256_key"]=Data([0])
            let selected=try DeviceIdentityService.scoped(to:binding,storage:memory.storage,useSecureEnclave:false)
            _ = try selected.installationID(); _ = try selected.getOrCreateKey(); _ = try selected.getOrCreateAgreementKey()
            memory.values["astra.identity.v3.\(binding).novax_software_p256_key"]=Data([0])
            let before=memory.values,transport=ResumeTransport(binding:binding);SecureAPIClient.handler=transport.send
            let flow=IdentityResumeHarness(auth:auth,identity:nil,coldStorage:memory.storage,
                legacyIdentity:DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false))
            do { _ = try await flow.sync(auth:auth);throw ResumeCheckError.failed("cold damaged scope replaced without recovery ticket") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(memory.values==before,"damaged selected scope and legacy archive survive denied recovery")
            try require(transport.enrollments.isEmpty,"damaged selected scope cannot become a new enrollment")
        }
        for transient in [DeviceIdentityError.keychain(-25308),DeviceIdentityError.keychain(-34018)] {
            let memory=ResumeMemory(),auth=AuthManager(),binding=DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
            let legacy=DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false)
            _ = try legacy.installationID(); _ = try legacy.getOrCreateKey(); _ = try legacy.getOrCreateAgreementKey()
            try legacy.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
            memory.readFailureTag="novax_signing_backend_v2";memory.readFailure=transient
            let before=memory.values,transport=ResumeTransport(binding:binding);SecureAPIClient.handler=transport.send
            let flow=IdentityResumeHarness(auth:auth,identity:nil,coldStorage:memory.storage,
                legacyIdentity:DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false))
            do { _ = try await flow.sync(auth:auth);throw ResumeCheckError.failed("temporary legacy storage error ignored") }
            catch DeviceIdentityError.keychain {}
            try require(memory.values==before && transport.calls.isEmpty,"locked or missing-entitlement legacy storage cannot trigger enrollment")
        }
        do {
            let memory=ResumeMemory(),auth=AuthManager(),binding=DeviceIdentityService.binding(forLicense:"RESUME-FIXTURE")
            let legacy=DeviceIdentityService(namespace:nil,storage:memory.storage,useSecureEnclave:false)
            _ = try legacy.installationID(); _ = try legacy.getOrCreateKey(); _ = try legacy.getOrCreateAgreementKey()
            try legacy.persistEnrollment(deviceKeyId:UUID().uuidString.lowercased())
            let before=memory.values,transport=ResumeTransport(binding:binding);SecureAPIClient.handler=transport.send
            let flow=IdentityResumeHarness(auth:auth,identity:nil,coldStorage:memory.storage,legacyIdentity:legacy)
            transport.onLegacyContext={flow.invalidate()}
            do { _ = try await flow.sync(auth:auth);throw ResumeCheckError.failed("cancelled cold migration continued") }
            catch is CancellationError {}
            try require(memory.values==before && transport.calls==["/api/v2/device/context"],"cold migration cancellation prevents writes and scoped enrollment")
        }
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
            transport.fractionalExpiry = enrolled
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
            do { try await flow.session(); throw ResumeCheckError.failed("lost private key regenerated") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(memory.values == before && !transport.calls.contains("/api/v2/device/enroll"),"lost private keys need explicit authorization")
        }
        for suffix in ["novax_software_p256_key","novax_signing_backend_v2","novax_agreement_software_p256_v2","novax_agreement_backend_v2"] {
            let (memory,identity,_,transport,flow)=try fixture(enrolled:false)
            let prefix="astra.identity.v3.\(identity.licenseBinding!)."
            memory.failTag=prefix+suffix
            do { try await flow.session();throw ResumeCheckError.failed("interrupted first provisioning ignored") }
            catch ResumeCheckError.writeFailure {}
            try require(!transport.calls.contains("/api/v2/device/enroll"),"failed initial key persistence never sends enrollment")
            let initialID=try identity.initialEnrollmentInstallationID()
            try require(initialID != nil,"first provisioning persists its installation before keys")
            let savedKeys=memory.values.filter{$0.key.contains("p256_key") || $0.key.contains("p256_v2")}
            memory.failTag=nil
            try await flow.session()
            try require(transport.openCount==1,"interrupted pristine provisioning can finish without admin reset")
            for(tag,data)in savedKeys { try require(memory.values[tag]==data,"initial retry preserves every already-created key") }
        }
        do {
            let(memory,identity,_,transport,flow)=try fixture(enrolled:false)
            transport.onEnrollment={ memory.values.removeValue(forKey:"astra.identity.v3.\(identity.licenseBinding!).novax_agreement_software_p256_v2") }
            do { try await flow.session();throw ResumeCheckError.failed("key lost after submission ignored") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            transport.onEnrollment=nil
            let before=memory.values
            do { try await flow.session();throw ResumeCheckError.failed("submitted missing key recreated") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(memory.values==before,"submitted first enrollment cannot regenerate a missing key")
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
        for missingOldKey in [false,true] {
            let(memory,old,_,transport,flow)=try fixture()
            let oldSigning=try old.getOrCreateKey().publicKeyX963Base64
            if missingOldKey {
                memory.values.removeValue(forKey:"astra.identity.v3.\(old.licenseBinding!).novax_software_p256_key")
            } else { transport.normalEnrollmentFailures=[.rejected("device_already_enrolled")] }
            transport.recoveryAuthorized=true
            try await flow.session()
            let selected=try DeviceIdentityService.scoped(to:old.licenseBinding!,storage:memory.storage,useSecureEnclave:false)
            try require(try selected.getOrCreateKey().publicKeyX963Base64 != oldSigning,"actual ensureSession selects fresh authorized keys")
            try require(transport.openCount==1 && transport.recoveryInstallations.count==1,"actual missing/revoked identity reaches ticketed enrollment and session")
        }
        for suffix in ["novax_software_p256_key","novax_agreement_software_p256_v2"] {
            let(memory,old,auth,transport,_)=try fixture()
            memory.values["astra.identity.v3.\(old.licenseBinding!)."+suffix]=Data([1,2,3])
            let reloaded=try DeviceIdentityService.scoped(to:old.licenseBinding!,storage:memory.storage,useSecureEnclave:false)
            let flow=IdentityResumeHarness(auth:auth,identity:reloaded)
            let before=memory.values
            do { try await flow.session();throw ResumeCheckError.failed("corrupt software key replaced without ticket") }
            catch ProtectedDownloadError.rejected("device_recovery_required") {}
            try require(memory.values==before && transport.enrollments.isEmpty,"malformed stored software material requires administrator ticket")
            transport.recoveryAuthorized=true
            try await flow.session()
            try require(transport.openCount==1,"authorized recovery can replace malformed stored "+suffix)
            try require(before.allSatisfy{memory.values[$0.key]==$0.value},"malformed old material remains archived")
        }
        do {
            let(memory,old,auth,transport,flow)=try fixture()
            transport.normalEnrollmentFailures=[.rejected("device_already_enrolled")]
            transport.recoveryAuthorized=true;transport.dropRecoveryResponse=true
            do { try await flow.session();throw ResumeCheckError.failed("committed recovery lost response ignored") }
            catch let error as URLError { try require(error.code == .networkConnectionLost,"recovery interruption propagates") }
            let recovery=transport.enrollments.last!
            memory.values.removeValue(forKey:"astra.identity.v3.\(old.licenseBinding!).novax_software_p256_key")
            let restarted=IdentityResumeHarness(auth:auth,identity:old)
            transport.recoveryAuthorized=false
            try await restarted.session()
            let repeated=transport.enrollments[transport.enrollments.count-2]
            for field in ["install_id","public_key_x963","agreement_public_key_x963"] {
                try require(recovery[field] as? String == repeated[field] as? String,"restart repeats exact committed candidate "+field)
            }
            try require(transport.openCount==1,"pending restart works despite missing old signer and consumed ticket")
        }
        do {
            let(_,old,auth,transport,flow)=try fixture()
            try await flow.session()
            transport.syncFailures=[.rejected("device_key_revoked")]
            transport.normalEnrollmentFailures=[.rejected("device_already_enrolled")]
            transport.recoveryAuthorized=true
            _ = try await flow.sync(auth:auth)
            try require(transport.openCount==2 && transport.recoveryInstallations.count==1,"live catalog revocation recovers without another user retry")
            try require(transport.calls.filter{$0 == "/api/v2/artifacts/sync"}.count==2,"live reset retries only read-only catalog once")
            try require(try old.persistedEnrollmentID() != nil,"live recovery preserves old archived identity")
        }
        print("Pinned-TLS enrollment/session regression: \(checks) checks passed")
    }
}
