import SwiftUI
import TracciNetworking

struct TripDateConfirmationRequest {
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
}

/// Pushed focused date task for the Edit Trip Settings page.
///
/// It shares the Settings page's authoritative ViewModel, keeps confirmation in the
/// active destination, and pops only after the independent date mutation succeeds.
struct TripDateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TripEditViewModel
    let onTripUpdated: ((Trip) -> Void)?

    @State private var confirmationRequest: TripDateConfirmationRequest?

    var body: some View {
        TracciDateRangePickerSheet(
            title: "修改出行日期",
            subtitle: "选择旅程的开始和结束日期",
            startDate: TripDateFormatting.date(from: viewModel.trip.startDate),
            endDate: TripDateFormatting.date(from: viewModel.trip.endDate),
            presentation: .pushed,
            isSubmitting: isLoading,
            onConfirm: saveDates
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isLoading)
        .overlay(alignment: .top) {
            if let errorMessage = viewModel.mutationError {
                errorBanner(message: errorMessage)
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.top, AppSpacing.xl)
            }
        }
        .onAppear {
            viewModel.clearMutationError()
            viewModel.onDateChangeNeedsConfirmation = { message, onConfirm, onCancel in
                confirmationRequest = TripDateConfirmationRequest(
                    message: message,
                    onConfirm: onConfirm,
                    onCancel: onCancel
                )
            }
        }
        .onDisappear {
            cancelStatusChange()
            viewModel.onDateChangeNeedsConfirmation = nil
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: Binding(
                    get: { confirmationRequest != nil },
                    set: { presented in
                        if !presented {
                            cancelStatusChange()
                        }
                    }
                ),
                tone: .caution,
                title: "确认修改出行日期？",
                message: confirmationRequest?.message ?? "修改日期可能改变旅程状态。",
                cancelTitle: "再想想",
                confirmTitle: "确认修改",
                onConfirm: confirmStatusChange,
                onCancel: cancelStatusChange
            )
        }
    }

    private var isLoading: Bool {
        viewModel.activeMutation == .date
    }

    private func saveDates(start: Date, end: Date) {
        Task {
            if await viewModel.updateDates(start: start, end: end) {
                onTripUpdated?(viewModel.trip)
                dismiss()
            }
        }
    }

    private func confirmStatusChange() {
        let action = confirmationRequest?.onConfirm
        confirmationRequest = nil
        action?()
    }

    private func cancelStatusChange() {
        let action = confirmationRequest?.onCancel
        confirmationRequest = nil
        action?()
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
#Preview("Trip Date Editor") {
    NavigationStack {
        TripDateEditorView(
            viewModel: TripEditViewModel(
                trip: Trip(
                    id: "preview-trip",
                    title: "京都秋日漫游",
                    startDate: "2026-10-01",
                    endDate: "2026-10-05",
                    status: .planning
                ),
                tripService: TripService(
                    apiClient: APIClient(),
                    fileUploadService: FileUploadService(apiClient: APIClient())
                )
            ),
            onTripUpdated: nil
        )
    }
}
#endif
