//
//  AirLiftPairingManager.swift
//  ThreeOneOSFive
//
//  Real on-device RPPairing host backed by AirliftFFI.
//

import Foundation
import UIKit
import Network
import Combine
import AVFAudio
import AirliftFFI

@MainActor
final class AirLiftPairingManager: NSObject, ObservableObject, NetServiceDelegate {
    static let shared = AirLiftPairingManager()

    enum BonjourStatus: Equatable {
        case idle
        case preparing
        case publishing
        case published
        case failed(String)
    }

    enum PairingStatus: String, CaseIterable {
        case ready = "File pairing hợp lệ"
        case verified = "Ghép đôi hoạt động"
        case revoked = "Đã bị gỡ trong Cài đặt"
        case missing = "Chưa có"
        case invalid = "Không hợp lệ"
        case pairing = "Đang khởi tạo RPPairing..."
        case waitingSettings = "Chờ ghép đôi từ Cài đặt..."
        case verifying = "Đang kiểm tra ghép đôi..."

        var isPaired: Bool {
            self == .ready || self == .verified
        }
    }

    enum PairingError: LocalizedError {
        case unsupportedOS
        case busy
        case localNetworkPermission
        case publicationFailed(String)
        case emptyRecord
        case invalidRecord
        case persistenceFailed(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "Ghép đôi trực tiếp trong Chế độ nhà phát triển chỉ dùng cho các build iOS 27 còn hỗ trợ. iOS 18.7.2–18.8.x và iOS 26.6.2 trở lên (bao gồm iOS 26.7) phải nhập pairing file tạo từ máy tính."
            case .busy:
                return "Một phiên ghép đôi đang chạy."
            case .localNetworkPermission:
                return "Astra chưa được phép dùng Mạng cục bộ. Vào Cài đặt → Astra → bật Mạng cục bộ rồi thử lại."
            case .publicationFailed(let message):
                return "Không thể phát thiết bị Astra qua Bonjour: \(message)"
            case .emptyRecord:
                return "Chưa xác nhận được dữ liệu ghép đôi. Phiên ghép đôi chưa sẵn sàng."
            case .invalidRecord:
                return "Ghép đôi đã trả dữ liệu nhưng thông tin xác thực chưa đầy đủ. Hãy xoá phiên Astra trong Chế độ nhà phát triển rồi ghép đôi lại."
            case .persistenceFailed(let message):
                return "Ghép đôi hoàn tất nhưng Astra không thể lưu thông tin xác thực an toàn: \(message)"
            case .failed(let message):
                return message
            }
        }
    }

    @Published var status: PairingStatus = .missing
    @Published var pairingFilePath: String?
    @Published var alertMessage: String?
    @Published var showAlert = false
    @Published var isBroadcastingBonjour = false
    @Published private(set) var bonjourStatus: BonjourStatus = .idle
    @Published var pairingPIN = ""
    @Published var isWiFiConnected = true
    @Published private(set) var isBackgroundKeepAliveActive = false

    var isPaired: Bool {
        status.isPaired
    }

    var isPairingHostActive: Bool { pairingThreadActive }
    var canRetryBonjourAdvertisement: Bool {
        pairingThreadActive && pendingPublication != nil && !isBroadcastingBonjour
    }

    var bonjourStatusText: String {
        switch bonjourStatus {
        case .idle: return "Chưa phát dịch vụ ghép nối"
        case .preparing: return "Đang khởi tạo RPPairing host"
        case .publishing: return "Đang đăng ký thiết bị Astra với Bonjour"
        case .published: return "Thiết bị Astra đang hiển thị để ghép nối"
        case .failed(let detail): return "Bonjour chưa phát được (\(detail))"
        }
    }

    private let pathMonitor = NWPathMonitor()
    private let localNetworkAuthorization = LocalNetworkAuthorization()
    private var netService: NetService?
    private let audioKeepAlive = PairingAudioKeepAlive()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingPublication: PairingPublication?
    private var publicationRetryCount = 0
    private var publicationRetryWorkItem: DispatchWorkItem?
    private var hostReadyWatchdog: DispatchWorkItem?
    private var continuation: CheckedContinuation<String, Error>?
    private var pairingThreadActive = false
    private var cancellables = Set<AnyCancellable>()
    private var verificationTimer: AnyCancellable?
    private var isVerifyingPairing = false

    private struct PairingPublication {
        let serviceID: String
        let port: UInt16
        let txt: [String: Data]
    }

    nonisolated private static let altIRKKey = "novax.airlift.hostAltIRK"
    nonisolated private static var storedAltIRK: String {
        get { UserDefaults.standard.string(forKey: altIRKKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: altIRKKey) }
    }

    private let pairingFileName = "novax_airlift_pairing.plist"
    private let pairingStagingFileName = "novax_airlift_pairing.pending.plist"
    private let pairingKeychainKey = "novax.airlift.pairingRecord.v1"
    private var pairingFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("AirLift", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        return folder.appendingPathComponent(pairingFileName)
    }

    private var pairingStagingFileURL: URL {
        pairingFileURL.deletingLastPathComponent().appendingPathComponent(pairingStagingFileName)
    }

    private var legacyPairingFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(".airlift", isDirectory: true)
            .appendingPathComponent(pairingFileName)
    }

    private override init() {
        super.init()
        guard ExploitSupportPolicy.currentStorageMode == .airLift else { return }
        discardPairingStagingFile()
        migrateLegacyPairingFileIfNeeded()
        restorePairingFileFromKeychainIfNeeded()
        checkPairingStatus()
        backupPairingFileToKeychainIfValid()
        setupNetworkMonitoring()
        setupLifecycleMonitoring()
    }

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isWiFiConnected = path.usesInterfaceType(.wifi)
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func setupLifecycleMonitoring() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard !AirTrafficProtocolClient.shared.isBusy, !self.isVerifyingPairing else { return }
                    self.checkPairingStatus()
                    if self.pairingThreadActive,
                       self.pendingPublication != nil,
                       !self.isBroadcastingBonjour {
                        self.retryBonjourAdvertisement(userInitiated: false)
                    }
                }
            }
            .store(in: &cancellables)

        AirLiftTunnelManager.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tunnelStatus in
                guard let self else { return }
                guard !AirTrafficProtocolClient.shared.isBusy, !self.isVerifyingPairing else { return }
                if tunnelStatus == .connected && self.status == .ready {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await self?.verifyPairingWithDevice(silent: true)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func startContinuousPairingMonitor() {
        // Debounced foreground checks replace background timer polling
        // to prevent socket contention on iOS 27 loopback services.
        verificationTimer?.cancel()
        verificationTimer = nil
    }

    func checkPairingStatus() {
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            if status != .revoked {
                status = .missing
            }
            pairingFilePath = nil
            return
        }
        guard let record = loadPairingRecord(at: pairingFileURL),
              Self.isSupportedPairingRecord(record) else {
            if restorePairingFileFromKeychainIfNeeded(replacingCurrentFile: true),
               let restored = loadPairingRecord(at: pairingFileURL),
               Self.isSupportedPairingRecord(restored) {
                status = .ready
                pairingFilePath = pairingFileURL.path
                return
            }
            status = .invalid
            pairingFilePath = nil
            return
        }
        if status != .verified && status != .verifying && status != .pairing && status != .waitingSettings {
            status = .ready
        }
        pairingFilePath = pairingFileURL.path
    }

    func verifyPairingStatus(activeProbe: Bool = false) {
        checkPairingStatus()
        guard activeProbe, status.isPaired, AirLiftTunnelManager.shared.isOperational else {
            return
        }
        Task {
            await verifyPairingWithDevice(silent: true)
        }
    }

    func verifyPairingWithDevice(silent: Bool = false) async {
        guard !isVerifyingPairing else { return }
        checkPairingStatus()
        guard status.isPaired else {
            if !silent {
                notify(message: "Chưa có file pairing để kiểm tra.")
            }
            return
        }
        guard AirLiftTunnelManager.shared.isOperational else {
            if !silent {
                notify(message: "LocalDevVPN chưa kết nối. Hãy bật LocalDevVPN trước khi kiểm tra ghép đôi.")
            }
            return
        }

        isVerifyingPairing = true
        let previousStatus = status
        status = .verifying

        let outcome = await AirTrafficProtocolClient.shared.verifyPairingWithDevice()
        isVerifyingPairing = false

        if outcome.isValid {
            status = .verified
            if !silent {
                notify(message: "Ghép đôi đang hoạt động bình thường trên iPhone.")
            }
        } else if outcome.isRevoked {
            if !silent {
                showAlert = true
            }
        } else {
            status = (previousStatus == .verifying) ? .ready : previousStatus
            if !silent {
                notify(message: outcome.message)
            }
        }
    }

    func handlePairingRevoked(reason: String) {
        stopBonjourBroadcast()
        if FileManager.default.fileExists(atPath: pairingFileURL.path) {
            try? FileManager.default.removeItem(at: pairingFileURL)
        }
        KeychainUtils.delete(key: pairingKeychainKey)
        Self.storedAltIRK = ""
        pairingFilePath = nil
        status = .revoked
        AirLiftGatekeeperManager.shared.triggerRePair(reason: "Thiết bị iPhone đã hủy ghép đôi với Astra trong Cài đặt.")
        let guidance = ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile
            ? "Vui lòng bấm 'Pair trên máy' để ghép đôi lại hoặc nhập pairing file hợp lệ."
            : "Vui lòng tạo lại file pairing trên máy tính rồi nhập file mới vào Astra."
        notify(message: "Thiết bị iPhone đã hủy ghép đôi với Astra. \(guidance)")
    }

    func importPairingFile(from sourceURL: URL) -> Bool {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: sourceURL)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let record = object as? [String: Any], Self.isSupportedPairingRecord(record) else {
                notify(message: "File pairing không hợp lệ. Hãy chọn record Lockdown hoặc RPPairing đầy đủ.")
                return false
            }
            try data.write(to: pairingFileURL, options: [.atomic, .completeFileProtection])
            backupPairingDataToKeychain(data)
            status = .ready
            pairingFilePath = pairingFileURL.path
            notify(message: "Đã nhập file pairing. Bật LocalDevVPN rồi chạy kiểm tra kết nối.")
            if AirLiftTunnelManager.shared.isOperational {
                Task { await verifyPairingWithDevice(silent: true) }
            }
            return true
        } catch {
            notify(message: "Không thể nhập file pairing: \(error.localizedDescription)")
            return false
        }
    }

    func pairDirectlyOnDevice() async {
        guard ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile else {
            notify(message: PairingError.unsupportedOS.localizedDescription)
            return
        }
        if pairingThreadActive {
            if pendingPublication != nil {
                retryBonjourAdvertisement(userInitiated: true)
            } else {
                notify(message: "RPPairing đang khởi tạo. Nếu Astra chưa xuất hiện sau 15 giây, hãy đóng hẳn ứng dụng rồi mở lại để tạo phiên mới.")
            }
            return
        }

        // This probe exists to trigger the Local Network prompt. A timeout is
        // not proof that permission was denied, so it must never prevent the
        // real RPPairing host and NetService publication from starting.
        _ = await localNetworkAuthorization.request()

        do {
            _ = try await startAndWait()
            notify(message: "Ghép đôi thành công. Astra đã lưu thông tin xác thực trên thiết bị.")
        } catch is CancellationError {
            return
        } catch {
            notify(message: "Ghép đôi thất bại: \(error.localizedDescription)")
        }
    }

    private func startAndWait() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            startBonjourPairingBroadcast()
        }
    }

    func startBonjourPairingBroadcast() {
        guard !pairingThreadActive else { return }
        stopAdvertisingOnly()
        pairingPIN = ""
        status = .pairing
        bonjourStatus = .preparing
        pairingThreadActive = true
        isBackgroundKeepAliveActive = audioKeepAlive.start()
        beginPairingBackgroundTask()
        startHostReadyWatchdog()

        let outputPath = preparePairingStagingFile().path
        let altIRK = Self.storedAltIRK
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

        DispatchQueue.global(qos: .userInitiated).async {
            var result = ALPairResult()
            let returnCode = "0.0.0.0".withCString { bind in
                "Astra".withCString { name in
                    "Mac17,7".withCString { model in
                        outputPath.withCString { output in
                            altIRK.withCString { irk in
                                al_pairing_run_host(
                                    bind, 0, name, model, output, irk,
                                    novaPairReadyCallback, novaPairPinCallback,
                                    context, &result
                                )
                            }
                        }
                    }
                }
            }

            let issuedIRK = Self.string(result.host_alt_irk_hex)
            let deviceName = Self.string(result.device_name)
            let errorMessage = Self.string(result.error)
            al_pairing_result_free(&result)

            DispatchQueue.main.async {
                Unmanaged<AirLiftPairingManager>.fromOpaque(context).release()
                self.finishPairing(
                    returnCode: returnCode,
                    outputPath: outputPath,
                    issuedIRK: issuedIRK,
                    deviceName: deviceName,
                    errorMessage: errorMessage
                )
            }
        }
    }

    func stopBonjourBroadcast() {
        stopAdvertisingOnly()
        pendingPublication = nil
        publicationRetryCount = 0
        hostReadyWatchdog?.cancel()
        hostReadyWatchdog = nil
        pairingPIN = ""
        isBroadcastingBonjour = false
        bonjourStatus = .idle
        if !pairingThreadActive {
            audioKeepAlive.stop()
            isBackgroundKeepAliveActive = false
            endPairingBackgroundTask()
        }
    }

    private func finishPairing(
        returnCode: Int32,
        outputPath: String,
        issuedIRK: String,
        deviceName: String,
        errorMessage: String
    ) {
        stopAdvertisingOnly()
        pendingPublication = nil
        publicationRetryCount = 0
        hostReadyWatchdog?.cancel()
        hostReadyWatchdog = nil
        pairingThreadActive = false
        pairingPIN = ""
        audioKeepAlive.stop()
        isBackgroundKeepAliveActive = false
        endPairingBackgroundTask()
        bonjourStatus = .idle
        defer { discardPairingStagingFile() }

        guard returnCode == 0 else {
            status = .missing
            pairingFilePath = nil
            let detail = errorMessage.isEmpty ? "RPPairing trả về mã \(returnCode)." : errorMessage
            resolve(.failure(PairingError.failed(detail)))
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)),
              !data.isEmpty else {
            status = .missing
            pairingFilePath = nil
            resolve(.failure(PairingError.emptyRecord))
            return
        }

        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let record = object as? [String: Any],
              Self.isSupportedPairingRecord(record) else {
            status = .invalid
            pairingFilePath = nil
            resolve(.failure(PairingError.invalidRecord))
            return
        }

        do {
            // Promote validated staging data with atomic replacement and
            // complete file protection; native output never becomes canonical.
            try data.write(to: pairingFileURL, options: [.atomic, .completeFileProtection])
        } catch {
            status = .invalid
            pairingFilePath = nil
            resolve(.failure(PairingError.persistenceFailed(error.localizedDescription)))
            return
        }

        if !issuedIRK.isEmpty { Self.storedAltIRK = issuedIRK }
        if !backupPairingDataToKeychain(data) {
            log("airlift pairing: valid record saved, but Keychain recovery backup failed")
        }

        // Pairing normally finishes while the UI is still in .waitingSettings.
        // File validity, not that transient state, is the completion authority.
        pairingFilePath = pairingFileURL.path
        status = .verified
        let label = deviceName.isEmpty ? "iPhone" : deviceName
        resolve(.success(pairingFileURL.path))
        alertMessage = "Đã ghép đôi với \(label)."
        if AirLiftTunnelManager.shared.isOperational {
            Task { @MainActor [weak self] in
                await self?.verifyPairingWithDevice(silent: true)
            }
        }
    }

    /// Native pairing writes to staging first. A valid existing record is
    /// copied there so the Rust host can reuse its signing identity on re-pair.
    private func preparePairingStagingFile() -> URL {
        discardPairingStagingFile()
        guard let data = try? Data(contentsOf: pairingFileURL),
              !data.isEmpty,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let record = object as? [String: Any],
              Self.isSupportedPairingRecord(record) else {
            return pairingStagingFileURL
        }
        do {
            try data.write(to: pairingStagingFileURL, options: [.atomic, .completeFileProtection])
        } catch {
            log("airlift pairing: could not seed staging record; starting with a fresh host identity")
        }
        return pairingStagingFileURL
    }

    private func discardPairingStagingFile() {
        try? FileManager.default.removeItem(at: pairingStagingFileURL)
    }

    private func resolve(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    fileprivate func publish(serviceID: String, port: UInt16, txt: [String: Data]) {
        hostReadyWatchdog?.cancel()
        hostReadyWatchdog = nil
        pendingPublication = PairingPublication(serviceID: serviceID, port: port, txt: txt)
        publicationRetryCount = 0
        publishPendingService()
    }

    private func publishPendingService() {
        guard pairingThreadActive, let publication = pendingPublication else { return }
        stopAdvertisingOnly()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: publication.serviceID,
            port: Int32(publication.port)
        )
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: publication.txt))
        // The Rust RPPairing host already owns/listens on this TCP port.
        // NetService must advertise that existing listener only; asking it to
        // listen as well can make publication fail or contend for the port.
        netService = service
        isBroadcastingBonjour = false
        bonjourStatus = .publishing
        status = .pairing
        // The RPPairing auth tag is tied to the service identifier. Bonjour
        // must not silently rename it to "name (2)" on a collision.
        service.publish(options: .noAutoRename)
    }

    func retryBonjourAdvertisement(userInitiated: Bool) {
        guard pairingThreadActive, pendingPublication != nil else {
            if userInitiated {
                notify(message: "RPPairing chưa tạo xong thông tin quảng bá. Hãy chờ vài giây rồi thử lại.")
            }
            return
        }
        publicationRetryWorkItem?.cancel()
        publicationRetryWorkItem = nil
        if userInitiated { publicationRetryCount = 0 }
        publishPendingService()
        if userInitiated {
            notify(message: "Astra đang phát lại thiết bị ghép nối. Hãy giữ Wi‑Fi và quyền Mạng cục bộ bật rồi mở lại Chế độ nhà phát triển.")
        }
    }

    func netServiceDidPublish(_ sender: NetService) {
        guard sender === netService else { return }
        publicationRetryWorkItem?.cancel()
        publicationRetryWorkItem = nil
        publicationRetryCount = 0
        isBroadcastingBonjour = true
        bonjourStatus = .published
        status = .waitingSettings
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        guard sender === netService else { return }
        isBroadcastingBonjour = false
        let code = errorDict[NetService.errorCode] ?? 0
        let domain = errorDict[NetService.errorDomain] ?? 0
        let detail = "mã \(code) · miền \(domain)"
        bonjourStatus = .failed(detail)

        guard pairingThreadActive, pendingPublication != nil else { return }
        if publicationRetryCount < 3 {
            publicationRetryCount += 1
            let delay = min(3.0, 0.75 * Double(publicationRetryCount))
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.publishPendingService() }
            }
            publicationRetryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            status = .pairing
            notify(message: PairingError.publicationFailed(
                "\(detail). Kiểm tra Cài đặt → Astra → Mạng cục bộ, bật Wi‑Fi rồi bấm Pair trên máy để phát lại."
            ).localizedDescription)
        }
    }

    func netServiceDidStop(_ sender: NetService) {
        guard sender === netService else { return }
        isBroadcastingBonjour = false
        guard pairingThreadActive, pendingPublication != nil else {
            bonjourStatus = .idle
            return
        }
        bonjourStatus = .failed("dịch vụ Bonjour đã dừng")
        if UIApplication.shared.applicationState == .active {
            DispatchQueue.main.async { [weak self] in
                self?.retryBonjourAdvertisement(userInitiated: false)
            }
        }
    }

    fileprivate func showPIN(_ pin: String) {
        pairingPIN = pin
        status = .waitingSettings
    }

    private func stopAdvertisingOnly() {
        publicationRetryWorkItem?.cancel()
        publicationRetryWorkItem = nil
        netService?.delegate = nil
        netService?.stop()
        netService = nil
        isBroadcastingBonjour = false
    }

    private func startHostReadyWatchdog() {
        hostReadyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.pairingThreadActive,
                      self.pendingPublication == nil else { return }
                self.bonjourStatus = .failed("RPPairing host chưa sẵn sàng")
                self.notify(message: "RPPairing không tạo được dịch vụ quảng bá sau 15 giây. Hãy đóng hẳn Astra, mở lại và thử ghép đôi lần nữa.")
            }
        }
        hostReadyWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func beginPairingBackgroundTask() {
        endPairingBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Astra.RPPairing") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endPairingBackgroundTask()
            }
        }
    }

    private func endPairingBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func openPairingSettings() {
        let candidates = [
            "App-Prefs:root=Privacy&path=DEVELOPER_SETTINGS",
            "App-Prefs:root=Privacy",
            UIApplication.openSettingsURLString
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) else { continue }
            UIApplication.shared.open(url)
            return
        }
    }

    func deletePairingFile() {
        stopBonjourBroadcast()
        do {
            if FileManager.default.fileExists(atPath: pairingFileURL.path) {
                try FileManager.default.removeItem(at: pairingFileURL)
            }
            KeychainUtils.delete(key: pairingKeychainKey)
            Self.storedAltIRK = ""
            status = .missing
            pairingFilePath = nil
            AirLiftGatekeeperManager.shared.triggerRePair(reason: "File pairing đã bị xóa khỏi thiết bị.")
            notify(message: "Đã xoá file pairing khỏi thiết bị.")
        } catch {
            notify(message: "Không thể xoá file pairing: \(error.localizedDescription)")
        }
    }

    func getPairingData() -> [String: Any]? {
        loadPairingRecord(at: pairingFileURL)
    }

    private func loadPairingRecord(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        return object as? [String: Any]
    }

    private func migrateLegacyPairingFileIfNeeded() {
        guard !FileManager.default.fileExists(atPath: pairingFileURL.path),
              FileManager.default.fileExists(atPath: legacyPairingFileURL.path) else { return }
        try? FileManager.default.moveItem(at: legacyPairingFileURL, to: pairingFileURL)
    }

    /// Persists the validated pairing record in Keychain as a recovery copy.
    /// Internal visibility is intentional: the gatekeeper commits its setup
    /// flag only after asking the pairing owner to persist the same record.
    @discardableResult
    func backupPairingFileToKeychainIfValid() -> Bool {
        guard let data = try? Data(contentsOf: pairingFileURL),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let record = object as? [String: Any],
              Self.isSupportedPairingRecord(record) else { return false }
        return backupPairingDataToKeychain(data)
    }

    @discardableResult
    private func backupPairingDataToKeychain(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return KeychainUtils.save(key: pairingKeychainKey, value: data.base64EncodedString())
    }

    /// Structural validation used by the startup gate. A `.ready` state alone
    /// is not enough if the underlying file was removed or corrupted later.
    var hasUsablePersistedPairingRecord: Bool {
        guard status != .revoked,
              let record = loadPairingRecord(at: pairingFileURL) else {
            return false
        }
        return Self.isSupportedPairingRecord(record)
    }

    @discardableResult
    private func restorePairingFileFromKeychainIfNeeded(replacingCurrentFile: Bool = false) -> Bool {
        if !replacingCurrentFile, FileManager.default.fileExists(atPath: pairingFileURL.path) {
            return false
        }
        guard let encoded = KeychainUtils.read(key: pairingKeychainKey),
              let data = Data(base64Encoded: encoded),
              !data.isEmpty,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let record = object as? [String: Any],
              Self.isSupportedPairingRecord(record) else {
            return false
        }
        do {
            try data.write(to: pairingFileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func isSupportedPairingRecord(_ record: [String: Any]) -> Bool {
        func string(_ key: String) -> Bool {
            guard let value = record[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func data(_ key: String, minimum: Int = 1) -> Bool {
            guard let value = record[key] as? Data else { return false }
            return value.count >= minimum
        }

        let lockdown = string("HostID") && string("SystemBUID") &&
            data("HostCertificate") && data("RootCertificate") &&
            data("DeviceCertificate") && data("HostPrivateKey") && data("RootPrivateKey")
        let remote = string("identifier") && data("public_key", minimum: 32) &&
            data("private_key", minimum: 32) && data("alt_irk", minimum: 16)
        return lockdown || remote
    }

    private nonisolated static func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    private func notify(message: String) {
        alertMessage = message
        showAlert = true
    }
}

/// Requests Local Network access by advertising and browsing a temporary
/// Bonjour service. This is only a prompt trigger: a timeout or transient
/// browser failure is not proof of denial, so the real publication still runs.
@MainActor
private final class LocalNetworkAuthorization {
    private let probeType = "_aircardprobe._tcp"
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutWorkItem: DispatchWorkItem?

    func request(timeout: TimeInterval = 2.0) async -> Bool {
        guard continuation == nil else { return false }
        cleanup(resumeWith: nil)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            do {
                let listener = try NWListener(using: parameters)
                listener.service = NWListener.Service(
                    name: "Astra-LocalNetwork-Probe-\(UUID().uuidString)",
                    type: probeType
                )
                listener.newConnectionHandler = { connection in connection.cancel() }
                listener.stateUpdateHandler = { [weak self] state in
                    guard case .failed = state else { return }
                    Task { @MainActor [weak self] in self?.finish(true) }
                }
                self.listener = listener

                let browser = NWBrowser(
                    for: .bonjour(type: probeType, domain: nil),
                    using: parameters
                )
                browser.stateUpdateHandler = { [weak self] state in
                    guard case .failed = state else { return }
                    Task { @MainActor [weak self] in self?.finish(true) }
                }
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    guard !results.isEmpty else { return }
                    Task { @MainActor [weak self] in self?.finish(true) }
                }
                self.browser = browser

                listener.start(queue: .main)
                browser.start(queue: .main)

                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.finish(true) }
                }
                self.timeoutWorkItem = timeoutWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
            } catch {
                finish(true)
            }
        }
    }

    private func finish(_ authorized: Bool) {
        cleanup(resumeWith: authorized)
    }

    private func cleanup(resumeWith result: Bool?) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        if let result, let continuation {
            self.continuation = nil
            continuation.resume(returning: result)
        }
    }
}

