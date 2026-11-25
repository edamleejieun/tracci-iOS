import SwiftUI

struct JournalEntryCard: View {
    let entry: JournalEntry
    var mood: JournalMood?
    /// Multi-member trips show the author next to time; solo trips hide it.
    var showsAuthor: Bool = false
    var photoDensity: JournalPhotoGrid.Density = .regular
    let onEdit: () -> Void
    let onToggleHighlight: () -> Void
    var onToggleFeaturedPhoto: ((JournalPhoto) -> Void)? = nil
    let onDelete: () -> Void
    var canManage: Bool = false

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if entry.isHighlight {
                highlightMark
            }

            metaRow

            if !entry.displayContent.isEmpty {
                Text(entry.displayContent)
                    .font(AppTypography.narrativeBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineSpacing(5)
                    .padding(.leading, AppSpacing.tight)
            }

            if entry.hasPhotos {
                JournalPhotoGrid(
                    photos: entry.photos,
                    density: photoDensity,
                    onToggleFeatured: canManage && !entry.isPrivate ? onToggleFeaturedPhoto : nil
                )
            }
        }
        .contentShape(Rectangle())
        .tracciLongPressActions(title: "日志操作", actions: journalActions)
        .overlay {
            TracciConfirmSheet(
                isPresented: $showDeleteConfirm,
                title: "确定删除这篇日志吗？",
                message: "删除后无法恢复。",
                confirmTitle: "删除",
                onConfirm: onDelete
            )
        }
        // 用 .contain 保留卡内「精选照片 / 操作菜单」按钮的独立焦点；.combine 会把它们吞成一个元素。
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    private var highlightMark: some View {
        HStack(spacing: AppSpacing.xs) {
            Capsule()
                .fill(AppColors.dawnGold)
                .frame(width: 18, height: 2)
            Text("精选")
                .font(AppTypography.editorialMeta)
                .tracking(0.8)
                .foregroundStyle(AppColors.dawnGold)
            Spacer(minLength: 0)
        }
        .accessibilityLabel("精选日志")
    }

    private var journalActions: [TracciActionItem] {
        guard canManage else { return [] }
        return [
            TracciActionItem(title: "编辑日志", systemImage: "pencil", action: onEdit),
            TracciActionItem(
                title: entry.isHighlight ? "取消精选" : "设为精选",
                systemImage: entry.isHighlight ? "star.slash" : "star",
                action: onToggleHighlight
            ),
            TracciActionItem(title: "删除日志", systemImage: "trash", role: .destructive) {
                showDeleteConfirm = true
            }
        ]
    }

    private var metaRow: some View {
        HStack(alignment: .center, spacing: AppSpacing.tight) {
            HStack(spacing: AppSpacing.xs) {
                if !entry.occurredTimeShort.isEmpty {
                    Text(entry.occurredTimeShort)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                if showsAuthor, let authorName = entry.authorName, !authorName.isEmpty {
                    Text("·")
                        .foregroundStyle(AppColors.textDisabled)
                    Text(authorName)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                if entry.isPrivate {
                    Text("·")
                        .foregroundStyle(AppColors.textDisabled)
                    Text("仅自己")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                if let locationName = entry.locationName {
                    Text("·")
                        .foregroundStyle(AppColors.textDisabled)
                    Circle()
                        .fill(AppColors.brandPrimary)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(locationName)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.xs) {
                if let mood {
                    JournalMoodBadge(mood: mood)
                }

                if canManage {
                    TracciActionMenuButton(actions: journalActions) {
                        Image(systemName: "ellipsis")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textDisabled)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("日志操作")
                }
            }
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if entry.isHighlight { parts.append("精选") }
        if !entry.occurredTimeShort.isEmpty { parts.append(entry.occurredTimeShort) }
        if showsAuthor, let authorName = entry.authorName, !authorName.isEmpty {
            parts.append(authorName)
        }
        if entry.isPrivate { parts.append("仅自己可见") }
        if let locationName = entry.locationName { parts.append(locationName) }
        if let mood { parts.append("心情：\(mood.label)") }
        if !entry.displayContent.isEmpty { parts.append(entry.displayContent) }
        if entry.hasPhotos { parts.append("\(entry.photos.count) 张照片") }
        return parts.joined(separator: "，")
    }
}

#if DEBUG
#Preview("精选 · 地点") {
    JournalEntryCard(
        entry: JournalPreviewFixtures.sampleEntry,
        mood: .peaceful,
        showsAuthor: false,
        onEdit: {},
        onToggleHighlight: {},
        onToggleFeaturedPhoto: { _ in },
        onDelete: {},
        canManage: true
    )
    .padding()
    .tracciPageBackground()
}

#Preview("多人 · 私密") {
    JournalEntryCard(
        entry: JournalPreviewFixtures.privateCollaborativeEntry,
        mood: .thoughtful,
        showsAuthor: true,
        onEdit: {},
        onToggleHighlight: {},
        onDelete: {},
        canManage: true
    )
    .padding()
    .tracciPageBackground()
}
#endif
