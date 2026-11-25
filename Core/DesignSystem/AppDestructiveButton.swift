import SwiftUI

/// Destructive action button — for delete, remove, and other irreversible actions.
///
/// Always paired with `TracciConfirmSheet` before executing destructive actions.
/// Uses danger color to signal irreversibility.
///
/// **Usage:**
/// ```swift
/// DestructiveButton("删除旅程", action: handleDelete)
///
/// DestructiveButton("删除旅程", systemImage: "trash", action: handleDelete)
/// ```
struct DestructiveButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    var accessibilityHint = "此操作不可撤销"
    var action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isLoading: Bool = false,
        accessibilityHint: String = "此操作不可撤销",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.tight) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.buttonIcon)
                }
                Text(title)
                    .font(AppTypography.buttonTitle)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(AppColors.danger)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }
}

// MARK: - Preview

#Preview("DestructiveButton") {
    VStack(spacing: AppSpacing.cardSmall) {
        DestructiveButton("删除旅程", systemImage: "trash") {
            print("delete tapped")
        }

        DestructiveButton("删除旅程", isLoading: true) {
            print("delete tapped")
        }
    }
    .padding(AppSpacing.pageX)
    .tracciPageBackground()
}
