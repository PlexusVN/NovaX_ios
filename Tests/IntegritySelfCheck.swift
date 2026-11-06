import Foundation
import CryptoKit
import Dispatch
import MachO

final class DeviceIdentityService {
    static let shared=DeviceIdentityService()
    func persistedEnrollmentID() throws -> String? { nil }
    func getOrCreateAgreementKey() throws -> (publicKeyX963Base64:String,assurance:String) { throw IntegrityError.invalid }
    func agreementSharedSecret(peerPublicKeyX963:Data) throws -> SharedSecret { throw IntegrityError.invalid }
}
@main struct IntegritySelfCheck {
    static func check(_ condition:@autoclosure() throws -> Bool,_ name:String) throws {
        guard try condition() else { throw NSError(domain:name,code:1) }
        print("[PASS] \(name)")
    }
    @MainActor static func main() async throws {
        try DeviceEnvironmentSelfCheck.run(fixtureURL: URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("device_environment_v1.json"))
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let fixture=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let document=fixture["document"] as! [String:Any],sealData=try ProtectedArtifactDecoder.canonicalData(document)
        let executable=Data(base64Encoded:fixture["executableBase64"] as! String)!,key=Data(base64Encoded:fixture["publicKey"] as! String)!
        let verifier=ServerSignatureVerifier(trustedPublicKeys:["integrity-public-test-key":key])
        let image=try ReleaseImage.read(executable),hash=image.sections.first { $0.name == "__text" }!.sha256
        func inspect(seal:Data?=nil,binary:Data?=nil,bundle:String="com.apple.mobile.MobileHouseArrest",build:String="1306",regular:Bool=true,memory:String?=nil,images:[String]=["/App/AstraQA","/usr/lib/libSystem.B.dylib"],debugger:Bool=false)->SecurityCheckResult {
            AntiTamper.inspect(ReleaseInspection(data:seal ?? sealData,executable:binary ?? executable,bundleID:bundle,version:"1.2.7",build:build,
                executableName:"AstraQA",regularExecutable:regular,memoryTextHash:memory ?? hash,loadedImages:images,debugger:debugger),verifier:verifier)
        }
        func changed(_ mutate:(inout [String:Any])->Void)throws->Data { var doc=document;mutate(&doc);return try ProtectedArtifactDecoder.canonicalData(doc) }
        try check(inspect().mask==1023,"all ten release checks pass on the approved image")
        let protocolChange=try changed { $0["protocol"]="other" }
        try check(inspect(seal:protocolChange).mask & 1 == 0,"check 01 protocol/schema mismatch")
        let signatureChange=try changed { $0["signature"]=Data(repeating:0,count:256).base64EncodedString() }
        try check(inspect(seal:signatureChange).mask & 2 == 0,"check 02 signature mismatch")
        try check(inspect(bundle:"other.bundle").mask & 4 == 0,"check 03 bundle substitution")
        try check(inspect(build:"1305").mask & 8 == 0,"check 04 build substitution")
        try check(inspect(regular:false).mask & 16 == 0,"check 05 executable file identity")
        var patched=executable;patched[512] ^= 1
        try check(inspect(binary:patched).mask & 32 == 0,"check 06 modified instruction bytes")
        try check(inspect(memory:String(repeating:"0",count:64)).mask & 64 == 0,"check 07 runtime instruction mismatch")
        var injected=executable;injected[300] ^= 1
        try check(inspect(binary:injected).mask & 128 == 0,"check 08 linked library alteration")
        try check(inspect(images:["/private/tmp/unknown.dylib"]).mask & 256 == 0,"check 09 unexpected loaded image")
        let ownMain="/App/AstraQA.app/AstraQA"
        try check(inspect(images:[ownMain,"/App/AstraQA.app/Frameworks/libSystem.B.dylib"]).mask==1023,"own approved framework is allowed")
        try check(inspect(images:[ownMain,"/Other.app/Frameworks/libSystem.B.dylib"]).mask & 256 == 0,"foreign app framework with approved basename is denied")
        try check(inspect(images:[ownMain,"/App/AstraQA.app/Frameworks/../../Other.app/Frameworks/libSystem.B.dylib"]).mask & 256 == 0,"framework dot-segment escape is denied")
        try check(inspect(images:[ownMain,"/System/Library/../../tmp/libSystem.B.dylib"]).mask & 256 == 0,"system-prefix dot-segment escape is denied")
        try check(inspect(images:[ownMain,"/private/preboot/Cryptexes/OS/usr/lib/libSystem.B.dylib"]).mask==1023,"private preboot Cryptex system library remains allowed")
        try check(inspect(images:[ownMain,"/System/Volumes/Preboot/Cryptexes/OS/usr/lib/libSystem.B.dylib"]).mask==1023,"System Volumes Cryptex system library remains allowed")
        let frameworkFixture=FileManager.default.temporaryDirectory.appendingPathComponent("astra-framework-check-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:frameworkFixture,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:frameworkFixture) }
        let app=frameworkFixture.appendingPathComponent("AstraQA.app",isDirectory:true)
        let frameworks=app.appendingPathComponent("Frameworks",isDirectory:true)
        let foreign=frameworkFixture.appendingPathComponent("Other.app/Frameworks",isDirectory:true)
        try FileManager.default.createDirectory(at:frameworks,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:foreign,withIntermediateDirectories:true)
        let target=foreign.appendingPathComponent("libSystem.B.dylib")
        try Data().write(to:target)
        try FileManager.default.createSymbolicLink(at:frameworks.appendingPathComponent("libSystem.B.dylib"),withDestinationURL:target)
        try check(inspect(images:[app.appendingPathComponent("AstraQA").path,frameworks.appendingPathComponent("libSystem.B.dylib").path]).mask & 256 == 0,"framework symlink escape to another app is denied")
        let linkedApp=frameworkFixture.appendingPathComponent("Linked.app",isDirectory:true)
        try FileManager.default.createDirectory(at:linkedApp,withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:linkedApp.appendingPathComponent("Frameworks",isDirectory:true),withDestinationURL:foreign)
        try check(inspect(images:[linkedApp.appendingPathComponent("AstraQA").path,linkedApp.appendingPathComponent("Frameworks/libSystem.B.dylib").path]).mask & 256 == 0,"Frameworks directory symlink cannot move the allowed root outside the app")
        try check(inspect(debugger:true).mask & 512 == 0,"check 10 debugger attachment")
        var resigned=executable;resigned.append(Data(repeating:0xa5,count:64));resigned[332]=64
        try check(inspect(binary:resigned).mask==1023,"code signature replacement preserves approved code checks")
        var malformed=executable;malformed[36]=1
        try check(inspect(binary:malformed).isCompromised,"malformed load command fails closed")
        try check(inspect(seal:Data()).isCompromised,"missing seal fails closed")
        let actual=try ReleaseImage.read(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[0])))
        guard let header=_dyld_get_image_header(0) else { throw IntegrityError.invalid }
        let memory=Data(bytes:UnsafeRawPointer(header).advanced(by:actual.textOffset),count:actual.textSize)
        let measured=SHA256.hash(data:memory).map { String(format:"%02x",$0) }.joined()
        try check(measured==actual.sections.first(where: { $0.name=="__text" })?.sha256,"actual loaded Mach-O instructions match file bytes under ASLR")
        let began=DispatchSemaphore(value:0),finish=DispatchSemaphore(value:0),ended=DispatchSemaphore(value:0)
        DispatchQueue.global().async { try? IntegrityCommitBarrier.withCommit { began.signal();finish.wait() };ended.signal() }
        began.wait();IntegrityCommitBarrier.block()
        try check(IntegrityCommitBarrier.count==1,"active native commit remains tracked after block")
        var denied=false
        do { try IntegrityCommitBarrier.requireAllowed() } catch IntegrityError.invalid { denied=true }
        try check(denied,"new operations denied after integrity failure")
        finish.signal();ended.wait()
        try check(IntegrityCommitBarrier.count==0,"shutdown barrier drains only after real native work completes")
        let controlled=ControlledIntegrityInspection()
        let runtime=AppIntegrityRuntime(inspect:{ controlled.inspect() },terminate:{})
        let old=Task { await runtime.verifyNow(force:true) }
        let deadline=Date().addingTimeInterval(5)
        while controlled.calls==0, Date()<deadline { try await Task.sleep(nanoseconds:1_000_000) }
        try check(controlled.calls==1,"controlled foreground inspection started")
        runtime.setActive(false)
        let fresh=await runtime.verifyNow(force:true)
        try check(!fresh && runtime.blocked,"fresh runtime violation blocks access")
        controlled.finishFirst.signal()
        let stale=await old.value
        try check(!stale && !runtime.allowed && runtime.blocked,"stale successful inspection cannot unlock a newer foreground failure")
        try check(runtime.acceptedResult == nil,"blocked runtime never retains an accepted report")
        let approved=SecurityCheckResult(mask:1023,releaseID:"00000000-0000-4000-8000-000000000015",
            sealDigest:String(repeating:"a",count:64),environment:DeviceEnvironmentResult(checkedMask:16383,signalMask:0))
        let acceptedInspection=ControlledAcceptedInspection(fresh:approved)
        let acceptedRuntime=AppIntegrityRuntime(inspect:{ acceptedInspection.inspect() },terminate:{})
        let superseded=Task { await acceptedRuntime.verifyNow(force:true) }
        let acceptedDeadline=Date().addingTimeInterval(5)
        while acceptedInspection.calls==0, Date()<acceptedDeadline { try await Task.sleep(nanoseconds:1_000_000) }
        try check(acceptedInspection.calls==1,"superseded global inspection started")
        acceptedRuntime.setActive(false)
        let accepted=await acceptedRuntime.verifyNow(force:true)
        try check(accepted && acceptedRuntime.acceptedResult?.releaseID==approved.releaseID,"current epoch publishes its accepted report snapshot")
        acceptedInspection.finishFirst.signal()
        let supersededAllowed=await superseded.value
        try check(!supersededAllowed && AntiTamper.lastResult.isCompromised,"stale global completion is ignored by runtime authorization")
        try check(acceptedRuntime.allowed && acceptedRuntime.acceptedResult?.releaseID==approved.releaseID
            && acceptedRuntime.acceptedResult?.sealDigest==approved.sealDigest,"accepted report does not follow stale global lastResult")
        acceptedRuntime.setActive(false)
        try check(!acceptedRuntime.allowed && acceptedRuntime.acceptedResult == nil,"foreground invalidation clears the accepted report")
        let invalidatedInspection=ControlledIntegrityInspection()
        let invalidatedRuntime=AppIntegrityRuntime(inspect:{ invalidatedInspection.inspect() },terminate:{})
        let invalidatedPending=Task { await invalidatedRuntime.verifyNow(force:true) }
        let invalidatedDeadline=Date().addingTimeInterval(5)
        while invalidatedInspection.calls==0, Date()<invalidatedDeadline { try await Task.sleep(nanoseconds:1_000_000) }
        try check(invalidatedInspection.calls==1,"pending successful report is controlled before invalidation")
        invalidatedRuntime.setActive(false)
        invalidatedInspection.finishFirst.signal()
        let invalidatedAllowed=await invalidatedPending.value
        try check(!invalidatedAllowed && !invalidatedRuntime.allowed && invalidatedRuntime.acceptedResult == nil,"stale success cannot repopulate an invalidated accepted report")
        let unverifiedInspection=SequencedIntegrityInspection([approved,SecurityCheckResult(mask:1023)])
        let unverifiedRuntime=AppIntegrityRuntime(inspect:{ unverifiedInspection.inspect() },terminate:{})
        let beforeUnverified=await unverifiedRuntime.verifyNow(force:true)
        let afterUnverified=await unverifiedRuntime.verifyNow(force:true)
        try check(beforeUnverified && !afterUnverified && !unverifiedRuntime.allowed && !unverifiedRuntime.blocked
            && unverifiedRuntime.acceptedResult == nil,"unverified measurement clears the accepted report without marking a permanent violation")
        let rejectedInspection=SequencedIntegrityInspection([approved,SecurityCheckResult(mask:1022,environment:approved.environment)])
        let rejectedRuntime=AppIntegrityRuntime(inspect:{ rejectedInspection.inspect() },terminate:{})
        let beforeRejection=await rejectedRuntime.verifyNow(force:true)
        let afterRejection=await rejectedRuntime.verifyNow(force:true)
        try check(beforeRejection && !afterRejection && rejectedRuntime.blocked && rejectedRuntime.acceptedResult == nil,"integrity rejection clears a previously accepted report")
        let signal=DeviceEnvironmentResult(checkedMask:0x23e0,signalMask:64)
        AntiTamper.recordCommitFailure(signal)
        try check(AntiTamper.checkAtLaunch().environment.state == .blocked,"commit-time violation remains latched after the injected image disappears")
    }
}

