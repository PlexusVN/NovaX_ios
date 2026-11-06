import Foundation
import CryptoKit
import Darwin
import MachO
import Combine

struct ReleaseSection: Codable, Equatable { let name: String; let size: Int; let sha256: String }
struct ReleaseBody: Codable {
    let release_id: String; let bundle_id: String; let version: String; let build: String
    let executable: String; let sections: [ReleaseSection]; let dependencies: [String]
}
struct ReleaseSeal: Codable { let `protocol`: String; let keyId: String; let body: ReleaseBody; let signature: String }
struct ReleaseImage {
    let sections: [ReleaseSection]; let dependencies: [String]; let textOffset: Int; let textSize: Int
    static func read(_ data: Data) throws -> ReleaseImage {
        func word(_ at: Int) throws -> UInt32 {
            guard at >= 0, at <= data.count-4 else { throw IntegrityError.invalid }
            return data[at..<at+4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset*8) }
        }
        func wide(_ at: Int) throws -> UInt64 { UInt64(try word(at)) | (UInt64(try word(at+4)) << 32) }
        func name(_ at: Int, _ length: Int) throws -> String {
            guard at >= 0, length >= 0, at <= data.count-length,
                  let text=String(data:data[at..<at+length].prefix { $0 != 0 },encoding:.ascii) else { throw IntegrityError.invalid }
            return text
        }
        guard data.count >= 32, try word(0) == 0xfeedfacf else { throw IntegrityError.invalid }
        let count=Int(try word(16)), bytes=Int(try word(20))
        guard count <= 4096, bytes <= data.count-32 else { throw IntegrityError.invalid }
        var position=32, sections:[ReleaseSection]=[], dependencies:[String]=[], textOffset=0, textSize=0
        for _ in 0..<count {
            let command=try word(position), size=Int(try word(position+4))
            guard size >= 8, position <= 32+bytes-size else { throw IntegrityError.invalid }
            if command == 0x19 {
                guard size >= 72 else { throw IntegrityError.invalid }
                let segment=try name(position+8,16), n=Int(try word(position+64))
                guard n <= 256, 72+n*80 <= size else { throw IntegrityError.invalid }
                for i in 0..<n {
                    let at=position+72+i*80, sectionName=try name(at,16), length=try wide(at+40), offset=Int(try word(at+48))
                    if segment == "__TEXT", length > 0 {
                        let segmentVM=try wide(position+24), segmentFileOffset=try wide(position+40), segmentSize=try wide(position+48), address=try wide(at+32)
                        guard length <= 128*1024*1024, offset <= data.count-Int(length),segmentFileOffset==0,
                              address>=segmentVM,address-segmentVM==UInt64(offset),UInt64(offset)+length<=segmentSize else { throw IntegrityError.invalid }
                        sections.append(ReleaseSection(name:sectionName,size:Int(length),sha256:integrityDigest(data.subdata(in:offset..<offset+Int(length)))))
                        if sectionName == "__text" { textOffset=offset; textSize=Int(length) }
                    }
                }
            }
            if [UInt32(0xc),0x80000018,0x8000001f,0x80000023].contains(command) {
                guard size >= 24 else { throw IntegrityError.invalid }
                let offset=Int(try word(position+8)); guard offset >= 24, offset < size else { throw IntegrityError.invalid }
                dependencies.append(try name(position+offset,size-offset))
            }
            position += size
        }
        guard position == 32+bytes, textSize > 0, Set(sections.map(\.name)).count == sections.count else { throw IntegrityError.invalid }
        return ReleaseImage(sections:sections.sorted { $0.name < $1.name },dependencies:dependencies.sorted(),textOffset:textOffset,textSize:textSize)
    }
}
enum IntegrityError: LocalizedError {
    case invalid
    var errorDescription: String? { "Không thể xác minh phiên bản ứng dụng. Hãy cài lại bản được cung cấp." }
}
private func integrityDigest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }

