import SwiftUI
import Observation

/// Mutable FAB state for trip detail. Owned by `TripDetailView` so scroll/lifecycle
/// hooks can call into it without reaching into a `View` value.
@MainActor
@Observable
final class TripDetailFABModel {
    var showingFabMenu = false
    var isFabVisible = false
    var fabRestingOffset: CGSize = .zero
    var isFabDragging = false
    var isFabScrollActive = false
    var fabPulseScale: CGFloat = 1

    @ObservationIgnored
    var fabScrollIdleTask: Task<Void, Never>?

    func noteScrolling(reduceMotion: Bool) {
        guard !showingFabMenu, !isFabDragging else { return }

        fabScrollIdleTask?.cancel()
        if !isFabScrollActive {
            withAnimation(AppMotion.animation(.easeOut(duration: 0.18), reduceMotion: reduceMotion)) {
                isFabScrollActive = true
            }
        }

        fabScrollIdleTask = Task { @MainActor in
            try? await Task.sleep(for: TripDetailLayout.fabScrollIdleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.animation(.easeOut(duration: 0.22), reduceMotion: reduceMotion)) {
                isFabScrollActive = false
            }
        }
    }

    func revealAfterTransition(reduceMotion: Bool) {
        isFabVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(AppMotion.animation(.easeOut(duration: 0.18), reduceMotion: reduceMotion)) {
                self.isFabVisible = true
            }
        }
    }

    func hideForNavigationPop() {
        fabScrollIdleTask?.cancel()
        isFabVisible = false
    }

    func handleDayChange() {
        fabScrollIdleTask?.cancel()
        isFabScrollActive = false
    }

    /// Milestone celebration after a node is created (P2): success haptic + a
    /// short press-scale then milestone spring back. Reduce Motion keeps the haptic.
    func celebrateCreation(reduceMotion: Bool) {
        AppHaptics.success()
        guard !reduceMotion else { return }

        fabScrollIdleTask?.cancel()
        fabPulseScale = 1
        withAnimation(AppMotion.press) {
            fabPulseScale = 1.08
        } completion: {
            withAnimation(AppMotion.milestoneSpring) {
                self.fabPulseScale = 1
            }
        }
    }
}

