//
//  AirLiftSettingsSection.swift
//  ThreeOneOSFive
//
//  Created by Astra AirLift Integration on 03/10/2026.
//  UI Components for AirLift & Loopback VPN configuration.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Cyberpunk OLED Dashboard Card (For DashboardView & ProfileView)

struct AirLiftDashboardCard: View {
    @StateObject private var tunnelManager = AirLiftTunnelManager.shared
    @StateObject private var pairingManager = AirLiftPairingManager.shared
    @StateObject private var storageCoordinator = StorageEngineCoordinator.shared
    @State private var showDocumentPicker = false
    @State private var showPairingStartAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            dashboardHeader
            transportStatus
            if let error = tunnelManager.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(AppTheme.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().background(AppTheme.grey200)
            externalVPNStatus
            Divider().background(AppTheme.grey200)
            pairingStatus
            pairingGuidance
            pairingActions
            Divider().background(AppTheme.grey200)
            storageEngineToggle
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.grey300, AppTheme.grey200],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
        )
        .sheet(isPresented: $showDocumentPicker) {
            AirLiftDocumentPicker { url in
                _ = pairingManager.importPairingFile(from: url)
            }
        }
        .alert(isPresented: $pairingManager.showAlert) {
            Alert(
                title: Text("Thông báo AirLift"),
                message: Text(pairingManager.alertMessage ?? ""),
                dismissButton: .default(Text("Đóng"))
            )
        }
        .alert("Ghép đôi trực tiếp", isPresented: $showPairingStartAlert) {
            Button("Huỷ", role: .cancel) { }
            Button("Bắt đầu phát sóng") {
                Task { await pairingManager.pairDirectlyOnDevice() }
            }
        } message: {
            Text("Astra sẽ chạy RPPairing host thật và phát Bonjour. Sau đó mở Cài đặt › Quyền riêng tư & Bảo mật › Chế độ nhà phát triển, chọn Pair with Astra và nhập PIN hiển thị trong ứng dụng.")
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.ink)

            Text("AIRLIFT TRANSPORT CHECK")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(AppTheme.ink)
                .tracking(0.5)

            Spacer()

            Text(tunnelManager.isOperational ? "ONLINE" : "OFFLINE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        tunnelManager.isOperational ? AppTheme.statusSuccess : AppTheme.statusError
                    )
                )
        }
    }

    private var transportStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: tunnelManager.isServiceReachable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(tunnelManager.isServiceReachable ? AppTheme.statusSuccess : AppTheme.statusError)
            Text(tunnelManager.serviceStatus.rawValue)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(tunnelManager.isServiceReachable ? AppTheme.statusSuccess : AppTheme.statusError)
            Spacer()
            Button("KIỂM TRA") {
                Task { await tunnelManager.verifyLoopbackService() }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(AppTheme.statusInfo)
            .disabled(tunnelManager.status == .checking)
        }
    }

    private var externalVPNStatus: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tunnelStatusColor.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: tunnelManager.status == .connected ? "bolt.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(tunnelStatusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("LocalDevVPN bên ngoài")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.ink)
                    Text("10.7.0.1")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.grey100)
                        .clipShape(Capsule())
                }

                HStack(spacing: 4) {
                    Circle().fill(tunnelStatusColor).frame(width: 6, height: 6)
                    Text(tunnelManager.isTunnelRouteDetected && !tunnelManager.isServiceReachable
                         ? "VPN đã bật · dịch vụ chưa phản hồi"
                         : tunnelManager.status.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(tunnelStatusColor)
                }
            }

            Spacer()

            Button {
                Haptics.medium()
                tunnelManager.openLocalDevVPN()
            } label: {
                Label("MỞ VPN", systemImage: "arrow.up.forward.app.fill")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        AppTheme.ink
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 8)
            }
        }
    }

    private var pairingStatus: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(pairingStatusColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: pairingManager.status == .ready ? "key.fill" : "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(pairingStatusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("AirTraffic Pairing")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                Text(pairingManager.status.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(pairingStatusColor)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var pairingGuidance: some View {
        if pairingManager.isBroadcastingBonjour || pairingManager.status == .waitingSettings {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView().tint(AppTheme.statusInfo).scaleEffect(0.8)
                    Text("Đang phát sóng ghép đôi ngầm...")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.statusInfo)
                    Spacer()
                }
                pairingPINCard
                wifiWarning
                pairingInstructions
                openDeveloperSettingsButton
            }
            .padding(12)
            .background(AppTheme.statusInfo.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.statusInfo.opacity(0.20), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var pairingPINCard: some View {
        if !pairingManager.pairingPIN.isEmpty {
            VStack(spacing: 6) {
                HStack {
                    Text("MÃ GHÉP ĐÔI (6 SỐ):")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.grey600)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = pairingManager.pairingPIN
                        Haptics.light()
                    } label: {
                        Label("Sao chép", systemImage: "doc.on.doc.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.statusInfo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.statusInfo.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                Text(pairingManager.pairingPIN)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(AppTheme.statusInfo)
                    .tracking(6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.statusInfo.opacity(0.28), lineWidth: 1)
                    )
            }
            .padding(8)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var wifiWarning: some View {
        if !pairingManager.isWiFiConnected {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.statusError)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LƯU Ý: CHƯA KẾT NỐI WI-FI")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(AppTheme.statusError)
                    Text("Apple chỉ hiển thị 'Pair with Astra' khi iPhone đang bật Wi-Fi (hoặc Điểm phát sóng). Nếu dùng 4G, vui lòng bật Wi-Fi.")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.grey700)
                }
            }
            .padding(8)
            .background(AppTheme.statusError.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.statusError.opacity(0.20), lineWidth: 1)
            )
        }
    }

    private var pairingInstructions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("QUY TRÌNH GHÉP ĐÔI TRÊN THIẾT BỊ (iOS 16+ / iOS 27):")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.statusInfo)
            Text("1. Đảm bảo iPhone đã bật Wi-Fi (hoặc Điểm phát sóng).")
            Text("2. Mở Cài đặt ➔ Quyền riêng tư & Bảo mật ➔ Chế độ nhà phát triển.")
            Text("3. Tại mục ghép đôi, chọn 'Pair with Astra'.")
            Text("4. Nhập mật mã máy, sau đó nhập mã 6 số ở trên vào ô yêu cầu.")
        }
        .font(.system(size: 10))
        .foregroundColor(AppTheme.grey700)
    }

    private var openDeveloperSettingsButton: some View {
        Button {
            Haptics.light()
            pairingManager.openPairingSettings()
        } label: {
            Label("Mở Cài đặt Chế độ nhà phát triển", systemImage: "arrow.up.forward.app.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.statusInfo)
                .clipShape(Capsule())
        }
    }

    private var pairingActions: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.light()
                showPairingStartAlert = true
            } label: {
                Label("Pair trên máy", systemImage: "iphone.and.arrow.forward")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.statusInfo)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.statusInfo.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.statusInfo.opacity(0.22), lineWidth: 1)
                    )
            }

            Button {
                Haptics.light()
                showDocumentPicker = true
            } label: {
                Label("Nhập .plist", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.statusInfo)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.statusInfo.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.statusInfo.opacity(0.22), lineWidth: 1)
                    )
            }

            if pairingManager.status == .ready {
                Button {
                    Haptics.light()
                    pairingManager.deletePairingFile()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.statusError)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppTheme.statusError.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.statusError.opacity(0.22), lineWidth: 1)
                        )
                }
            }
        }
    }

    private var storageEngineToggle: some View {
        Toggle(isOn: $storageCoordinator.useAirLiftForAll) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sử dụng AirLift Engine toàn bộ")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                Text("RPPairing + RSD/AFC + AirTraffic; bắt buộc canary read-back")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.grey500)
            }
        }
        .tint(AppTheme.ink)
        .disabled(!storageCoordinator.isAirTrafficEngineLinked)
    }
    
    private var tunnelStatusColor: Color {
        switch tunnelManager.status {
        case .connected:
            return AppTheme.statusSuccess
        case .connecting, .disconnecting, .checking:
            return AppTheme.statusInfo
        case .disconnected, .invalid:
            return AppTheme.statusError
        }
    }

    private var pairingStatusColor: Color {
        switch pairingManager.status {
        case .ready:
            return AppTheme.statusSuccess
        case .pairing, .waitingSettings:
            return AppTheme.statusInfo
        case .missing, .invalid:
            return AppTheme.statusError
        }
    }
}

