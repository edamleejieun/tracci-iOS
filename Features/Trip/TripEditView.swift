import PhotosUI
import SwiftUI
import TracciNetworking

/// V2 Edit Trip — Settings page with focused single-field tasks.
///
/// No global save button. The trip name is edited inline, cover opens PhotosPicker
/// directly, and only destination/date keep the focused context they require.
/// The page itself is pushed onto a NavigationStack (from Home or Trip Detail) and
/// relies on the system back gesture — there is no page-level Done.
///
/// Collaboration entries (members / activity log) and destructive actions (delete)
/// reuse the existing routes and confirmation sheets.
struct TripEditView: View {
    let onDeleted: (() -> Void)?
    let onOpenMembers: ((String, String, TripAccessContext?) -> Void)?
    let onOpenActivityLog: ((String) -> Void)?
    let onTripUpdated: ((Trip) -> Void)?

    @State private var viewModel: TripEditViewModel
    @State private var showingDeleteConfirm = false
    @State private var showingDestinationSelection = false
    @State private var titleDraft: String
    @State private var titleSubmissionError: String?
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var coverFeedback: TracciToastMessage?
    @FocusState private var isTitleFocused: Bool

    init(
        trip: Trip,
        tripService: TripService,
        currentUserAccess: TripAccessContext? = nil,
        onDeleted: (() -> Void)? = nil,
        onOpenMembers: ((String, String, TripAccessContext?) -> Void)? = nil,
        onOpenActivityLog: ((String) -> Void)? = nil,
        onTripUpdated: ((Trip) -> Void)? = nil
    ) {
        self.onDeleted = onDeleted
        self.onOpenMembers = onOpenMembers
        self.onOpenActivityLog = onOpenActivityLog
        self.onTripUpdated = onTripUpdated
        _titleDraft = State(initialValue: trip.title)
        _titleSubmissionError = State(initialValue: nil)
        _viewModel = State(
            initialValue: TripEditViewModel(
                trip: trip,
                tripService: tripService,
                initialAccess: currentUserAccess
            )
        )
    }

    private var effectiveAccess: TripAccessContext? {
        viewModel.effectiveAccess
    }

    private var canShowDelete: Bool {
        onDeleted != nil && viewModel.canDeleteTrip
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                if viewModel.coverPreviewURL != nil || viewModel.canUpdateTrip {
                    coverSection
                }

                basicInfoSection

                if onOpenMembers != nil || onOpenActivityLog != nil {
                    collaborationSection
                }

                if canShowDelete {
                    dangerSection
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.vertical, AppSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .tracciPageBackground()
        .tracciNavigationSubpage()
        .navigationTitle("编辑旅程")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationBarMinimizeOnScroll()
        .onAppear {
            Task { await viewModel.refreshAccess() }
        }
        .onChange(of: viewModel.trip.title) { _, title in
            guard !isTitleFocused else { return }
            titleDraft = title
        }
        .navigationDestination(for: TripEditFocusedRoute.self) { _ in
            TripDateEditorView(
                viewModel: viewModel,
                onTripUpdated: onTripUpdated
            )
        }
        .sheet(isPresented: $showingDestinationSelection) {
            TripDestinationSelectionSheet(
                initialName: viewModel.trip.destinationName,
                isLoading: viewModel.activeMutation == .destination,
                errorMessage: viewModel.mutationError,
                onSelect: { destination, manualName in
                    Task {
                        if await viewModel.updateDestination(destination, manualName: manualName) {
                            onTripUpdated?(viewModel.trip)
                            showingDestinationSelection = false
                        }
                    }
                },
                onCancel: {
                    viewModel.clearMutationError()
                    showingDestinationSelection = false
                }
            )
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingDeleteConfirm,
                tone: .destructive,
                title: "确定要删除这段旅程吗？",
                message: "删除后无法恢复，旅程中的行程、日志和开支记录都将被清除。",
                cancelTitle: "再想想",
                confirmTitle: "删除旅程",
                onConfirm: { Task { await deleteTrip() } }
            )
        }
        .tracciToast($coverFeedback, bottomPadding: 28)
        .onChange(of: viewModel.deleteError) { _, error in
            if let error {
                coverFeedback = .error(error)
            }
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        TracciSettingsSection(title: "基本信息") {
            inlineTitleEditor

            TracciSettingsDivider()

            TracciSettingsRow(
                label: "目的地",
                value: viewModel.destinationDisplayValue.isEmpty ? nil : viewModel.destinationDisplayValue,
                systemImage: "mappin.and.ellipse",
                action: viewModel.canUpdateTrip ? {
                    isTitleFocused = false
                    viewModel.clearMutationError()
                    showingDestinationSelection = true
                } : nil
            )
            .disabled(!viewModel.canUpdateTrip || viewModel.isMutating)

            TracciSettingsDivider()

            NavigationLink(value: TripEditFocusedRoute.dates) {
                TripEditNavigationRow(
                    label: "出行日期",
                    value: viewModel.dateRangeDisplayValue,
                    systemImage: "calendar",
                    valuePlacement: .below
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                isTitleFocused = false
                viewModel.clearMutationError()
            })
            .disabled(!viewModel.canUpdateTrip || viewModel.isMutating)
        }
    }

    private var inlineTitleEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                TracciSettingsGlyph(systemImage: "textformat")

                Text("旅程名称")
                    .font(AppTypography.settingsRowLabel)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize()

                TextField(
                    "",
                    text: $titleDraft,
                    prompt: Text("请输入旅程名称").foregroundStyle(AppColors.textPlaceholder)
                )
                .font(AppTypography.settingsRowValue)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isTitleFocused)
                .onSubmit { isTitleFocused = false }
                .onChange(of: titleDraft) { _, _ in
                    titleSubmissionError = nil
                    viewModel.clearMutationError()
                }
                .onChange(of: isTitleFocused) { _, focused in
                    if !focused {
                        submitInlineTitle()
                    }
                }
                .disabled(!viewModel.canUpdateTrip || viewModel.isMutating)
                .accessibilityLabel("旅程名称")

