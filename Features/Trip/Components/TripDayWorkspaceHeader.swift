import SwiftUI

/// Sticky workspace chrome with two explicit levels:
/// overview / Day scope first, then itinerary / journal / expense for a selected Day.
struct TripDayWorkspaceHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Binding var selectedTab: TripDetailTab
    @Binding var selectedDayIndex: Int
    let totalDays: Int
    let tripStartDate: String
    let pinnedProgress: CGFloat
    var navOverlayProgress: CGFloat = 0
    var safeAreaTop: CGFloat = 0
    /// When true, hide the day-scoped tab bar (行程/日志/开支).
    /// Used in map mode where the carousel + day feed is the only content.
    var hidesTabBar: Bool = false
    /// Soft emphasis on the journey-level insight entry (e.g. ongoing suggestion).
    var insightShowsSoftDot: Bool = false
    /// Stage-aware page seam color (`AppAtmosphereStyle.heroSeamColor`).
    /// Unpinned the header stays transparent so the page paper shows through;
    /// pinned the glass is tinted with this color instead of a fixed mist.
    var stageSeamColor: Color = AppColors.creekMistTop
    var onOpenInsight: (() -> Void)? = nil

    @State private var headerMinY: CGFloat = .greatestFiniteMagnitude

    private var isStuckToTop: Bool { headerMinY <= 2 }
    private var showsPinnedChrome: Bool { isStuckToTop || pinnedProgress > 0.08 }

    private var stickyTopInset: CGFloat {
        guard showsPinnedChrome else { return 0 }
        let navClearance = TripDetailLayout.collapsedNavBodyHeight
            * min(max(navOverlayProgress, 0), 1)
        return safeAreaTop + navClearance
    }

    var body: some View {
        VStack(spacing: 0) {
            scopeSelector

            if selectedTab != .overview && !hidesTabBar {
                AppCreekDivider()
                    .padding(.horizontal, TripDetailLayout.pageInset)
                    .padding(.top, 7)
                    .padding(.bottom, 5)

                TripDetailTabBar(
                    selectedTab: $selectedTab,
                    isCompact: pinnedProgress > 0.35
                )
            }
        }
        .padding(.top, (showsPinnedChrome ? 7 : 11) + stickyTopInset)
        .padding(.bottom, AppSpacing.tight)
        .background {
            if showsPinnedChrome {
                stickyChromeBackground
            }
            // 未吸顶不再铺平面底色：页面氛围（顶部即 hero 接缝色）直接透出，
            // 形成「沉浸媒体 → 查看范围」的连续纸面。
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.borderDefault.opacity(0.10 + 0.22 * pinnedProgress))
                .frame(height: 0.5)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named("TripDetailScroll")).minY
        } action: { minY in
            headerMinY = minY
        }
        .animation(
            AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion),
            value: selectedTab
        )
    }

    /// 吸顶 = 明确的控制层：L3 Glass + 阶段纸色 tint（G5.5：iOS 26 用原生玻璃
    /// 承载阶段色，与全 App Liquid Glass 语言一致；其余走材质 + 叠色）。
    @ViewBuilder
    private var stickyChromeBackground: some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            Color.clear
                .glassEffect(.regular.tint(stageSeamColor.opacity(0.82)), in: Rectangle())
                .ignoresSafeArea(edges: .top)
        } else {
            legacyStickyBackground
        }
        #else
        legacyStickyBackground
        #endif
    }

    @ViewBuilder
    private var legacyStickyBackground: some View {
        if reduceTransparency {
            // Reduce Transparency:不用材质，阶段纸色直接实底。
            Rectangle()
                .fill(stageSeamColor)
                .ignoresSafeArea(edges: .top)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(stageSeamColor.opacity(0.82))
                .ignoresSafeArea(edges: .top)
        }
    }

    private var scopeSelector: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .center) {
                Text("查看范围")
                    .font(AppTypography.editorialMeta)
                    .foregroundStyle(AppColors.textMuted)
                    .tracking(0.8)

                Spacer(minLength: 8)

                insightEntryButton
            }

            HStack(alignment: .bottom, spacing: AppSpacing.xs) {
                overviewRail

                TripDayRail(
                    selectedDayIndex: $selectedDayIndex,
                    totalDays: totalDays,
                    tripStartDate: tripStartDate,
                    isOverviewSelected: selectedTab == .overview,
                    onSelectDay: selectDay
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, TripDetailLayout.pageInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("查看范围，总览及 \(totalDays) 天")
    }

    /// Fixed scope control: same track chrome & baseline as Day rail, but reads as
    /// “全程范围” rather than another date cell (icon + 总览 + 共 N 天).
    private var overviewRail: some View {
        overviewButton
            .padding(.bottom, AppSpacing.sm)
            .background(alignment: .bottom) {
                Capsule()
                    .fill(
                        selectedTab == .overview
                            ? AppColors.stageOngoing.opacity(0.76)
                            : AppColors.borderSubtle.opacity(0.72)
                    )
                    .frame(height: 2)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, AppSpacing.tight)
            .padding(.horizontal, AppSpacing.xs)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: TripDetailLayout.railTrackRadius, style: .continuous)
                        .fill(AppColors.paperWarmLight.opacity(0.74))

                    // Slightly cooler mist than Day rail so “范围” and “按天”可区分。
                    RoundedRectangle(cornerRadius: TripDetailLayout.railTrackRadius, style: .continuous)
                        .fill(
                            selectedTab == .overview
                                ? AppColors.brandPrimaryBackground.opacity(0.28)
                                : AppColors.creekMistTop.opacity(0.40)
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: TripDetailLayout.railTrackRadius, style: .continuous)
                    .stroke(
                        selectedTab == .overview
                            ? AppColors.brandPrimary.opacity(0.18)
                            : AppColors.borderSubtle.opacity(0.35),
                        lineWidth: 0.5
                    )
            }
    }

    private var overviewButton: some View {
        let isSelected = selectedTab == .overview

        return Button {
            guard !isSelected else { return }
            AppHaptics.selection()
            withAnimation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion)) {
                selectedTab = .overview
            }
        } label: {
            VStack(spacing: 2) {
                // Primary row: compact grid glyph + 总览 — scope, not a calendar day.
                HStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2")
                        .font(TripDetailTypography.inlineIcon)
                        .symbolRenderingMode(.monochrome)
                        .accessibilityHidden(true)

                    Text("总览")
                        .font(isSelected ? TripDetailTypography.dayDateSelected : TripDetailTypography.dayDate)
                        .lineLimit(1)
                }

                // Tool-first secondary: total trip length (replaces vague「全程」as body copy).
                Text("共 \(max(totalDays, 1)) 天")
                    .font(isSelected ? TripDetailTypography.dayWeekdaySelected : TripDetailTypography.dayWeekday)
                    .foregroundStyle(
                        isSelected
                            ? AppColors.brandPrimary.opacity(0.9)
                            : AppColors.textMuted
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()

                // Match Day rail badge row height; show「全程」only when selected (like「今天」).
                Group {
                    if isSelected {
                        Text("全程")
                            .font(TripDetailTypography.dayBadge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .frame(minHeight: 16)
                            .background(AppColors.brandPrimary)
                            .clipShape(Capsule())
                    } else {
                        Color.clear
                            .frame(height: 16)
                            .accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(width: 68)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(
                        isSelected
                            ? AppColors.brandPrimaryBackground.opacity(0.88)
                            : AppColors.paperWarmLight.opacity(0.35)
                    )
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.35), lineWidth: 1)
                }
            }
            .tracciElevation(isSelected ? .l1 : .l0)
            .overlay(alignment: .bottom) {
                // Scope marker: square (not day stream circle) to signal “全程” vs “按天”.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? AppColors.stageOngoing : AppColors.paperWarmLight)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(
                                isSelected
                                    ? Color.white.opacity(0.92)
                                    : AppColors.stagePlanning.opacity(0.62),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                    .frame(width: isSelected ? 10 : 8, height: isSelected ? 10 : 8)
                    .tracciElevation(isSelected ? .l1 : .l0)
                    .offset(y: AppSpacing.xs + 1)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("旅程总览，共 \(max(totalDays, 1)) 天")
        .accessibilityHint("查看全部日期的行程安排")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectDay(_ dayIndex: Int) {
        if selectedDayIndex != dayIndex {
            selectedDayIndex = dayIndex
        }
        if selectedTab == .overview {
            selectedTab = .itinerary
        }
    }

    /// Journey-level insight entry — not a fourth content tab and not part of Day Rail.
    private var insightEntryButton: some View {
        Button {
            AppHaptics.selection()
            onOpenInsight?()
        } label: {
            HStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Text("洞察")
                        .font(AppTypography.editorialMeta)
                        .tracking(0.4)

                    if insightShowsSoftDot {
                        Circle()
                            .fill(AppColors.brandPrimary)
                            .frame(width: 5, height: 5)
                            .offset(x: 5, y: -3)
                            .accessibilityHidden(true)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(TripDetailTypography.microChevron)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppControlMetrics.minimumTapTarget)
        .disabled(onOpenInsight == nil)
        .opacity(onOpenInsight == nil ? 0.45 : 1)
        .accessibilityLabel("洞察")
        .accessibilityHint("查看这趟旅程的概况与数据")
        .accessibilityAddTraits(.isButton)
    }
}
