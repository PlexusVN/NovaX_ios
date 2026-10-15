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
final class AirLiftPairingManager: ObservableObject {
    static let shared = AirLiftPairingManager()

    enum PairingStatus: String {
        case ready = "File pairing hợp lệ"
        case missing = "Chưa có"
        case invalid = "Không hợp lệ"
        case pairing = "Đang khởi tạo RPPairing..."
        case waitingSettings = "Chờ ghép đôi từ Cài đặt..."
    }

    enum PairingError: LocalizedError {
        case unsupportedOS
        case busy
        case emptyRecord
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "Ghép đôi trực tiếp yêu cầu iOS 27 trở lên."
            case .busy:
                return "Một phiên ghép đôi đang chạy."
            case .emptyRecord:
                return "Ghép đôi hoàn tất nhưng file thông tin xác thực bị trống."
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
    @Published var pairingPIN = ""
    @Published var isWiFiConnected = true

    private let pathMonitor = NWPathMonitor()
    private var permissionBrowser: NWBrowser?
    private var netService: NetService?
    private let audioKeepAlive = PairingAudioKeepAlive()
    private var continuation: CheckedContinuation<String, Error>?
    private var pairingThreadActive = false

    private static let altIRKKey = "novax.airlift.hostAltIRK"
    nonisolated private static var storedAltIRK: String {
        get { UserDefaults.standard.string(forKey: altIRKKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: altIRKKey) }
    }

    private let pairingFileName = "novax_airlift_pairing.plist"
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

    private var legacyPairingFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(".airlift", isDirectory: true)
            .appendingPathComponent(pairingFileName)
    }

    private init() {
        migrateLegacyPairingFileIfNeeded()
        checkPairingStatus()
        setupNetworkMonitoring()
        triggerLocalNetworkPermission()
    }

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isWiFiConnected = path.usesInterfaceType(.wifi)
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func triggerLocalNetworkPermission() {
        permissionBrowser?.cancel()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_remotepairing-pairable-host._tcp", domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            Task { @MainActor [weak self] in
                self?.alertMessage = "Không thể truy cập mạng cục bộ: \(error.localizedDescription)"
            }
        }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        permissionBrowser = browser
    }

    func checkPairingStatus() {
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            status = .missing
            pairingFilePath = nil
            return
        }
        guard let record = loadPairingRecord(at: pairingFileURL),
              Self.isSupportedPairingRecord(record) else {
            status = .invalid
            pairingFilePath = nil
            return
        }
        status = .ready
        pairingFilePath = pairingFileURL.path
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
            checkPairingStatus()
            notify(message: "Đã nhập file pairing. Bật LocalDevVPN rồi chạy kiểm tra kết nối.")
            return true
        } catch {
            notify(message: "Không thể nhập file pairing: \(error.localizedDescription)")
            return false
        }
    }

    func pairDirectlyOnDevice() async {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            notify(message: PairingError.unsupportedOS.localizedDescription)
            return
        }
        guard !pairingThreadActive else {
            notify(message: PairingError.busy.localizedDescription)
            return
        }

        do {
            _ = try await startAndWait()
            notify(message: "Ghép đôi thành công. NovaX đã lưu thông tin xác thực trên thiết bị.")
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
        triggerLocalNetworkPermission()
        stopAdvertisingOnly()
        pairingPIN = ""
        status = .pairing
        pairingThreadActive = true
        audioKeepAlive.start()

        let outputPath = pairingFileURL.path
        let altIRK = Self.storedAltIRK
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

        DispatchQueue.global(qos: .userInitiated).async {
            var result = ALPairResult()
            let returnCode = "0.0.0.0".withCString { bind in
                "NovaX".withCString { name in
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
            let resultPath = Self.string(result.pairing_file_path)
            let deviceName = Self.string(result.device_name)
            let errorMessage = Self.string(result.error)
            al_pairing_result_free(&result)

            DispatchQueue.main.async {
                Unmanaged<AirLiftPairingManager>.fromOpaque(context).release()
                self.finishPairing(
                    returnCode: returnCode,
                    outputPath: resultPath.isEmpty ? outputPath : resultPath,
                    issuedIRK: issuedIRK,
                    deviceName: deviceName,
                    errorMessage: errorMessage
                )
            }
        }
    }

    func stopBonjourBroadcast() {
        stopAdvertisingOnly()
        pairingPIN = ""
        isBroadcastingBonjour = false
        if !pairingThreadActive {
            audioKeepAlive.stop()
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
        pairingThreadActive = false
        pairingPIN = ""
        audioKeepAlive.stop()

        if returnCode == 0,
           let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)),
           !data.isEmpty {
            if !issuedIRK.isEmpty { Self.storedAltIRK = issuedIRK }
            if outputPath != pairingFileURL.path {
                try? data.write(to: pairingFileURL, options: [.atomic, .completeFileProtection])
            }
            checkPairingStatus()
            guard status == .ready else {
                resolve(.failure(PairingError.emptyRecord))
                return
            }
            let label = deviceName.isEmpty ? "iPhone" : deviceName
            resolve(.success(pairingFileURL.path))
            alertMessage = "Đã ghép đôi với \(label)."
        } else {
            status = .missing
            let detail = errorMessage.isEmpty ? "RPPairing trả về mã \(returnCode)." : errorMessage
            resolve(.failure(PairingError.failed(detail)))
        }
    }

    private func resolve(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    fileprivate func publish(serviceID: String, port: UInt16, txt: [String: Data]) {
        stopAdvertisingOnly()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: Int32(port)
        )
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish(options: [.listenForConnections])
        netService = service
        isBroadcastingBonjour = true
        status = .waitingSettings
    }

    fileprivate func showPIN(_ pin: String) {
        pairingPIN = pin
        status = .waitingSettings
    }

    private func stopAdvertisingOnly() {
        netService?.stop()
        netService = nil
        isBroadcastingBonjour = false
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
            Self.storedAltIRK = ""
            checkPairingStatus()
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

    func start() {
        guard !running else { return }
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
                  ) else { return }
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
        } catch {
            stop()
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
