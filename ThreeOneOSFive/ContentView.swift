import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var authManager: AuthManager
    @State private var tabNavigation: AppTabNavigationState
    @State private var heartbeatTimer: Timer?
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var tabAnimationNamespace
    @State private var showLoginSuccessPopup = false
    @State private var showSystemDashboard = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-files-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-patch-tab") {
            initialTab = 2
        } else {
            initialTab = AppSection.features.rawValue
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.ink)
        .imageScale(.small)
        .sheet(isPresented: $showSystemDashboard) {
            DashboardView(showCloseButton: true, onClose: { showSystemDashboard = false })
        }
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            // Patches tab đã bị ẩn - không làm gì
            _ = requestID
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            _ = requestID
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
            startHeartbeat()
        }
        .onDisappear {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { startHeartbeat() }
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: tabSelection) {
                ForEach(featureVisibility.visibleSections) { section in
                    sectionContent(section)
                        .tag(section.rawValue)
                        .toolbar(.hidden, for: .tabBar)
                }
            }

            customFloatingTabBar
        }
    }

    private var customFloatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(featureVisibility.visibleSections) { section in
                let isSelected = section.rawValue == tabNavigation.selectedTab

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        tabNavigation.select(section.rawValue)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : AppTheme.grey500)
                        Text(language.text(section.titleKey))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(isSelected ? .white : AppTheme.grey500)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(AppTheme.ink)
                                    .matchedGeometryEffect(id: "TAB_BG", in: tabAnimationNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .highPriorityGesture(
            DragGesture()
                .onEnded { value in
                    let translation = value.translation.width
                    let sections = featureVisibility.visibleSections
                    guard let currentIndex = sections.firstIndex(where: { $0.rawValue == tabNavigation.selectedTab }) else { return }

                    if translation < -40 && currentIndex < sections.count - 1 {
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            tabNavigation.select(sections[currentIndex + 1].rawValue)
                        }
                    } else if translation > 40 && currentIndex > 0 {
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            tabNavigation.select(sections[currentIndex - 1].rawValue)
                        }
                    }
                }
        )
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.grey100
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("Astra")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            DashboardView()
        case .files:
            AppDataBrowserView(tabSession: filesTabSession)
        case .patches:
            PatchProjectsView()
        case .features:
            FeaturesView(showSystemDashboard: $showSystemDashboard)
        case .guides:
            GuidesView(showSystemDashboard: $showSystemDashboard)
        case .cleaner:
            EmptyView()
        case .wallpapers:
            EmptyView()
        case .dns:
            // DNS đã bỏ - fallback trống
            EmptyView()
        case .profile:
            ProfileView(showSystemDashboard: $showSystemDashboard)
                .environmentObject(authManager)
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(
            cleanerEnabled: false,
            wallpapersEnabled: false,
            wallpapersSupported: false
        )
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                if authManager.authState == .verified {
                    let _ = DecoyAuth.checkLicenseIntegrity(authManager.licenseKey)
                    let _ = DecoyAuth.validateHMAC(key: authManager.licenseKey, payload: authManager.hwid)
                }
            }
        }
    }

    private var selectedVisibleSection: AppSection {
        guard let section = AppSection(rawValue: tabNavigation.selectedTab),
              featureVisibility.isVisible(section) else {
            return featureVisibility.visibleSections.first ?? .features
        }
        return section
    }
}

