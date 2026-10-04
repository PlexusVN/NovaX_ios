//
//  AirLiftSettingsSection.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.cyberCyan)
                    .shadow(color: AppTheme.cyberCyan.opacity(0.4), radius: 4)
                
                Text("AIRLIFT ENGINE (iOS 15 - 27)")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(0.5)
                
                Spacer()
                
                Text(tunnelManager.status == .connected ? "ONLINE" : "OFFLINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(tunnelManager.status == .connected ? AppTheme.cyberCyan : .white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((tunnelManager.status == .connected ? AppTheme.cyberCyan : Color.white).opacity(0.12))
                    )
            }
            
            Divider().background(Color.white.opacity(0.06))
            
            // 1. LocalDevVPN Loopback Tunnel Status & Toggle
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
                        Text("NovaX VPN devoloper")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("10.7.1.1")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.cyberCyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.cyberCyan.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tunnelStatusColor)
                            .frame(width: 6, height: 6)
                        Text(tunnelManager.status.rawValue)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(tunnelStatusColor)
                    }
                }
                
                Spacer()
                
                Button {
                    Haptics.medium()
                    Task { await tunnelManager.toggleTunnel() }
                } label: {
                    HStack(spacing: 5) {
                        if tunnelManager.status == .connecting || tunnelManager.status == .disconnecting || tunnelManager.status == .checking {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: tunnelManager.status == .connected ? "power" : "bolt.fill")
                                .font(.system(size: 11, weight: .black))
                        }
                        Text(tunnelManager.status == .connected ? "TẮT VPN" : "BẬT VPN")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        tunnelManager.status == .connected
                            ? LinearGradient(colors: [Color.red.opacity(0.85), Color.red], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [AppTheme.cyberCyan, Color(hex: 0x0088FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: (tunnelManager.status == .connected ? Color.red : AppTheme.cyberCyan).opacity(0.4), radius: 8)
                }
            }
            
            Divider().background(Color.white.opacity(0.06))
            
            // 2. Pairing Status & Action Buttons
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((pairingManager.status == .ready ? Color.green : Color.orange).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: pairingManager.status == .ready ? "key.fill" : "lock.trianglebadge.exclamationmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(pairingManager.status == .ready ? Color.green : Color.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AirTraffic Pairing")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(pairingManager.status.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(pairingManager.status == .ready ? Color.green : Color.orange)
                }
                
                Spacer()
            }
            
            // Bonjour Pairing waiting guidance
            if pairingManager.isBroadcastingBonjour || pairingManager.status == .waitingSettings {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(AppTheme.cyberCyan)
                            .scaleEffect(0.8)
                        Text("Đang phát sóng ngầm...")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.cyberCyan)
                    }
                    
                    Text("Chế độ chạy ngầm đã kích hoạt. Vào Cài đặt ➔ Quyền riêng tư & Bảo mật ➔ Chế độ nhà phát triển ➔ Đợi 2-3 giây tại mục 'Các thiết bị khác' và bấm \"Pair with NOVAX PROXY\".")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Button {
                        Haptics.light()
                        pairingManager.openPairingSettings()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 10))
                            Text("Mở Cài đặt ghép đôi")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.cyberCyan)
                        .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(AppTheme.cyberCyan.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.cyberCyan.opacity(0.25), lineWidth: 1))
            }
            
            // Pairing buttons
            HStack(spacing: 8) {
                Button {
                    Haptics.light()
                    Task { await pairingManager.pairDirectlyOnDevice() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 10, weight: .bold))
                        Text("Pair trên máy")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(AppTheme.cyberCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.cyberCyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppTheme.cyberCyan.opacity(0.3), lineWidth: 1))
                }
                
                Button {
                    Haptics.light()
                    showDocumentPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("Nhập .plist")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                
                if pairingManager.status == .ready {
                    Button {
                        Haptics.light()
                        pairingManager.deletePairingFile()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.06))
            
            // 3. Storage Engine Switch
            Toggle(isOn: $storageCoordinator.useAirLiftForAll) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sử dụng AirLift Engine toàn bộ")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Hỗ trợ ghi file, patch game iOS 27 không cần Jailbreak")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .tint(AppTheme.cyberCyan)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.55))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.cyberCyan.opacity(0.35), AppTheme.cyberPurple.opacity(0.2), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: AppTheme.cyberCyan.opacity(0.1), radius: 20, y: 10)
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
    }
    
    private var tunnelStatusColor: Color {
        switch tunnelManager.status {
        case .connected:
            return AppTheme.cyberCyan
        case .connecting, .disconnecting:
            return .yellow
        case .disconnected, .invalid:
            return .red.opacity(0.8)
        case .checking:
            return .gray
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
            // 1. Kết nối tunnel
            HStack {
                Text("Kết nối tunnel")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(tunnelStatusColor)
                        .frame(width: 8, height: 8)
                    Text(tunnelManager.status.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await tunnelManager.toggleTunnel() }
            }
            
            // 2. Pairing Status
            HStack {
                Text("Pairing")
                Spacer()
                Text(pairingManager.status.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(pairingManager.status == .ready ? Color.green : Color.orange)
            }
            
            // 3. Pair trực tiếp trên iPhone
            Button {
                Task { await pairingManager.pairDirectlyOnDevice() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.82, green: 0.45, blue: 0.32))
                        .frame(width: 24)
                    
                    Text("Pair trực tiếp trên iPhone")
                        .foregroundStyle(Color(red: 0.82, green: 0.45, blue: 0.32))
                }
            }
            
            // 4. Nhập file pairing
            Button {
                showDocumentPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.82, green: 0.45, blue: 0.32))
                        .frame(width: 24)
                    
                    Text("Nhập file pairing")
                        .foregroundStyle(Color(red: 0.82, green: 0.45, blue: 0.32))
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
                            .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.30))
                            .frame(width: 24)
                        
                        Text("Xoá file pairing")
                            .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.30))
                    }
                }
            }
            
            // 6. Sử dụng AirLift cho toàn bộ
            Toggle(isOn: $storageCoordinator.useAirLiftForAll) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.82, green: 0.45, blue: 0.32))
                        .frame(width: 24)
                    
                    Text("Sử dụng AirLift cho toàn bộ")
                        .foregroundStyle(.primary)
                }
            }
            .tint(Color(red: 0.88, green: 0.55, blue: 0.42))
        } footer: {
            Text("Sau khi pairing và tunnel hoạt động, bật mục này để danh sách ứng dụng, App Group, đọc/ghi tệp, hình nền, Dialer và patch đều sử dụng AirLift. Tắt để quay lại phương thức trực tiếp / kernel exploit.")
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
            return .green
        case .connecting, .disconnecting:
            return .yellow
        case .disconnected, .invalid:
            return .red
        case .checking:
            return .gray
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

