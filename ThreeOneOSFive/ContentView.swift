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
            initialTab = 0
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
        .tint(AppTheme.accent)
        .imageScale(.small)
        .sheet(isPresented: $showSystemDashboard) {
            DashboardView(showCloseButton: true, onClose: { showSystemDashboard = false })
        }
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.patches.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.patches.rawValue) }
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
            startHeartbeat()
            showLoginSuccessPopup = true
        }
        .onDisappear {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { startHeartbeat() }
        }
        .overlay {
            loginSuccessPopup
        }
    }

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
                    tabNavigation.select(section.rawValue)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? AppTheme.cyberCyan : .white.opacity(0.45))
                            .frame(height: 20)
                            .shadow(color: isSelected ? AppTheme.cyberCyan.opacity(0.6) : .clear, radius: 8)
                        
                        Text(language.text(section.titleKey))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? AppTheme.cyberCyan : .white.opacity(0.45))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.cyberCyan.opacity(0.22), AppTheme.cyberPurple.opacity(0.22)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(AppTheme.cyberCyan.opacity(0.4), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "TAB_BG", in: tabAnimationNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: tabNavigation.selectedTab)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppTheme.cyberOLED.opacity(0.8))
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.cyberCyan.opacity(0.45), AppTheme.cyberPurple.opacity(0.25), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AppTheme.cyberCyan.opacity(0.12), radius: 20, y: 10)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .highPriorityGesture(
            DragGesture()
                .onEnded { value in
                    let translation = value.translation.width
                    let sections = featureVisibility.visibleSections
                    guard let currentIndex = sections.firstIndex(where: { $0.rawValue == tabNavigation.selectedTab }) else { return }
                    
                    if translation < -40 && currentIndex < sections.count - 1 {
                        Haptics.light()
                        tabNavigation.select(sections[currentIndex + 1].rawValue)
                    } else if translation > 40 && currentIndex > 0 {
                        Haptics.light()
                        tabNavigation.select(sections[currentIndex - 1].rawValue)
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
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("NovaX")
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
            AppDataBrowserView(
                tabSession: filesTabSession
            )
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
            DNSManagerView(showSystemDashboard: $showSystemDashboard)
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

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

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

extension ContentView {
    // MARK: - Login Success Popup
    
    @ViewBuilder
    private var loginSuccessPopup: some View {
        if showLoginSuccessPopup {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showLoginSuccessPopup = false
                        }
                    }
                
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [AppTheme.cyberCyan.opacity(0.3), AppTheme.cyberPurple.opacity(0.15), Color.clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 50
                                )
                            )
                            .frame(width: 100, height: 100)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.cyberGradient)
                            .shadow(color: AppTheme.cyberCyan.opacity(0.6), radius: 15)
                    }
                        
                    VStack(spacing: 8) {
                        Text("Đăng Nhập Thành Công")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            
                        Text("Hệ thống đã sẵn sàng hoạt động")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("License Key")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text(authManager.licenseKey.isEmpty ? "N/A" : String(authManager.licenseKey.prefix(12)) + "...")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        HStack {
                            Text("Thời hạn")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text(getRemainingTime(from: authManager.expiresAt))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppTheme.cyberCyan)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            )
                    )
                    
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showLoginSuccessPopup = false
                        }
                    } label: {
                        Text("Bắt đầu ngay")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(CyberGlowButtonStyle(cornerRadius: 14))
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.cyberSurface.opacity(0.85))
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.2)
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            .zIndex(100)
        }
    }
    
    private func getRemainingTime(from date: Date?) -> String {
        guard let date = date else { return "Vĩnh viễn" }
        let now = Date()
        if date < now { return "Đã hết hạn" }
        
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: date)
        if let days = components.day, days > 0 {
            return "\(days) ngày \(components.hour ?? 0) giờ"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) giờ \(components.minute ?? 0) phút"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes) phút"
        } else {
            return "Dưới 1 phút"
        }
    }
}

private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    var showCloseButton: Bool = false
    var onClose: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()

                ScrollView {
                    VStack(spacing: 20) {
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
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .tint(AppTheme.accent)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.cyberCyan.opacity(0.2), AppTheme.cyberPurple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppTheme.cyberGradient)
            }
            .shadow(color: AppTheme.cyberCyan.opacity(0.4), radius: 20)

            VStack(spacing: 4) {
                Text("NovaX")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Hệ thống & Thiết bị")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.cyberCyan.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.2)
                )
                .shadow(color: AppTheme.cyberCyan.opacity(0.12), radius: 24, y: 4)
        )
    }

    // MARK: - Device Info

    private var deviceInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "iphone.gen3", title: "Thiết bị")

            infoRow(label: "Model", value: AppInfo.displayMachineName, icon: "cpu")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Tên thiết bị", value: UIDevice.current.name, icon: "person.crop.rectangle")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Hệ điều hành", value: "iOS \(AppInfo.osVersion)", icon: "apple.logo")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Build", value: AppInfo.osBuild, icon: "number")
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - System Info

    private var systemInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "cpu", title: "Thông số hệ thống")

            infoRow(label: "Bộ nhớ RAM", value: ramString, icon: "memorychip")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Dung lượng", value: diskString, icon: "internaldrive")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: " pin", value: batteryString, icon: "battery.full")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Màn hình", value: screenString, icon: "rectangle.landscape.rotate")
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "shield.checkered", title: "Trạng thái")

            HStack {
                Image(systemName: appState.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(appState.isSupported ? AppTheme.cyberCyan : .red.opacity(0.8))
                Text("Tương thích")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(appState.accessLevelDescription)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(appState.isSupported ? AppTheme.cyberCyan : .red.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill((appState.isSupported ? AppTheme.cyberCyan : .red).opacity(0.12))
                    )
            }

            if appState.kernelExploitApplicable {
                Divider().background(Color.white.opacity(0.06))
                HStack {
                    Image(systemName: appState.kernelExploitRunning ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(appState.kernelExploitRunning ? AppTheme.cyberCyan : .orange.opacity(0.8))
                    Text("Kernel Exploit")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    if appState.kernelExploitRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(AppTheme.cyberCyan)
                                .scaleEffect(0.7)
                            Text("Đang chạy")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.cyberCyan)
                        }
                    } else {
                        Text(appState.exploitStatus.isSuccess ? "Đã kích hoạt" : "Chưa hoạt động")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(appState.exploitStatus.isSuccess ? AppTheme.cyberCyan : .white.opacity(0.35))
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - App Info

    private var appInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "info.circle", title: "Ứng dụng")

            infoRow(label: "Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0", icon: "tag")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Build Number", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1", icon: "number")
            Divider().background(Color.white.opacity(0.06))
            infoRow(label: "Developer", value: "Trần Minh Khải", icon: "person.fill")
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.cyberCyan)
                .shadow(color: AppTheme.cyberCyan.opacity(0.4), radius: 4)
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.cyberCyan.opacity(0.7))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.cyberSurface.opacity(0.55))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.cyberCyan.opacity(0.25), AppTheme.cyberPurple.opacity(0.12), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
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
