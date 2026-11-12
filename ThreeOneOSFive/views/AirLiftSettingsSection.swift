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
    @StateObject private var airTrafficClient = AirTrafficProtocolClient.shared
    @State private var showDocumentPicker = false
    @State private var showPairingStartAlert = false
    @State private var isComprehensiveChecking = false
    
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
            Divider().background(AppTheme.grey200)
            realAirLiftStatusView
            Divider().background(AppTheme.grey200)
            ios27ReadinessCard
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.paperRaised)
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
        .task {
            if storageCoordinator.isAirLiftActive {
                await runComprehensiveCheck()
            }
        }
        .onChange(of: storageCoordinator.useAirLiftForAll) { isEnabled in
            if isEnabled {
                Task { await runComprehensiveCheck() }
            }
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
            Image(systemName: tunnelManager.isOperational ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(tunnelManager.isOperational ? AppTheme.statusSuccess : AppTheme.statusError)
            Text(tunnelManager.isOperational ? "Đường truyền LocalDevVPN đã sẵn sàng" : tunnelManager.serviceStatus.rawValue)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(tunnelManager.isOperational ? AppTheme.statusSuccess : AppTheme.statusError)
            Spacer()
            Button("KIỂM TRA") {
                Task {
                    await tunnelManager.verifyLoopbackService()
                    await pairingManager.verifyPairingWithDevice(silent: false)
                }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(AppTheme.statusInfo)
            .disabled(tunnelManager.status == .checking || pairingManager.status == .verifying)
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
                    Text(tunnelManager.isOperational
                         ? "VPN đã kết nối"
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(pairingStatusColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: pairingStatusIcon)
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
                if pairingManager.status.isPaired {
                    Button("XÁC MINH") {
                        Task { await pairingManager.verifyPairingWithDevice(silent: false) }
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.statusInfo)
                    .disabled(pairingManager.status == .verifying)
                }
            }

            if pairingManager.status == .revoked {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.statusError)
                    Text(pairingRecoveryMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.statusError)
                }
                .padding(8)
                .background(AppTheme.statusError.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var pairingStatusIcon: String {
        switch pairingManager.status {
        case .ready, .verified:
            return "key.fill"
        case .pairing, .waitingSettings, .verifying:
            return "arrow.triangle.2.circlepath"
        case .revoked:
            return "lock.slash.fill"
        case .missing, .invalid:
            return "lock.trianglebadge.exclamationmark"
        }
    }

    @ViewBuilder
    private var pairingGuidance: some View {
        if pairingManager.isPairingHostActive || pairingManager.isBroadcastingBonjour || pairingManager.status == .waitingSettings {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if pairingManager.isBroadcastingBonjour {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(AppTheme.statusSuccess)
                    } else {
                        ProgressView().tint(AppTheme.statusInfo).scaleEffect(0.8)
                    }
                    Text(pairingManager.bonjourStatusText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(pairingManager.isBroadcastingBonjour ? AppTheme.statusSuccess : AppTheme.statusInfo)
                    Spacer()
                }
                if pairingManager.canRetryBonjourAdvertisement {
                    Button("Phát lại thiết bị Astra") {
                        pairingManager.retryBonjourAdvertisement(userInitiated: true)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.statusInfo)
                }
                if !pairingManager.isBackgroundKeepAliveActive {
                    Text("Không thể bật giữ nền bằng âm thanh. Hãy mở nhanh Chế độ nhà phát triển; nếu Astra biến mất, quay lại app và bấm phát lại.")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.statusWarning)
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
                    .background(AppTheme.paperRaised)
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
            Text("GHÉP ĐÔI TRÊN THIẾT BỊ (CHỈ BUILD IOS 27 CÒN HỖ TRỢ):")
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
            if ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile {
                Button {
                    Haptics.light()
                    if pairingManager.isPairingHostActive {
                        pairingManager.retryBonjourAdvertisement(userInitiated: true)
                    } else {
                        showPairingStartAlert = true
                    }
                } label: {
                    Label(
                        pairingManager.isPairingHostActive ? "Phát lại Astra" : "Pair trên máy",
                        systemImage: "iphone.and.arrow.forward"
                    )
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

            if pairingManager.status.isPaired {
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
                Text(storageCoordinator.isAirLiftActive
                    ? "AirLift bắt buộc theo phiên bản iOS"
                    : "Ghi trực tiếp · Không cần AirLift")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                Text("RPPairing + RSD/AFC + AirTraffic; bắt buộc canary read-back")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.grey500)
            }
        }
        .tint(AppTheme.ink)
        .disabled(true)
    }

    private var isAirLiftFullyReady: Bool {
        storageCoordinator.isAirLiftActive &&
        tunnelManager.isOperational &&
        pairingManager.status.isPaired &&
        pairingManager.status != .revoked &&
        airTrafficClient.engineHealthState.isHealthy
    }

    private var pairingRecoveryMessage: String {
        if ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile {
            return "iPhone đã hủy ghép đôi trong Cài đặt. Bấm 'Pair trên máy' ở dưới để kết nối lại."
        }
        return "File pairing đã hết hiệu lực. Hãy tạo file pairing mới trên máy tính rồi nhập lại vào Astra."
    }

    private var realAirLiftStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.ink)

                Text("TRẠNG THÁI AIRLIFT THỰC TẾ")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(AppTheme.ink)
                    .tracking(0.5)

                Spacer()

                Button {
                    Haptics.medium()
                    airTrafficClient.resetSession()
                    Task {
                        await runComprehensiveCheck()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .bold))
                        Text("LÀM MỚI")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(AppTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.grey100)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(airLiftRealStatusColor)
                        .frame(width: 7, height: 7)
                    Text("Dịch vụ AirTraffic:")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.grey600)
                    Text(airTrafficClient.engineHealthState.message)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(airLiftRealStatusColor)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.grey500)
                    Text("Mức xác minh:")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.grey600)
                    Text(airTrafficClient.verificationLevel.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.grey600)
                        .lineLimit(1)
                }

                if !airTrafficClient.lastLogLine.isEmpty {
                    Text("Log: \(airTrafficClient.lastLogLine)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(AppTheme.grey400)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.grey200, lineWidth: 1)
            )
        }
    }

    private var ios27ReadinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isAirLiftFullyReady ? Color(hex: 0x10B981).opacity(0.18) : AppTheme.statusWarning.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: isAirLiftFullyReady ? "checkmark.seal.fill" : (storageCoordinator.isAirLiftActive ? "exclamationmark.triangle.fill" : "poweroff"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x10B981) : (storageCoordinator.isAirLiftActive ? AppTheme.statusWarning : AppTheme.grey400))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isAirLiftFullyReady ? "AIRLIFT SẴN SÀNG" : "TRẠNG THÁI GHI FILE AIRLIFT")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x065F46) : AppTheme.ink)

                        Text(isAirLiftFullyReady ? "SẴN SÀNG" : (isComprehensiveChecking ? "ĐANG KIỂM TRA" : "CHƯA SẴN SÀNG"))
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    isAirLiftFullyReady
                                    ? Color(hex: 0x10B981)
                                    : (isComprehensiveChecking ? AppTheme.statusInfo : (storageCoordinator.isAirLiftActive ? AppTheme.statusError : AppTheme.grey500))
                                )
                            )
                    }

                    Text(ios27ReadinessSummaryText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x047857) : AppTheme.grey500)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Haptics.light()
                    Task { await runComprehensiveCheck() }
                } label: {
                    if isComprehensiveChecking {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x065F46) : AppTheme.ink)
                            .padding(6)
                            .background(Circle().fill(isAirLiftFullyReady ? Color(hex: 0x10B981).opacity(0.18) : AppTheme.grey100))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isComprehensiveChecking)
            }

            VStack(alignment: .leading, spacing: 4) {
                readinessFactorRow(
                    title: "LocalDevVPN (10.7.0.1)",
                    isMet: tunnelManager.isOperational,
                    detail: tunnelManager.isOperational ? "Đã kết nối" : "Chưa bật VPN"
                )
                readinessFactorRow(
                    title: "Ghép đôi thiết bị (Pairing)",
                    isMet: pairingManager.status.isPaired && pairingManager.status != .revoked,
                    detail: pairingManager.status == .revoked ? "Đã bị hủy ghép đôi" : (pairingManager.status.isPaired ? "Hợp lệ" : "Chưa ghép đôi")
                )
                readinessFactorRow(
                    title: "AirLift Engine (AirTraffic)",
                    isMet: airTrafficClient.engineHealthState.isHealthy,
                    detail: airTrafficClient.engineHealthState.isHealthy ? "Kênh xác thực OK" : "Chưa phản hồi"
                )
                readinessFactorRow(
                    title: "Bật AirLift Engine toàn bộ",
                    isMet: storageCoordinator.isAirLiftActive,
                    detail: storageCoordinator.isAirLiftActive ? "Bắt buộc theo phiên bản iOS" : "Không cần cho phiên bản iOS này"
                )
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isAirLiftFullyReady
                    ? LinearGradient(
                        colors: [Color(hex: 0x10B981).opacity(0.14), Color(hex: 0x059669).opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [AppTheme.grey50, AppTheme.grey100],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isAirLiftFullyReady
                            ? Color(hex: 0x10B981).opacity(0.4)
                            : (storageCoordinator.isAirLiftActive ? AppTheme.statusWarning.opacity(0.35) : AppTheme.grey200),
                            lineWidth: 1
                        )
                )
        )
    }

    private func readinessFactorRow(title: String, isMet: Bool, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isMet ? Color(hex: 0x10B981) : AppTheme.statusError)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.ink)
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isMet ? Color(hex: 0x065F46) : AppTheme.grey500)
        }
    }

    private var ios27ReadinessSummaryText: String {
        if isAirLiftFullyReady {
            return "VPN + Ghép đôi + AirTraffic đã xác thực. Canary sẽ được kiểm tra lại trước mỗi lần ghi."
        }
        if isComprehensiveChecking {
            return "Đang tự động kiểm tra VPN, Ghép đôi và AirLift..."
        }
        if !storageCoordinator.isAirLiftActive {
            return "Phiên bản iOS này dùng đường ghi trực tiếp và không cần pairing AirLift."
        }
        if !tunnelManager.isOperational {
            return "Thiếu LocalDevVPN: Vui lòng mở app LocalDevVPN và bật tunnel 10.7.0.1."
        }
        if pairingManager.status == .revoked {
            return pairingRecoveryMessage
        }
        if !pairingManager.status.isPaired {
            return ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile
                ? "Thiếu Pairing: Vui lòng bấm Pair trên máy để ghép đôi thiết bị."
                : "Thiếu Pairing: Hãy tạo file pairing trên máy tính rồi nhập vào Astra."
        }
        if !airTrafficClient.engineHealthState.isHealthy {
            return "AirLift chưa phản hồi: Bấm 'LÀM MỚI' ở trên để khởi động lại session."
        }
        return "Chưa sẵn sàng: Kiểm tra lại các điều kiện bên dưới."
    }

    private var airLiftRealStatusColor: Color {
        switch airTrafficClient.engineHealthState {
        case .healthy:
            return Color(hex: 0x10B981)
        case .checking:
            return AppTheme.statusInfo
        case .error:
            return AppTheme.statusError
        case .idle:
            return AppTheme.grey400
        }
    }

    private func runComprehensiveCheck() async {
        isComprehensiveChecking = true
        defer { isComprehensiveChecking = false }
        await tunnelManager.verifyLoopbackService()
        if tunnelManager.isOperational && pairingManager.status.isPaired && pairingManager.status != .revoked {
            _ = await airTrafficClient.checkRealAirLiftHealth()
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
        case .ready, .verified:
            return AppTheme.statusSuccess
        case .pairing, .waitingSettings, .verifying:
            return AppTheme.statusInfo
        case .missing, .invalid, .revoked:
            return AppTheme.statusError
        }
    }
}
// MARK: - Form Section (For Form-based SettingsView)

