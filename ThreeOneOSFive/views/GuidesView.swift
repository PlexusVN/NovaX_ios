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
                    VStack(spacing: 20) {
                        headerBanner

                        if guideService.isLoading && guideService.guides.isEmpty {
                            loadingPlaceholder
                        } else if guideService.guides.isEmpty {
                            emptyPlaceholder
                        } else {
                            LazyVStack(spacing: 18) {
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
            .tint(AppTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.light()
                        showSystemDashboard = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.cyberCyan)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(AppTheme.cyberSurface.opacity(0.8)))
                            .overlay(Circle().stroke(AppTheme.cyberCyan.opacity(0.35), lineWidth: 1))
                            .shadow(color: AppTheme.cyberCyan.opacity(0.3), radius: 6)
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
            // Trình phát video toàn màn hình
            .fullScreenCover(item: $playingVideoItem) { item in
                FullScreenVideoPlayer(url: item.url)
                    .ignoresSafeArea()
            }
            // Xem ảnh phóng to
            .sheet(item: $previewImageItem) { item in
                FullScreenImageView(url: item.url)
            }
        }
    }

    // MARK: - Top Header Banner

    private var headerBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.cyberPurple.opacity(0.3), AppTheme.cyberCyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.cyberGradient)
            }
            .shadow(color: AppTheme.cyberCyan.opacity(0.3), radius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Trung tâm Hướng dẫn")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Video hướng dẫn & bài viết chi tiết từ Admin")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.cyberBorderGradient, lineWidth: 1)
                )
        )
    }

    // MARK: - Loading & Empty States

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.cyberCyan)
                .scaleEffect(1.2)
            Text("Đang tải danh sách bài hướng dẫn...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.25))
            Text("Chưa có bài hướng dẫn nào")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Các video và bài viết hướng dẫn từ Admin sẽ xuất hiện tại đây.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Guide Card View (Dạng thẻ bài viết Cyberpunk)

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
            // Header bài viết
            HStack(alignment: .center, spacing: 8) {
                mediaBadge
                Spacer()
                if let dateStr = guide.createdAt, !dateStr.isEmpty {
                    Text(formattedDate(dateStr))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            // Tiêu đề
            Text(guide.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            // Khu vực Media (Video hoặc Ảnh)
            mediaContainer

            // Nội dung văn bản
            if !guide.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(guide.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.82))
                        .lineSpacing(4)
                        .lineLimit(isExpanded ? nil : 4)

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
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.cyberCyan)
                            .padding(.top, 2)
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Footer (Nút Like & Share)
            HStack(spacing: 16) {
                // Nút Like
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
                            .foregroundColor(isLiked ? Color(red: 1.0, green: 0.2, blue: 0.45) : .white.opacity(0.4))
                            .scaleEffect(isLikeAnimating ? 1.35 : 1.0)
                            .shadow(color: isLiked ? Color(red: 1.0, green: 0.2, blue: 0.45).opacity(0.5) : .clear, radius: 6)

                        Text("\(guide.likesCount)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(isLiked ? Color(red: 1.0, green: 0.2, blue: 0.45) : .white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(isLiked ? Color(red: 1.0, green: 0.2, blue: 0.45).opacity(0.12) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isLiked ? Color(red: 1.0, green: 0.2, blue: 0.45).opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Nút chia sẻ
                ShareLink(item: "\(guide.title)\n\n\(guide.content)") {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Chia sẻ")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.68))
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    guide.mediaType == "video" ? Color(red: 1.0, green: 0.2, blue: 0.45).opacity(0.3) : AppTheme.cyberCyan.opacity(0.3),
                                    AppTheme.cyberPurple.opacity(0.15),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
        )
    }

    // MARK: - Media Badge

    private var mediaBadge: some View {
        Group {
            if guide.mediaType == "video" {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("VIDEO HƯỚNG DẪN")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundColor(Color(red: 1.0, green: 0.25, blue: 0.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(red: 1.0, green: 0.25, blue: 0.5).opacity(0.12)))
                .overlay(Capsule().stroke(Color(red: 1.0, green: 0.25, blue: 0.5).opacity(0.3), lineWidth: 1))
            } else if guide.mediaType == "image" {
                HStack(spacing: 5) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("HÌNH ẢNH")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundColor(AppTheme.cyberCyan)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppTheme.cyberCyan.opacity(0.12)))
                .overlay(Capsule().stroke(AppTheme.cyberCyan.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("BÀI VIẾT")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
    }

    // MARK: - Media Container

    @ViewBuilder
    private var mediaContainer: some View {
        if guide.mediaType == "video", let urlStr = guide.mediaUrl, let videoURL = URL(string: urlStr) {
            Button {
                Haptics.medium()
                onPlayVideo(videoURL)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                        .aspectRatio(16/9, contentMode: .fit)

                    // Nút Play Neon
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.2, blue: 0.45), AppTheme.cyberPurple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.45).opacity(0.6), radius: 12)

                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: 2)
                        }

                        Text("Chạm để phát video")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    case .failure:
                        HStack(spacing: 8) {
                            Image(systemName: "photo")
                            Text("Không thể tải hình ảnh")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    case .empty:
                        ProgressView()
                            .tint(AppTheme.cyberCyan)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .background(Color.black.opacity(0.3))
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

// MARK: - Trình phát Video Full Screen

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
                ProgressView()
                    .tint(.white)
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
                            .foregroundColor(.white.opacity(0.8))
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

// MARK: - Trình xem Ảnh Full Screen

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
                        .foregroundColor(AppTheme.cyberCyan)
                }
            }
        }
    }
}

