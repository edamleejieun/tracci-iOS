import SwiftUI
import TracciNetworking
import UIKit

/// V2 Create Trip — single continuous Task host, presented full-screen for brand immersion.
///
/// Per the V2 guardrail there is exactly one modal Task host for Create Trip
/// (the full-screen cover in `MainScenePresentationModifier`). Inside that host we never
/// stack child sheets for destination or dates:
///
/// 1. The initial screen IS the destination search surface — no source-selection
///    middleman. Saved Places are intentionally reserved for Add Itinerary Node.
/// 2. Picking a destination swaps the search surface for the selected-destination
///    summary; the date row appears in place.
/// 3. Tapping the date row pushes the calendar inside the SAME `NavigationStack`;
///    on confirm it pops back and the auto-generated title appears in place.
/// 4. The title is editable inline; `titleOrigin.userEdited` is respected.
///
/// Tapping the destination row re-opens the search surface (draft preserved).
/// Cover / member / permission are intentionally absent — those belong to Edit.
///
/// The full-screen host ignores the top safe area so the page canvas runs under the
/// status bar; the editorial chrome below positions itself with the resolved inset.
struct TripCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSuccess: (Trip) -> Void

    @State private var viewModel: TripCreateViewModel
    @State private var path: [CreateRoute] = []
    @State private var isChoosingDestination = true
    @State private var showingDiscardConfirmation = false
    @State private var submitTask: Task<Void, Never>?
    @State private var didCompleteSubmission = false
    @State private var topInset = SafeAreaMetrics.top

    init(
        tripService: TripService,
        seed: TripCreateSeed? = nil,
        onSuccess: @escaping (Trip) -> Void
    ) {
        self.onSuccess = onSuccess
        _viewModel = State(
            initialValue: TripCreateViewModel(tripService: tripService, seed: seed)
        )
        // 目的地已由探索预填，直接落到日期这一步，不再走搜索。
        _isChoosingDestination = State(initialValue: seed == nil)
    }

    var body: some View {
        NavigationStack(path: $path) {
            TracciTaskSheetScaffold(
                title: "创建旅程",
                ctaTitle: "创建旅程",
                ctaSystemImage: "plus",
                isCTAEnabled: viewModel.isFormValid,
                isCTALoading: viewModel.isSubmitting,
                errorMessage: viewModel.errorMessage,
                isDirty: viewModel.isDirty,
                presentation: .pushed,
                onAttemptToDismiss: requestDismiss,
                onCancel: requestDismiss,
                onCTA: startSubmission,
                chrome: { createChrome }
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    if isChoosingDestination {
                        TripCreateDestinationSearchView(
                            onSelect: { destination in
                                dismissKeyboard()
                                transitionToForm {
                                    isChoosingDestination = false
                                    viewModel.selectDestination(destination)
                                }
                            },
                            onUseManual: { name in
                                dismissKeyboard()
                                transitionToForm {
                                    isChoosingDestination = false
                                    viewModel.useManualDestination(name)
                                }
                            }
                        )
                    } else {
                        TracciSettingsSection(title: "基本信息") {
                            destinationRow
                            TracciSettingsDivider()
                            dateRow
                        }
                        .fadeSlideIn(index: 0)
                    }

                    if viewModel.showsTitleEditor {
                        titleSection
                            .fadeSlideIn(index: 1)
                    }
                }
                .animation(
                    AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion),
                    value: viewModel.showsTitleEditor
                )
            }
            .tracciFormChromePage(presentation: .pushed)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CreateRoute.self) { route in
                switch route {
                case .destinationPicker:
                    TripCreateDestinationSearchView(
                        configuration: .destination(initialQuery: viewModel.destinationDisplayName),
                        onSelect: { destination in
                            dismissKeyboard()
                            viewModel.selectDestination(destination)
                            popRoute()
                        },
                        onUseManual: { name in
                            dismissKeyboard()
                            viewModel.useManualDestination(name)
                            popRoute()
                        },
                        onCancel: cancelDestinationEdit
                    )
                    .padding(.horizontal, AppSpacing.pageX)
                    .background(AppColors.backgroundGrouped.ignoresSafeArea())
                    .toolbar(.hidden, for: .navigationBar)
                case .datePicker:
                    TracciDateRangePickerSheet(
                        startDate: viewModel.startDate,
                        endDate: viewModel.endDate,
                        presentation: .pushed,
                        onConfirm: { start, end in
                            viewModel.updateDates(start: start, end: end)
                            // Pushed pickers keep navigation with the host. Create has
                            // no status-change confirmation, so pop right after commit.
                            popRoute()
                        },
                        onCancel: {
                            if !path.isEmpty { path.removeLast() }
                        }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingDiscardConfirmation,
                tone: .destructive,
                title: "放弃创建旅程？",
                message: "已填写的目的地、日期和名称不会保留。",
                cancelTitle: "继续编辑",
                confirmTitle: "放弃",
                onConfirm: dismiss.callAsFunction
            )
        }
        .onDisappear {
            submitTask?.cancel()
            submitTask = nil
        }
    }

    // MARK: - Editorial chrome

    /// Full-screen task chrome: quiet close, editorial title block, and the
    /// destination → date → name progress meta. The canvas ignores the top safe
    /// area, so pad with the resolved inset to stay below the Dynamic Island.
    private var createChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, AppSpacing.pageX)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("创建旅程")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("先选目的地和日期，名称会自动生成")
                    .font(AppTypography.pageSubtitle)
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, 2)

            TripCreateProgressSteps(current: currentCreateStep)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.md)

            AppCreekDivider()
                .padding(.top, AppSpacing.md)
        }
        .padding(.top, SafeAreaMetrics.chromeTopPadding(using: topInset))
        .padding(.bottom, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundGrouped)
        .tracciReadsSafeAreaTop($topInset)
    }

    private var closeButton: some View {
        Button(action: requestDismiss) {
            Image(systemName: "xmark")
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppColors.fillSubtle, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44, alignment: .leading)
        .disabled(viewModel.isSubmitting)
        .opacity(viewModel.isSubmitting ? 0.4 : 1)
        .accessibilityLabel("取消创建")
    }

    private var currentCreateStep: TripCreateProgressSteps.Step {
        if isChoosingDestination || !viewModel.hasDestination { return .destination }
        if !viewModel.hasCompleteDateRange { return .dates }
        return .title
    }

    private func transitionToForm(_ changes: () -> Void) {
        withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
            changes()
        }
    }

    // MARK: - Rows

    private var destinationRow: some View {
        TracciSettingsRow(
            label: "目的地",
            value: viewModel.hasDestination ? viewModel.destinationDisplayName : nil,
            systemImage: "mappin.and.ellipse",
            // 规格 §7.3：探索带来的目的地只读预填，不给改的入口。
            showsChevron: !viewModel.isDestinationLocked,
            action: viewModel.isDestinationLocked ? nil : { path.append(.destinationPicker) }
        )
    }

    private var dateRow: some View {
        TracciSettingsRow(
            label: "出行日期",
            value: dateRowValue,
            systemImage: "calendar",
            action: { path.append(.datePicker) }
        )
    }

    private var dateRowValue: String? {
        guard let start = viewModel.startDate, let end = viewModel.endDate else { return nil }
        let days = TracciDateContext.inclusiveDayCount(start: start, end: end) ?? 1
        return "\(TripDateFormatting.displayString(from: start)) — \(TripDateFormatting.displayString(from: end)) · \(days) 天"
    }

    // MARK: - Title editor

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("旅程名称")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
                .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)

            TracciSettingsSection {
                TextField(
                    "",
                    text: titleBinding,
                    prompt: Text("例如 京都 3 日游").foregroundStyle(AppColors.textPlaceholder)
                )
                .font(AppTypography.formValue)
                .foregroundStyle(AppColors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
                .padding(.vertical, AppSpacing.settingsRowVerticalPadding)
                .frame(minHeight: AppSpacing.settingsRowMinHeight)
            }

            HStack {
                if let error = viewModel.validationMessage(for: .title) {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                }
                Spacer()
                Text("\(viewModel.title.count)/\(viewModel.titleMaxLength)")
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        viewModel.title.count > viewModel.titleMaxLength
                            ? AppColors.danger
                            : AppColors.textDisabled
                    )
            }
            .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { viewModel.title },
            set: { viewModel.userDidEditTitle($0) }
        )
    }

    // MARK: - Submit

    private func startSubmission() {
        guard submitTask == nil, !viewModel.isSubmitting, !didCompleteSubmission else { return }
        submitTask = Task {
            await submit()
            submitTask = nil
        }
    }

    private func submit() async {
        guard let trip = await viewModel.submit(),
              !Task.isCancelled,
              !didCompleteSubmission else { return }
        didCompleteSubmission = true
        dismissKeyboard()
        onSuccess(trip)
        dismiss()
    }

    private func requestDismiss() {
        switch viewModel.dismissDecision {
        case .dismissImmediately:
            dismiss()
        case .confirmDiscard:
            showingDiscardConfirmation = true
        case .blockedWhileSubmitting:
            return
        }
    }

    private func popRoute() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    private func cancelDestinationEdit() {
        dismissKeyboard()
        popRoute()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private enum CreateRoute: Hashable {
    case destinationPicker
    case datePicker
}

// MARK: - Progress steps

/// Quiet editorial progress meta for the Create Trip task: 目的地 → 日期 → 名称.
/// Pure presentation — it only mirrors the draft state already owned by the ViewModel.
private struct TripCreateProgressSteps: View {
    enum Step: Int, CaseIterable {
        case destination
        case dates
        case title

        var label: String {
            switch self {
            case .destination: return "目的地"
            case .dates: return "日期"
            case .title: return "名称"
            }
        }
    }

    let current: Step

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Step.allCases.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(connectorColor(entering: step))
                        .frame(width: 16, height: 1)
                        .padding(.horizontal, AppSpacing.tight)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(dotColor(for: step))
                        .frame(width: 6, height: 6)

                    Text(step.label)
                        .font(AppTypography.chipSemibold)
                        .foregroundStyle(textColor(for: step))
                }
            }
        }
        .animation(
            AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion),
            value: current
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("创建进度：第 \(current.rawValue + 1) 步，共 3 步，\(current.label)")
    }

    private func isDone(_ step: Step) -> Bool {
        step.rawValue < current.rawValue
    }

    private func isActive(_ step: Step) -> Bool {
        step == current
    }

    private func dotColor(for step: Step) -> Color {
        if isActive(step) { return AppColors.brandPrimary }
        if isDone(step) { return AppColors.brandPrimary.opacity(0.42) }
        return AppColors.textDisabled.opacity(0.6)
    }

    private func textColor(for step: Step) -> Color {
        if isActive(step) { return AppColors.textPrimary }
        if isDone(step) { return AppColors.textMuted }
        return AppColors.textPlaceholder
    }

    private func connectorColor(entering step: Step) -> Color {
        isDone(step) || isActive(step)
            ? AppColors.brandPrimary.opacity(0.28)
            : AppColors.borderDefault
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Trip Create — Search") {
    TripCreateView(
        tripService: TripService(apiClient: APIClient(), fileUploadService: FileUploadService(apiClient: APIClient())),
        onSuccess: { _ in }
    )
}

/// 探索城市页「用这里创建旅程」：目的地只读预填，直接落到日期这一步（规格 §7.3）。
#Preview("Trip Create — 探索预填目的地") {
    TripCreateView(
        tripService: TripService(apiClient: APIClient(), fileUploadService: FileUploadService(apiClient: APIClient())),
        seed: TripCreateSeed(destinationSavedPlaceId: "saved-preview", destinationName: "杭州"),
        onSuccess: { _ in }
    )
}
#endif