struct AirLiftSettingsSection: View {
    @StateObject private var tunnelManager = AirLiftTunnelManager.shared
    @StateObject private var pairingManager = AirLiftPairingManager.shared
    @StateObject private var storageCoordinator = StorageEngineCoordinator.shared
    @StateObject private var airTrafficClient = AirTrafficProtocolClient.shared
    @State private var showDocumentPicker = false
    @State private var isComprehensiveChecking = false
    
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
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await pairingManager.verifyPairingWithDevice(silent: false) }
            }

            if pairingManager.status == .revoked {
                Text(pairingRecoveryMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.statusError)
            }
            
            // 3. Pair trực tiếp chỉ có trên các build iOS 27 còn hỗ trợ.
            if ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile {
                Button {
                    Task { await pairingManager.pairDirectlyOnDevice() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(AppTheme.statusInfo)
                            .frame(width: 24)

                        Text(pairingManager.isPairingHostActive ? "Phát lại thiết bị Astra" : "Pair trực tiếp trên iPhone")
                            .foregroundStyle(AppTheme.statusInfo)
                    }
                }
                HStack {
                    Text("Bonjour")
                    Spacer()
                    Text(pairingManager.bonjourStatusText)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(pairingManager.isBroadcastingBonjour ? AppTheme.statusSuccess : Color.secondary)
                }
            } else if ExploitSupportPolicy.currentPairingMode == .importedFile {
                Text("Phiên bản iOS này dùng AirLift nhưng không ghép trực tiếp trong Chế độ nhà phát triển. Hãy tạo pairing file bằng máy tính rồi chọn “Nhập file pairing” bên dưới. Quy tắc này áp dụng cả iOS 26.7.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            if pairingManager.status.isPaired {
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
                    
                    Text(storageCoordinator.isAirLiftActive
                        ? "AirLift bắt buộc theo phiên bản iOS"
                        : "Ghi trực tiếp · Không cần AirLift")
                        .foregroundStyle(.primary)
                }
            }
            .tint(AppTheme.ink)
            .disabled(true)

            // 7. Trạng thái AirTraffic thực tế
            realAirLiftStatusFormRow

            // 8. Nhãn sẵn sàng cho iOS 27
            airLiftReadinessFormRow
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
        .task {
            if storageCoordinator.isAirLiftActive {
                await runComprehensiveCheck()
            }
        }
        .onChange(of: storageCoordinator.useAirLiftForAll) { isEnabled in
            if isEnabled {
                Task { await runComprehensiveCheck() }
            }
        }
    }
    
    private var isAirLiftFullyReady: Bool {
        storageCoordinator.isAirLiftActive &&
        tunnelManager.isOperational &&
        pairingManager.status.isPaired &&
        pairingManager.status != .revoked &&
        airTrafficClient.engineHealthState.isHealthy
    }

    private var pairingRecoveryMessage: String {
        if ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile {
            return "iPhone đã hủy ghép đôi trong Cài đặt. Vui lòng bấm 'Pair trực tiếp trên iPhone' để ghép đôi lại."
        }
        return "File pairing đã hết hiệu lực. Hãy tạo file pairing mới trên máy tính rồi nhập lại vào Astra."
    }

    private var realAirLiftStatusFormRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dịch vụ AirTraffic thực tế")
                    .font(.subheadline.bold())
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Button {
                    Haptics.medium()
                    airTrafficClient.resetSession()
                    Task { await runComprehensiveCheck() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Làm mới")
                    }
                    .font(.caption2.bold())
                    .foregroundColor(AppTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.grey100)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(airLiftRealStatusColor)
                    .frame(width: 8, height: 8)
                Text(airTrafficClient.engineHealthState.message)
                    .font(.caption)
                    .foregroundColor(airLiftRealStatusColor)
            }

            HStack(spacing: 4) {
                Text("Mức xác minh:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(airTrafficClient.verificationLevel.rawValue)
                    .font(.caption2.bold())
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    private var airLiftReadinessFormRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isAirLiftFullyReady ? "checkmark.seal.fill" : (storageCoordinator.isAirLiftActive ? "exclamationmark.triangle.fill" : "poweroff"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x10B981) : (storageCoordinator.isAirLiftActive ? AppTheme.statusWarning : AppTheme.grey400))

                Text(isAirLiftFullyReady ? "AIRLIFT SẴN SÀNG ĐỂ INJECT" : "TRẠNG THÁI GHI FILE AIRLIFT")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x065F46) : AppTheme.ink)

                Spacer()

                Text(isAirLiftFullyReady ? "SẴN SÀNG" : (isComprehensiveChecking ? "ĐANG KIỂM TRA" : "CHƯA SẴN SÀNG"))
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            isAirLiftFullyReady
                            ? Color(hex: 0x10B981)
                            : (isComprehensiveChecking ? AppTheme.statusInfo : (storageCoordinator.isAirLiftActive ? AppTheme.statusError : AppTheme.grey500))
                        )
                    )
            }

            Text(ios27ReadinessSummaryText)
                .font(.caption)
                .foregroundColor(isAirLiftFullyReady ? Color(hex: 0x047857) : .secondary)

            HStack(spacing: 12) {
                factorIcon(title: "VPN", isMet: tunnelManager.isOperational)
                factorIcon(title: "Pairing", isMet: pairingManager.status.isPaired && pairingManager.status != .revoked)
                factorIcon(title: "AirTraffic", isMet: airTrafficClient.engineHealthState.isHealthy)
                factorIcon(title: "AirLift theo iOS", isMet: storageCoordinator.isAirLiftActive)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isAirLiftFullyReady
                    ? Color(hex: 0x10B981).opacity(0.12)
                    : (storageCoordinator.isAirLiftActive ? AppTheme.statusWarning.opacity(0.08) : AppTheme.grey100.opacity(0.5))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isAirLiftFullyReady
                    ? Color(hex: 0x10B981).opacity(0.35)
                    : (storageCoordinator.isAirLiftActive ? AppTheme.statusWarning.opacity(0.25) : AppTheme.grey200),
                    lineWidth: 1
                )
        )
        .padding(.vertical, 4)
    }

    private func factorIcon(title: String, isMet: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isMet ? Color(hex: 0x10B981) : AppTheme.statusError)
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.ink)
        }
    }

    private var ios27ReadinessSummaryText: String {
        if isAirLiftFullyReady {
            return "VPN + Ghép đôi + AirTraffic đã xác thực. Canary sẽ được kiểm tra lại trước mỗi lần ghi."
        }
        if isComprehensiveChecking {
            return "Đang tự động kiểm tra VPN, Ghép đôi và AirLift..."
        }
        if !storageCoordinator.isAirLiftActive {
            return "Phiên bản iOS này dùng đường ghi trực tiếp và không cần pairing AirLift."
        }
        if !tunnelManager.isOperational {
            return "Thiếu LocalDevVPN: Vui lòng mở app LocalDevVPN và bật tunnel 10.7.0.1."
        }
        if pairingManager.status == .revoked {
            return pairingRecoveryMessage
        }
        if !pairingManager.status.isPaired {
            return ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile
                ? "Thiếu Pairing: Vui lòng bấm Pair trên máy để ghép đôi thiết bị."
                : "Thiếu Pairing: Hãy tạo file pairing trên máy tính rồi nhập vào Astra."
        }
        if !airTrafficClient.engineHealthState.isHealthy {
            return "AirLift chưa phản hồi: Bấm 'LÀM MỚI' ở trên để khởi động lại session."
        }
        return "Chưa sẵn sàng: Kiểm tra lại các điều kiện bên dưới."
    }

    private var airLiftRealStatusColor: Color {
        switch airTrafficClient.engineHealthState {
        case .healthy:
            return Color(hex: 0x10B981)
        case .checking:
            return AppTheme.statusInfo
        case .error:
            return AppTheme.statusError
        case .idle:
            return AppTheme.grey400
        }
    }

    private func runComprehensiveCheck() async {
        isComprehensiveChecking = true
        defer { isComprehensiveChecking = false }
        await tunnelManager.verifyLoopbackService()
        if tunnelManager.isOperational && pairingManager.status.isPaired && pairingManager.status != .revoked {
            _ = await airTrafficClient.checkRealAirLiftHealth()
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
        case .ready, .verified:
            return AppTheme.statusSuccess
        case .pairing, .waitingSettings, .verifying:
            return AppTheme.statusInfo
        case .missing, .invalid, .revoked:
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

// MARK: - AirLift Gatekeeper Manager (Dành cho iOS 27 & thiết bị cần AirLift)

@MainActor
final class AirLiftGatekeeperManager: ObservableObject {
    static let shared = AirLiftGatekeeperManager()

    private let setupCompletedKey = "airlift_ios27_setup_completed"
    private let setupCompletedKeychainKey = "novax.airlift.setupCompleted.v1"
    private let requireRePairKey = "airlift_ios27_require_repair"
    private let rePairReasonKey = "airlift_ios27_repair_reason"

    @Published var isSetupCompleted: Bool {
        didSet {
            UserDefaults.standard.set(isSetupCompleted, forKey: setupCompletedKey)
            if isSetupCompleted {
                _ = KeychainUtils.save(key: setupCompletedKeychainKey, value: "1")
            } else {
                KeychainUtils.delete(key: setupCompletedKeychainKey)
            }
        }
    }

    @Published var requiresRePair: Bool {
        didSet {
            UserDefaults.standard.set(requiresRePair, forKey: requireRePairKey)
        }
    }

    @Published var rePairReason: String? {
        didSet {
            UserDefaults.standard.set(rePairReason, forKey: rePairReasonKey)
        }
    }

    var requiresPairingForCurrentDevice: Bool {
        // Cả iOS 27 (.onDeviceOrImportedFile) và iOS 18.7.2 - 18.10 (.importedFile)
        // đều sử dụng AirLift để patch file và yêu cầu ghép đôi / nhập file pairing.
        ExploitSupportPolicy.currentStorageMode == .airLift
    }

    var isAirLiftFullyReady: Bool {
        AirLiftTunnelManager.shared.isOperational &&
        AirLiftPairingManager.shared.status.isPaired &&
        AirLiftPairingManager.shared.status != .revoked &&
        (AirTrafficProtocolClient.shared.engineHealthState.isHealthy || AirLiftPairingManager.shared.hasUsablePersistedPairingRecord)
    }

    var canBypassGatekeeper: Bool {
        // Chỉ các build hỗ trợ ghép đôi trực tiếp mới yêu cầu Gatekeeper.
        guard requiresPairingForCurrentDevice else { return true }

        // Cờ hoàn tất không được phép đứng một mình: pairing file bên dưới
        // cũng phải còn tồn tại, đúng cấu trúc và chưa bị thu hồi.
        return isSetupCompleted &&
            !requiresRePair &&
            AirLiftPairingManager.shared.hasUsablePersistedPairingRecord
    }

    private init() {
        let persistedRequiresRePair = UserDefaults.standard.bool(forKey: requireRePairKey)
        let persistedReason = UserDefaults.standard.string(forKey: rePairReasonKey)
        let persistedCompletion = (UserDefaults.standard.bool(forKey: setupCompletedKey)
            || KeychainUtils.read(key: setupCompletedKeychainKey) == "1"
        ) && !persistedRequiresRePair

        self.isSetupCompleted = persistedCompletion
        self.requiresRePair = persistedRequiresRePair
        self.rePairReason = persistedRequiresRePair ? persistedReason : nil

        if persistedRequiresRePair {
            UserDefaults.standard.set(false, forKey: setupCompletedKey)
            KeychainUtils.delete(key: setupCompletedKeychainKey)
        } else if persistedCompletion {
            UserDefaults.standard.set(true, forKey: setupCompletedKey)
            _ = KeychainUtils.save(key: setupCompletedKeychainKey, value: "1")
        }
    }

    @discardableResult
    func markSetupCompleted() -> Bool {
        guard isAirLiftFullyReady,
              AirLiftPairingManager.shared.hasUsablePersistedPairingRecord else {
            log("airlift gatekeeper: refused setup completion because readiness or pairing persistence is missing")
            return false
        }

        let backupSaved = AirLiftPairingManager.shared.backupPairingFileToKeychainIfValid()
        if !backupSaved {
            // The protected Application Support copy is still authoritative
            // for this installation; Keychain is a recovery layer for relaunch.
            log("airlift gatekeeper: pairing record is valid but Keychain recovery backup could not be refreshed")
        }

        isSetupCompleted = true
        requiresRePair = false
        rePairReason = nil
        UserDefaults.standard.set(true, forKey: setupCompletedKey)
        UserDefaults.standard.set(false, forKey: requireRePairKey)
        UserDefaults.standard.removeObject(forKey: rePairReasonKey)
        _ = KeychainUtils.save(key: setupCompletedKeychainKey, value: "1")
        return true
    }

    func triggerRePair(reason: String) {
        // Chỉ trigger re-pair nếu người dùng thực sự xóa hoặc huỷ pairing file
        if !AirLiftPairingManager.shared.status.isPaired && AirLiftPairingManager.shared.getPairingData() == nil {
            isSetupCompleted = false
            requiresRePair = true
            rePairReason = reason
            UserDefaults.standard.set(true, forKey: requireRePairKey)
            UserDefaults.standard.set(reason, forKey: rePairReasonKey)
        }
    }

    func resetGatekeeper() {
        isSetupCompleted = false
        requiresRePair = false
        rePairReason = nil
        UserDefaults.standard.removeObject(forKey: setupCompletedKey)
        UserDefaults.standard.removeObject(forKey: requireRePairKey)
        UserDefaults.standard.removeObject(forKey: rePairReasonKey)
        KeychainUtils.delete(key: setupCompletedKeychainKey)
    }
}

// MARK: - Dedicated iOS 27 AirLift & Pairing Setup View

struct IOS27PairingSetupView: View {
    @ObservedObject var auth: AuthManager
    var onComplete: () -> Void

    @StateObject private var gatekeeper = AirLiftGatekeeperManager.shared
    @StateObject private var tunnelManager = AirLiftTunnelManager.shared
    @StateObject private var pairingManager = AirLiftPairingManager.shared
    @StateObject private var airTrafficClient = AirTrafficProtocolClient.shared
    @StateObject private var storageCoordinator = StorageEngineCoordinator.shared

    @State private var showDocumentPicker = false
    @State private var showPairingStartAlert = false
    @State private var isComprehensiveChecking = false

    var isStep1Done: Bool { tunnelManager.isOperational }
    var isStep2Done: Bool { pairingManager.status.isPaired && pairingManager.status != .revoked }
    var isStep3Done: Bool { airTrafficClient.engineHealthState.isHealthy || pairingManager.status == .verified }
    var isReadyToProceed: Bool {
        isStep1Done && isStep2Done && isStep3Done && !isComprehensiveChecking
    }

    var completedStepsCount: Int {
        (isStep1Done ? 1 : 0) + (isStep2Done ? 1 : 0) + (isStep3Done ? 1 : 0)
    }

    var body: some View {
        ZStack {
            GamingBackdrop()

            ScrollView {
                VStack(spacing: 14) {
                    headerSection
                        .padding(.top, 14)

                    if gatekeeper.requiresRePair, let reason = gatekeeper.rePairReason, !reason.isEmpty {
                        rePairNoticeCard(reason: reason)
                    }

                    overallProgressCard

                    vpnStepCard

                    pairingStepCard

                    airTrafficStepCard

                    actionButtonsSection
                        .padding(.top, 4)
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 16)
            }
        }
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
            Text("Mở Cài đặt › Quyền riêng tư & Bảo mật › Chế độ nhà phát triển, chọn ghép đôi với Astra rồi nhập mã PIN hiển thị.")
        }
        .task {
            await runComprehensiveCheck()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 14) {
            AppLogo(size: 54)

            VStack(alignment: .leading, spacing: 6) {
                Text("Thiết lập AirLift")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.gamingText)

                HStack(spacing: 5) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 10, weight: .semibold))
                    Text(ExploitSupportPolicy.currentPairingMode == .none
                        ? "KHÔNG CẦN GHÉP NỐI"
                        : (ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile ? "BẮT BUỘC TRÊN IOS 27 (DỰ PHÒNG)" : "BẮT BUỘC TRÊN IOS 18.7.2+ / 26.7.3+"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.45)
                }
                .foregroundColor(AppTheme.gamingBlueBright)

                Text(ExploitSupportPolicy.currentPairingMode == .none
                    ? "Astra dùng cơ chế truy cập trực tiếp phù hợp với phiên bản iOS. Bạn không cần file pairing cho cơ chế này."
                    : (ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile
                        ? "Hoàn thành một lần để Astra có thể sử dụng kết nối an toàn khi áp dụng chức năng."
                        : "Nhập file pairing trích xuất từ máy tính để Astra có thể patch file qua AirLift."))
                    .font(.system(size: 11.5))
                    .foregroundColor(AppTheme.gamingTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppTheme.gamingSurface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.gamingBorderGradient, lineWidth: 1)
        )
    }

    // MARK: - Re-Pair Notice
    private func rePairNoticeCard(reason _: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.statusError)

            VStack(alignment: .leading, spacing: 4) {
                Text("CẦN THIẾT LẬP LẠI")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.statusError)
                Text("Quyền ghép đôi không còn hợp lệ.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(AppTheme.gamingText)
                Text("Hoàn thành lại ba bước bên dưới để tiếp tục.")
                    .font(.system(size: 10.5))
                    .foregroundColor(AppTheme.gamingTextSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppTheme.statusError.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.statusError.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Progress Card
    private var overallProgressCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TIẾN ĐỘ THIẾT LẬP")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(AppTheme.gamingTextSecondary)
                Spacer()
                Text("\(completedStepsCount)/3 BƯỚC SẴN SÀNG")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isReadyToProceed ? AppTheme.statusSuccess : AppTheme.statusInfo)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.gamingSurfaceRaised)
                        .frame(height: 6)

                    Capsule()
                        .fill(isReadyToProceed ? LinearGradient(colors: [AppTheme.statusSuccess, Color(hex: 0x10B981)], startPoint: .leading, endPoint: .trailing) : AppTheme.gamingAccentGradient)
                        .frame(width: max(0, min(geo.size.width * CGFloat(completedStepsCount) / 3.0, geo.size.width)), height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: completedStepsCount)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(AppTheme.gamingSurface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.gamingBorder.opacity(0.85), lineWidth: 1))
    }

    // MARK: - Step 1: LocalDevVPN
    private var vpnStepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isStep1Done ? AppTheme.statusSuccess.opacity(0.18) : AppTheme.statusError.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: isStep1Done ? "checkmark" : "1.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isStep1Done ? AppTheme.statusSuccess : AppTheme.ink)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("BƯỚC 1 · KẾT NỐI LOCALDEVVPN")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(AppTheme.gamingText)
                    Text("Bật đường truyền cục bộ trên thiết bị")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.gamingTextSecondary)
                }
                Spacer()

                Text(isStep1Done ? "ONLINE" : "OFFLINE")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(isStep1Done ? AppTheme.statusSuccess : AppTheme.statusError)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((isStep1Done ? AppTheme.statusSuccess : AppTheme.statusError).opacity(0.13)))
                    .overlay(Capsule().stroke((isStep1Done ? AppTheme.statusSuccess : AppTheme.statusError).opacity(0.3), lineWidth: 1))
            }

            Text("Mở LocalDevVPN, bật kết nối rồi quay lại Astra để kiểm tra trạng thái.")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.gamingTextSecondary)

            HStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    tunnelManager.openLocalDevVPN()
                } label: {
                    Label("Mở LocalDevVPN", systemImage: "arrow.up.forward.app.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.gamingAccentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    Haptics.light()
                    Task { await tunnelManager.verifyLoopbackService() }
                } label: {
                    Label("Kiểm tra lại", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.gamingText)
                        .frame(width: 126)
                        .padding(.vertical, 10)
                        .background(AppTheme.gamingSurfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.gamingViolet.opacity(0.28), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(AppTheme.gamingSurface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isStep1Done ? AppTheme.statusSuccess.opacity(0.4) : AppTheme.gamingBorder.opacity(0.9), lineWidth: 1))
    }

    // MARK: - Step 2: Pairing
    private var pairingStepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isStep2Done ? AppTheme.statusSuccess.opacity(0.18) : AppTheme.statusError.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: isStep2Done ? "checkmark" : "2.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isStep2Done ? AppTheme.statusSuccess : AppTheme.ink)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("BƯỚC 2 · GHÉP ĐÔI THIẾT BỊ")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(AppTheme.gamingText)
                    Text("Lưu quyền truy cập an toàn trên thiết bị")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.gamingTextSecondary)
                }
                Spacer()

                Text(pairingManager.status.rawValue)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(isStep2Done ? AppTheme.statusSuccess : AppTheme.statusError)
                    .lineLimit(1)
            }

            if pairingManager.isPairingHostActive {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.statusInfo)
                        Text("ĐANG CHỜ GHÉP ĐÔI...")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.statusInfo)
                        Spacer()
                    }

                    if !pairingManager.pairingPIN.isEmpty {
                        VStack(spacing: 4) {
                            Text("MÃ PIN GHÉP ĐÔI")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.grey500)
                            Text(pairingManager.pairingPIN)
                                .font(.system(size: 32, weight: .black, design: .monospaced))
                                .foregroundColor(AppTheme.gamingBlueBright)
                                .tracking(6)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(AppTheme.gamingBackgroundRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.gamingBlueBright.opacity(0.4), lineWidth: 1.5))
                        }
                    }

                    if ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Mở Cài đặt › Quyền riêng tư & Bảo mật › Chế độ nhà phát triển.")
                            Text("2. Chọn Astra trong danh sách ghép đôi.")
                            Text("3. Nhập mã PIN đang hiển thị.")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.gamingTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.gamingBackgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Kết nối iPhone với máy tính qua USB hoặc Wi-Fi.")
                            Text("2. Trích xuất file pairing (.plist) từ máy tính.")
                            Text("3. Bấm 'Nhập file pair' bên dưới để lưu vào Astra.")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.gamingTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.gamingBackgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(12)
                .background(AppTheme.statusInfo.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.statusInfo.opacity(0.2), lineWidth: 1))
            }

            HStack(spacing: 10) {
                if ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile {
                    Button {
                        Haptics.medium()
                        if pairingManager.isPairingHostActive {
                            pairingManager.retryBonjourAdvertisement(userInitiated: true)
                        } else {
                            showPairingStartAlert = true
                        }
                    } label: {
                        Label(
                            pairingManager.isPairingHostActive ? "Phát lại Astra" : "Pair trên máy",
                            systemImage: "iphone.and.arrow.forward"
                        )
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.gamingAccentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Button {
                    Haptics.light()
                    showDocumentPicker = true
                } label: {
                    Label("Nhập file pair", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.gamingText)
                        .frame(maxWidth: ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile ? 126 : .infinity)
                        .padding(.vertical, 10)
                        .background(ExploitSupportPolicy.currentPairingMode == .onDeviceOrImportedFile ? AnyView(AppTheme.gamingSurfaceRaised) : AnyView(AppTheme.gamingAccentGradient))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.gamingViolet.opacity(0.28), lineWidth: 1))
                }

                if isStep2Done {
                    Button {
                        Haptics.light()
                        pairingManager.deletePairingFile()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.statusError)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppTheme.statusError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.statusError.opacity(0.3), lineWidth: 1))
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.gamingSurface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isStep2Done ? AppTheme.statusSuccess.opacity(0.4) : AppTheme.gamingBorder.opacity(0.9), lineWidth: 1))
    }

    // MARK: - Step 3: AirTraffic & Canary
    private var airTrafficStepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isStep3Done ? AppTheme.statusSuccess.opacity(0.18) : AppTheme.statusError.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: isStep3Done ? "checkmark" : "3.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isStep3Done ? AppTheme.statusSuccess : AppTheme.ink)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("BƯỚC 3 · XÁC MINH KẾT NỐI")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(AppTheme.gamingText)
                    Text("Kiểm tra trạng thái trước khi sử dụng")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.gamingTextSecondary)
                }
                Spacer()

                Text(isStep3Done ? "SẴN SÀNG" : "CHƯA SẴN SÀNG")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(isStep3Done ? AppTheme.statusSuccess : AppTheme.statusError)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(isStep3Done ? AppTheme.statusSuccess : AppTheme.statusError)
                    .frame(width: 7, height: 7)
                Text(step3StatusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.gamingTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.gamingBackgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Haptics.medium()
                Task { await runComprehensiveCheck() }
            } label: {
                HStack(spacing: 6) {
                    if isComprehensiveChecking {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text(isComprehensiveChecking ? "Đang kiểm tra..." : "Kiểm tra kết nối")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppTheme.gamingAccentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isComprehensiveChecking)
        }
        .padding(16)
        .background(AppTheme.gamingSurface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isStep3Done ? AppTheme.statusSuccess.opacity(0.4) : AppTheme.gamingBorder.opacity(0.9), lineWidth: 1))
    }

    private var step3StatusMessage: String {
        if isStep3Done { return "Kết nối an toàn đã sẵn sàng để sử dụng." }
        if isComprehensiveChecking { return "Astra đang xác minh kết nối an toàn..." }
        if case .error(let msg) = airTrafficClient.engineHealthState {
            return msg
        }
        if !isStep1Done || !isStep2Done { return "Hoàn thành hai bước đầu trước khi kiểm tra." }
        return "Nhấn kiểm tra để hoàn tất thiết lập."
    }

    // MARK: - Action Buttons
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                guard gatekeeper.markSetupCompleted() else {
                    Haptics.medium()
                    return
                }
                Haptics.success()
                onComplete()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isReadyToProceed ? "arrow.right.circle.fill" : "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(isReadyToProceed ? "TIẾP TỤC VÀO ASTRA" : "HOÀN THÀNH 3 BƯỚC ĐỂ TIẾP TỤC")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.3)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    isReadyToProceed
                    ? AnyView(AppTheme.gamingAccentGradient)
                    : AnyView(AppTheme.gamingSurfaceRaised)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isReadyToProceed ? Color.white.opacity(0.12) : AppTheme.gamingBorder.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: isReadyToProceed ? AppTheme.gamingViolet.opacity(0.25) : Color.clear, radius: 12, y: 5)
            }
            .disabled(!isReadyToProceed)

            Button {
                Haptics.light()
                auth.logout()
            } label: {
                Text("Đăng xuất key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.grey500)
                    .padding(.vertical, 6)
            }
        }
    }

    private func runComprehensiveCheck() async {
        guard !isComprehensiveChecking, !airTrafficClient.isBusy else { return }
        isComprehensiveChecking = true
        defer { isComprehensiveChecking = false }
        await tunnelManager.verifyLoopbackService()
        if tunnelManager.isOperational && pairingManager.status.isPaired && pairingManager.status != .revoked {
            _ = await airTrafficClient.checkRealAirLiftHealth()
        }
    }
}