public struct SecurityCheckResult: Sendable {
    public let isCompromised: Bool
    public let compromisedReasons: [String]
    let mask: Int; let releaseID: String; let sealDigest: String
    let environment: DeviceEnvironmentResult
    init(mask: Int, releaseID: String = "", sealDigest: String = "", environment: DeviceEnvironmentResult = .unverified) {
        self.mask=mask; self.releaseID=releaseID; self.sealDigest=sealDigest
        self.environment=environment
        isCompromised = mask != 1023 || environment.state == .blocked
        compromisedReasons = mask != 1023 ? ["integrity_unverified"] : environment.state == .blocked ? ["device_environment_rejected"] : []
    }
    var permitsProtectedOperation: Bool { !isCompromised && environment.state == .allowed }
    var reportV2: [String: Any] { ["release_id":releaseID,"seal_digest":sealDigest,"check_mask":mask,"environment":environment.report] }
}
struct ReleaseInspection {
    let data: Data; let executable: Data; let bundleID: String; let version: String; let build: String; let executableName: String
    let regularExecutable: Bool; let memoryTextHash: String?; let loadedImages: [String]; let debugger: Bool
}
public enum AntiTamper {
    private static let lock=NSLock()
    private static var latest=SecurityCheckResult(mask:0)
    private static var hasSignal=false
    private static var commitFailure:DeviceEnvironmentResult?
    public static var hasPendingSecuritySignal: Bool { lock.lock(); defer { lock.unlock() }; return hasSignal }
    public static var isPermanentlyLocked: Bool { false }
    static var lastResult: SecurityCheckResult { lock.lock(); defer { lock.unlock() }; return latest }
    @inline(__always) private static func c0(_ seal: ReleaseSeal) -> Bool {
        seal.protocol == "astra-release-v1" && UUID(uuidString:seal.body.release_id) != nil
            && (1...128).contains(seal.body.sections.count) && seal.body.dependencies.count <= 256
            && seal.body.sections.allSatisfy { $0.size > 0 && $0.size <= 128*1024*1024
                && $0.sha256.range(of:#"^[0-9a-f]{64}$"#,options:.regularExpression) != nil }
    }
    @inline(__always) private static func c1(_ seal: ReleaseSeal, verifier: ServerSignatureVerifier) -> Bool {
        guard let data=try? JSONEncoder().encode(seal.body), let object=try? JSONSerialization.jsonObject(with:data),
              let canonical=try? ProtectedArtifactDecoder.canonicalData(object) else { return false }
        return verifier.verifyRS256(keyID:seal.keyId,signedData:Data("ASTRA-RELEASE-V1\n".utf8)+canonical,signatureBase64:seal.signature)
    }
    @inline(__always) private static func c2(_ seal: ReleaseSeal, _ value: ReleaseInspection) -> Bool {
        value.bundleID == "com.apple.mobile.MobileHouseArrest" && value.bundleID == seal.body.bundle_id
    }
    @inline(__always) private static func c3(_ seal: ReleaseSeal, _ value: ReleaseInspection) -> Bool {
        !value.version.isEmpty && value.version == seal.body.version && !value.build.isEmpty && value.build == seal.body.build
    }
    @inline(__always) private static func c4(_ seal: ReleaseSeal, _ value: ReleaseInspection) -> Bool {
        value.regularExecutable && value.executableName == seal.body.executable
            && !value.executableName.isEmpty && !value.executableName.contains("/") && !value.executableName.contains("\\")
    }
    @inline(__always) private static func c5(_ image: ReleaseImage, _ seal: ReleaseSeal) -> Bool { image.sections == seal.body.sections.sorted { $0.name < $1.name } }
    @inline(__always) private static func c6(_ image: ReleaseImage, _ value: ReleaseInspection) -> Bool {
        guard let expected=image.sections.first(where: { $0.name == "__text" }), let measured=value.memoryTextHash else { return false }
        return measured == expected.sha256
    }
    @inline(__always) private static func c7(_ image: ReleaseImage, _ seal: ReleaseSeal) -> Bool { image.dependencies == seal.body.dependencies.sorted() }
    private static func canonicalLoadedImage(_ path:String) -> URL? {
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              !path.split(separator:"/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
    }
    @inline(__always) private static func c8(_ value: ReleaseInspection, _ seal: ReleaseSeal) -> Bool {
        let expected=Set(seal.body.dependencies.map { ($0 as NSString).lastPathComponent })
        guard let main=value.loadedImages.first, let executable=canonicalLoadedImage(main),
              executable.lastPathComponent==value.executableName else { return false }
        // Resolve the main bundle before deriving its own Frameworks subtree.
        // Do not resolve Frameworks itself: a symlink to another app must not
        // become the allowed root. Each loaded image is resolved independently.
        let bundleRoot=executable.deletingLastPathComponent().path
        let frameworkRoot=(bundleRoot.hasSuffix("/") ? bundleRoot : bundleRoot + "/") + "Frameworks/"
        // Cryptex roots can themselves be aliases to a boot-specific directory.
        // Resolve the trusted roots as well as images so those system libraries
        // remain valid without accepting a link that escapes a trusted subtree.
        let systemRoots=["/System", "/usr/lib", "/private/preboot/Cryptexes/OS", "/System/Volumes/Preboot/Cryptexes/OS"]
            .compactMap { canonicalLoadedImage($0)?.path }
            .filter { $0 != "/" }
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return value.loadedImages.dropFirst().allSatisfy { image in
            guard let url=canonicalLoadedImage(image) else { return false }
            let path=url.path
            return systemRoots.contains(where: { path.hasPrefix($0) })
                || (path.hasPrefix(frameworkRoot) && expected.contains(url.lastPathComponent))
        }
    }
    @inline(__always) private static func c9(_ value: ReleaseInspection) -> Bool { !value.debugger }
    static func inspect(_ value: ReleaseInspection, verifier: ServerSignatureVerifier) -> SecurityCheckResult {
        guard value.data.count <= 65536, let seal=try? JSONDecoder().decode(ReleaseSeal.self,from:value.data),
              let image=try? ReleaseImage.read(value.executable) else { return SecurityCheckResult(mask:0) }
        let checks=[c0(seal),c1(seal,verifier:verifier),c2(seal,value),c3(seal,value),c4(seal,value),c5(image,seal),c6(image,value),c7(image,seal),c8(value,seal),c9(value)]
        let mask=checks.enumerated().reduce(0) { $1.element ? $0 | (1 << $1.offset) : $0 }
        return SecurityCheckResult(mask:mask,releaseID:seal.body.release_id,sealDigest:integrityDigest(value.data))
    }
    public static var isDebuggerAttached: Bool {
        var info=kinfo_proc(), mib:[Int32]=[CTL_KERN,KERN_PROC,KERN_PROC_PID,getpid()]
        var size=MemoryLayout<kinfo_proc>.stride
        return sysctl(&mib,UInt32(mib.count),&info,&size,nil,0) == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
    private static func current() -> ReleaseInspection? {
        guard let executableURL=Bundle.main.executableURL, let dataURL=Bundle.main.url(forResource:"Astra",withExtension:"release"),
              let bytes=try? Data(contentsOf:executableURL,options:.mappedIfSafe), let data=try? Data(contentsOf:dataURL),
              let image=try? ReleaseImage.read(bytes) else { return nil }
        let attributes=try? FileManager.default.attributesOfItem(atPath:executableURL.path)
        var images:[String]=[]
        for i in 0..<_dyld_image_count() { if let name=_dyld_get_image_name(i) { images.append(String(cString:name)) } }
        var memoryHash:String?
        if image.textOffset > 0, image.textSize > 0, let header=_dyld_get_image_header(0) {
            let pointer=UnsafeRawPointer(header).advanced(by:image.textOffset)
            memoryHash=integrityDigest(Data(bytes:pointer,count:image.textSize))
        }
        return ReleaseInspection(data:data,executable:bytes,bundleID:Bundle.main.bundleIdentifier ?? "",version:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",
            build:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "",executableName:executableURL.lastPathComponent,
            regularExecutable:attributes?[.type] as? FileAttributeType == .typeRegular,memoryTextHash:memoryHash,loadedImages:images,debugger:isDebuggerAttached)
    }
    public static func checkAtLaunch() -> SecurityCheckResult {
        let image=current().map { inspect($0,verifier:.shared) } ?? SecurityCheckResult(mask:0)
        let environment=DeviceEnvironmentInspector.inspect()
        lock.lock(); let latched=commitFailure; lock.unlock()
        let result=SecurityCheckResult(mask:image.mask,releaseID:image.releaseID,sealDigest:image.sealDigest,
                                       environment:latched ?? environment)
        lock.lock(); latest=result; hasSignal = hasSignal || result.isCompromised; lock.unlock()
        return result
    }
    public static func checkAfterLogin() -> SecurityCheckResult { checkAtLaunch() }
    public static func checkBeforePatch() -> Bool { checkAtLaunch().permitsProtectedOperation }
    @discardableResult public static func periodicCheck() -> SecurityCheckResult { checkAtLaunch() }
    public static func reportCrackAndLockMachine(reason: String, details: [String:Any]) { lock.lock(); hasSignal=true; lock.unlock() }
    static func recordCommitFailure(_ result:DeviceEnvironmentResult) {
        guard result.state == .blocked else { return }
        lock.lock(); commitFailure=result; hasSignal=true; lock.unlock()
    }
}
enum IntegrityCommitBarrier {
    private static let lock=NSLock(); private static var blocked=false; private static var writers=0
    static var count:Int { lock.lock(); defer { lock.unlock() }; return writers }
    static func block() { lock.lock(); blocked=true; lock.unlock() }
    static func requireAllowed() throws { lock.lock(); defer { lock.unlock() }; if blocked { throw IntegrityError.invalid } }
    static func withCommit<T>(_ action:() throws -> T) throws -> T {
        let measurement=DeviceEnvironmentInspector.commitMeasurement()
        if measurement.state == .blocked {
            AntiTamper.recordCommitFailure(measurement)
            block()
            Task { @MainActor in _ = await AppIntegrityRuntime.shared.verifyNow(force:true) }
            throw IntegrityError.invalid
        }
        lock.lock(); if blocked { lock.unlock(); throw IntegrityError.invalid }; writers += 1; lock.unlock()
        defer { lock.lock(); writers -= 1; lock.unlock() }
        return try action()
    }
}
@MainActor final class AppIntegrityRuntime: ObservableObject {
    static let shared=AppIntegrityRuntime()
    @Published private(set) var allowed=false
    @Published private(set) var blocked=false
    @Published private(set) var failureDetail: String?
    private(set) var acceptedResult:SecurityCheckResult?
    private var pending:(id:UUID,epoch:UInt64,task:Task<SecurityCheckResult,Never>)?
    private var epoch:UInt64=0
    private var polling:Task<Void,Never>?
    private var reporter:((SecurityCheckResult) async -> Void)?
    private var lastCheck:TimeInterval=0
    private let inspect:@Sendable () -> SecurityCheckResult
    private let terminate:@Sendable () -> Void
    init(inspect:@escaping @Sendable () -> SecurityCheckResult = { AntiTamper.checkAtLaunch() },
         terminate:@escaping @Sendable () -> Void = { Darwin.exit(173) }) {
        self.inspect=inspect; self.terminate=terminate
    }
    func configureReporter(_ value:@escaping (SecurityCheckResult) async -> Void) { reporter=value }
    func setActive(_ value:Bool) {
        acceptedResult=nil
        epoch &+= 1; pending?.task.cancel(); pending=nil; lastCheck=0
        polling?.cancel(); polling=nil
        guard !blocked else { return }; allowed=false
        guard value else { return }
        polling=Task { [weak self] in
            while !Task.isCancelled {
                _ = await self?.verifyNow(force:true)
                do { try await Task.sleep(nanoseconds:5_000_000_000) } catch { return }
            }
        }
    }
    func verifyNow(force:Bool=false) async -> Bool {
        guard !blocked else { return false }
        if !force, allowed, acceptedResult != nil, ProcessInfo.processInfo.systemUptime-lastCheck < 2 { return true }
        if pending == nil { let inspect=self.inspect; pending=(UUID(),epoch,Task.detached(priority:.utility) { inspect() }) }
        guard let current=pending else { return false }
        let result=await current.task.value
        guard !blocked else { return false }
        guard current.epoch==epoch else { return false }
        guard pending?.id==current.id else {
            if pending != nil { return await verifyNow(force:true) }
            return allowed && acceptedResult != nil
        }
        pending=nil; lastCheck=ProcessInfo.processInfo.systemUptime
        if result.isCompromised { reject(result); return false }
        guard result.permitsProtectedOperation else {
            acceptedResult=nil
            allowed=false; failureDetail="Chưa xác minh được môi trường thiết bị. Hãy kiểm tra lại."
            NotificationCenter.default.post(name:Notification.Name("AstraNetworkAccessInvalidated"),object:nil)
            return false
        }
        acceptedResult=result; failureDetail=nil; allowed=true; return true
    }
    func requireAllowed(force:Bool=false) async throws { guard await verifyNow(force:force) else { throw IntegrityError.invalid } }
    private func reject(_ result:SecurityCheckResult) {
        guard !blocked else { return }; blocked=true; allowed=false; acceptedResult=nil
        failureDetail=result.environment.state == .blocked ? "Thiết bị không đáp ứng yêu cầu bảo mật. Hãy sử dụng thiết bị chưa jailbreak và bản ứng dụng được cung cấp." : IntegrityError.invalid.localizedDescription
        IntegrityCommitBarrier.block()
        NotificationCenter.default.post(name:Notification.Name("AstraNetworkAccessInvalidated"),object:nil)
        let report=reporter
        Task {
            if let report { await report(result) }
            while IntegrityCommitBarrier.count > 0 { try? await Task.sleep(nanoseconds:100_000_000) }
            terminate()
        }
    }
}