// MARK: - Form Section (For Form-based SettingsView)

struct AirLiftSettingsSection: View {
    @StateObject private var tunnelManager = AirLiftTunnelManager.shared
    @StateObject private var pairingManager = AirLiftPairingManager.shared
    @StateObject private var storageCoordinator = StorageEngineCoordinator.shared
    @State private var showDocumentPicker = false
    
    var body: some View {
        Section {
            // 1. External LocalDevVPN
            Button {
                tunnelManager.openLocalDevVPN()
            } label: {
                HStack {
                    Text("Mở ứng dụng LocalDevVPN")
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                }
            }

            HStack {
                Text("Trạng thái LocalDevVPN")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(tunnelStatusColor)
                        .frame(width: 8, height: 8)
                    Text(tunnelManager.status.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(tunnelStatusColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await tunnelManager.verifyLoopbackService() }
            }

            HStack {
                Text("Dịch vụ thiết bị")
                Spacer()
                Text(tunnelManager.serviceStatus.rawValue)
                    .font(.caption)
                    .foregroundStyle(tunnelManager.isServiceReachable ? AppTheme.statusSuccess : AppTheme.statusError)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await tunnelManager.verifyLoopbackService() }
            }
            
            // 2. Pairing Status
            HStack {
                Text("Pairing")
                Spacer()
                Text(pairingManager.status.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(pairingStatusColor)
            }
            
            // 3. Pair trực tiếp trên iPhone
            Button {
                Task { await pairingManager.pairDirectlyOnDevice() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.statusInfo)
                        .frame(width: 24)
                    
                    Text("Pair trực tiếp trên iPhone")
                        .foregroundStyle(AppTheme.statusInfo)
                }
            }
            
            // 4. Nhập file pairing
            Button {
                showDocumentPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.statusInfo)
                        .frame(width: 24)
                    
                    Text("Nhập file pairing")
                        .foregroundStyle(AppTheme.statusInfo)
                }
            }
            