// MARK: - Section titles & icons

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.system"
        case .files: return "tab.files"
        case .patches: return "tab.patches"
        case .features: return "tab.features"
        case .guides: return "tab.guides"
        case .cleaner: return "tab.cleaner"
        case .wallpapers: return "tab.wallpapers"
        case .dns: return "DNS"
        case .profile: return "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "gearshape.2.fill"
        case .files: return "folder.fill"
        case .patches: return "shippingbox.fill"
        case .features: return "wand.and.stars"
        case .guides: return "book.fill"
        case .cleaner: return "sparkles"
        case .wallpapers: return "photo.on.rectangle.angled"
        case .dns: return "shield.righthalf.filled"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - System Dashboard

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    var showCloseButton: Bool = false
    var onClose: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        deviceInfoPanel
                        systemInfoPanel
                        statusPanel
                        AirLiftDashboardCard()
                        appInfoPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Hệ thống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.light()
                            onClose?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.grey600)
                        }
                    }
                }
            }
            .tint(AppTheme.ink)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.ink)
                    .frame(width: 64, height: 64)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Astra")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Hệ thống & Thiết bị")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.grey500)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    // MARK: Device Info

    private var deviceInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "iphone.gen3", title: "Thiết bị")
            infoRow(label: "Model", value: AppInfo.displayMachineName, icon: "cpu")
            divider
            infoRow(label: "Tên thiết bị", value: UIDevice.current.name, icon: "person.crop.rectangle")
            divider
            infoRow(label: "Hệ điều hành", value: "iOS \(AppInfo.osVersion)", icon: "apple.logo")
            divider
            infoRow(label: "Build", value: AppInfo.osBuild, icon: "number")
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: System Info

    private var systemInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "cpu", title: "Thông số hệ thống")
            infoRow(label: "Bộ nhớ RAM", value: ramString, icon: "memorychip")
            divider
            infoRow(label: "Dung lượng", value: diskString, icon: "internaldrive")
            divider
            infoRow(label: "Pin", value: batteryString, icon: "battery.full")
            divider
            infoRow(label: "Màn hình", value: screenString, icon: "rectangle.landscape.rotate")
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: Status

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "shield.checkered", title: "Trạng thái")

            HStack {
                Image(systemName: appState.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(appState.isSupported ? AppTheme.statusSuccess : AppTheme.statusError)
                Text("Tương thích")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.grey700)
                Spacer()
                Text(appState.accessLevelDescription)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(appState.isSupported ? AppTheme.statusSuccess : AppTheme.statusError)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.grey100)
                    .clipShape(Capsule())
            }

            if appState.kernelExploitApplicable {
                divider
                HStack {
                    Image(systemName: appState.kernelExploitRunning ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            appState.kernelExploitRunning
                                ? AppTheme.statusInfo
                                : (appState.exploitStatus.isSuccess ? AppTheme.statusSuccess : AppTheme.statusError)
                        )
                    Text("Kernel Exploit")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.grey700)
                    Spacer()
                    if appState.kernelExploitRunning {
                        HStack(spacing: 6) {
                            ProgressView().tint(AppTheme.statusInfo).scaleEffect(0.7)
                            Text("Đang chạy")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.statusInfo)
                        }
                    } else {
                        Text(appState.exploitStatus.isSuccess ? "Đã kích hoạt" : "Chưa hoạt động")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(appState.exploitStatus.isSuccess ? AppTheme.statusSuccess : AppTheme.statusError)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: App Info

    private var appInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "info.circle", title: "Ứng dụng")
            infoRow(label: "Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0", icon: "tag")
            divider
            infoRow(label: "Build Number", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1", icon: "number")
            divider
            infoRow(label: "Developer", value: "Minh Khải & Sơn Dev", icon: "person.fill")
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: Helpers

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.grey200)
            .frame(height: 1)
            .padding(.leading, 32)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Spacer()
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.grey700)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.grey200, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    private var ramString: String {
        let total = ProcessInfo.processInfo.physicalMemory
        if total >= 1_073_741_824 {
            return String(format: "%.0f GB", Double(total) / 1_073_741_824)
        }
        return String(format: "%.0f MB", Double(total) / 1_048_576)
    }

    private var diskString: String {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attrs[.systemSize] as? Int64 else { return "N/A" }
        if total >= 1_073_741_824 {
            return String(format: "%.0f GB", Double(total) / 1_073_741_824)
        }
        return String(format: "%.0f MB", Double(total) / 1_048_576)
    }

    private var batteryString: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "N/A" }
        return String(format: "%.0f%%", level * 100)
    }

    private var screenString: String {
        let scale = UIScreen.main.scale
        let w = UIScreen.main.bounds.width * scale
        let h = UIScreen.main.bounds.height * scale
        return String(format: "%.0f x %.0f @%.0fx", w, h, scale)
    }
}
