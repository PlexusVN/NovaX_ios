import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.vietnamese.rawValue
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var showContainerScanHistory = false
    @ObservedObject private var ios27Preparation = IOS27ContainerPreparation.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Astra").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Bản cập nhật")
                        Spacer()
                        if updateManager.isChecking {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppTheme.statusInfo)
                        } else {
                            Button("Kiểm tra") {
                                updateManager.checkForUpdate(showFeedback: true)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.statusInfo)
                        }
                    }
                    if let msg = updateManager.lastCheckedMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(updateManager.updateOffer != nil ? AppTheme.statusInfo : AppTheme.statusSuccess)
                    }
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                }

                if ExploitSupportPolicy.currentAccessProvider == .airLift {
                    AirLiftSettingsSection()
                } else {
                    Section("Cơ chế truy cập") {
                        switch ExploitSupportPolicy.currentAccessProvider {
                        case .legacy3105:
                            Text("3105 · Truy cập trực tiếp theo phiên bản iOS")
                        case .worseQuery:
                            Text("worse_query · Quyền App Group và container đã chuẩn bị")
                        case .unsupported:
                            Text(appState.unsupportedMessage ?? "Phiên bản iOS/build này chưa được hỗ trợ.")
                        case .airLift:
                            EmptyView()
                        }
                    }
                }

                if ExploitSupportPolicy.currentRequiresWorseQueryPreparation {
                    Section {
                        Button("Xem nhật ký quét thư mục") { showContainerScanHistory = true }
                        Button("Quét lại quyền truy cập game") { ios27Preparation.reset(forceScan: true) }
                    } header: {
                        Text("Quét thư mục iOS \(AppInfo.versionTuple.major)")
                    } footer: {
                        Text("Theo dõi tiến trình khi bật chức năng cần tìm thư mục game. Có thể sao chép nhật ký để gửi hỗ trợ.")
                    }
                }

                Section {
                    HStack {
                        Text(language.text("settings.current_version"))
                        Spacer()
                        Text(appState.accessLevelDescription)
                        .foregroundStyle(appState.isSupported ? AppTheme.statusSuccess : AppTheme.statusError)
                    }
                    LabeledContent("iOS 16", value: ExploitSupportPolicy.verifiedIOS16Range)
                    LabeledContent("iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range)
                    LabeledContent("iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range)
                    LabeledContent("iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS 27 · 3105 / worse_query")
                            .font(.body)
                        ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { version in
                            Text(versionLabel(version))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Phân tuyến theo phiên bản iOS")
                } footer: {
                    Text("Các khoảng này là chính sách chọn cơ chế theo source tham khảo. Quyền của bản ký và khả năng đọc/ghi trên thiết bị vẫn được kiểm tra khi thực hiện thao tác; không phải mọi build đều đã được thử trên máy thật.")
                }
            }
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showContainerScanHistory) {
                NavigationStack {
                    ContainerScanProgressView(progress: ContainerScanProgress.shared)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Xong") { showContainerScanHistory = false }
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var appVersion: String {
        AppUpdateChecker.currentVersion
    }

    private func versionLabel(_ version: ExploitSupportPolicy.VerifiedBuild) -> String {
        "\(version.label) · \(version.build)"
    }
}
