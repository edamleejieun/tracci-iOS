import SwiftUI

struct TripMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AuthSession.self) private var authSession

    let tripId: String
    let tripTitle: String
    let collaborationService: CollaborationService
    /// 所有权转让等会改变当前用户能力时回调（详情/编辑页应立即替换本地 access 快照）。
    let onAccessUpdated: ((TripAccessContext) -> Void)?

    @State private var viewModel: CollaborationViewModel
    @State private var showingInviteSheet = false
    @State private var showingRemoveConfirm: TripMemberResp?
    @State private var showingTransferConfirm: TripMemberResp?
    @State private var toastMessage: String?

    init(
        tripId: String,
        tripTitle: String,
        collaborationService: CollaborationService,
        currentUserId: String?,
        currentUserAccess: TripAccessContext?,
        onAccessUpdated: ((TripAccessContext) -> Void)? = nil,
        demoMembers: [TripMemberResp]? = nil
    ) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.collaborationService = collaborationService
        self.onAccessUpdated = onAccessUpdated
        let vm = CollaborationViewModel(
            tripId: tripId,
            tripTitle: tripTitle,
            collaborationService: collaborationService,
            currentUserId: currentUserId,
            currentUserAccess: currentUserAccess
        )
        if let demoMembers {
            vm.applyDemoMembers(demoMembers)
        }
        _viewModel = State(initialValue: vm)
    }

    private var isDemo: Bool { viewModel.isDemoMode }

    var body: some View {
        Group {
            if viewModel.isLoadingMembers && viewModel.members.isEmpty {
                InlineLoadingStateView(message: "加载成员列表")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.membersError, viewModel.members.isEmpty {
                ErrorStateView(
                    title: "成员加载失败",
                    message: error,
                    retryTitle: "再试一次"
                ) {
                    Task { await viewModel.loadMembers() }
                }
            } else {
                memberContent
            }
        }
        .navigationTitle(isDemo ? "示例成员" : "旅程成员")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationBarMinimizeOnScroll()
        .tracciNavigationSubpage()
        .safeAreaInset(edge: .bottom) {
            if viewModel.canInvite {
                inviteButton
            }
        }
        .onChange(of: showingInviteSheet) { _, isShowing in
            if !isShowing {
                viewModel.clearCreatedInvitation()
                viewModel.clearInvitationError()
            }
        }
        .tracciBottomSheet(
            isPresented: $showingInviteSheet,
            height: TracciDialogMetrics.invitationSheetHeight(
                state: viewModel.invitationSheetState,
                errorMessage: viewModel.invitationError,
                dynamicTypeSize: dynamicTypeSize
            ),
            showDragBar: false
        ) {
            CreateInvitationView(
                tripTitle: tripTitle,
                viewModel: viewModel,
                onClose: { showingInviteSheet = false }
            )
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: Binding(
                    get: { showingRemoveConfirm != nil },
                    set: { presented in
                        if !presented { showingRemoveConfirm = nil }
                    }
                ),
                title: "确定要移除该成员吗？",
                message: showingRemoveConfirm.map { "移除后，\($0.nickname) 将无法访问此旅程。" } ?? "",
                confirmTitle: "移除",
                sheetHeight: 340,
                onConfirm: {
                    guard let member = showingRemoveConfirm else { return }
                    Task {
                        let success = await viewModel.removeMember(memberId: member.id)
                        if success {
                            AppHaptics.success()
                            showToast("已移除 \(member.nickname)")
                        } else {
                            AppHaptics.error()
                        }
                        showingRemoveConfirm = nil
                    }
                },
                onCancel: {
                    showingRemoveConfirm = nil
                }
            )
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: Binding(
                    get: { showingTransferConfirm != nil },
                    set: { presented in
                        if !presented { showingTransferConfirm = nil }
                    }
                ),
                title: "转让旅程所有权？",
                message: showingTransferConfirm.map {
                    "转让给 \($0.nickname) 后，你将变为可编辑成员，成员管理、旅程设置和删除权限会立即移交。"
                } ?? "",
                confirmTitle: "确认转让",
                sheetHeight: 370,
                onConfirm: {
                    guard let member = showingTransferConfirm else { return }
                    Task {
                        let success = await viewModel.transferOwnership(to: member.id)
                        if success {
                            AppHaptics.success()
                            if let access = viewModel.currentUserAccess {
                                onAccessUpdated?(access)
                                TripAccessUpdate.post(tripId: tripId, access: access)
                            }
                            showToast("已将旅程所有权转让给 \(member.nickname)")
                        } else {
                            AppHaptics.error()
                        }
                        showingTransferConfirm = nil
                    }
                },
                onCancel: {
                    showingTransferConfirm = nil
                }
            )
        }
        .onChange(of: viewModel.memberOperationError) { _, error in
            guard let error else { return }
            showToast(error)
            viewModel.clearMemberOperationError()
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                toast(message: toastMessage)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: toastMessage)
        .task {
            await viewModel.loadMembers()
        }
    }

    // MARK: - Member Content

    private var memberContent: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.cozy) {
                if isDemo {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "eye")
                            .font(AppTypography.captionSemibold)
                        Text(DemoReadOnlyCopy.membersReadOnly)
                            .font(AppTypography.captionMedium)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(AppColors.brandPrimary)
                    .padding(.horizontal, AppSpacing.cardSmall)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                            .fill(AppColors.brandPrimary.opacity(0.08))
                    )
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.top, AppSpacing.cozy)
                    .accessibilityLabel(DemoReadOnlyCopy.membersReadOnly)
                }

                // Section header
                HStack {
                    Text("成员 · \(viewModel.members.count) 人")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, isDemo ? AppSpacing.xs : AppSpacing.cozy)
                .padding(.bottom, AppSpacing.sm)

                // Member cards
                ForEach(viewModel.members) { member in
                    MemberCard(
                        member: member,
                        isCurrentUser: viewModel.currentUserMember?.id == member.id,
                        canManage: viewModel.canManageMembers,
                        canTransferOwnership: viewModel.canTransferOwnership,
                        isOperating: viewModel.operatingMemberId == member.id,
                        onRoleChange: { newRole in
                            Task {
                                let success = await viewModel.updateMemberRole(
                                    memberId: member.id,
                                    newRole: newRole
                                )
                                if success {
                                    AppHaptics.success()
                                    showToast("已将 \(member.nickname) 设为\(newRole.label)")
                                } else {
                                    AppHaptics.error()
                                }
                            }
                        },
                        onRemove: {
                            showingRemoveConfirm = member
                        },
                        onTransferOwnership: {
                            showingTransferConfirm = member
                        }
                    )
                    .padding(.horizontal, AppSpacing.pageX)
                    .fadeSlideIn(index: viewModel.members.firstIndex(where: { $0.id == member.id }) ?? 0)
                }
            }
            .padding(.bottom, 120)
        }
        .refreshable {
            guard !isDemo else { return }
            await viewModel.loadMembers()
        }
    }

    // MARK: - Invite Button

    private var inviteButton: some View {
        Button {
            AppHaptics.lightImpact()
            showingInviteSheet = true
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: "person.badge.plus")
                    .font(AppTypography.listTitle)
                Text("邀请好友")
                    .font(AppTypography.listTitle)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.cardSmall)
            .background(AppColors.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.vertical, AppSpacing.cozy)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Toast

    private func toast(message: String) -> some View {
        Text(message)
            .font(AppTypography.bodyMedium)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.cozy)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.6)
            }
            .clipShape(Capsule())
            .tracciElevation(.l3)
            .padding(.bottom, 100)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - Member Card

