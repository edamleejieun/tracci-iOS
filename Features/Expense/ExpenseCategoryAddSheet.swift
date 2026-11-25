import SwiftUI

/// 记一笔表单内的轻量「添加分类」弹层：输入名称 → 提交 → 自动选中新分类并关闭。
///
/// 取代原「分类管理」整页 Sheet + 系统 alert 的两层结构；删除分类改由表单网格长按完成。
struct ExpenseCategoryAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 分类操作失败原因（透传自 ExpenseViewModel.categoryErrorMessage）。
    var errorMessage: String?
    let onAdd: (String) async -> CustomExpenseCategory?
    let onCreated: (CustomExpenseCategory) -> Void

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var hasAttemptedSubmit = false
    /// 提交失败后用户再次编辑时隐藏旧错误，避免对已修改的输入产生误导。
    @State private var hasEditedSinceSubmit = false
    @FocusState private var isFieldFocused: Bool

    /// 与分类网格磁贴宽度匹配的展示上限（超长名称会被网格截断）。
    private let maxLength = 12

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && trimmedName.count <= maxLength && !isSubmitting
    }

    /// 错误仅在「已提交且提交后未再编辑」时展示；父级透传的旧错误不会误导新的输入。
    private var visibleErrorMessage: String? {
        guard hasAttemptedSubmit, !hasEditedSinceSubmit else { return nil }
        return errorMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            TracciPickerSheetTopChrome()

            TracciPickerSheetHeader(
                title: "添加分类",
                subtitle: "为这段旅程添加一个常用分类，例如签证费、按摩。",
                accessory: { TracciSheetCloseButton() }
            )
            .tracciPickerHorizontalPadding()

            TracciFocusableFormField(
                label: "分类名称",
                systemImage: "tag",
                placeholder: "例如：签证费",
                text: $name,
                errorMessage: visibleErrorMessage,
                focus: true,
                focusedField: $isFieldFocused,
                submitLabel: .done,
                onSubmit: { Task { await addCategory() } },
                autocorrectionDisabled: true
            )
            .tracciPickerHorizontalPadding()
            .tracciPickerContentTopSpacing()
            .onChange(of: name) { _, newValue in
                hasEditedSinceSubmit = true
                guard newValue.count > maxLength else { return }
                let capped = String(newValue.prefix(maxLength))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { name = capped }
            }

            HStack(spacing: AppSpacing.sm) {
                SecondaryButton(title: "取消") { dismiss() }

                PrimaryButton(
                    title: "添加",
                    isLoading: isSubmitting,
                    isEnabled: !trimmedName.isEmpty,
                    action: { Task { await addCategory() } }
                )
            }
            .tracciPickerHorizontalPadding()
            .padding(.top, AppSpacing.sectionSpacingCompact)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundGrouped)
        .tracciEditorSheet()
        .onAppear {
            isFieldFocused = true
        }
    }

    // MARK: - Actions

    private func addCategory() async {
        guard canSubmit else { return }
        hasAttemptedSubmit = true
        hasEditedSinceSubmit = false
        isSubmitting = true
        defer { isSubmitting = false }

        if let created = await onAdd(trimmedName) {
            AppHaptics.success()
            onCreated(created)
            dismiss()
        }
    }

}

// MARK: - Preview

#Preview("添加分类") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExpenseCategoryAddSheet(
                errorMessage: nil,
                onAdd: { name in
                    CustomExpenseCategory(id: "cat-new", tripId: "trip-1", name: name, sortOrder: 1)
                },
                onCreated: { _ in }
            )
        }
}

#Preview("添加分类 · 失败") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExpenseCategoryAddSheet(
                errorMessage: "该分类已存在，换个名字试试",
                onAdd: { _ in nil },
                onCreated: { _ in }
            )
        }
}
