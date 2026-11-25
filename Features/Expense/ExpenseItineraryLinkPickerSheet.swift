import SwiftUI

/// 关联行程选择器：按天分组、以开支日期定位当天、节点较多时支持搜索。
struct ExpenseItineraryLinkPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let options: [ExpenseItineraryLink]
    let selected: ExpenseItineraryLink?
    /// 打开时滚动到该日期所在的天（找不到同日时取最近一天）。
    var spentAt: Date = Date()
    let onSelect: (ExpenseItineraryLink?) -> Void

    @State private var searchText = ""

    /// 节点数量超过阈值才展示搜索框，短列表不增加噪音。
    private static let searchThreshold = 15

    private var showsSearch: Bool {
        options.count > Self.searchThreshold
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredOptions: [ExpenseItineraryLink] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.type.label.localizedCaseInsensitiveContains(query)
        }
    }

    private var daySections: [DaySection] {
        Self.daySections(from: filteredOptions)
    }

    var body: some View {
        VStack(spacing: 0) {
            TracciPickerSheetHeader(
                title: "关联行程",
                subtitle: "选择这笔开支对应的行程节点，可不关联。",
                accessory: { TracciSheetCloseButton() }
            )
            .tracciPickerHorizontalPadding()
            .padding(.top, AppSpacing.pickerChromeTop)

            if showsSearch {
                searchField
                    .tracciPickerHorizontalPadding()
                    .padding(.top, AppSpacing.md)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppSpacing.cardSmall, pinnedViews: [.sectionHeaders]) {
                        unlinkedRow
                            .padding(.top, AppSpacing.md)

                        if isSearching {
                            searchResults
                        } else {
                            dayGroupList
                        }
                    }
                    .tracciPickerHorizontalPadding()
                    .padding(.bottom, AppSpacing.pageTop)
                }
                .scrollDismissesKeyboard(.immediately)
                .onAppear {
                    scrollToAnchorDay(proxy: proxy)
                    scheduleAnchorScrollRetry(proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundGrouped)
        .tracciSheetPresentation(.subSheetFraction(0.8))
    }

    // MARK: - Day Grouping

    private struct DaySection: Identifiable {
        let dayIndex: Int
        let dayDate: String?
        var links: [ExpenseItineraryLink]

        var id: Int { dayIndex }
        var sectionId: String { "day-section-\(dayIndex)" }

        var headerTitle: String {
            var title = "第 \(dayIndex) 天"
            if let dateText = dayDate.flatMap(Self.displayDayDate) {
                title += " · \(dateText)"
            }
            return title
        }

        /// `yyyy-MM-dd` → 「6月1日 周一」；解析失败时返回 nil（仅显示第 N 天）。
        static func displayDayDate(_ raw: String) -> String? {
            guard let date = Self.parseDayDate(raw) else { return nil }
            return TracciCalendarFormatting.shortDate(date) + " " + TracciCalendarFormatting.weekday(date)
        }

        static func parseDayDate(_ raw: String) -> Date? {
            // 复用共享的业务日历解析器（Asia/Shanghai + en_US_POSIX，静态实例）。
            TripDateFormatting.date(from: raw)
        }
    }

    private static func daySections(from options: [ExpenseItineraryLink]) -> [DaySection] {
        var sections: [DaySection] = []
        for option in options {
            if let index = sections.firstIndex(where: { $0.dayIndex == option.dayIndex }) {
                sections[index].links.append(option)
            } else {
                sections.append(
                    DaySection(dayIndex: option.dayIndex, dayDate: option.dayDate, links: [option])
                )
            }
        }
        return sections
    }

    /// 与 `spentAt` 同日 → 该天；否则取日期距离最近的一天；无可用日期时用已选项所在天。
    private var anchorDayIndex: Int? {
        let calendar = TracciDateContext.calendar
        let spentAtDay = calendar.startOfDay(for: spentAt)
        let candidates = daySections.compactMap { section -> (dayIndex: Int, distance: Int)? in
            guard let date = section.dayDate.flatMap(DaySection.parseDayDate) else { return nil }
            let distance = abs(
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: date),
                    to: spentAtDay
                ).day ?? Int.max
            )
            return (section.dayIndex, distance)
        }
        return candidates.min(by: { $0.distance < $1.distance })?.dayIndex ?? selected?.dayIndex
    }

    private func scrollToAnchorDay(proxy: ScrollViewProxy) {
        guard !isSearching, let anchorDayIndex,
              daySections.contains(where: { $0.dayIndex == anchorDayIndex })
        else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo("day-section-\(anchorDayIndex)", anchor: .top)
        }
    }

    /// LazyVStack 懒加载：长行程中锚点天分区可能尚未布局，首次 `scrollTo` 会静默落空。
    /// 布局稳定后补滚一次；幂等，重复执行无副作用。
    private func scheduleAnchorScrollRetry(proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            scrollToAnchorDay(proxy: proxy)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var dayGroupList: some View {
        ForEach(daySections) { section in
            Section {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(section.links) { option in
                        optionRow(option)
                    }
                }
                .padding(.bottom, AppSpacing.tight)
            } header: {
                Text(section.headerTitle)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.tight)
                    .background(AppColors.backgroundGrouped)
                    .id(section.sectionId)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if filteredOptions.isEmpty {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textDisabled)
                Text("没有匹配的行程节点")
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.pageTop)
        } else {
            VStack(spacing: AppSpacing.tight) {
                ForEach(filteredOptions) { option in
                    optionRow(option, showsDayPrefix: true)
                }
            }
        }
    }

    // MARK: - Rows

    private var unlinkedRow: some View {
        optionButton(
            icon: "minus.circle",
            iconColor: AppColors.textMuted,
            iconBackground: AppColors.subtleBackground,
            title: "不关联",
            subtitle: "这笔开支不挂到具体行程",
            isSelected: selected == nil,
            accessibilitySuffix: ""
        ) {
            onSelect(nil)
            dismiss()
        }
    }

    private func optionRow(_ option: ExpenseItineraryLink, showsDayPrefix: Bool = false) -> some View {
        let subtitle = showsDayPrefix || isSearching
            ? "第 \(option.dayIndex) 天 · \(option.type.label)"
            : option.type.label

        return optionButton(
            icon: option.type.icon,
            iconColor: AppColors.brandPrimary,
            iconBackground: AppColors.brandPrimaryBackground.opacity(0.6),
            title: option.title,
            subtitle: subtitle,
            isSelected: selected == option,
            accessibilitySuffix: "，第\(option.dayIndex)天\(option.type.label)"
        ) {
            AppHaptics.selection()
            onSelect(option)
            dismiss()
        }
    }

    private func optionButton(
        icon: String,
        iconColor: Color,
        iconBackground: Color,
        title: String,
        subtitle: String,
        isSelected: Bool,
        accessibilitySuffix: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.cozy) {
                Image(systemName: icon)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(iconColor)
                    .frame(width: 38, height: 38)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textDisabled)
            }
            .padding(AppSpacing.cozy)
            .background(isSelected ? AppColors.brandPrimaryBackground.opacity(0.5) : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColors.brandPrimary.opacity(0.3) : AppColors.borderSubtle,
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.94))
        .accessibilityLabel("\(title)\(accessibilitySuffix)\(isSelected ? "，已选择" : "")")
        .accessibilityHint("选择后关闭")
    }

    // MARK: - Chrome

    private var searchField: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPlaceholder)

            TextField("搜索行程节点", text: $searchText)
                .font(AppTypography.formValue)
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("搜索行程节点")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
        }
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: searchText.isEmpty
        )
    }
}

