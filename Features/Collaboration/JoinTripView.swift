import SwiftUI
import TracciNetworking
import UIKit

/// V2 Join Trip — single full-screen task host, visually consistent with Create Trip.
///
/// The invite code field auto-focuses; the keyboard "完成" accessory collapses the
/// keyboard, and the bottom CTA hides while the keyboard is visible — the same
/// task-host rules as Create Trip. Success plays a check overlay, then the host
/// dismisses the cover.
///
/// Layout is a single editorial axis: chrome explains the task, the four code cells
/// are the only visual weight, and a quiet caption sits underneath. No competing
/// hero / promise cards.
///
/// The full-screen host ignores the top safe area so the page canvas runs under the
/// status bar; the editorial chrome below positions itself with the resolved inset.
struct JoinTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: JoinTripViewModel
    @State private var showJoinSuccess = false
    @State private var topInset = SafeAreaMetrics.top
    @FocusState private var isInviteCodeFocused: Bool
    let onJoined: (JoinInvitationResponse) -> Void
    var onCancel: (() -> Void)?

    init(
        collaborationService: CollaborationService,
        initialCode: String = "",
        onCancel: (() -> Void)? = nil,
        onJoined: @escaping (JoinInvitationResponse) -> Void
    ) {
        let model = JoinTripViewModel(
            collaborationService: collaborationService,
            initialCode: initialCode
        )
        _viewModel = State(initialValue: model)
        self.onCancel = onCancel
        self.onJoined = onJoined
    }

    var body: some View {
        TracciTaskSheetScaffold(
            title: "加入旅程",
            ctaTitle: "加入旅程",
            ctaSystemImage: "person.2",
            isCTAEnabled: viewModel.canJoin && !showJoinSuccess,
            isCTALoading: viewModel.isJoining,
            presentation: .pushed,
            onCancel: { close() },
            onCTA: { Task { await join() } },
            chrome: { joinChrome }
        ) {
            VStack(spacing: AppSpacing.sectionSpacingCompact) {
                inviteCodeStage
                    .tracciFormSectionAppear(index: 0)

                joinCaption
                    .tracciFormSectionAppear(index: 1)
            }
            .frame(maxWidth: .infinity)
            .animation(
                AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
                value: viewModel.errorMessage
            )
        }
        .tracciFormChromePage(presentation: .pushed)
        .overlay {
            if showJoinSuccess {
                joinSuccessOverlay
                    .transition(AppMotion.revealTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(
            AppMotion.animation(AppMotion.successCheck, reduceMotion: reduceMotion),
            value: showJoinSuccess
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    isInviteCodeFocused = false
                }
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.interactiveText)
            }
        }
        .onAppear {
            isInviteCodeFocused = true
        }
        .onChange(of: viewModel.inviteCode) { oldValue, newValue in
            if newValue.count == TripInviteCode.codeLength,
               oldValue.count != TripInviteCode.codeLength {
                AppHaptics.lightImpact()
            }
        }
        .onDisappear {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    // MARK: - Editorial chrome

    /// Full-screen task chrome: quiet close, editorial title block, and a creek
    /// divider. The canvas ignores the top safe area, so pad with the resolved
    /// inset to stay below the Dynamic Island — same layout as Create Trip.
    private var joinChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, AppSpacing.pageX)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("加入旅程")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("输入好友分享的 4 位邀请码")
                    .font(AppTypography.pageSubtitle)
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, 2)

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
        Button(action: close) {
            Image(systemName: "xmark")
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppColors.fillSubtle, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44, alignment: .leading)
        .disabled(viewModel.isJoining || showJoinSuccess)
        .opacity(viewModel.isJoining || showJoinSuccess ? 0.4 : 1)
        .accessibilityLabel("取消加入")
    }

    private func close() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    // MARK: - Content

    /// Four code wells are the page signature — no wrapping card, no counter, no
    /// repeated helper copy. Progress is the filled cells themselves.
    private var inviteCodeStage: some View {
        VStack(spacing: AppSpacing.cozy) {
            Text("邀请码")
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textMuted)
                .accessibilityHidden(true)

            ZStack {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(0..<TripInviteCode.codeLength, id: \.self) { index in
                        codeCell(at: index)
                    }
                }

                hiddenInviteCodeField
            }
            .frame(maxWidth: 340)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .onTapGesture {
                isInviteCodeFocused = true
            }
            .tracciErrorShake(viewModel.errorMessage)

            if let errorMessage = viewModel.errorMessage {
                TracciFormErrorText(message: errorMessage)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var joinCaption: some View {
        Text("加入后按邀请权限进入这段旅程。")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)
    }

    private func codeCell(at index: Int) -> some View {
        let character = codeCharacter(at: index)
        let isEmpty = character.isEmpty
        let isActive = isInviteCodeFocused
            && index == min(viewModel.inviteCode.count, TripInviteCode.codeLength - 1)
        let hasError = viewModel.errorMessage != nil

        return Group {
            if isEmpty {
                Text(" ")
                    .font(AppFont.system(28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                TracciNumberPopIn(
                    text: character,
                    font: AppFont.system(28, weight: .semibold, design: .monospaced),
                    color: AppColors.textPrimary
                )
            }
        }
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
            .background(codeCellBackground(isEmpty: isEmpty, isActive: isActive, hasError: hasError))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(
                        codeCellBorder(isEmpty: isEmpty, isActive: isActive, hasError: hasError),
                        lineWidth: (isActive || hasError) ? 1.5 : 1
                    )
            }
            .accessibilityHidden(true)
    }

    private var hiddenInviteCodeField: some View {
        TextField(
            "",
            text: Binding(
                get: { viewModel.inviteCode },
                set: { viewModel.updateInviteCode($0) }
            )
        )
        .focused($isInviteCodeFocused)
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled(true)
        .submitLabel(.join)
        .textFieldStyle(.plain)
        .foregroundStyle(Color.clear)
        .tint(Color.clear)
        .onSubmit {
            Task { await join() }
        }
        .opacity(0.02)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("邀请码")
        .accessibilityValue(viewModel.inviteCode.isEmpty ? "未输入" : viewModel.inviteCode)
        .accessibilityHint("输入 4 位邀请码")
    }

    private func codeCharacter(at index: Int) -> String {
        let characters = Array(viewModel.inviteCode)
        guard characters.indices.contains(index) else { return "" }
        return String(characters[index])
    }

    private func codeCellBackground(isEmpty: Bool, isActive: Bool, hasError: Bool) -> Color {
        if hasError {
            return AppColors.dangerBackground
        }
        if isActive || !isEmpty {
            return AppColors.cardBackground
        }
        return AppColors.subtleBackground
    }

    private func codeCellBorder(isEmpty: Bool, isActive: Bool, hasError: Bool) -> Color {
        if hasError {
            return AppColors.danger.opacity(0.4)
        }
        if isActive {
            return AppColors.brandPrimary.opacity(0.55)
        }
        if !isEmpty {
            return AppColors.borderSubtle
        }
        return AppColors.borderSubtle.opacity(0.7)
    }

    @MainActor
    private func join() async {
        guard viewModel.canJoin else { return }
        if let result = await viewModel.join() {
            isInviteCodeFocused = false
            AppHaptics.success()
            withAnimation(AppMotion.animation(AppMotion.successCheck, reduceMotion: reduceMotion)) {
                showJoinSuccess = true
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? AppMotion.quickDuration : AppMotion.joinSuccessHoldDuration))
            onJoined(result)
        }
    }

    private var joinedRoleLabel: String {
        guard let raw = viewModel.joinResult?.role else { return "" }
        return TripMemberRole(rawValue: raw)?.label ?? raw
    }

    private var joinSuccessOverlay: some View {
        ZStack {
            AppColors.backgroundGrouped.opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                TracciSuccessCheck(size: 56)

                Text("已加入这段旅程")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                if !joinedRoleLabel.isEmpty {
                    Text("权限：\(joinedRoleLabel)")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                joinedRoleLabel.isEmpty
                    ? "已加入这段旅程"
                    : "已加入这段旅程，权限\(joinedRoleLabel)"
            )
        }
    }

}

// MARK: - Preview

#if DEBUG
#Preview("Join Trip") {
    JoinTripView(
        collaborationService: CollaborationService(apiClient: APIClient()),
        onCancel: {},
        onJoined: { _ in }
    )
}

#Preview("Join Trip — filled") {
    JoinTripView(
        collaborationService: CollaborationService(apiClient: APIClient()),
        initialCode: "8K3M",
        onCancel: {},
        onJoined: { _ in }
    )
}
#endif
