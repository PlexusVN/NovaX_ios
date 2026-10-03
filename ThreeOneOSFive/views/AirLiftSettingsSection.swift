//
//  AirLiftSettingsSection.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  UI Section matching the native AirLift & Loopback configuration view.
//

import SwiftUI
import UniformTypeIdentifiers

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