                if viewModel.activeMutation == .title {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在保存旅程名称")
                }
            }
            .frame(minHeight: AppSpacing.settingsRowMinHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.canUpdateTrip, !viewModel.isMutating else { return }
                isTitleFocused = true
            }

            if let titleErrorMessage {
                Text(titleErrorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, AppSpacing.settingsDividerLeadingInset)
            }
        }
        .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
        .padding(.vertical, AppSpacing.settingsRowVerticalPadding)
        .opacity(viewModel.canUpdateTrip ? 1 : 0.5)
    }

    private var coverSection: some View {
        TracciSettingsSection(
            title: "封面",
            subtitle: "用于首页和旅程详情",
            showsSurface: false
        ) {
            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                coverCard
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canUpdateTrip || viewModel.isMutating)
            .opacity(viewModel.canUpdateTrip ? 1 : 0.5)
            .onChange(of: selectedCoverItem) { _, item in
                guard let item else { return }
                selectedCoverItem = nil
                Task { await uploadCover(from: item) }
            }
            .accessibilityLabel("旅程封面")
            .accessibilityHint(viewModel.coverPreviewURL == nil ? "添加封面" : "更换封面")
        }
    }

    /// Wide editorial cover surface: full-bleed media with a scrim action chip,
    /// or a quiet placeholder that invites adding one.
    private var coverCard: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = viewModel.coverPreviewURL {
                TripCoverView(url: url, height: 168, cornerRadius: AppRadius.large)

                coverActionChip(title: viewModel.activeMutation == .cover ? "正在更新" : "更换封面")
                    .padding(AppSpacing.cozy)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "photo.badge.plus")
                        .font(AppFont.system(26, weight: .medium))
                        .foregroundStyle(AppColors.textPlaceholder)

                    Text(viewModel.activeMutation == .cover ? "正在更新" : "添加封面")
                        .font(AppTypography.buttonTitleMedium)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .background(AppColors.fillSubtle)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                        .strokeBorder(AppColors.borderSubtle, lineWidth: 0.8)
                }
            }

            if viewModel.activeMutation == .cover {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .fill(.black.opacity(0.18))
                ProgressView()
                    .tint(viewModel.coverPreviewURL == nil ? AppColors.brandPrimary : .white)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .accessibilityHidden(true)
    }

    private func coverActionChip(title: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "camera")
                .font(AppTypography.captionSemibold)
            Text(title)
                .font(AppTypography.captionSemibold)
        }
        .foregroundStyle(AppColors.textInverse)
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, 7)
        .background(.black.opacity(0.42), in: Capsule())
    }

    private var collaborationSection: some View {
        TracciSettingsSection(title: "协作") {
            if onOpenMembers != nil {
                TracciSettingsRow(
                    label: "旅程成员",
                    systemImage: "person.2",
                    disclosure: true,
                    action: {
                        isTitleFocused = false
                        openMembers()
                    }
                )
                TracciSettingsDivider()
            }

            if let onOpenActivityLogRequest {
                TracciSettingsRow(
                    label: "旅程动态",
                    systemImage: "clock.arrow.circlepath",
                    disclosure: true,
                    action: {
                        isTitleFocused = false
                        onOpenActivityLogRequest()
                    }
                )
            }
        }
    }

    private var dangerSection: some View {
        TracciSettingsSection(title: "危险操作", showsSurface: false) {
            Button(role: .destructive) {
                isTitleFocused = false
                showingDeleteConfirm = true
            } label: {
                HStack(spacing: AppSpacing.tight) {
                    if viewModel.isDeleting {
                        ProgressView().tint(AppColors.danger)
                    } else {
                        Image(systemName: "trash").font(AppTypography.bodySemibold)
                    }
                    Text(viewModel.isDeleting ? "删除中..." : "删除旅程")
                        .font(AppTypography.buttonTitle)
                }
                .foregroundStyle(viewModel.isDeleting ? AppColors.textDisabled : AppColors.danger)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous)
                        .stroke(AppColors.danger.opacity(0.22), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isDeleting)
        }
    }

    // MARK: - Actions

    private var normalizedTitleDraft: String {
        titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTitleChanges: Bool {
        normalizedTitleDraft != viewModel.trip.title
    }

    private var titleCharacterCount: Int {
        normalizedTitleDraft.count
    }

    private var titleDraftIsValid: Bool {
        !normalizedTitleDraft.isEmpty && titleCharacterCount <= viewModel.titleMaxLength
    }

    private var canSubmitTitle: Bool {
        viewModel.canUpdateTrip
            && viewModel.activeMutation == nil
            && hasTitleChanges
            && titleDraftIsValid
    }

    private var titleErrorMessage: String? {
        if titleCharacterCount > viewModel.titleMaxLength {
            return "旅程名称不能超过 \(viewModel.titleMaxLength) 字"
        }
        if hasTitleChanges, normalizedTitleDraft.isEmpty {
            return "请输入旅程名称"
        }
        return titleSubmissionError
    }

    private func submitInlineTitle() {
        guard canSubmitTitle else { return }
        titleSubmissionError = nil
        Task {
            if await viewModel.updateTitle(normalizedTitleDraft) {
                titleDraft = viewModel.trip.title
                isTitleFocused = false
                onTripUpdated?(viewModel.trip)
                AppHaptics.success()
            } else {
                titleSubmissionError = viewModel.mutationError
            }
        }
    }

    private func uploadCover(from item: PhotosPickerItem) async {
        viewModel.clearMutationError()
        do {
            let processed = try await ImagePickerProcessing.process(
                item: item,
                fileNamePrefix: "trip_cover"
            )
            if await viewModel.uploadCover(
                imageData: processed.data,
                fileName: processed.fileName,
                contentType: processed.contentType,
                width: processed.width,
                height: processed.height
            ) {
                onTripUpdated?(viewModel.trip)
                coverFeedback = .success("封面已更新")
                AppHaptics.success()
            } else if let message = viewModel.mutationError {
                coverFeedback = .error(message)
            }
        } catch {
            coverFeedback = .error(error.localizedDescription)
        }
    }

    private var onOpenActivityLogRequest: (() -> Void)? {
        onOpenActivityLog.map { handler in
            { handler(viewModel.trip.id) }
        }
    }

    private func openMembers() {
        onOpenMembers?(viewModel.trip.id, viewModel.trip.title, effectiveAccess)
    }

    private func deleteTrip() async {
        if await viewModel.deleteTrip() {
            onDeleted?()
        }
    }

}

