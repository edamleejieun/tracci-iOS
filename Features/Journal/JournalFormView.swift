import SwiftUI
import UIKit

enum JournalFormInitialSection {
    case content
    case photos
}

struct JournalFormView: View {
    let mode: JournalFormMode
    let journalService: JournalService
    let tripId: String
    let searchContext: PlaceSearchContext
    let initialSection: JournalFormInitialSection
    let onToggleFeaturedPhoto: (JournalFormState.ExistingPhoto) async -> String?
    let onSave: (JournalFormState) async -> String?
    let onCancel: () -> Void

    @State private var formState: JournalFormState
    @State private var isSubmitting = false
    @State private var isTogglingFeaturedPhoto = false
    @State private var errorMessage: String?
    @State private var showingLocationSearch = false
    @State private var showSaveSuccess = false
    @State private var showingDetails = false
    @FocusState private var isContentFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var dayWeather: TripWeatherDisplayItem? = nil

    init(
        mode: JournalFormMode,
        journalService: JournalService,
        tripId: String,
        searchContext: PlaceSearchContext = PlaceSearchContext(name: nil, cityName: nil, country: nil, latitude: nil, longitude: nil),
        defaultDate: Date? = nil,
        initialSection: JournalFormInitialSection = .content,
        onToggleFeaturedPhoto: @escaping (JournalFormState.ExistingPhoto) async -> String? = { _ in nil },
        onSave: @escaping (JournalFormState) async -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.journalService = journalService
        self.tripId = tripId
        self.searchContext = searchContext
        self.initialSection = initialSection
        self.onToggleFeaturedPhoto = onToggleFeaturedPhoto
        self.onSave = onSave
        self.onCancel = onCancel

        switch mode {
        case .create:
            let date = defaultDate ?? mode.defaultDate
            _formState = State(initialValue: .empty(defaultOccurredDate: date))
        case .edit(let entry):
            _formState = State(initialValue: JournalFormState.from(entry: entry))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: mode.title,
                saveTitle: "保存",
                isSubmitting: isSubmitting,
                isSaveEnabled: !isFormInvalid,
                showSaveSuccess: showSaveSuccess,
                presentation: .sheet,
                onCancel: handleCancel,
                onSave: {
                    Task { await submit() }
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    pageHeader
                    photoCanvas
                    unlabeledBody
                    detailsDisclosure
                    if !formState.existingPhotos.isEmpty {
                        existingPhotoFeatureStrip
                    }
                    errorBanner
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.card)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .background(
                AppColors.pageBackground
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isContentFocused = false
                    }
            )
            .scrollDismissesKeyboard(.interactively)
        }
        .tracciPageBackground()
        .tracciDismissKeyboardOnBlankTap()
        .toolbar(.hidden, for: .navigationBar)
        .tracciFormSheet()
        .sheet(isPresented: $showingLocationSearch) {
            POISearchSheet(
                searchContext: searchContext,
                onSelect: { location in
                    AppHaptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                        formState.location = location
                    }
                    showingLocationSearch = false
                },
                onCancel: {
                    showingLocationSearch = false
                }
            )
            .tracciSheetPresentation(.subSheetFraction(0.86))
        }
    }

    private var pageDate: Date {
        formState.occurredAtOverride
            ?? formState.defaultOccurredDate
            ?? mode.defaultDate
            ?? Date()
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(JournalFormatting.editorialDate(pageDate))
                .font(AppTypography.editorialMeta)
                .tracking(0.6)
                .foregroundStyle(AppColors.textMuted)

            Text("·")
                .font(AppTypography.editorialMeta)
                .foregroundStyle(AppColors.textDisabled)

            Button {
                showingLocationSearch = true
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    Circle()
                        .fill(AppColors.brandPrimary)
                        .frame(width: 6, height: 6)
                    Text(formState.location?.name ?? "地点")
                        .font(AppTypography.editorialMeta)
                        .tracking(0.4)
                        .foregroundStyle(
                            formState.location == nil ? AppColors.textPlaceholder : AppColors.textSecondary
                        )
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel(formState.location?.name ?? "添加地点")

            if formState.location != nil {
                Button {
                    AppHaptics.lightImpact()
                    withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                        formState.location = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.listBody)
                        .foregroundStyle(AppColors.textDisabled)
                        .frame(minWidth: 28, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除地点")
            }

            Spacer(minLength: AppSpacing.xs)

            if let dayWeather {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: dayWeather.sfSymbolName)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    if let temp = dayWeather.compactTemperatureText {
                        Text(temp)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel(dayWeather.weather)
            }
        }
    }

    private var photoCanvas: some View {
        JournalImagePicker(
            existingPhotos: $formState.existingPhotos,
            localImages: $formState.localImages,
            tripId: tripId,
            journalService: journalService,
            maxImages: 9,
            chrome: .canvas,
            autoPresentOnAppear: initialSection == .photos && formState.existingPhotos.isEmpty && formState.localImages.isEmpty,
            onCaptureDates: { dates in
                guard formState.occurredAtOverride == nil, let first = dates.first else { return }
                formState.occurredAtOverride = first
            }
        )
    }

    private var unlabeledBody: some View {
        ZStack(alignment: .topLeading) {
            if formState.content.isEmpty {
                Text("写一句今天的事就好")
                    .font(AppTypography.narrativeBody)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .padding(.top, 8)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $formState.content)
                .font(AppTypography.narrativeBody)
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isContentFocused)
                .frame(minHeight: 140)
                .onChange(of: formState.content) { _, newValue in
                    if newValue.count > 2000 {
                        formState.content = String(newValue.prefix(2000))
                    }
                }
        }
        .accessibilityLabel("日志内容")
    }

    private var detailsDisclosure: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button {
                AppHaptics.selection()
                withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                    showingDetails.toggle()
                }
            } label: {
                HStack {
                    Text("心情与可见性")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("心情与可见性")
            .accessibilityHint(showingDetails ? "收起" : "展开")

            if showingDetails {
                JournalMoodPicker(selection: $formState.mood)
                highlightSection
                visibilitySection
            }
        }
    }

    private var existingPhotoFeatureStrip: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("想优先看到的照片，点一下星标即可")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Array(formState.existingPhotos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            Task { await toggleFeaturedPhoto(at: index) }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: photo.displayURL) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        AppColors.subtleBackground
                                    }
                                }
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                                Image(systemName: photo.userFeatured ? "star.fill" : "star")
                                    .font(AppTypography.chipSemibold)
                                    .foregroundStyle(photo.userFeatured ? AppColors.featured : .white)
                                    .frame(width: 26, height: 26)
                                    .background(Color.black.opacity(0.34), in: Circle())
                                    .padding(5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.userFeatured ? "取消精选照片" : "精选照片")
                    }
                }
            }
        }
    }

    @MainActor
    private func toggleFeaturedPhoto(at index: Int) async {
        guard formState.existingPhotos.indices.contains(index), !isTogglingFeaturedPhoto else { return }
        let photo = formState.existingPhotos[index]
        isTogglingFeaturedPhoto = true
        defer { isTogglingFeaturedPhoto = false }
        if let message = await onToggleFeaturedPhoto(photo) {
            errorMessage = message
        } else {
            formState.existingPhotos[index].userFeatured.toggle()
        }
    }

    // MARK: - Highlight Section

    private var highlightSection: some View {
        TracciSwitchRow(isOn: Binding(
            get: { formState.isHighlight },
            set: { formState.isHighlight = $0 }
        )) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: formState.isHighlight ? "star.fill" : "star")
                    .foregroundStyle(formState.isHighlight ? AppColors.featured : AppColors.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("标成重要时刻")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("回看时会更容易找到")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(formState.isHighlight ? AppColors.dawnGoldBackground : AppColors.paperWarmLight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(
                    formState.isHighlight ? AppColors.dawnGold.opacity(0.32) : AppColors.borderSubtle.opacity(0.5),
                    lineWidth: 0.8
                )
        )
        .tracciElevation(.l0)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: formState.isHighlight)
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        TracciSwitchRow(isOn: Binding(
            get: { formState.isPrivate },
            set: { formState.isPrivate = $0 }
        )) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: formState.isPrivate ? "lock.fill" : "lock.open")
                    .foregroundStyle(formState.isPrivate ? AppColors.textMuted : AppColors.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("仅自己可见")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("其他行程成员不会看到这篇日志")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(formState.isPrivate ? AppColors.subtleSurface : AppColors.paperWarmLight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(
                    formState.isPrivate ? AppColors.textDisabled.opacity(0.32) : AppColors.borderSubtle.opacity(0.5),
                    lineWidth: 0.8
                )
        )
        .tracciElevation(.l0)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: formState.isPrivate)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage {
            AppElevationCard(level: .l0, role: .utility, radius: AppRadius.medium, padding: 12) {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.danger)
                    Text(errorMessage)
                        .font(AppTypography.labelRegular)
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                }
            }
            .tracciErrorShake(errorMessage, onAppear: true)
        }
    }

    // MARK: - Validation

    private var isFormInvalid: Bool {
        let trimmed = formState.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContent = !trimmed.isEmpty
        let hasImages = !formState.allFileIds.isEmpty
        let tooLong = trimmed.count > 2000
        let tooManyImages = formState.allFileIds.count > 9

        return (!hasContent && !hasImages) || tooLong || tooManyImages || formState.isUploading
    }

    // MARK: - Submit

    private func submit() async {
        guard !isSubmitting else { return }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let saveError = await onSave(formState)
        if let saveError {
            errorMessage = saveError
        } else {
            await TracciFormSaveFeedback.celebrateBeforeDismiss(showSaveSuccess: $showSaveSuccess) {
                onCancel()
            }
        }
    }

    private func handleCancel() {
        isContentFocused = false
        onCancel()
    }
}

// MARK: - Form Mode

enum JournalFormMode: Identifiable {
    case create(defaultDate: Date?)
    case edit(JournalEntry)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let entry): return "edit-\(entry.id)"
        }
    }

    var title: String {
        switch self {
        case .create: return "写日志"
        case .edit: return "编辑日志"
        }
    }

    var defaultDate: Date? {
        if case .create(let date) = self { return date }
        return nil
    }
}

#if DEBUG
#Preview("摊开一页") {
    NavigationStack {
        JournalFormView(
            mode: .create(defaultDate: Date()),
            journalService: JournalPreviewFixtures.journalService,
            tripId: "trip-1",
            onSave: { _ in nil },
            onCancel: {}
        )
    }
}
#endif
