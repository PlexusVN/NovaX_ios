import SwiftUI
import UIKit

struct ContainerScanProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var progress: ContainerScanProgress
    var isPreparation = false
    var isPreparing = false
    var preparationReady = false
    var preparationError: String?
    var onRetry: (() -> Void)?
    var onContinue: (() -> Void)?
    var onAirLift: (() -> Void)?
    @State private var copied = false
    private var state: ContainerScanSnapshot { progress.snapshot }

    var body: some View {
        ZStack {
            AppTheme.gamingBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: state.phase == .scanning ? "folder.badge.gearshape" : "folder")
                        .font(.system(size: 30))
                        .foregroundColor(AppTheme.gamingBlueBright)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title3.bold())
                        Text("iOS \(AppInfo.versionTuple.major) · Tìm thư mục ứng dụng")
                            .font(.caption).foregroundColor(AppTheme.gamingTextSecondary)
                    }
                    Spacer()
                    if state.phase == .scanning || isPreparing { ProgressView().tint(AppTheme.gamingBlueBright) }
                }
                Text(preparationError ?? (preparationReady ? "Đã kiểm tra quyền truy cập thư mục game. Chọn Vào ứng dụng để tiếp tục." : state.phase == .scanning || isPreparing
                     ? "Lần đầu có thể mất vài phút hoặc lâu hơn. Giữ Astra ở màn hình này; lần sau sẽ dùng đường dẫn đã lưu nếu còn hợp lệ."
                     : state.detail.isEmpty ? "Chuẩn bị worse_query trước khi vào màn hình Chức năng." : state.detail))
                    .font(.subheadline).foregroundColor(AppTheme.gamingTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !state.bundleID.isEmpty {
                    Text(state.bundleID).font(.caption.monospaced()).lineLimit(2)
                }
                if state.total > 0 {
                    ProgressView(value: state.fraction).tint(AppTheme.gamingBlueBright)
                    HStack {
                        Text("Phạm vi đã dò: \(Int(state.fraction * 100))%")
                        Spacer()
                        Text("\(state.candidates) thư mục · \(state.grants) truy cập được")
                    }.font(.caption).foregroundColor(AppTheme.gamingTextSecondary)
                    Text("Tỷ lệ theo phạm vi tìm kiếm; có thể kết thúc sớm khi tìm thấy ứng dụng.")
                        .font(.caption2).foregroundColor(AppTheme.gamingTextSecondary)
                }
                HStack {
                    Text("Nhật ký tiến trình").font(.subheadline.bold())
                    Spacer()
                    Button(copied ? "Đã sao chép" : "Sao chép") {
                        UIPasteboard.general.string = progress.shareText
                        copied = true
                    }.disabled(state.logs.isEmpty)
                }
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(state.logs.enumerated()), id: \.offset) { index, line in
                                Text(line).font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }.padding(14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onChange(of: state.logs.last) { _ in
                        guard !state.logs.isEmpty else { return }
                        reader.scrollTo(state.logs.count - 1, anchor: .bottom)
                    }
                }
                if isPreparation && !isPreparing {
                    Button(preparationReady ? "Vào ứng dụng" : "Thử lại") {
                        if preparationReady { onContinue?() } else { onRetry?() }
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.gamingBlue)
                    .frame(maxWidth: .infinity)
                    if let onAirLift {
                        Button("Thiết lập AirLift dự phòng", action: onAirLift)
                            .font(.subheadline)
                    }
                } else {
                Button(state.phase == .scanning || isPreparing ? (progress.cancelPending ? "Đang dừng…" : "Dừng quét") : "Đóng") {
                    if state.phase == .scanning { progress.requestCancellation() } else { progress.dismiss(); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.gamingBlue)
                .frame(maxWidth: .infinity)
                .disabled(progress.cancelPending)
                }
            }
            .padding(22)
            .frame(maxWidth: 620)
            .foregroundColor(AppTheme.gamingText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled(state.phase == .scanning)
    }

    private var title: String {
        if isPreparation {
            if preparationReady { return "Đã chuẩn bị xong iOS 27" }
            if isPreparing { return progress.cancelPending ? "Đang dừng quét" : "Chuẩn bị quyền truy cập iOS 27" }
            if preparationError != nil { return "Chưa chuẩn bị xong" }
            return "Chuẩn bị quyền truy cập iOS 27"
        }
        switch state.phase {
        case .idle: return "Nhật ký quét thư mục"
        case .scanning: return progress.cancelPending ? "Đang dừng quét" : "Đang tìm thư mục dữ liệu"
        case .resolved: return "Đã tìm thấy thư mục"
        case .failed: return "Chưa hoàn tất quét"
        case .cancelled: return "Đã dừng quét"
        case .interrupted: return "Phiên quét trước bị gián đoạn"
        }
    }
}