private struct MemberCard: View {
    let member: TripMemberResp
    let isCurrentUser: Bool
    let canManage: Bool
    let canTransferOwnership: Bool
    let isOperating: Bool
    let onRoleChange: (TripMemberRole) -> Void
    let onRemove: () -> Void
    let onTransferOwnership: () -> Void

    var body: some View {
        AppElevationCard(level: .l0, role: .content, radius: AppRadius.large, padding: 16) {
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.md) {
                    // Avatar
                    TripMemberAvatarView(
                        member: member,
                        size: 48,
                        showsOwnerRing: true
                    )

                    // Name + role
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(member.nickname)
                                .font(AppTypography.listTitleMedium)
                                .foregroundStyle(AppColors.textPrimary)

                            if isCurrentUser {
                                Text("我")
                                    .font(AppTypography.microSemibold)
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .padding(.horizontal, AppSpacing.xs)
                                    .padding(.vertical, 2)
                                    .background(AppColors.brandPrimary.opacity(0.1))
                                    .clipShape(Capsule())
                            }

                            if member.isOwner {
                                Image(systemName: "crown.fill")
                                    .font(AppTypography.chipSemibold)
                                    .foregroundStyle(AppColors.ownerAmber)
                            }
                        }

                        // Role + status
                        HStack(spacing: AppSpacing.tight) {
                            HStack(spacing: AppSpacing.xxs) {
                                Image(systemName: member.roleIcon)
                                    .font(AppTypography.micro)
                                Text(member.isOwner ? "创建者" : member.roleLabel)
                                    .font(AppTypography.caption)
                            }
                            .foregroundStyle(member.isOwner ? AppColors.ownerAmber : AppColors.textMuted)

                            if member.isAccountDeleted {
                                Text("账号已注销")
                                    .font(AppTypography.chipRegular)
                                    .foregroundStyle(AppColors.textMuted)
                            } else if member.isActive {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(AppColors.success)
                                        .frame(width: 5, height: 5)
                                    Text("活跃")
                                        .font(AppTypography.chipRegular)
                                        .foregroundStyle(AppColors.textMuted)
                                }
                            }
                        }