// MARK: - Preview

#if DEBUG
private enum ExpenseItineraryLinkPreviewFixtures {
    static func options(dayCount: Int, nodesPerDay: Int) -> [ExpenseItineraryLink] {
        (1...dayCount).flatMap { dayIndex in
            (0..<nodesPerDay).map { nodeIndex in
                ExpenseItineraryLink(
                    nodeId: "node-\(dayIndex)-\(nodeIndex)",
                    stayGroupId: nil,
                    title: "节点 \(dayIndex)-\(nodeIndex)",
                    type: [ItineraryNodeType.attraction, .restaurant, .transport][nodeIndex % 3],
                    dayIndex: dayIndex,
                    dayDate: {
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        formatter.dateFormat = "yyyy-MM-dd"
                        let base = formatter.date(from: "2026-06-01") ?? Date()
                        let day = Calendar.current.date(byAdding: .day, value: dayIndex - 1, to: base) ?? base
                        return formatter.string(from: day)
                    }()
                )
            }
        }
    }
}

#Preview("关联行程 · 分组") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExpenseItineraryLinkPickerSheet(
                options: ExpenseItineraryLinkPreviewFixtures.options(dayCount: 5, nodesPerDay: 3),
                selected: nil,
                spentAt: Date(),
                onSelect: { _ in }
            )
        }
}

#Preview("关联行程 · 搜索") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExpenseItineraryLinkPickerSheet(
                options: ExpenseItineraryLinkPreviewFixtures.options(dayCount: 8, nodesPerDay: 4),
                selected: nil,
                spentAt: Date(),
                onSelect: { _ in }
            )
        }
}
#endif
