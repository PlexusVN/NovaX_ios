import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var authManager = AuthManager()
    @StateObject private var featurePatchService = FeaturePatchService()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.vietnamese.rawValue
    @State private var showSplash = true
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: NovaX launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
        let securityResult = AntiTamper.checkAtLaunch()
        if securityResult.isCompromised {
            log("app: security notice — \(securityResult.compromisedReasons.joined(separator: ", "))")
        }
        configureAppearance()
    }

    private func configureAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.10, green: 0.55, blue: 1.00, alpha: 1)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor(red: 0.10, green: 0.55, blue: 1.00, alpha: 1)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .vietnamese
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authManager.authState == .verified {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(patchDraftCoordinator)
                        .environmentObject(fileOperationCoordinator)
                        .environmentObject(authManager)
                        .environmentObject(featurePatchService)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity)
                } else {
                    LoginView(auth: authManager)
                        .environmentObject(appState)
                        .transition(.opacity)
                }

                if showSplash {
                    SplashScreen {
                        let v = AppInfo.versionTuple
                        let supported = ExploitSupportPolicy.isSupported(
                            major: v.major,
                            minor: v.minor,
                            patch: v.patch,
                            build: AppInfo.osBuild
                        )
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSplash = false
                        }
                        if supported {
                            appState.detectSupport()
                            if !authManager.licenseKey.isEmpty {
                                Task { await authManager.restoreSessionIfNeeded() }
                            }
                            checkForUpdate()
                            Task { await featurePatchService.syncFromServer(auth: authManager) }
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
                
                if let offer = updateOffer {
                    UpdateRequiredView(offer: offer)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if !showSplash {
                    appState.detectSupport()
                    checkForUpdate()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showSplash else { return }
                appState.detectSupport()
                Task { await featurePatchService.syncFromServer(auth: authManager) }
            }
            .onChange(of: authManager.authState) { state in
                if state == .verified {
                    Task { await featurePatchService.syncFromServer(auth: authManager) }
                }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false
    @Published var hasDirectDirectoryAccess: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        let bundleIDs = ["com.dts.freefireth", "com.dts.freefiremax"]
        for bundleID in bundleIDs {
            if let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID) {
                let docPath = (path as NSString).appendingPathComponent("Documents")
                if FileManager.default.isWritableFile(atPath: docPath) {
                    return true
                }
                let testFile = (docPath as NSString).appendingPathComponent(".novax_test")
                do {
                    try "test".write(toFile: testFile, atomically: true, encoding: .utf8)
                    try? FileManager.default.removeItem(atPath: testFile)
                    return true
                } catch {
                    // fallthrough to next bundle ID
                }
            }
        }
        return false
        #endif
    }()

    @Published var hasSandboxAccess: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return KernelExploit.hasSandboxAccess()
        #endif
    }()

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { hasDirectDirectoryAccess || hasSandboxAccess || (unsupportedMessage == nil && exploitStatus.isSuccess) }

    var accessLevelDescription: String {
        var features: [String] = []
        if hasDirectDirectoryAccess { features.append("Thư mục") }
        if hasSandboxAccess { features.append("Sandbox") }
        if exploitStatus.isSuccess { features.append("Kernel") }
        
        if features.count == 3 {
            return "Full quyền"
        } else if features.isEmpty {
            return "Không hỗ trợ"
        } else {
            return "Được hỗ trợ (\(features.joined(separator: ", ")))"
        }
    }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !hasSandboxAccess && !hasDirectDirectoryAccess,
              !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() || hasSandboxAccess || hasDirectDirectoryAccess {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !hasSandboxAccess && !hasDirectDirectoryAccess,
              !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let (ok, fullAccess) = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if fullAccess {
                    self.hasSandboxAccess = true
                }
                if ok || self.hasSandboxAccess || self.hasDirectDirectoryAccess {
                    self.exploitStatus = .success(method: "kexploit")
                    if self.hasSandboxAccess || self.hasDirectDirectoryAccess {
                        log("app: kernel exploit success — full sandbox access")
                    } else {
                        log("app: kernel exploit success — kernel R/W only")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}

struct UpdateRequiredView: View {
    let offer: AppUpdateChecker.Offer
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            LinearGradient(
                colors: [AppTheme.accent.opacity(0.1), Color.black],
                startPoint: .top,
                endPoint: .bottom
            ).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(AppTheme.accent)
                    .padding(.bottom, 8)
                
                Text("BẢN CẬP NHẬT BẮT BUỘC")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                
                Text("Phiên bản \(offer.version) đã sẵn sàng.\nVui lòng cập nhật để tiếp tục sử dụng NovaX.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 32)
                
                Button(action: {
                    Haptics.medium()
                    UIApplication.shared.open(offer.url)
                }) {
                    HStack {
                        Image(systemName: "arrow.down.app")
                        Text("TẢI XUỐNG NGAY")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.accent)
                    .cornerRadius(12)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 16)
                
                developerCard
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
            }
        }
    }
    
    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NHÀ PHÁT TRIỂN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                        .tracking(1)
                    Text("Liên hệ hỗ trợ tải bản cập nhật")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
            }

            Divider().background(AppTheme.accent.opacity(0.15))
                .padding(.vertical, 10)

            // Admin info
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().stroke(AppTheme.accent.opacity(0.4), lineWidth: 1.5)
                        )
                    Text("MK")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Trần Minh Khải")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("Nhà phát triển NovaX")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.accent.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.accent.opacity(0.5))
                        Text("0342145707")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()
            }
            .padding(.vertical, 2)
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    Haptics.light()
                    if let url = URL(string: "https://zalo.me/0342145707") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Liên hệ Zalo")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PremiumButtonStyle(color: Color(hex: 0x0068FF), cornerRadius: 8))
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.1))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}