                        // Joined time
                        if let joinedText = formattedJoinedAt {
                            Text(joinedText)
                                .font(AppTypography.chipRegular)
                                .foregroundStyle(AppColors.textPlaceholder)
                        }
                    }

                    Spacer()

                    // Actions — owner 行不展示管理菜单（唯一 active owner）
                    if isOperating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if (canManage || canTransferOwnership) && !member.isOwner {
                        memberActionsMenu
                    }
                }
            }
        }
        .tracciLongPressActions(
            title: member.nickname,
            actions: memberLongPressActions
        )
    }

    private var formattedJoinedAt: String? {
        guard let joinedAt = member.joinedAt,
              let date = ISO8601DateFormatter().date(from: joinedAt)
        else { return nil }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0

        if calendar.isDateInToday(date) { return "今天加入" }
        if calendar.isDateInYesterday(date) { return "昨天加入" }
        if days < 7 { return "\(days)天前加入" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM月dd日加入"
        return formatter.string(from: date)
    }

    private var memberLongPressActions: [TracciActionItem] {
        guard !member.isOwner else { return [] }
        var actions: [TracciActionItem] = []
        if canTransferOwnership && member.isActive {
            actions.append(TracciActionItem(
                title: "转让所有权",
                systemImage: "crown",
                action: onTransferOwnership
            ))
        }
        if canManage {
            actions.append(TracciActionItem(
                title: member.isAccountDeleted ? "移除记录" : "移除成员",
                systemImage: "trash",
                role: .destructive,
                action: onRemove
            ))
        }
        return actions
    }

    private var memberRoleActions: [TracciActionItem] {
        if member.isAccountDeleted {
            guard canManage else { return [] }
            return [
                TracciActionItem(title: "移除记录", systemImage: "trash", role: .destructive, action: onRemove)
            ]
        }
        var actions: [TracciActionItem] = []
        if canTransferOwnership && member.isActive {
            actions.append(TracciActionItem(
                title: "转让所有权",
                systemImage: "crown",
                action: onTransferOwnership
            ))
        }
        if canManage {
            actions.append(contentsOf: [
                TracciActionItem(title: "可编辑", systemImage: "pencil") { onRoleChange(.editor) },
                TracciActionItem(title: "仅查看", systemImage: "eye") { onRoleChange(.viewer) },
                TracciActionItem(title: "移除", systemImage: "trash", role: .destructive, action: onRemove)
            ])
        }
        return actions
    }

    private var memberActionsMenu: some View {
        TracciActionMenuButton(
            title: "成员权限",
            subtitle: member.nickname,
            actions: memberRoleActions
        ) {
            HStack(spacing: AppSpacing.xxs) {
                Text(member.roleLabel)
                    .font(AppTypography.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTypography.microSemibold)
            }
            .foregroundStyle(AppColors.brandPrimary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.brandPrimary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
