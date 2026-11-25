import SwiftUI

enum JournalPhotoCollage {
    static let maxHeroHeight: CGFloat = 260
    static let compactHeroHeight: CGFloat = 180
    static let mosaicHeight: CGFloat = 220
    static let compactMosaicHeight: CGFloat = 160
    static let minHeroHeight: CGFloat = 96
    static let fallbackLandscapeAspect: CGFloat = 4.0 / 3.0

    static func aspectRatio(for photo: JournalPhoto) -> CGFloat {
        photo.aspectRatio ?? fallbackLandscapeAspect
    }

    static func heroSize(containerWidth: CGFloat, photo: JournalPhoto, compact: Bool) -> CGSize {
        let cap = compact ? compactHeroHeight : maxHeroHeight
        let aspect = aspectRatio(for: photo)
        var height = containerWidth / aspect
        var width = containerWidth
        if height > cap {
            height = cap
            width = min(containerWidth, cap * aspect)
        }
        if height < minHeroHeight {
            height = minHeroHeight
            width = min(containerWidth, height * aspect)
        }
        return CGSize(width: width, height: height)
    }

    static func pairHeight(containerWidth: CGFloat, photos: [JournalPhoto], compact: Bool) -> CGFloat {
        let cap = compact ? compactHeroHeight : mosaicHeight
        let cellWidth = (containerWidth - AppSpacing.tight) / 2
        let tallest = photos.prefix(2).map { cellWidth / aspectRatio(for: $0) }.max() ?? cap
        return min(max(tallest, minHeroHeight), cap)
    }
}

struct JournalPhotoGrid: View {
    enum Density {
        case regular
        case compact
    }

    let photos: [JournalPhoto]
    var density: Density = .regular
    var onToggleFeatured: ((JournalPhoto) -> Void)?
    @State private var selectedPhoto: JournalPhoto?
    @Namespace private var photoZoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCompact: Bool { density == .compact }

