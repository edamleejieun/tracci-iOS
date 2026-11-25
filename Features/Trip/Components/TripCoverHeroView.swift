import SwiftUI
import UIKit

/// Detail-page cover hero with an iOS wallpaper-style blurred top extension for Dynamic Island / notch.
struct TripCoverHeroView: View {
    let url: URL?
    var fallbackURL: URL? = nil
    var heroHeight: CGFloat = 280
    var pullOffset: CGFloat = 0
    let safeAreaTop: CGFloat

    @State private var loadedImage: UIImage?
    @State private var phase: TripCoverChromePhase = .empty

    private var loadToken: String {
        [url?.absoluteString, fallbackURL?.absoluteString]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    var body: some View {
        let stretch = min(max(pullOffset, 0), 96)
        let totalHeight = safeAreaTop + heroHeight + stretch

        ZStack(alignment: .top) {
            if let loadedImage {
                TripCoverHeroImageLayers(
                    image: Image(uiImage: loadedImage),
                    safeAreaTop: safeAreaTop,
                    heroHeight: heroHeight,
                    stretch: stretch
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.22)))
            } else {
                heroChrome(phase: phase, totalHeight: totalHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .offset(y: -stretch)
        .clipped()
        .accessibilityHidden(true)
        .task(id: loadToken) {
            await loadCoverImage()
        }
    }

    @MainActor
    private func loadCoverImage() async {
        loadedImage = nil

        guard let url else {
            phase = .empty
            return
        }

        phase = .loading
        if let image = await TripCoverImageLoader.load(url: url) {
            loadedImage = image
            phase = .empty
            return
        }

        if let fallbackURL, fallbackURL != url, let image = await TripCoverImageLoader.load(url: fallbackURL, timeout: 8) {
            loadedImage = image
            phase = .empty
            return
        }

        phase = .failure
    }

    private func heroChrome(phase: TripCoverChromePhase, totalHeight: CGFloat) -> some View {
        ZStack {
            TripCoverChrome(phase: phase, iconPointSize: 28, showsGlyph: false)

            // Glyph centers in the hero band below the status bar / Dynamic Island.
            VStack(spacing: 0) {
                Color.clear.frame(height: safeAreaTop)
                Spacer(minLength: 0)
                heroGlyph(for: phase)
                Spacer(minLength: 0)
            }
        }
        .frame(height: totalHeight)
    }

    private func heroGlyph(for phase: TripCoverChromePhase) -> some View {
        let diameter: CGFloat = 58
        return ZStack {
            Circle()
                .fill(AppColors.cardBackground.opacity(phase == .failure ? 0.72 : 0.78))
                .frame(width: diameter, height: diameter)
            Image(systemName: phase == .failure ? "photo.badge.exclamationmark" : (phase == .loading ? "photo" : "map"))
                .font(AppTypography.pageTitle)
                .foregroundStyle(phase == .failure ? AppColors.textMuted.opacity(0.72) : AppColors.textDisabled)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}

struct TripCoverPreviewSource: Identifiable, Equatable {
    let urls: [URL]
    let accessibilityLabel: String

    var id: String {
        urls.map(\.absoluteString).joined(separator: "|")
    }
}

/// 旅程封面全屏预览：原图优先，失败时依次回退，并使用 UIScrollView 提供原生缩放与拖动。
struct TripCoverFullScreenPreview: View {
    @Environment(\.dismiss) private var dismiss

    let source: TripCoverPreviewSource

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                if let image {
                    TripCoverZoomableImage(
                        image: image,
                        accessibilityLabel: source.accessibilityLabel,
                        onPullDown: dismiss.callAsFunction
                    )
                    .ignoresSafeArea()
                } else if isLoading {
                    AppProgressIndicator(tint: .white, diameter: 26)
                } else if failed {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 30, weight: .regular))
                        Text("封面加载失败")
                            .font(AppTypography.bodySemibold)
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                AppHaptics.lightImpact()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.36), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.sm)
            .padding(.trailing, AppSpacing.card)
            .accessibilityLabel("关闭封面预览")
        }
        .statusBarHidden(true)
        .task(id: source.id) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        isLoading = true
        failed = false

        let cached = source.urls.lazy.compactMap { url in
            TracciImageCache.image(for: url).map { (url, $0) }
        }.first
        if let cached {
            image = cached.1
            isLoading = false
            if cached.0 == source.urls.first {
                return
            }
        }

        if let originalURL = source.urls.first,
           let original = await TripCoverImageLoader.load(url: originalURL) {
            guard !Task.isCancelled else { return }
            image = original
            isLoading = false
            return
        }

        if image != nil {
            return
        }

        for url in source.urls.dropFirst() {
            guard !Task.isCancelled else { return }
            if let loaded = await TripCoverImageLoader.load(url: url) {
                image = loaded
                isLoading = false
                return
            }
        }

        isLoading = false
        failed = true
    }
}

private struct TripCoverZoomableImage: UIViewRepresentable {
    let image: UIImage
    let accessibilityLabel: String
    let onPullDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPullDown: onPullDown)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = context.coordinator.imageView
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityLabel = accessibilityLabel
        imageView.accessibilityHint = "双指缩放，双击可放大或还原；未放大时下拉可关闭"
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        scrollView.panGestureRecognizer.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )

        context.coordinator.scrollView = scrollView
        imageView.image = image
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onPullDown = onPullDown
        context.coordinator.imageView.accessibilityLabel = accessibilityLabel
        guard context.coordinator.imageView.image !== image else { return }
        context.coordinator.imageView.image = image
        scrollView.setZoomScale(1, animated: false)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        var onPullDown: () -> Void
        private var didTriggerPullDown = false

        init(onPullDown: @escaping () -> Void) {
            self.onPullDown = onPullDown
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(2.5, scrollView.maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            scrollView.zoom(
                to: CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                ),
                animated: true
            )
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView,
                  scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
            else { return }

            switch recognizer.state {
            case .began:
                didTriggerPullDown = false
            case .ended:
                let translation = recognizer.translation(in: scrollView)
                guard !didTriggerPullDown,
                      translation.y > 120,
                      abs(translation.y) > abs(translation.x)
                else { return }
                didTriggerPullDown = true
                onPullDown()
            default:
                break
            }
        }
    }
}

private struct TripCoverHeroImageLayers: View {
    let image: Image
    let safeAreaTop: CGFloat
    let heroHeight: CGFloat
    let stretch: CGFloat

    /// 状态栏可读性 scrim 高度（在安全区下方再淡出一点）。
    private var statusScrimHeight: CGFloat { safeAreaTop + 36 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalHeight = safeAreaTop + heroHeight + stretch

            ZStack(alignment: .top) {
                // 封面全出血到状态栏/灵动岛：同一张图连续铺满，避免顶部灰条与下方画面割裂。
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: totalHeight)
                    .clipped()

                // 轻量顶部暗角：保证时间/信号/电量对比度，不用重模糊（重模糊易发灰、像第二块安全区底）。
                if safeAreaTop > 0 {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.42),
                            Color.black.opacity(0.16),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: width, height: statusScrimHeight)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: totalHeight)
        }
        .frame(height: safeAreaTop + heroHeight + stretch)
    }
}

#Preview("With Image") {
    TripCoverHeroView(
        url: URL(string: "https://images.unsplash.com/photo-1559827291-72ee739d0d9a?w=800&h=600&fit=crop"),
        safeAreaTop: 54
    )
    .ignoresSafeArea(edges: .top)
}

#Preview("Placeholder") {
    TripCoverHeroView(url: nil, safeAreaTop: 54)
        .ignoresSafeArea(edges: .top)
}
