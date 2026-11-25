import SwiftUI
import UIKit

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: FocusedField?

    var tripId: String = ""
    let tripStartDate: String
    let tripEndDate: String
    let baseCurrency: String
    let isSubmitting: Bool
    let submitError: String?
    let members: [TripMemberResp]
    let currentUserId: String?
    let itineraryOptions: [ExpenseItineraryLink]
    let customCategories: [CustomExpenseCategory]
    /// 分类添加/删除的失败原因（透传自 ExpenseViewModel.categoryErrorMessage）。
    var categoryError: String? = nil
    let onAddCategory: (String) async -> CustomExpenseCategory?
    let onDeleteCategory: (String) async -> Bool
    let onSubmit: (CreateExpenseRequest) async -> Bool

    @State private var amount: String = ""
    @State private var selectedCategory: ExpenseCategory?
    /// 当前仅支持人民币（提交固定 CNY）；外币记账与选择器 UI 待后续版本。
    private let selectedCurrency: ExpenseCurrency = .cny
    @State private var note: String = ""
    @State private var spentAt: Date = Date()
    @State private var pressedCategory: ExpenseCategory?
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingItineraryPicker = false
    @State private var showingAddCategory = false
    @State private var showSaveSuccess = false
    @State private var selectedLink: ExpenseItineraryLink?
    /// 长按删除的确认目标（自定义分类）。
    @State private var pendingDeleteCategory: CustomExpenseCategory?

    // Group expense fields
    @State private var expenseScope: ExpenseScope = .personal
    @State private var payerMemberId: String?
    @State private var selectedParticipantIds: Set<String> = []
    @State private var extrasExpanded = false

    private let isEditing: Bool

    private enum FocusedField {
        case amount
        case note
    }

    init(
        expense: Expense? = nil,
        duplicate: Expense? = nil,
        defaultDate: Date? = nil,
        tripId: String = "",
        tripStartDate: String,
        tripEndDate: String,
        baseCurrency: String,
        isSubmitting: Bool,
        submitError: String?,
        members: [TripMemberResp] = [],
        currentUserId: String? = nil,
        itineraryOptions: [ExpenseItineraryLink] = [],
        customCategories: [CustomExpenseCategory] = [],
        categoryError: String? = nil,
        onAddCategory: @escaping (String) async -> CustomExpenseCategory? = { _ in nil },
        onDeleteCategory: @escaping (String) async -> Bool = { _ in true },
        initialLink: ExpenseItineraryLink? = nil,
        onSubmit: @escaping (CreateExpenseRequest) async -> Bool
    ) {
        self.tripId = tripId
        self.tripStartDate = tripStartDate
        self.tripEndDate = tripEndDate
        self.baseCurrency = baseCurrency
        self.isSubmitting = isSubmitting
        self.submitError = submitError
        self.members = members
        self.currentUserId = currentUserId
        self.itineraryOptions = itineraryOptions
        self.customCategories = customCategories
        self.categoryError = categoryError
        self.onAddCategory = onAddCategory
        self.onDeleteCategory = onDeleteCategory
        self.onSubmit = onSubmit

        if let expense {
            isEditing = true
            _amount = State(initialValue: expense.amountInput)
            _selectedCategory = State(initialValue: expense.category)
            _note = State(initialValue: expense.note ?? "")
            _spentAt = State(initialValue: expense.spentAtDate ?? ExpenseFormatters.tripDateRange(start: tripStartDate, end: tripEndDate).lowerBound)
            _expenseScope = State(initialValue: expense.expenseScope ?? .personal)
            _payerMemberId = State(initialValue: expense.payerMemberId)
            _selectedParticipantIds = State(initialValue: Set(expense.participantMemberIds ?? []))
            _selectedLink = State(initialValue: Self.matchingLink(in: itineraryOptions, expense: expense) ?? initialLink)
        } else {
            isEditing = false
            let range = ExpenseFormatters.tripDateRange(start: tripStartDate, end: tripEndDate)
            let initialDate: Date
            if let defaultDate {
                initialDate = TracciCalendarFormatting.mergeTime(Date(), preservingDateFrom: defaultDate)
            } else {
                initialDate = Self.defaultExpenseDate(in: range)
            }
            let clampedDate = Self.clamped(initialDate, to: range)
            let lastCategory = ExpenseFormDraft.category(
                fromStoredId: ExpenseLastCategoryStore.load(tripId: tripId),
                customCategories: customCategories
            )
            let draft = ExpenseFormDraft.createDefaults(
                members: members,
                currentUserId: currentUserId,
                suggestedCategory: initialLink?.suggestedCategory,
                lastCategory: lastCategory,
                duplicate: duplicate
            )
            _spentAt = State(initialValue: clampedDate)
            _selectedLink = State(initialValue: initialLink)
            _amount = State(initialValue: draft.amount)
            _selectedCategory = State(initialValue: draft.category)
            _expenseScope = State(initialValue: draft.expenseScope)
            _payerMemberId = State(initialValue: draft.payerMemberId)
            _selectedParticipantIds = State(initialValue: draft.participantIds)
            if let duplicate {
                _note = State(initialValue: duplicate.note ?? "")
                _selectedLink = State(
                    initialValue: Self.matchingLink(in: itineraryOptions, expense: duplicate) ?? initialLink
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: isEditing ? "编辑开支" : "记一笔",
                saveTitle: "保存",
                isSubmitting: isSubmitting,
                isSaveEnabled: isFormValid,
                showSaveSuccess: showSaveSuccess,
                presentation: .sheet,
                onCancel: handleCancel,
                onSave: {
                    Task { await submit() }
                }
            )

            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: AppSpacing.pageTop) {
                        amountInputSection
                            .tracciFormSectionAppear(index: 0)
                        if let preview = splitPreview {
                            splitPreviewRow(preview)
                                .tracciFormSectionAppear(index: 1)
                        }
                        categoryPickerSection
                            .tracciFormSectionAppear(index: 2)
                        extrasDisclosure
                            .tracciFormSectionAppear(index: 3)
                        errorBanner
                            .tracciFormSectionAppear(index: 4)
                    }
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.vertical, AppSpacing.pageTop)
                    // Fill the viewport so the area below form fields is real blank space to tap.
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                    .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: expenseScope)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppColors.pageBackground)
            }
            .task {
                guard !isEditing else { return }
                try? await Task.sleep(nanoseconds: 120_000_000)
                focusedField = .amount
            }
            .sheet(isPresented: $showingItineraryPicker) {
                ExpenseItineraryLinkPickerSheet(
                    options: itineraryOptions,
                    selected: selectedLink,
                    spentAt: spentAt
                ) { selectedLink = $0 }
            }
            .sheet(isPresented: $showingAddCategory) {
                ExpenseCategoryAddSheet(
                    errorMessage: categoryError,
                    onAdd: onAddCategory
                ) { created in
                    withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                        selectedCategory = created.asExpenseCategory
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                TracciDatePickerSheet(
                    title: "消费日期",
                    subtitle: "选择这笔开支发生的日期。",
                    date: spentAt,
                    minimumDate: dateRange.lowerBound,
                    maximumDate: dateRange.upperBound
                ) { selectedDate in
                    spentAt = Self.clamped(
                        TracciCalendarFormatting.mergeDate(selectedDate, preservingTimeFrom: spentAt),
                        to: dateRange
                    )
                }
            }
            .sheet(isPresented: $showingTimePicker) {
                TracciTimePickerSheet(
                    title: "消费时间",
                    subtitle: "选择这笔开支发生的时间。",
                    date: spentAt
                ) { selectedTime in
                    spentAt = Self.clamped(
                        TracciCalendarFormatting.mergeTime(selectedTime, preservingDateFrom: spentAt),
                        to: dateRange
                    )
                }
            }
        }
        // Match journal / itinerary form sheets: page surface + hidden nav bar chrome.
        .tracciPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        // Blank-area / chrome taps dismiss keyboard — no Done toolbar on decimal pad.
        .tracciDismissKeyboardOnBlankTap()
        .tracciFormSheet()
        .confirmationDialog(
            "删除“\(pendingDeleteCategory?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteCategory != nil },
                set: { if !$0 { pendingDeleteCategory = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteCategory
        ) { category in
            Button("删除", role: .destructive) {
                Task { await deleteCategory(category) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除后无法恢复")
        }
        // A deleted category (here or elsewhere) must not stay selected.
        .onChange(of: customCategories) { _, currentCategories in
            guard let selectedCategory,
                  let customId = selectedCategory.customId,
                  !currentCategories.contains(where: { $0.id == customId })
            else { return }
            self.selectedCategory = nil
        }
    }

    private func handleCancel() {
        dismissKeyboard()
        dismiss()
    }

    private func dismissKeyboard() {
        focusedField = nil
        // Also resign system first responder so note `TextEditor` (internal focus) clears too.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    // MARK: - Amount Input

    /// Amount field is the primary input of this form. Keep the card's view identity
    /// stable across focus changes — swapping `AppElevationCard` level/role (and
    /// animating that swap) rebuilds the hosted `TextField` and can hang the main
    /// thread in an AttributeGraph / focus loop on iOS 17+.
    private var amountInputSection: some View {
        let isAmountFocused = focusedField == .amount

        return AppElevationCard(
            level: .l1,
            role: .content,
            radius: AppRadius.large,
            padding: 20
        ) {
            VStack(spacing: AppSpacing.tight) {
                HStack(alignment: .center, spacing: AppSpacing.xs) {
                    Text(selectedCurrency.symbol)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(amount.isEmpty ? AppColors.textDisabled : AppColors.textMuted)

                    ZStack(alignment: .center) {
                        if amount.isEmpty {
                            Text("0.00")
                                .font(AppTypography.bigNumber)
                                .foregroundStyle(AppColors.textDisabled)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .allowsHitTesting(false)
                        }

                        TextField("", text: $amount)
                            .font(AppTypography.bigNumber)
                            .foregroundStyle(AppColors.textPrimary)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amount)
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .onChange(of: amount) { _, newValue in
                                let filtered = filterAmountInput(newValue)
                                if filtered != newValue {
                                    // Avoid animating text mutations driven by filtering.
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        amount = filtered
                                    }
                                }
                            }
                    }
                    .frame(minWidth: 160, maxWidth: 240, minHeight: 58, alignment: .center)
                }
                .frame(maxWidth: .infinity)

                Text(isAmountFocused ? "轻点空白处可收起键盘" : "点击输入金额")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
        }
        // Focus chrome lives in overlays so focus never restructures the card tree.
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .fill(
                    isAmountFocused
                        ? AppColors.stageOngoingBackground.opacity(0.28)
                        : Color.clear
                )
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(
                    isAmountFocused ? AppColors.brandPrimary.opacity(0.32) : Color.clear,
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        // Tap empty card chrome to focus; TextField still receives direct taps itself.
        // Do not attach an implicit animation to focus — that re-enters layout during
        // keyboard presentation and previously froze the app.
        .onTapGesture {
            focusedField = .amount
        }
    }

    // MARK: - Group Split Toggle

    private var extrasDisclosure: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button {
                dismissKeyboard()
                AppHaptics.selection()
                withAnimation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion)) {
                    extrasExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("垫付、日期与备注")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Image(systemName: extrasExpanded ? "chevron.up" : "chevron.down")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("垫付、日期与备注")
            .accessibilityHint(extrasExpanded ? "收起" : "展开")

            if extrasExpanded {
                if canEnableGroupSplit {
                    groupSplitToggleSection
                    if expenseScope == .group {
                        groupExpenseSection
                    }
                }
                if !itineraryOptions.isEmpty {
                    itineraryLinkSection
                }
                Text(selectedCurrency.displayName)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                datePickerSection
                noteSection
            }
        }
    }

    private func splitPreviewRow(_ preview: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: "divide.circle.fill")
                .font(AppTypography.listTitleMedium)
                .foregroundStyle(AppColors.brandPrimary)
            Text(preview)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(AppSpacing.cozy)
        .background(AppColors.brandPrimaryBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .accessibilityLabel(preview)
    }

    /// AA split is only meaningful when at least two members are on the trip.
    private var canEnableGroupSplit: Bool {
        members.count >= 2
    }

    private var isGroupSplitEnabled: Bool {
        expenseScope == .group
    }

    private var groupSplitToggleSection: some View {
        TracciSwitchRow(isOn: Binding(
            get: { isGroupSplitEnabled },
            set: { enabled in
                withAnimation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion)) {
                    setGroupSplitEnabled(enabled)
                }
            }
        )) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isGroupSplitEnabled ? "person.3.fill" : "person.3")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(isGroupSplitEnabled ? AppColors.brandPrimary : AppColors.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AA 分摊")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("记录垫付人与参与人，自动计算均摊")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(isGroupSplitEnabled ? AppColors.brandPrimaryBackground.opacity(0.45) : AppColors.cardAltBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(isGroupSplitEnabled ? AppColors.brandPrimary.opacity(0.25) : AppColors.borderSubtle, lineWidth: 1)
        )
        .accessibilityHint("开启后可设置垫付人与参与人")
    }

    private func setGroupSplitEnabled(_ enabled: Bool) {
        dismissKeyboard()
        if enabled {
            expenseScope = .group
            if payerMemberId == nil {
                defaultPayerToCurrentUser()
            }
        } else {
            expenseScope = .personal
            payerMemberId = nil
            selectedParticipantIds.removeAll()
        }
    }

    private func defaultPayerToCurrentUser() {
        guard let currentUserId,
              let me = members.first(where: { $0.userId == currentUserId })
        else { return }
        payerMemberId = me.id
    }

    // MARK: - Group Expense Section

    private var groupExpenseSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cardSmall) {
            // Payer picker
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Text("垫付人")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPlaceholder)

                ForEach(members) { member in
                    memberSelectionRow(
                        member: member,
                        isSelected: payerMemberId == member.id,
                        onTap: {
                            payerMemberId = member.id
                        }
                    )
                }
            }

            // Participants
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Text("参与人（均摊）")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPlaceholder)

                ForEach(members) { member in
                    memberSelectionRow(
                        member: member,
                        isSelected: selectedParticipantIds.contains(member.id),
                        isCheckmark: true,
                        onTap: {
                            if selectedParticipantIds.contains(member.id) {
                                selectedParticipantIds.remove(member.id)
                            } else {
                                selectedParticipantIds.insert(member.id)
                            }
                        }
                    )
                }
            }

            // Real-time split preview
            if let preview = splitPreview {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "divide.circle.fill")
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.brandPrimary)
                    Text(preview)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .padding(AppSpacing.cozy)
                .background(AppColors.brandPrimaryBackground.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }
        }
    }

    private func memberSelectionRow(
        member: TripMemberResp,
        isSelected: Bool,
        isCheckmark: Bool = false,
        onTap: @escaping () -> Void
    ) -> some View {
        Button {
            dismissKeyboard()
            onTap()
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                Circle()
                    .fill(member.memberColorBg)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(member.displayInitial)
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(member.memberColor)
                    }

                Text(member.nickname)
                    .font(AppTypography.buttonTitleMedium)
                    .foregroundStyle(AppColors.textPrimary)

                if member.isOwner {
                    Image(systemName: "crown.fill")
                        .font(AppTypography.microRegular)
                        .foregroundStyle(AppColors.ownerAmber)
                }

                Spacer()

                if isSelected {
                    Image(systemName: isCheckmark ? "checkmark.circle.fill" : "circle.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.brandPrimary)
                } else {
                    Image(systemName: isCheckmark ? "circle" : "circle")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textDisabled)
                }
            }
            .padding(AppSpacing.cozy)
            .background(isSelected ? AppColors.brandPrimaryBackground.opacity(0.5) : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.brandPrimary.opacity(0.3) : AppColors.borderSubtle, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Picker

    private var categoryPickerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("选择分类")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPlaceholder)

            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ExpenseCategory.allSystemCases) { category in
                    categoryButton(category)
                }
                ForEach(customCategories) { custom in
                    categoryButton(custom.asExpenseCategory)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeleteCategory = custom
                            } label: {
                                Label("删除分类", systemImage: "trash")
                            }
                        }
                }
                addCategoryButton
            }

            if !customCategories.isEmpty {
                Text("长按自定义分类可删除")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }

            if let categoryError {
                categoryErrorBanner(categoryError)
            }
        }
    }

    /// 虚线描边的品牌色「添加」磁贴：直接在网格内新增分类，成功后自动选中。
    private var addCategoryButton: some View {
        Button {
            dismissKeyboard()
            showingAddCategory = true
        } label: {
            VStack(spacing: AppSpacing.tight) {
                Image(systemName: "plus")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(height: 26)
                Text("添加")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.brandPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.cardSmall)
            .background(AppColors.brandPrimaryBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .strokeBorder(
                        AppColors.brandPrimary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .pressableCardStyle(scale: 0.97, opacity: 0.92)
        .accessibilityLabel("添加分类")
        .accessibilityHint("打开添加分类弹层")
    }

    private func categoryErrorBanner(_ message: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppColors.danger)
            Text(message)
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .background(AppColors.dangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func deleteCategory(_ category: CustomExpenseCategory) async {
        if await onDeleteCategory(category.id) {
            AppHaptics.lightImpact()
        }
    }

    private func categoryButton(_ category: ExpenseCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            dismissKeyboard()
            AppHaptics.selection()
            selectedCategory = category
            withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                pressedCategory = category
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                    pressedCategory = nil
                }
            }
        } label: {
            VStack(spacing: AppSpacing.tight) {
                Image(systemName: category.systemImage)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : Color(hex: category.colorHex))
                    .frame(height: 26)
                Text(category.displayName)
                    .font(AppTypography.label)
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.cardSmall)
            .background(isSelected ? AppColors.brandPrimaryBackground : AppColors.cardAltBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.brandPrimary.opacity(0.72) : AppColors.borderSubtle, lineWidth: 1)
            )
            .scaleEffect(pressedCategory == category ? 0.96 : 1)
        }
        .pressableCardStyle(scale: 0.97, opacity: 0.92)
    }

    // MARK: - Date Picker

    private var datePickerSection: some View {
        FormSection("日期时间") {
            VStack(spacing: 0) {
                TracciPickerTriggerRow(
                    icon: "calendar",
                    title: "日期",
                    value: TracciCalendarFormatting.displayDate(spentAt)
                ) {
                    dismissKeyboard()
                    showingDatePicker = true
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)

                Divider()
                    .overlay(AppColors.borderSubtle)
                    .padding(.leading, 44)

                TracciPickerTriggerRow(
                    icon: "clock",
                    title: "时间",
                    value: TracciCalendarFormatting.displayTime(spentAt)
                ) {
                    dismissKeyboard()
                    showingTimePicker = true
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .padding(.vertical, 2)
        }
    }

    private var dateRange: ClosedRange<Date> {
        ExpenseFormatters.tripDateRange(start: tripStartDate, end: tripEndDate)
    }

    // MARK: - Note

    private var noteSection: some View {
        TracciFormTextArea(
            label: "消费说明",
            systemImage: "note.text",
            placeholder: "例如：酒店住宿、晚餐、地铁票",
            text: $note,
            isOptional: true,
            isFocused: focusedField == .note,
            minHeight: 96,
            maxLength: 200,
            showsCharacterCount: true
        )
    }

    // MARK: - Error

    @ViewBuilder
    private var errorBanner: some View {
        if let submitError {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(AppColors.danger)
                Text(submitError)
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.md)
            .background(AppColors.dangerBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    // MARK: - Helpers

    /// Real-time per-person split preview for group expenses.
    private var splitPreview: String? {
        guard expenseScope == .group,
              let decimalAmount = ExpenseFormatters.decimal(from: amount),
              decimalAmount > 0,
              !selectedParticipantIds.isEmpty
        else { return nil }

        let symbol = selectedCurrency.symbol
        let count = Decimal(selectedParticipantIds.count)
        let perPerson = decimalAmount / count
        let perPersonFormatted = ExpenseFormatters.money(perPerson, symbol: "")

        return "\(symbol)\(ExpenseFormatters.money(decimalAmount, symbol: "")) ÷ \(selectedParticipantIds.count)人 = \(symbol)\(perPersonFormatted)/人"
    }

    private var isFormValid: Bool {
        guard selectedCategory != nil else { return false }
        guard let value = ExpenseFormatters.decimal(from: amount), value > 0 else { return false }
        guard dateRange.contains(spentAt) else { return false }
        guard note.count <= 200 else { return false }

        if expenseScope == .group {
            guard payerMemberId != nil else { return false }
            guard !selectedParticipantIds.isEmpty else { return false }
        }

        return true
    }

    private func filterAmountInput(_ input: String) -> String {
        var result = ""
        var hasDecimalPoint = false
        var decimalDigits = 0

        for character in input {
            if character.isWholeNumber {
                if hasDecimalPoint {
                    guard decimalDigits < 2 else { continue }
                    decimalDigits += 1
                }
                result.append(character)
            } else if character == ".", !hasDecimalPoint {
                hasDecimalPoint = true
                result.append(result.isEmpty ? "0." : ".")
            }
        }

        return result
    }

    private func submit() async {
        guard !isSubmitting, isFormValid, let selectedCategory else { return }

        dismissKeyboard()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = CreateExpenseRequest(
            amountInput: amount,
            currency: ExpenseCurrency.cny.rawValue,
            category: selectedCategory.id,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            spentAt: ExpenseFormatters.apiString(from: spentAt),
            expenseScope: expenseScope == .group ? expenseScope.rawValue : nil,
            payerMemberId: expenseScope == .group ? payerMemberId : nil,
            participantMemberIds: expenseScope == .group ? Array(selectedParticipantIds) : nil,
            splitMethod: expenseScope == .group ? SplitMethod.equal.rawValue : nil,
            linkedNodeId: selectedLink?.nodeId,
            linkedStayGroupId: selectedLink?.stayGroupId
        )
        if await onSubmit(request) {
            if !isEditing {
                ExpenseLastCategoryStore.save(tripId: tripId, categoryId: selectedCategory.id)
            }
            await TracciFormSaveFeedback.celebrateBeforeDismiss(showSaveSuccess: $showSaveSuccess) {
                dismiss()
            }
        }
    }

    private static func clamped(_ date: Date, to range: ClosedRange<Date>) -> Date {
        min(max(date, range.lowerBound), range.upperBound)
    }

    private static func matchingLink(
        in options: [ExpenseItineraryLink],
        expense: Expense
    ) -> ExpenseItineraryLink? {
        if let stayGroupId = expense.linkedStayGroupId {
            return options.first { $0.stayGroupId == stayGroupId }
        }
        if let linkedNodeId = expense.linkedNodeId {
            return options.first { $0.nodeId == linkedNodeId }
        }
        return nil
    }

    private var itineraryLinkSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("关联行程")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPlaceholder)

            Button {
                dismissKeyboard()
                showingItineraryPicker = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.brandPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedLink?.title ?? "不关联")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(selectedLink?.subtitle ?? "可选，记在具体行程上方便回看")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
                .padding(AppSpacing.md)
                .background(AppColors.cardAltBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColors.borderSubtle, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关联行程")
        }
    }

    private static func defaultExpenseDate(in range: ClosedRange<Date>, now: Date = Date()) -> Date {
        if range.contains(now) {
            return now
        }

        let calendar = Calendar.current
        let targetDate = now < range.lowerBound ? range.lowerBound : range.upperBound
        return TracciCalendarFormatting.mergeTime(now, preservingDateFrom: calendar.startOfDay(for: targetDate))
    }
}

#if DEBUG
private enum ExpenseFormPreviewFixtures {
    static let members: [TripMemberResp] = [
        TripMemberResp(
            id: "member-1",
            tripId: "trip-1",
            userId: "user-1",
            nickname: "小明",
            role: .owner,
            status: "ACTIVE",
            joinedAt: nil
        ),
        TripMemberResp(
            id: "member-2",
            tripId: "trip-1",
            userId: "user-2",
            nickname: "小红",
            role: .editor,
            status: "ACTIVE",
            joinedAt: nil
        ),
        TripMemberResp(
            id: "member-3",
            tripId: "trip-1",
            userId: "user-3",
            nickname: "阿杰",
            role: .editor,
            status: "ACTIVE",
            joinedAt: nil
        )
    ]
}

#Preview("记一笔 · 多人旅程") {
    NavigationStack {
        ExpenseFormView(
            tripStartDate: "2026-06-01",
            tripEndDate: "2026-06-10",
            baseCurrency: "CNY",
            isSubmitting: false,
            submitError: nil,
            members: ExpenseFormPreviewFixtures.members,
            currentUserId: "user-1",
            customCategories: [
                CustomExpenseCategory(id: "cat-1", tripId: "trip-1", name: "按摩", sortOrder: 1),
                CustomExpenseCategory(id: "cat-2", tripId: "trip-1", name: "签证费", sortOrder: 2)
            ]
        ) { _ in true }
    }
}

#Preview("记一笔 · 单人旅程") {
    NavigationStack {
        ExpenseFormView(
            tripStartDate: "2026-06-01",
            tripEndDate: "2026-06-10",
            baseCurrency: "CNY",
            isSubmitting: false,
            submitError: nil,
            members: [ExpenseFormPreviewFixtures.members[0]],
            currentUserId: "user-1"
        ) { _ in true }
    }
}
#endif