    var body: some View {
        Group {
            switch photos.count {
            case 0:
                EmptyView()
            case 1:
                heroLayout(photos[0])
            case 2:
                pairLayout
            case 3:
                mosaicLayout
            case 4:
                quadLayout
            default:
                gridLayout
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            JournalPhotoPreview(photos: photos, selectedPhoto: photo)
                .tracciHeroZoomDestination(id: photo.id, in: photoZoomNamespace, reduceMotion: reduceMotion)
        }
    }

    private var collageSpacing: CGFloat { AppSpacing.tight }

    private func heroLayout(_ photo: JournalPhoto) -> some View {
        let cap = isCompact ? JournalPhotoCollage.compactHeroHeight : JournalPhotoCollage.maxHeroHeight
        return photoButton(photo) {
            fittedPhoto(photo, radius: AppRadius.large)
                .aspectRatio(JournalPhotoCollage.aspectRatio(for: photo), contentMode: .fit)
        }
        .frame(maxWidth: .infinity, maxHeight: cap)
    }

    private var pairLayout: some View {
        GeometryReader { geo in
            let height = JournalPhotoCollage.pairHeight(
                containerWidth: geo.size.width,
                photos: photos,
                compact: isCompact
            )
            HStack(spacing: collageSpacing) {
                ForEach(Array(photos.prefix(2))) { photo in
                    photoButton(photo) {
                        fittedPhoto(photo, radius: AppRadius.small)
                    }
                }
            }
            .frame(height: height)
        }
        .frame(height: isCompact ? JournalPhotoCollage.compactMosaicHeight : JournalPhotoCollage.mosaicHeight)
    }

    private var mosaicLayout: some View {
        let height = isCompact ? JournalPhotoCollage.compactMosaicHeight : JournalPhotoCollage.mosaicHeight
        return GeometryReader { geo in
            let spacing = collageSpacing
            let leftWidth = (geo.size.width - spacing) * 0.58
            let rightWidth = geo.size.width - spacing - leftWidth
            let smallHeight = (height - spacing) / 2
            HStack(spacing: spacing) {
                photoButton(photos[0]) {
                    fittedPhoto(photos[0], radius: AppRadius.small)
                }
                .frame(width: leftWidth, height: height)

                VStack(spacing: spacing) {
                    photoButton(photos[1]) {
                        fittedPhoto(photos[1], radius: AppRadius.small)
                    }
                    .frame(width: rightWidth, height: smallHeight)
                    photoButton(photos[2]) {
                        fittedPhoto(photos[2], radius: AppRadius.small)
                    }
                    .frame(width: rightWidth, height: smallHeight)
                }
            }
        }
        .frame(height: height)
    }

    private var quadLayout: some View {
        let height = isCompact ? JournalPhotoCollage.compactMosaicHeight : JournalPhotoCollage.mosaicHeight
        let rowHeight = (height - collageSpacing) / 2
        return VStack(spacing: collageSpacing) {
            HStack(spacing: collageSpacing) {
                ForEach(Array(photos.prefix(2))) { photo in
                    photoButton(photo) {
                        fittedPhoto(photo, radius: AppRadius.small)
                    }
                }
            }
            .frame(height: rowHeight)
            HStack(spacing: collageSpacing) {
                ForEach(Array(photos.dropFirst(2).prefix(2))) { photo in
                    photoButton(photo) {
                        fittedPhoto(photo, radius: AppRadius.small)
                    }
                }
            }
            .frame(height: rowHeight)
        }
        .frame(height: height)
    }

    private var gridLayout: some View {
        let items = Array(photos.prefix(9))
        let rows = stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start..<min(start + 3, items.count)])
        }
        return VStack(spacing: collageSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: collageSpacing) {
                    ForEach(row) { photo in
                        photoButton(photo) {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .background(AppColors.subtleBackground)
                                .overlay {
                                    fittedPhoto(photo, radius: 0)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        }
                    }
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    private func fittedPhoto(_ photo: JournalPhoto, radius: CGFloat) -> some View {
        CachedRemotePhotoView(
            url: photo.collageDisplayURL,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func photoButton<Content: View>(_ photo: JournalPhoto, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                AppHaptics.lightImpact()
                selectedPhoto = photo
            } label: {
                content()
            }
            .pressableCardStyle(scale: 0.98, opacity: 0.92)
            .tracciHeroZoomSource(id: photo.id, in: photoZoomNamespace)

            if let onToggleFeatured {
                Button {
                    AppHaptics.lightImpact()
                    onToggleFeatured(photo)
                } label: {
                    Image(systemName: photo.userFeatured ? "star.fill" : "star")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(photo.userFeatured ? AppColors.dawnGold : .white)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.34), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .accessibilityLabel(photo.userFeatured ? "取消精选照片" : "精选照片")
            }
        }
        .tracciLongPressActions(actions: photoActions(for: photo))
    }

    private func photoActions(for photo: JournalPhoto) -> [TracciActionItem] {
        var actions = [
            TracciActionItem(title: "预览照片", systemImage: "eye") {
                selectedPhoto = photo
            }
        ]
        if let onToggleFeatured {
            actions.append(
                TracciActionItem(
                    title: photo.userFeatured ? "取消精选照片" : "精选这张照片",
                    systemImage: photo.userFeatured ? "star.slash" : "star"
                ) {
                    onToggleFeatured(photo)
                }
            )
        }
        return actions
    }
}

// MARK: - Cached remote photo (grid / list)

/// Fixed-geometry remote image with process cache — prevents CLS and re-fetch flash in grids.
private struct CachedRemotePhotoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            photoPlaceholder

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(AppMotion.animation(AppMotion.imageFade, reduceMotion: reduceMotion)))
            } else if !failed, url != nil {
                ProgressView()
                    .tint(AppColors.textDisabled)
            }
        }
        .clipped()
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            .fill(AppColors.subtleBackground)
            .overlay {
                if failed || url == nil {
                    Image(systemName: "photo")
                        .font(AppTypography.listBody)
                        .foregroundStyle(AppColors.textDisabled)
                }
            }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }

        if let cached = TracciImageCache.image(for: url) {
            image = cached
            failed = false
            return
        }

        failed = false
        if let loaded = await TripCoverImageLoader.load(url: url) {
            image = loaded
            failed = false
        } else {
            image = nil
            failed = true
        }
    }
}

private struct JournalPhotoPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let photos: [JournalPhoto]
    let selectedPhoto: JournalPhoto
    @State private var selectedId: String

    init(photos: [JournalPhoto], selectedPhoto: JournalPhoto) {
        self.photos = photos
        self.selectedPhoto = selectedPhoto
        _selectedId = State(initialValue: selectedPhoto.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedId) {
                ForEach(photos) { photo in
                    CachedRemotePhotoView(
                        url: photo.previewDisplayURL,
                        contentMode: .fit
                    )
                    .background(Color.black)
                    .tag(photo.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))

            Button {
                AppHaptics.lightImpact()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(AppSpacing.card)
            .accessibilityLabel("关闭预览")
        }
    }
}
