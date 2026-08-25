import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var tabNavigation = AppTabNavigationState()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedSection {
                case .home:
                    PatchProjectsView()
                case .system:
                    SystemView()
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(
                selectedTab: Binding(
                    get: { tabNavigation.selectedTab },
                    set: { tabNavigation.select($0) }
                ),
                language: language
            )
        }
        .ignoresSafeArea(.keyboard)
        .tint(AppTheme.accent)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.home.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.home.rawValue) }
        }
    }

    private var selectedSection: AppSection {
        AppSection(rawValue: tabNavigation.selectedTab) ?? .home
    }
}

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    let language: AppLanguage

    private let tabs: [(AppSection, String, String)] = [
        (.home, "tab.home", "shippingbox.fill"),
        (.system, "tab.system", "gearshape.fill"),
        (.profile, "tab.profile", "person.fill")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0.id) { section, titleKey, icon in
                TabBarButton(
                    isSelected: selectedTab == section.rawValue,
                    title: language.text(titleKey),
                    icon: icon
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = section.rawValue
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }
}

private struct TabBarButton: View {
    let isSelected: Bool
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                if isSelected {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, isSelected ? 16 : 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isSelected {
                        AppTheme.accent
                            .clipShape(Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System View (Dashboard)

private struct SystemView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            List {
                deviceSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showLogs = true } label: {
                        Image(systemName: "apple.terminal")
                    }
                    .accessibilityLabel(language.text("accessibility.open_logs"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(language.text("accessibility.open_settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
        }
    }

    private var deviceSection: some View {
        Section {
            LabeledContent(language.text("dashboard.hardware_model")) {
                Text(AppInfo.displayMachineName)
                    .font(.body.monospaced())
            }
            LabeledContent(language.text("settings.ios_version")) {
                Text("\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.body.monospaced())
            }
            HStack {
                Text(language.text("settings.compatibility"))
                Spacer()
                Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                    .foregroundStyle(appState.isSupported ? Color.green : Color.red)
            }

            if appState.kernelExploitApplicable && AppInfo.versionTuple.major < 26 {
                HStack {
                    Text(language.text("dashboard.kernel_status"))
                    Spacer()
                    if appState.kernelExploitRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(language.text("dashboard.kernel_running"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(language.text(appState.exploitStatus.isSuccess ? "dashboard.kernel_active" : "dashboard.kernel_inactive"))
                            .foregroundStyle(appState.exploitStatus.isSuccess ? Color.green : Color.secondary)
                    }
                }
            }
        } header: {
            Text(language.text("common.device"))
        } footer: {
            Text(language.text("settings.supported_range_summary"))
        }
    }
}