            // 5. Xoá file pairing
            if pairingManager.status == .ready {
                Button {
                    pairingManager.deletePairingFile()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(AppTheme.statusError)
                            .frame(width: 24)
                        
                        Text("Xoá file pairing")
                            .foregroundStyle(AppTheme.statusError)
                    }
                }
            }
            
            // 6. Sử dụng AirLift cho toàn bộ
            Toggle(isOn: $storageCoordinator.useAirLiftForAll) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 24)
                    
                    Text("Sử dụng AirLift cho toàn bộ")
                        .foregroundStyle(.primary)
                }
            }
            .tint(AppTheme.ink)
            .disabled(!storageCoordinator.isAirTrafficEngineLinked)
        } footer: {
            Text("Astra không còn chứa VPN tích hợp. Hãy bật ứng dụng LocalDevVPN riêng; Astra chỉ kiểm tra RSD/Lockdown và ghi qua AirTraffic sau khi canary được đọc lại chính xác.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showDocumentPicker) {
            AirLiftDocumentPicker { url in
                _ = pairingManager.importPairingFile(from: url)
            }
        }
        .alert(isPresented: $pairingManager.showAlert) {
            Alert(
                title: Text("Thông báo"),
                message: Text(pairingManager.alertMessage ?? ""),
                dismissButton: .default(Text("Đóng"))
            )
        }
    }
    
    private var tunnelStatusColor: Color {
        switch tunnelManager.status {
        case .connected:
            return AppTheme.statusSuccess
        case .connecting, .disconnecting, .checking:
            return AppTheme.statusInfo
        case .disconnected, .invalid:
            return AppTheme.statusError
        }
    }

    private var pairingStatusColor: Color {
        switch pairingManager.status {
        case .ready:
            return AppTheme.statusSuccess
        case .pairing, .waitingSettings:
            return AppTheme.statusInfo
        case .missing, .invalid:
            return AppTheme.statusError
        }
    }
}

// MARK: - Document Picker

struct AirLiftDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data, .xml], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AirLiftDocumentPicker
        init(_ parent: AirLiftDocumentPicker) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}