/// Floating add chrome for trip detail: menu, reposition drag, empty-day pulse, scroll prominence.
struct TripDetailFABChrome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var model: TripDetailFABModel
    let selectedDayIndex: Int
    let selectedDayHasContent: Bool
    let canEdit: Bool
    let safeAreaTop: CGFloat

    let onAddNode: () -> Void
    let onAddJournal: () -> Void
    let onAddPhotoJournal: () -> Void
    let onAddExpense: () -> Void

    @GestureState private var fabDragTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            if model.showingFabMenu {
                fabScrim
                    .onTapGesture { dismissFabMenu() }
                    .transition(.opacity)
                    .zIndex(1)
            }

            GeometryReader { proxy in
                let bottomPadding = max(SafeAreaMetrics.bottom, 16)
                fabMenu(containerSize: proxy.size, bottomPadding: bottomPadding, safeAreaTop: safeAreaTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, TripDetailLayout.pageInset)
                    .padding(.bottom, bottomPadding)
                    .offset(currentFabOffset)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(2)
        }
        .onChange(of: selectedDayIndex) { _, _ in
            model.handleDayChange()
        }
    }

    // MARK: - Internals

    private var fabScrim: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                Color.black.opacity(0.14)
            }
            .ignoresSafeArea()
    }

    private var currentFabOffset: CGSize {
        CGSize(
            width: model.fabRestingOffset.width + fabDragTranslation.width,
            height: model.fabRestingOffset.height + fabDragTranslation.height
        )
    }

    private func fabMenu(containerSize: CGSize, bottomPadding: CGFloat, safeAreaTop: CGFloat) -> some View {
        let fabButtonSize: CGFloat = TripDetailLayout.fabSize
        let isOpen = model.showingFabMenu

        return VStack(alignment: .trailing, spacing: isOpen ? AppSpacing.tight : 0) {
            if isOpen {
                fabMenuItem(
                    icon: "signpost.right.fill",
                    label: "添加行程",
                    subtitle: "安排这一天的地点与时间",
                    isPrimary: true,
                    action: {
                        dismissFabMenu()
                        onAddNode()
                    }
                )
                .transition(fabItemTransition(delay: 0))

                fabMenuItem(
                    icon: "book.pages",
                    label: "写日志",
                    subtitle: "记录当天的文字和照片",
                    isPrimary: false,
                    action: {
                        dismissFabMenu()
                        onAddJournal()
                    }
                )
                .transition(fabItemTransition(delay: 0.04))

                fabMenuItem(
                    icon: "photo.on.rectangle.angled",
                    label: "记照片",
                    subtitle: "先选图，再补一句就好",
                    isPrimary: false,
                    action: {
                        dismissFabMenu()
                        onAddPhotoJournal()
                    }
                )
                .transition(fabItemTransition(delay: 0.08))

                fabMenuItem(
                    icon: "wallet.pass",
                    label: "记一笔",
                    subtitle: "添加花费和分摊信息",
                    isPrimary: false,
                    action: {
                        dismissFabMenu()
                        onAddExpense()
                    }
                )
                .transition(fabItemTransition(delay: 0.12))
            }

            Button {
                AppHaptics.lightImpact()
                let opening = !model.showingFabMenu
                withAnimation(
                    AppMotion.animation(
                        opening ? AppMotion.morphOpen : AppMotion.morphClose,
                        reduceMotion: reduceMotion
                    )
                ) {
                    model.showingFabMenu.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .font(TripDetailTypography.fabGlyph)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: fabButtonSize, height: fabButtonSize)
                    .background {
                        Circle()
                            .fill(AppColors.brandPrimaryBackground.opacity(0.88))
                            .tracciElevation(.l1)
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                AppColors.brandPrimary.opacity(TripDetailLayout.fabBorderOpacity),
                                lineWidth: 0.6
                            )
                    }
                    .contentShape(Circle())
                    .rotationEffect(.degrees(isOpen && !reduceMotion ? 45 : 0))
            }
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.45)
            .accessibilityLabel(isOpen ? "关闭添加菜单" : "添加行程、日志、照片或开支")
            .simultaneousGesture(
                fabRepositionGesture(
                    containerSize: containerSize,
                    bottomPadding: bottomPadding,
                    buttonSize: fabButtonSize,
                    safeAreaTop: safeAreaTop
                )
            )
            .accessibilityHint("轻点展开添加菜单。长按并拖动可调整按钮位置")
        }
        .padding(isOpen ? AppSpacing.tight : 0)
        .offset(x: fabPeekOffset)
        .opacity(model.isFabVisible || isOpen ? fabProminenceOpacity : 0)
        .scaleEffect(model.isFabVisible || isOpen ? fabDisplayScale : 0.92, anchor: .bottomTrailing)
        .animation(
            AppMotion.animation(isOpen ? AppMotion.morphOpen : AppMotion.morphClose, reduceMotion: reduceMotion),
            value: isOpen
        )
        .animation(AppMotion.animation(.easeOut(duration: 0.18), reduceMotion: reduceMotion), value: model.isFabVisible)
        .animation(AppMotion.animation(.easeOut(duration: 0.22), reduceMotion: reduceMotion), value: model.isFabScrollActive)
        .animation(AppMotion.animation(.easeOut(duration: 0.22), reduceMotion: reduceMotion), value: selectedDayHasContent)
        .animation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion), value: model.isFabDragging)
        .animation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion), value: model.fabPulseScale)
    }

    private var fabDisplayScale: CGFloat {
        if model.isFabDragging { return 1.04 }
        return model.fabPulseScale
    }

    private var fabProminenceOpacity: Double {
        if model.showingFabMenu || model.isFabDragging {
            return 1
        }
        if model.isFabScrollActive {
            return TripDetailLayout.fabScrollingOpacity
        }
        return selectedDayHasContent
            ? TripDetailLayout.fabIdleOpacityWithContent
            : TripDetailLayout.fabIdleOpacityEmpty
    }

    private var fabPeekOffset: CGFloat {
        guard !reduceMotion, model.isFabScrollActive, !model.showingFabMenu, !model.isFabDragging else { return 0 }
        return TripDetailLayout.fabScrollingPeekOffset
    }

    private func fabRepositionGesture(
        containerSize: CGSize,
        bottomPadding: CGFloat,
        buttonSize: CGFloat,
        safeAreaTop: CGFloat
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($fabDragTranslation) { value, state, _ in
                guard case .second(true, let drag?) = value else { return }
                state = drag.translation
            }
            .onChanged { value in
                guard case .second(true, _) = value, !model.isFabDragging else { return }
                model.isFabDragging = true
                AppHaptics.mediumImpact()
            }
            .onEnded { value in
                defer { model.isFabDragging = false }
                guard case .second(true, let drag?) = value else { return }

                let proposedOffset = CGSize(
                    width: model.fabRestingOffset.width + drag.translation.width,
                    height: model.fabRestingOffset.height + drag.translation.height
                )
                let clampedOffset = clampedFabOffset(
                    proposedOffset,
                    containerSize: containerSize,
                    bottomPadding: bottomPadding,
                    buttonSize: buttonSize,
                    safeAreaTop: safeAreaTop
                )

                withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                    model.fabRestingOffset = clampedOffset
                }
            }
    }

    private func clampedFabOffset(
        _ offset: CGSize,
        containerSize: CGSize,
        bottomPadding: CGFloat,
        buttonSize: CGFloat,
        safeAreaTop: CGFloat
    ) -> CGSize {
        let horizontalMargin: CGFloat = 12
        let topMargin = safeAreaTop + 12
        let minX = -(containerSize.width - TripDetailLayout.pageInset - buttonSize - horizontalMargin)
        let maxX = max(TripDetailLayout.pageInset - horizontalMargin, 0)
        let minY = -(containerSize.height - bottomPadding - buttonSize - topMargin)
        let maxY: CGFloat = 0

        return CGSize(
            width: min(max(offset.width, minX), maxX),
            height: min(max(offset.height, minY), maxY)
        )
    }

    private func fabMenuItem(
        icon: String,
        label: String,
        subtitle: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(isPrimary ? TripDetailTypography.fabMenuPrimary : TripDetailTypography.fabMenuSecondary)
                        .foregroundStyle(isPrimary ? .white : AppColors.textPrimary)
                    Text(subtitle)
                        .font(TripDetailTypography.fabMenuCaption)
                        .foregroundStyle(isPrimary ? Color.white.opacity(0.72) : AppColors.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: icon)
                    .font(TripDetailTypography.fabMenuIcon)
                    .foregroundStyle(isPrimary ? .white : AppColors.brandPrimary)
                    .frame(width: 34, height: 34)
                    .background(isPrimary ? Color.white.opacity(0.18) : AppColors.brandPrimaryBackground)
                    .clipShape(Circle())
            }
            .padding(.leading, AppSpacing.cardSmall)
            .padding(.trailing, AppSpacing.md)
            .frame(
                width: TripDetailLayout.fabMenuWidth,
                height: isPrimary ? TripDetailLayout.fabMenuPrimaryHeight : TripDetailLayout.fabMenuSecondaryHeight
            )
            .background(isPrimary ? AppColors.brandPrimary : AppColors.subtleWarm)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.18) : AppColors.borderDefault.opacity(0.2), lineWidth: 0.6)
            }
            .tracciElevation(isPrimary ? .l2 : .l1)
        }
        .buttonStyle(PressableCardStyle(scale: 0.975, opacity: 0.94))
    }

    private func fabItemTransition(delay: Double) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: AppMotion.modalOpenScale, anchor: .bottomTrailing))
            .animation(AppMotion.morphOpen.delay(delay))
    }

    private func dismissFabMenu() {
        withAnimation(AppMotion.animation(AppMotion.morphClose, reduceMotion: reduceMotion)) {
            model.showingFabMenu = false
        }
    }
}
