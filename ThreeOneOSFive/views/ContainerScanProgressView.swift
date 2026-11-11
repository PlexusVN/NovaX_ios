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
                        Text("iOS 27 · Tìm thư mục ứng dụng")
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
    var body: some View {
        ContainerScanProgressView(progress: .shared,
            isPreparation: true,
            isPreparing: preparation.state == .preparing,
            preparationReady: preparation.state == .ready,
            preparationError: preparation.failure,
            onRetry: { Task { await preparation.prepareIfNeeded(force: true) } },
            onContinue: { preparation.enterApplication() },
            onAirLift: preparation.canUseAirLift ? { preparation.chooseAirLift() } : nil)
        .task {
            // Let SwiftUI draw the gate before any private native API runs.
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            await preparation.prepareIfNeeded()
        }
    }
}