struct IOS27PreparationView: View {
    @ObservedObject var preparation: IOS27ContainerPreparation
    @ObservedObject private var progress = ContainerScanProgress.shared
    @State private var copiedError = false

    private var isPreparing: Bool { preparation.state == .idle || preparation.state == .preparing }
    private var isReady: Bool { preparation.state == .ready }
    private var platformLabel: String { "iOS \(AppInfo.versionTuple.major)" }

    var body: some View {
        ZStack {
            GamingBackdrop()
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 20) {
                        AppLogo(size: 96)
                            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .stroke(AppTheme.gamingBorderGradient, lineWidth: 1))
                            .shadow(color: AppTheme.gamingBlue.opacity(0.20), radius: 28, y: 8)
                            .accessibilityLabel("Astra")
                        Text("ASTRA")
                            .font(.system(size: 13, weight: .semibold)).tracking(5)
                            .foregroundColor(AppTheme.gamingTextSecondary)
                    }

                    VStack(spacing: 12) {
                        Text(isReady ? "Đã sẵn sàng cho \(platformLabel)" : isPreparing ? "Đang chuẩn bị cho \(platformLabel)" : "Chưa thể hoàn tất chuẩn bị")
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(isReady ? "Astra đã sẵn sàng. Bạn có thể tiếp tục." : isPreparing ? "Vui lòng giữ Astra ở màn hình này." : "Hãy thử lại hoặc gửi thông tin lỗi để được hỗ trợ.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.gamingTextSecondary)
                            .multilineTextAlignment(.center)
                    }

                    preparationProgress

                    if let failure = preparation.failure {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Không thể chuẩn bị \(platformLabel)", systemImage: "exclamationmark.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(AppTheme.statusError)
                            Text(failure.replacingOccurrences(
                                of: "Xem dòng log cuối rồi chọn Thử lại để tiếp tục.",
                                with: "Chọn Thử lại để tiếp tục hoặc sao chép thông tin lỗi để được hỗ trợ."))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(copiedError ? "Đã sao chép thông tin lỗi" : "Sao chép thông tin lỗi") {
                                UIPasteboard.general.string = "Astra · Chuẩn bị \(platformLabel)\n\(failure)\n\n\(progress.shareText)"
                                copiedError = true
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.gamingBlueBright)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(AppTheme.gamingSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.statusError.opacity(0.35), lineWidth: 1))
                        .accessibilityElement(children: .contain)
                    }

                    preparationActions
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 28)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height * 0.78)
            }
        }
        .foregroundColor(AppTheme.gamingText)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled(isPreparing)
        .task {
            // Let SwiftUI draw the gate before any private native API runs.
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            await preparation.prepareIfNeeded()
        }
    }

    @ViewBuilder
    private var preparationProgress: some View {
        if isPreparing && progress.snapshot.total == 0 {
            ProgressView().progressViewStyle(.linear)
                .tint(AppTheme.gamingBlueBright)
                .accessibilityLabel("Đang chuẩn bị cho \(platformLabel)")
        } else {
            ProgressView(value: isReady ? 1 : progress.snapshot.fraction)
                .progressViewStyle(.linear)
                .tint(AppTheme.gamingBlueBright)
                .accessibilityLabel(isReady ? "Đã chuẩn bị xong" : "Tiến trình chuẩn bị \(platformLabel)")
        }
    }

    @ViewBuilder
    private var preparationActions: some View {
        if isPreparing {
            Button(progress.cancelPending ? "Đang dừng…" : "Hủy chuẩn bị") {
                if progress.snapshot.phase == .scanning { progress.requestCancellation() }
            }
            .font(.subheadline)
            .foregroundColor(AppTheme.gamingTextSecondary)
            .disabled(progress.cancelPending)
        } else {
            Button {
                if isReady { preparation.enterApplication() }
                else {
                    copiedError = false
                    Task { await preparation.prepareIfNeeded(force: true) }
                }
            } label: {
                Text(isReady ? "Vào ứng dụng" : "Thử lại")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(AppTheme.gamingAccentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(GamingPressButtonStyle())
            if preparation.canUseAirLift {
                Button("Thiết lập AirLift dự phòng") { preparation.chooseAirLift() }
                    .font(.subheadline).foregroundColor(AppTheme.gamingBlueBright)
            }
        }
    }
}