private final class ControlledAcceptedInspection: @unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    private let fresh:SecurityCheckResult
    let finishFirst=DispatchSemaphore(value:0)
    init(fresh:SecurityCheckResult) { self.fresh=fresh }
    var calls:Int { lock.lock(); defer { lock.unlock() }; return count }
    func inspect() -> SecurityCheckResult {
        lock.lock();count+=1;let index=count;lock.unlock()
        if index==1 {
            _ = finishFirst.wait(timeout:.now()+10)
            // Exercise the real process-global publisher without exposing a
            // production setter just for tests. CLI has no approved app seal.
            return AntiTamper.checkAtLaunch()
        }
        return fresh
    }
}

private final class SequencedIntegrityInspection: @unchecked Sendable {
    private let lock=NSLock()
    private var values:[SecurityCheckResult]
    init(_ values:[SecurityCheckResult]) { self.values=values }
    func inspect() -> SecurityCheckResult {
        lock.lock(); defer { lock.unlock() }
        return values.isEmpty ? SecurityCheckResult(mask:0) : values.removeFirst()
    }
}

private final class ControlledIntegrityInspection: @unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    let finishFirst=DispatchSemaphore(value:0)
    var calls:Int { lock.lock(); defer { lock.unlock() }; return count }
    func inspect() -> SecurityCheckResult {
        lock.lock();count+=1;let index=count;lock.unlock()
        if index==1 { _ = finishFirst.wait(timeout:.now()+10) }
        return SecurityCheckResult(mask:1023,environment:DeviceEnvironmentResult(checkedMask:16383,signalMask:index==1 ? 0 : 64))
    }
}
