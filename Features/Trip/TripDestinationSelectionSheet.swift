import SwiftUI
import TracciNetworking

/// Focused destination selection sheet for the Edit Trip Settings page.
///
/// Reuses the Create flow's search surface (`TripCreateDestinationSearchView`) but
/// without the Saved Places entry — consistent with the Create Trip boundary where
/// Saved Places are reserved for Add Itinerary Node only.
///
/// Selection is the commit action: choosing a search result or manual destination
/// immediately writes through `TripEditViewModel.updateDestination`. Search text is
/// transient, so leaving the task does not require a discard confirmation.
struct TripDestinationSelectionSheet: View {
    let initialName: String?
    var isLoading = false
    var errorMessage: String?
    let onSelect: (TripDestination?, String?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: "选择目的地",
                isCancelEnabled: !isLoading,
                isSubmitting: isLoading,
                showsSaveButton: false,
                presentation: .sheet,
                onCancel: onCancel
            )

            if let errorMessage {
                errorBanner(message: errorMessage)
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.top, AppSpacing.sm)
            }

            TripCreateDestinationSearchView(
                configuration: .destination(initialQuery: initialName ?? ""),
                onSelect: { destination in
                    AppHaptics.selection()
                    onSelect(destination, nil)
                },
                onUseManual: { name in
                    AppHaptics.selection()
                    onSelect(nil, name)
                },
                onCancel: nil
            )
            .disabled(isLoading)
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.pageBackground.ignoresSafeArea())
        .tracciDismissKeyboardOnBlankTap()
        .tracciInteractiveDismissDisabled(isLoading)
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.danger)
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.dangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Trip Destination Selection") {
    TripDestinationSelectionSheet(
        initialName: "京都",
        onSelect: { _, _ in },
        onCancel: {}
    )
}
#endif