private enum TripEditFocusedRoute: Hashable {
    case dates
}

private struct TripEditNavigationRow: View {
    enum ValuePlacement {
        case trailing
        case below
    }

    let label: String
    let value: String?
    let systemImage: String
    var valuePlacement: ValuePlacement = .trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TracciSettingsGlyph(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(AppTypography.settingsRowLabel)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if valuePlacement == .below, let value, !value.isEmpty {
                    Text(value)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            if valuePlacement == .trailing, let value, !value.isEmpty {
                Text(value)
                    .font(AppTypography.settingsRowValue)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Image(systemName: "chevron.right")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPlaceholder)
        }
        .frame(minHeight: AppSpacing.settingsRowMinHeight)
        .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
        .padding(.vertical, AppSpacing.settingsRowVerticalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityHint("打开\(label)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Trip Edit — Settings") {
    let sampleTrip = Trip(
        id: "preview-trip",
        title: "京都秋日漫游",
        startDate: "2026-10-01",
        endDate: "2026-10-05",
        status: .planning,
        totalDays: 5,
        destination: TripDestination(name: "京都", provider: "APPLE", country: "日本"),
        coverPhoto: nil,
        baseCurrency: "CNY",
        totalCny: nil,
        nodeCount: 8,
        journalCount: 3,
        expenseCount: 5,
        access: TripAccessContext(role: .owner, permissions: [.updateTrip, .deleteTrip, .editContent]),
        createdAt: "2026-08-01T00:00:00Z",
        updatedAt: "2026-08-10T00:00:00Z"
    )

    NavigationStack {
        TripEditView(
            trip: sampleTrip,
            tripService: TripService(apiClient: APIClient(), fileUploadService: FileUploadService(apiClient: APIClient())),
            onDeleted: {},
            onOpenMembers: { _, _, _ in },
            onOpenActivityLog: { _ in }
        )
    }
}
#endif