private let novaPairReadyCallback: ALPairReadyCb = { context, serviceID, port, keys, values, count in
    guard let context, let serviceID else { return }
    let manager = Unmanaged<AirLiftPairingManager>.fromOpaque(context).takeUnretainedValue()
    var txt: [String: Data] = [:]
    if let keys, let values {
        for index in 0..<Int(count) {
            guard let key = keys[index], let value = values[index] else { continue }
            txt[String(cString: key)] = Data(String(cString: value).utf8)
        }
    }
    let identifier = String(cString: serviceID)
    DispatchQueue.main.async {
        manager.publish(serviceID: identifier, port: port, txt: txt)
    }
}

private let novaPairPinCallback: ALPairPinCb = { pin, context in
    guard let context, let pin else { return }
    let manager = Unmanaged<AirLiftPairingManager>.fromOpaque(context).takeUnretainedValue()
    let value = String(cString: pin)
    DispatchQueue.main.async { manager.showPIN(value) }
}

@MainActor
private final class PairingAudioKeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var running = false

    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if player.engine == nil { engine.attach(player) }
            let format = engine.outputNode.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: max(1_024, AVAudioFrameCount(format.sampleRate))
                  ) else { return false }
            buffer.frameLength = buffer.frameCapacity
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    memset(channels[channel], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
                }
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            running = true
            return true
        } catch {
            stop()
            return false
        }
    }

    func stop() {
        player.stop()
        if engine.isRunning { engine.stop() }
        if player.engine != nil { engine.detach(player) }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        running = false
    }
}
