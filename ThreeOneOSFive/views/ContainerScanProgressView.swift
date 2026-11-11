import SwiftUI
import UIKit

struct ContainerScanProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var progress: ContainerScanProgress
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
                    if state.phase == .scanning { ProgressView().tint(AppTheme.gamingBlueBright) }
                }
                Text(state.phase == .scanning
                     ? "Lần đầu có thể mất vài phút hoặc lâu hơn. Giữ Astra ở màn hình này; lần sau sẽ dùng đường dẫn đã lưu nếu còn hợp lệ."
                     : state.detail.isEmpty ? "Nhật ký xuất hiện khi một chức năng cần dò thư mục. Astra không tự quét khi vừa mở app." : state.detail)
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
                Button(state.phase == .scanning ? (progress.cancelPending ? "Đang dừng…" : "Dừng quét") : "Đóng") {
                    if state.phase == .scanning { progress.requestCancellation() } else { progress.dismiss(); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.gamingBlue)
                .frame(maxWidth: .infinity)
                .disabled(progress.cancelPending)
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
