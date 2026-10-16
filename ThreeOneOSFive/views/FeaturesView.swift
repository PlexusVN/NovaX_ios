import SwiftUI

struct FeaturesView: View {
    var showSystemDashboard: Binding<Bool>? = nil

    @EnvironmentObject private var service: FeaturePatchService
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedVariant: GamePatchVariant = .ffth
    @State private var activeToast: ToastInfo?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        variantSelector
                        releaseCard
                        featureList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 200)
                }
                .refreshable { await reload(showLoading: false) }

                injectBar
                    .padding(.bottom, 88)
            }
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let showSystemDashboard {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.light()
                            showSystemDashboard.wrappedValue = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 34, height: 34)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppTheme.grey200, lineWidth: 1))
                        }
                    }
                }
            }
            .task(id: selectedVariant) {
                await reload(showLoading: true)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { break }
                    await service.refreshNativeState(variant: selectedVariant, auth: authManager)
                }
            }
        }
        .glassToast(toast: $activeToast)
    }

    private var variantSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Phiên bản game", systemImage: "gamecontroller.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 8) {
                ForEach(GamePatchVariant.allCases) { variant in
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedVariant = variant
                        }
                    } label: {
                        Text(variant.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedVariant == variant ? Color.white : AppTheme.grey500)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedVariant == variant ? AppTheme.ink : AppTheme.grey50)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private var releaseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Patch \(selectedVariant.shortTitle)", systemImage: "shippingbox.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                statusBadge
            }

            if service.isNativeLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(AppTheme.ink)
                    Text("Đang xác thực key và tải Patch Menu...")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                }
                .padding(.vertical, 8)
            } else if let release = service.nativeRelease {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.ink)
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(release.version)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(release.gameBuild.isEmpty ? "Build game chưa khai báo" : "Game build: \(release.gameBuild)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.grey500)
                        Text(formatSize(release.fileSize))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.grey500)
                    }
                    Spacer()
                }

                if !release.changelog.isEmpty {
                    Text(release.changelog)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AppTheme.grey500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Server chưa phát hành patch cho \(selectedVariant.title)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red)
                    .padding(.vertical, 8)
            }
        }
        .cardStyle()
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(service.nativeAssemblyOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(service.nativeAssemblyOnline ? "ONLINE" : "OFFLINE")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(service.nativeAssemblyOnline ? Color.green : Color.red)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((service.nativeAssemblyOnline ? Color.green : Color.red).opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var featureList: some View {
        if service.nativeRelease != nil {
            if service.nativeFeatures.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "switch.2")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(AppTheme.grey400)
                    Text("Patch chưa khai báo danh sách chức năng")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.grey500)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .cardStyle()
            } else {
                ForEach(featureSections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.uppercased())
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("\(features(in: section).count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.grey500)
                        }

                        ForEach(features(in: section)) { feature in
                            NativeFeatureControlRow(
                                feature: feature,
                                variant: selectedVariant,
                                service: service,
                                auth: authManager,
                                activeToast: $activeToast
                            )
                        }
                    }
                    .cardStyle()
                }
            }
        }
    }

    private var injectBar: some View {
        VStack(spacing: 8) {
            Text(service.nativeStatusMessage)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.grey500)
                .lineLimit(1)

            Button {
                injectSelectedPatch()
            } label: {
                HStack(spacing: 10) {
                    if service.isNativeInjecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: service.isNativePatchInjected(variant: selectedVariant) ? "checkmark.seal.fill" : "arrow.down.app.fill")
                    }
                    Text(service.isNativePatchInjected(variant: selectedVariant)
                         ? "INJECT LẠI PATCH \(selectedVariant.shortTitle)"
                         : "TẢI VÀ INJECT PATCH \(selectedVariant.shortTitle)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(service.nativeRelease == nil ? AppTheme.grey400 : AppTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: AppTheme.ink.opacity(0.35), radius: 14, x: 0, y: 6)
            }
            .disabled(service.nativeRelease == nil || service.isNativeInjecting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            VisualEffectBlur()
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var featureSections: [String] {
        service.nativeFeatures.reduce(into: [String]()) { result, feature in
            if !result.contains(feature.section) { result.append(feature.section) }
        }
    }

    private func features(in section: String) -> [NovaXFeatureDefinition] {
        service.nativeFeatures.filter { $0.section == section }
    }

    private func reload(showLoading: Bool) async {
        guard authManager.authState == .verified else { return }
        do {
            try await service.loadNativeMenu(variant: selectedVariant, auth: authManager, showLoading: showLoading)
        } catch {
            activeToast = ToastInfo(title: "Không thể tải Patch Menu", message: error.localizedDescription, isSuccess: false)
        }
    }

    private func injectSelectedPatch() {
        Haptics.medium()
        Task { @MainActor in
            do {
                try await service.injectNativePatch(variant: selectedVariant, auth: authManager)
                activeToast = ToastInfo(
                    title: "Inject thành công",
                    message: "Đã tải và áp dụng patch \(selectedVariant.title).",
                    isSuccess: true
                )
            } catch {
                activeToast = ToastInfo(title: "Inject thất bại", message: error.localizedDescription, isSuccess: false)
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }
}

private struct NativeFeatureControlRow: View {
    let feature: NovaXFeatureDefinition
    let variant: GamePatchVariant
    @ObservedObject var service: FeaturePatchService
    @ObservedObject var auth: AuthManager
    @Binding var activeToast: ToastInfo?

    @State private var isSending = false
    @State private var sliderValue: Double = 0

    private var desired: NovaXRemoteFeatureState? { service.nativeDesiredState[feature.id] }
    private var actual: NovaXRemoteFeatureState? { service.nativeActualState[feature.id] }
    private var desiredEnabled: Bool { desired?.enabled ?? false }
    private var desiredValue: Int { desired?.value ?? feature.default }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    HStack(spacing: 5) {
                        Circle().fill(stateColor).frame(width: 6, height: 6)
                        Text(stateText)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(stateColor)
                    }
                }
                Spacer()

                if isSending {
                    ProgressView().tint(AppTheme.ink).scaleEffect(0.8)
                } else if feature.type == "toggle" {
                    Toggle("", isOn: Binding(
                        get: { desiredEnabled },
                        set: { send(enabled: $0, value: desiredValue) }
                    ))
                    .labelsHidden()
                    .tint(AppTheme.ink)
                } else if feature.type == "select" {
                    if feature.options.isEmpty {
                        Text("Chưa có dữ liệu")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.grey400)
                    } else {
                        Menu {
                            ForEach(feature.options) { option in
                                Button(option.title) { send(enabled: true, value: option.value) }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedOptionTitle)
                                Image(systemName: "chevron.down")
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.grey50)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            if feature.type == "range" {
                HStack(spacing: 10) {
                    Slider(
                        value: $sliderValue,
                        in: Double(feature.min)...Double(max(feature.min + 1, feature.max)),
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { send(enabled: true, value: Int(sliderValue)) }
                        }
                    )
                    .tint(AppTheme.ink)
                    Text("\(Int(sliderValue))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 30)
                }
            }
        }
        .padding(12)
        .background(AppTheme.grey50)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppTheme.grey200, lineWidth: 1))
        .onAppear { sliderValue = Double(desiredValue) }
        .onChange(of: desiredValue) { sliderValue = Double($0) }
    }

    private var stateColor: Color {
        guard service.nativeAssemblyOnline else { return .red }
        guard let desired else { return AppTheme.grey400 }
        if let actual, actual.enabled == desired.enabled, actual.value == desired.value { return .green }
        return .blue
    }

    private var stateText: String {
        guard service.nativeAssemblyOnline else { return "ASSEMBLY OFFLINE" }
        guard let desired else { return "CHƯA GỬI" }
        if let actual, actual.enabled == desired.enabled, actual.value == desired.value { return "ĐÃ ÁP DỤNG" }
        return "ĐANG ĐỒNG BỘ"
    }

    private var selectedOptionTitle: String {
        feature.options.first(where: { $0.value == desiredValue })?.title ?? "\(desiredValue)"
    }

    private func send(enabled: Bool, value: Int) {
        Haptics.light()
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                try await service.sendNativeCommand(
                    feature: feature,
                    enabled: enabled,
                    value: value,
                    variant: variant,
                    auth: auth
                )
            } catch {
                activeToast = ToastInfo(title: "Không thể gửi lệnh", message: error.localizedDescription, isSuccess: false)
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.grey200, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
