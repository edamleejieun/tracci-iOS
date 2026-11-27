import SwiftUI
import PhotosUI

struct JournalImagePicker: View {
    enum Chrome {
        case compact
        case canvas
    }

    @Binding var existingPhotos: [JournalFormState.ExistingPhoto]
    @Binding var localImages: [JournalFormState.LocalImage]
    let tripId: String
    let journalService: JournalService
    let maxImages: Int
    var chrome: Chrome = .compact
    var autoPresentOnAppear: Bool = false
    var onCaptureDates: (([Date]) -> Void)?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isProcessing = false
    @State private var pickerErrorMessage: String?
    @State private var showingPicker = false
    @State private var didAutoPresent = false

    init(
        existingPhotos: Binding<[JournalFormState.ExistingPhoto]>,
        localImages: Binding<[JournalFormState.LocalImage]>,
        tripId: String,
        journalService: JournalService,
        maxImages: Int = 9,
        chrome: Chrome = .compact,
        autoPresentOnAppear: Bool = false,
        onCaptureDates: (([Date]) -> Void)? = nil
    ) {
        self._existingPhotos = existingPhotos
        self._localImages = localImages
        self.tripId = tripId
        self.journalService = journalService
        self.maxImages = maxImages
        self.chrome = chrome
        self.autoPresentOnAppear = autoPresentOnAppear
        self.onCaptureDates = onCaptureDates
    }

    private var totalCount: Int {
        existingPhotos.count + localImages.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if chrome == .canvas, totalCount == 0 {
                canvasEmptyButton
            } else if totalCount > 0 {
                photoGrid
            }

            if totalCount < maxImages, chrome == .compact || totalCount > 0 {
                addPhotosButton
            }

            if chrome == .compact || totalCount > 0 {
                Text("\(totalCount)/\(maxImages) 张照片")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textDisabled)
            }

