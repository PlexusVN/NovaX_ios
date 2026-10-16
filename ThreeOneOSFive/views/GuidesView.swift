import SwiftUI
import AVKit

struct MediaPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct GuidesView: View {
    @Binding var showSystemDashboard: Bool
    @StateObject private var guideService = GuideService.shared
    @State private var playingVideoItem: MediaPreviewItem? = nil
    @State private var previewImageItem: MediaPreviewItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headerBanner

                        if guideService.isLoading && guideService.guides.isEmpty {
                            loadingPlaceholder
                        } else if guideService.guides.isEmpty {
                            emptyPlaceholder
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(guideService.guides) { guide in
                                    GuideCardView(
                                        guide: guide,
                                        isLiked: guideService.isLiked(guide.id),
                                        onLike: {
                                            guideService.toggleLike(for: guide.id)
                                        },
                                        onPlayVideo: { url in
                                            playingVideoItem = MediaPreviewItem(url: url)
                                        },
                                        onPreviewImage: { url in
                                            previewImageItem = MediaPreviewItem(url: url)
                                        }
                                    )
                                }
                            }
                        }

                        Spacer().frame(height: 120)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Hướng dẫn")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.ink)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.light()
                        showSystemDashboard = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AppTheme.grey200, lineWidth: 1))
                    }
                }
            }
            .refreshable {
                await guideService.fetchGuides()
            }
            .onAppear {
                Task {
                    await guideService.fetchGuides()
                }
            }
            .fullScreenCover(item: $playingVideoItem) { item in
                FullScreenVideoPlayer(url: item.url)
                    .ignoresSafeArea()
            }
            .sheet(item: $previewImageItem) { item in
                FullScreenImageView(url: item.url)
            }
        }
    }

    // MARK: - Header

    private var headerBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.ink)
                    .frame(width: 56, height: 56)
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trung tâm Hướng dẫn")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .kerning(-0.4)
                Text("Video hướng dẫn & bài viết chi tiết từ Admin")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.grey500)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    // MARK: - States

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView().tint(AppTheme.ink).scaleEffect(1.2)
            Text("Đang tải danh sách bài hướng dẫn...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppTheme.grey500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.grey400)
            Text("Chưa có bài hướng dẫn nào")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.grey500)
            Text("Các video và bài viết hướng dẫn từ Admin sẽ xuất hiện tại đây.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.grey400)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Guide Card View (Doanh nghiệp 2026)

private struct GuideCardView: View {
    let guide: GuideItem
    let isLiked: Bool
    let onLike: () -> Void
    let onPlayVideo: (URL) -> Void
    let onPreviewImage: (URL) -> Void

    @State private var isExpanded = false
    @State private var isLikeAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                mediaBadge
                Spacer()
                if let dateStr = guide.createdAt, !dateStr.isEmpty {
                    Text(formattedDate(dateStr))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                }
            }

            Text(guide.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .kerning(-0.4)
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            mediaContainer

            if !guide.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(guide.content)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.grey700)
                        .lineSpacing(4)
                        .lineLimit(isExpanded ? nil : 3)

                    if guide.content.count > 120 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Thu gọn" : "Xem thêm")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.top, 2)
                        }
                    }
                }
            }

            Rectangle()
                .fill(AppTheme.grey200)
                .frame(height: 1)
                .padding(.top, 2)

            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                        isLikeAnimating = true
                    }
                    onLike()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLikeAnimating = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isLiked ? AppTheme.ink : AppTheme.grey500)
                            .scaleEffect(isLikeAnimating ? 1.35 : 1.0)

                        Text("\(guide.likesCount)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isLiked ? AppTheme.grey50 : Color.white)
                    .overlay(
                        Capsule().stroke(isLiked ? AppTheme.ink : AppTheme.grey200, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                ShareLink(item: "\(guide.title)\n\n\(guide.content)") {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Chia sẻ")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    private var mediaBadge: some View {
        Group {
            if guide.mediaType == "video" {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("VIDEO")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AppTheme.ink)
                .clipShape(Capsule())
            } else if guide.mediaType == "image" {
                HStack(spacing: 5) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("HÌNH ẢNH")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AppTheme.ink)
                .clipShape(Capsule())
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("BÀI VIẾT")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(AppTheme.grey600)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AppTheme.grey50)
                .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var mediaContainer: some View {
        if guide.mediaType == "video", let urlStr = guide.mediaUrl, let videoURL = URL(string: urlStr) {
            Button {
                Haptics.medium()
                onPlayVideo(videoURL)
            } label: {
                ZStack {
                    LinearGradient(colors: [AppTheme.grey100, AppTheme.grey200],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.ink)
                                .frame(width: 56, height: 56)
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }

                        Text("Chạm để phát video")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.grey600)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.grey200, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if guide.mediaType == "image", let urlStr = guide.mediaUrl, let imgURL = URL(string: urlStr) {
            Button {
                Haptics.light()
                onPreviewImage(imgURL)
            } label: {
                AsyncImage(url: imgURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.grey200, lineWidth: 1)
                            )
                    case .failure:
                        HStack(spacing: 8) {
                            Image(systemName: "photo")
                            Text("Không thể tải hình ảnh")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.grey500)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(AppTheme.grey50)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    case .empty:
                        ProgressView()
                            .tint(AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .background(AppTheme.grey50)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func formattedDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: raw)
        }
        guard let validDate = date else { return "" }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .none
        displayFormatter.locale = Locale(identifier: "vi_VN")
        return displayFormatter.string(from: validDate)
    }
}

// MARK: - Full screen video player

private struct FullScreenVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            self.player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Full screen image

private struct FullScreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }
}
