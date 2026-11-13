import SwiftUI
import UIKit

@main
@MainActor
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var authManager = AuthManager()
    @StateObject private var featurePatchService = FeaturePatchService()
    @StateObject private var updateManager = UpdateManager.shared
    @StateObject private var gatekeeper = AirLiftGatekeeperManager.shared
    @StateObject private var networkAccess = NetworkAccessGate.shared
    @StateObject private var containerScan = ContainerScanProgress.shared
    @StateObject private var ios27Preparation = IOS27ContainerPreparation.shared
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.vietnamese.rawValue
    @State private var showMainInterface = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: Astra launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
        configureAppearance()
        if requiresWorseQueryPreparation {
            IOS27ContainerPreparation.shared.configureTargets(bundleIDs: AppSecurityConfiguration.protectedBundleIDs)
        }
    }

    private func configureAppearance() {
        // Trắng hoàn toàn theo design.md doanh nghiệp 2026
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0.012, green: 0.027, blue: 0.071, alpha: 0.96)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.55, green: 0.55, blue: 0.97, alpha: 1)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(red: 0.012, green: 0.027, blue: 0.071, alpha: 0.96)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor(red: 0.55, green: 0.55, blue: 0.97, alpha: 1)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .vietnamese
    }

    private var requiresWorseQueryPreparation: Bool {
        ExploitSupportPolicy.currentRequiresWorseQueryPreparation
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Một màn hình duy nhất: SplashLoginView gộp loading + login
                // → liền mạch, không có "chuyển cảnh" giữa 2 view (giống HTML)
                Group {
                    if authManager.authState == .verified && requiresWorseQueryPreparation && !ios27Preparation.didContinue {
                        IOS27PreparationView(preparation: ios27Preparation)
                            .zIndex(2)
                    } else if authManager.authState == .verified && gatekeeper.requiresPairingForCurrentDevice && !gatekeeper.canBypassGatekeeper {
                        IOS27PairingSetupView(auth: authManager) {
                            withAnimation(.easeInOut(duration: 0.32)) {
                                showMainInterface = true
                            }
                        }
                        .environmentObject(appState)
                        .environmentObject(authManager)
                        .environmentObject(updateManager)
                        .transition(.opacity.combined(with: .scale(scale: 1.01)))
                        .zIndex(2)
                    } else if showMainInterface {
                        ContentView()
                            .environmentObject(appState)
                            .environmentObject(patchDraftCoordinator)
                            .environmentObject(fileOperationCoordinator)
                            .environmentObject(authManager)
                            .environmentObject(featurePatchService)
                            .environmentObject(updateManager)
                            .environmentObject(StorageEngineCoordinator.shared)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                            .transition(.opacity.combined(with: .scale(scale: 1.01)))
                            .zIndex(1)
                    } else {
                        SplashLoginView(auth: authManager)
                            .environmentObject(appState)
                            .environmentObject(updateManager)
                            .onAppear {
                                // Trigger init giống như splash cũ
                                updateManager.checkForUpdate()
                                appState.detectSupport()
                                if !authManager.licenseKey.isEmpty {
                                    Task { await authManager.restoreSessionIfNeeded() }
                                }
                            }
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }

                if requiresWorseQueryPreparation && containerScan.isPresented && authManager.authState == .verified && (!requiresWorseQueryPreparation || ios27Preparation.didContinue) {
                    ContainerScanProgressView(progress: containerScan)
                        .zIndex(2.5)
                }

                if let offer = updateManager.updateOffer {
                    UpdateRequiredView(offer: offer)
                        .transition(.opacity)
                        .zIndex(3)
                }
                if !networkAccess.isAllowed {
                    NetworkAccessBlockedView(gate: networkAccess)
                        .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.32), value: showMainInterface)
            .animation(.easeInOut(duration: 0.32), value: ios27Preparation.didContinue)
            .preferredColorScheme(.dark)
            .task(id: authManager.authState == .verified) {
                guard authManager.authState == .verified else {
                    showMainInterface = false
                    ios27Preparation.reset()
                    return
                }

                // Giữ Login đủ lâu để người dùng nhìn thấy trạng thái thành công.
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard !Task.isCancelled, authManager.authState == .verified else { return }
                withAnimation(.easeInOut(duration: 0.32)) {
                    showMainInterface = true
                }
            }
            .onAppear {
                networkAccess.setActive(scenePhase == .active)
                updateManager.checkForUpdate()
                appState.detectSupport()
            }
            .onChange(of: scenePhase) { phase in
                // Switching to Settings invalidates the old network lease before
                // any future API/apply work. Foreground always verifies again.
                networkAccess.setActive(phase == .active)
                if phase != .active && ExploitSupportPolicy.currentAccessProvider == .airLift {
                    AirLiftTunnelManager.shared.cancelPendingChecks()
                    AirLiftPairingManager.shared.cancelPendingChecks()
                    AirTrafficProtocolClient.shared.cancelPendingChecks()
                }
                guard phase == .active else { return }
                updateManager.checkForUpdate()
                appState.detectSupport()
                Task { await featurePatchService.syncFromServer(auth: authManager) }
            }
            .onChange(of: networkAccess.state) { state in
                if state == .blocked {
                    // Discard only the in-memory download session. A verified
                    // recovery opens a new one; license and device keys remain.
                    ProtectedDownloadService.shared.reset()
                } else if state == .allowed, authManager.authState == .verified {
                    Task { await featurePatchService.syncFromServer(auth: authManager) }
                }
            }
            .onChange(of: authManager.authState) { state in
                updateManager.checkForUpdate()
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

private struct NetworkAccessBlockedView: View {
    @ObservedObject var gate: NetworkAccessGate

    var body: some View {
        ZStack {
            AppTheme.gamingBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: gate.state == .checking ? "lock.shield" : "wifi.exclamationmark")
                    .font(.system(size: 38))
                    .foregroundColor(AppTheme.gamingBlueBright)
                Text(gate.state == .checking ? "Kiểm tra kết nối bảo mật" : "Tạm dừng sử dụng")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.gamingText)
                Text(gate.blockingMessage ?? "Cần xác minh kết nối trước khi tiếp tục.")
                    .font(.body)
                    .foregroundColor(AppTheme.gamingTextSecondary)
                    .multilineTextAlignment(.center)
                if gate.state == .checking {
                    ProgressView().tint(AppTheme.gamingBlueBright)
                } else {
                    Button("Kiểm tra lại") {
                        Task { await gate.checkNow() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.gamingBlue)
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled()
    }
}

// MARK: - AppState giữ nguyên

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false
    @Published var hasDirectDirectoryAccess: Bool = false

    @Published var hasSandboxAccess: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return KernelExploit.hasSandboxAccess()
        #endif
    }()

    private var autoRunAttempted = false
    private var isCheckingDirectAccess = false

    func checkDirectDirectoryAccessAsync() {
        // Probe only the selected 3105 route. Worse_query waits for its explicit
        // preparation gate; AirLift waits for pairing and transport checks.
        guard ExploitSupportPolicy.currentAccessProvider == .legacy3105 else { return }
        #if targetEnvironment(simulator)
        DispatchQueue.main.async { self.hasDirectDirectoryAccess = true }
        #else
        guard !isCheckingDirectAccess else { return }
        isCheckingDirectAccess = true
        DispatchQueue.global(qos: .utility).async {
            let bundleIDs = ["com.dts.freefireth", "com.dts.freefiremax"]
            for bundleID in bundleIDs {
                if let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID, allowMetadataScan: false) {
                    let docPath = (path as NSString).appendingPathComponent("Documents")
                    if FileManager.default.isWritableFile(atPath: docPath) {
                        DispatchQueue.main.async {
                            self.hasDirectDirectoryAccess = true
                            self.isCheckingDirectAccess = false
                        }
                        return
                    }
                    let testFile = (docPath as NSString).appendingPathComponent(".novax_test")
                    do {
                        try "test".write(toFile: testFile, atomically: true, encoding: .utf8)
                        try? FileManager.default.removeItem(atPath: testFile)
                        DispatchQueue.main.async {
                            self.hasDirectDirectoryAccess = true
                            self.isCheckingDirectAccess = false
                        }
                        return
                    } catch {
                        // fallthrough to next bundle ID
                    }
                }
            }
            DispatchQueue.main.async {
                self.hasDirectDirectoryAccess = false
                self.isCheckingDirectAccess = false
            }
        }
        #endif
    }

    var kernelExploitApplicable: Bool {
        ExploitSupportPolicy.supportsKernelExploit(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch
        )
    }

    var isSupported: Bool {
        let version = AppInfo.versionTuple
        return ExploitSupportPolicy.isSupported(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            build: AppInfo.osBuild
        )
    }

    var hasFullAccess: Bool { hasDirectDirectoryAccess && hasSandboxAccess && exploitStatus.isSuccess }

    var accessLevelDescription: String {
        switch ExploitSupportPolicy.currentStorageMode {
        case .direct:
            return "Hỗ trợ · Ghi trực tiếp"
        case .airLift:
            switch ExploitSupportPolicy.currentPairingMode {
            case .importedFile:
                return "Hỗ trợ · AirLift · File pair máy tính"
            case .onDeviceOrImportedFile:
                return "Hỗ trợ · AirLift · Pair trên máy/file"
            case .none, .unavailable:
                return "Hỗ trợ · AirLift"
            }
        case .unsupported:
            return "Không hỗ trợ"
        }
    }

    func detectSupport() {
        checkDirectDirectoryAccessAsync()
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

        let missingBuild = ExploitSupportPolicy.requiresBuildIdentification(
            major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild)
        unsupportedMessage = supported ? nil : (missingBuild
            ? "Chưa xác định được build iOS 27.0 để chọn cơ chế truy cập. Hãy mở lại Astra rồi kiểm tra phiên bản hệ điều hành."
            : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))")
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = ExploitSupportPolicy.supportsKernelExploit(
            major: v.major,
            minor: v.minor,
            patch: v.patch
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
        let v = AppInfo.versionTuple
        guard ExploitSupportPolicy.supportsKernelExploit(major: v.major, minor: v.minor, patch: v.patch) else {
            log("app: kernel exploit not applicable for iOS \(v.major); skipping")
            return
        }
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

// MARK: - Update Required (trắng-đen)

struct UpdateRequiredView: View {
    let offer: AppUpdateChecker.Offer

    var body: some View {
        ZStack {
            GamingBackdrop()

            VStack(spacing: 24) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(AppTheme.statusError)
                    .padding(.bottom, 8)

                Text("BẢN CẬP NHẬT BẮT BUỘC")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundColor(AppTheme.statusError)

                Text("Phiên bản \(offer.version) đã sẵn sàng.\nVui lòng cập nhật để tiếp tục sử dụng Astra.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.grey600)
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
                    .background(AppTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.ink, lineWidth: 1)
                        .background(AppTheme.paperRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(width: 42, height: 42)
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NHÀ PHÁT TRIỂN")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                    Text("Liên hệ hỗ trợ tải bản cập nhật")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.grey500)
                }
                Spacer()
            }

            Rectangle().fill(AppTheme.grey200).frame(height: 1).padding(.vertical, 16)

            DeveloperContactsList()
        }
        .padding(16)
        .background(AppTheme.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
    }
}