            if let pickerErrorMessage {
                Text(pickerErrorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
            }
        }
        .photosPicker(
            isPresented: $showingPicker,
            selection: $selectedItems,
            maxSelectionCount: max(maxImages - totalCount, 1),
            matching: .images
        )
        .onChange(of: selectedItems) { _, newItems in
            Task {
                await processSelectedItems(newItems)
            }
        }
        .task {
            guard autoPresentOnAppear, !didAutoPresent, totalCount == 0 else { return }
            didAutoPresent = true
            await Task.yield()
            showingPicker = true
        }
    }

    private var canvasEmptyButton: some View {
        Button {
            showingPicker = true
        } label: {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text("添加照片")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .background(AppColors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .frame(minHeight: 44)
        .accessibilityLabel("添加照片")
    }

    private var addPhotosButton: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "plus")
                    .font(AppTypography.bodyMedium)
                Text(totalCount == 0 ? "添加照片" : "继续添加照片")
                    .font(AppTypography.bodyMedium)
            }
            .foregroundStyle(AppColors.interactiveText)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(AppColors.brandPrimaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(totalCount == 0 ? "添加照片" : "继续添加照片")
    }

    private var photoGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        return LazyVGrid(columns: columns, spacing: 8) {
            // Existing photos from server
            ForEach(existingPhotos) { photo in
                existingPhotoThumbnail(photo)
            }

            // Newly picked local images
            ForEach(localImages) { image in
                localImageThumbnail(image)
            }
        }
    }

    // MARK: - Existing Photo Thumbnail

    private func existingPhotoThumbnail(_ photo: JournalFormState.ExistingPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: photo.displayURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    photoPlaceholder
                case .empty:
                    photoPlaceholder
                        .overlay {
                            ProgressView()
                                .tint(AppColors.textDisabled)
                        }
                @unknown default:
                    photoPlaceholder
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            // Remove button
            Button {
                removeExistingPhoto(photo)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)
                    .tracciShadow(AppShadow.textStrong)
            }
            .offset(x: 6, y: -6)
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
    }

    // MARK: - Local Image Thumbnail

    private func localImageThumbnail(_ image: JournalFormState.LocalImage) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: image.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }

            // Upload status overlay
            if image.isUploading {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            // Error overlay
            if image.uploadError != nil {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .overlay {
                        VStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Button("重试") {
                                retryUpload(image)
                            }
                            .font(AppTypography.chipSemibold)
                        }
                        .foregroundStyle(.white)
                    }
            }

            // Remove button
            if !image.isUploading {
                Button {
                    removeLocalImage(image)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                        .tracciShadow(AppShadow.textStrong)
                }
                .offset(x: 6, y: -6)
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
    }

    // MARK: - Helpers

    private var thumbnailSize: CGFloat {
        let totalWidth = SafeAreaMetrics.windowWidth - AppSpacing.pageX * 2
        return (totalWidth - 16) / 3
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            .fill(AppColors.subtleBackground)
            .overlay {
                Image(systemName: "photo")
                    .font(AppTypography.listBody)
                    .foregroundStyle(AppColors.textDisabled)
            }
    }

    private func removeExistingPhoto(_ photo: JournalFormState.ExistingPhoto) {
        existingPhotos.removeAll { $0.id == photo.id }
    }

    private func removeLocalImage(_ image: JournalFormState.LocalImage) {
        localImages.removeAll { $0.id == image.id }
    }

    private func processSelectedItems(_ items: [PhotosPickerItem]) async {
        isProcessing = true
        pickerErrorMessage = nil
        defer { isProcessing = false }

        var capturedDates: [Date] = []
        for item in items {
            let processed: ProcessedPickerImage
            do {
                processed = try await ImagePickerProcessing.process(item: item, fileNamePrefix: "journal")
            } catch {
                pickerErrorMessage = error.localizedDescription
                continue
            }

            let localImage = JournalFormState.LocalImage(
                data: processed.data,
                fileName: processed.fileName,
                contentType: processed.contentType,
                width: processed.width,
                height: processed.height,
                capturedAt: processed.capturedAt
            )
            localImages.append(localImage)
            if let capturedAt = processed.capturedAt {
                capturedDates.append(capturedAt)
            }

            let imageId = localImage.id

            // Upload in background
            Task {
                guard let imageIndex = localImages.firstIndex(where: { $0.id == imageId }) else { return }
                guard imageIndex < localImages.count else { return }
                localImages[imageIndex].isUploading = true
                localImages[imageIndex].uploadError = nil

                do {
                    let fileId = try await uploadImage(
                        data: processed.data,
                        fileName: processed.fileName,
                        contentType: processed.contentType,
                        width: processed.width,
                        height: processed.height
                    )

                    guard let imageIndex = localImages.firstIndex(where: { $0.id == imageId }) else { return }
                    localImages[imageIndex].fileId = fileId
                    localImages[imageIndex].isUploading = false
                } catch {
                    guard let imageIndex = localImages.firstIndex(where: { $0.id == imageId }) else { return }
                    localImages[imageIndex].isUploading = false
                    localImages[imageIndex].uploadError = error.localizedDescription
                }
            }
        }

        if !capturedDates.isEmpty {
            onCaptureDates?(capturedDates)
        }
        selectedItems = []
    }

    private func uploadImage(data: Data, fileName: String, contentType: String, width: Int?, height: Int?) async throws -> String {
        let response = try await journalService.uploadImage(
            tripId: tripId,
            imageData: data,
            fileName: fileName,
            contentType: contentType,
            width: width,
            height: height
        )
        return response.id
    }

    private func retryUpload(_ image: JournalFormState.LocalImage) {
        let imageId = image.id
        guard let imageIndex = localImages.firstIndex(where: { $0.id == imageId }) else { return }

        Task {
            guard imageIndex < localImages.count else { return }
            localImages[imageIndex].isUploading = true
            localImages[imageIndex].uploadError = nil

            do {
                let fileId = try await uploadImage(
                    data: image.data,
                    fileName: image.fileName,
                    contentType: image.contentType,
                    width: image.width,
                    height: image.height
                )

                guard let imageIndex = localImages.firstIndex(where: { $0.id == imageId }) else { return }
                localImages[imageIndex].fileId = fileId
                localImages[imageIndex].isUploading = false
            } catch {
                guard let imageIndex = localImages.firstIndex(where: { $0.id == imageId }) else { return }
                localImages[imageIndex].isUploading = false
                localImages[imageIndex].uploadError = error.localizedDescription
            }
        }
    }
}
