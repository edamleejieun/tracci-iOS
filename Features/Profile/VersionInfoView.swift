import SwiftUI

/// Version metadata page — light “检查更新” row; primary CTA only when update exists.
struct VersionInfoView: View {
    @Environment(\.openURL) private var openURL
    @State private var checker: AppUpdateChecker
    @State private var isShareSheetPresented = false

    init(checker: AppUpdateChecker) {
        _checker = State(initialValue: checker)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                brandHeader
                versionSection
                moreSection
                #if DEBUG
                debugMetaCard
                #endif
                copyrightFooter
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .navigationTitle("版本信息")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .exportSharePresenter(isPresented: $isShareSheetPresented, items: ProfileSupportLinks.shareItems)
        .task {
            if case .idle = checker.status {
                await checker.checkForUpdate(userInitiated: false)
            }
        }
    }

    // MARK: - Brand + version under lockup

    private var brandHeader: some View {
        VStack(spacing: AppSpacing.md) {
            BrandLockupView(style: .primary, showsGlow: true)

            // Version sits where slogan used to be — calmer hierarchy under the wordmark.
            HStack(spacing: AppSpacing.tight) {
                Text("v\(checker.currentVersion)")
                    .font(AppFont.system(16, weight: .light, design: .rounded))
                    .foregroundStyle(AppColors.textMuted)
                    .tracking(0.6)
                    .monospacedDigit()
                CreekStatusDot(kind: checker.status.creekDotKind)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前版本 \(checker.currentVersion)，\(accessibilityStatusPhrase)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("趣溪，当前版本 \(checker.currentVersion)")
    }

    // MARK: - Actions (check update)

    private var versionSection: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: 0) {
            VStack(spacing: 0) {
                checkUpdateRow

                // Status only when it needs attention — never show “已是最新” on the page.
                if case .updateAvailable(let latest) = checker.status {
                    rowDivider
                    updateAvailableBlock(latest: latest)
                }

                if case .failed(let message) = checker.status {
                    rowDivider
                    failureHint(message)
                }
            }
        }
    }

    /// Light list row — trailing only spinner / chevron, no status text.
    private var checkUpdateRow: some View {
        Button {
            Task { await runCheck(userInitiated: true) }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppTypography.listBody)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 40, height: 40)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                Text(checkUpdateTitle)
                    .font(AppTypography.cardBody)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 0)

                if checker.status.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.textMuted)
                } else {
                    Image(systemName: "chevron.right")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textDisabled)
                }
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
            .opacity(checker.status.isChecking ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .disabled(checker.status.isChecking)
        .accessibilityLabel(checkUpdateTitle)
        .accessibilityHint("检查 App Store 是否有新版本")
        .accessibilityValue(checker.status.isChecking ? "正在检查" : accessibilityStatusPhrase)
    }

    private var checkUpdateTitle: String {
        checker.status.isChecking ? "正在检查…" : "检查更新"
    }

    private func updateAvailableBlock(latest: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            HStack(spacing: AppSpacing.tight) {
                CreekStatusDot(kind: .available)
                Text("有新版本 v\(latest)")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }

            PrimaryButton(title: "前往 App Store 更新", systemImage: "arrow.up.circle") {
                AppHaptics.lightImpact()
                openAppStore()
            }
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .contain)
    }

    private func failureHint(_ message: String) -> some View {
        Button {
            openAppStore()
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.tight) {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text("打开商店")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 App Store")
        .accessibilityHint(message)
    }

    // MARK: - More

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionHeaderBottom) {
            Text("更多")
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.horizontal, AppSpacing.xxs)

            AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: 0) {
                VStack(spacing: 0) {
                    actionRow(icon: "star", title: "给我们评分", subtitle: "在 App Store 写评价") {
                        openReview()
                    }
                    rowDivider
                    actionRow(icon: "square.and.arrow.up", title: "推荐给朋友", subtitle: "分享趣溪") {
                        isShareSheetPresented = true
                    }
                }
            }
        }
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppTypography.listBody)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 40, height: 40)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private var rowDivider: some View {
        Divider()
            .background(AppColors.borderSubtle)
            .padding(.leading, 76)
    }

    // MARK: - Footer

    private var copyrightFooter: some View {
        VStack(spacing: 5) {
            Text("Made with ♥ in Shanghai")
                .font(AppFont.system(12, weight: .light, design: .rounded))
                .foregroundStyle(AppColors.textPlaceholder.opacity(0.85))
                .tracking(0.5)

            Link(destination: URL(string: ProfileSupportLinks.beianURL)!) {
                Text(ProfileSupportLinks.beianNumber)
                    .font(AppTypography.microRegular)
                    .foregroundStyle(AppColors.textDisabled)
            }

            Text("Copyright 2026 Tracci. All rights reserved.")
                .font(AppTypography.microRegular)
                .foregroundStyle(AppColors.textDisabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    #if DEBUG
    private var debugMetaCard: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Text("调试信息")
                    .font(AppTypography.sectionEyebrow)
                    .foregroundStyle(AppColors.textPlaceholder)
                if let build = checker.buildNumber {
                    Text("Build \(build)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .monospacedDigit()
                }
                Text("Bundle \(AppStoreConfig.bundleID)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif

    /// For VoiceOver only — not shown as duplicate UI copy when up to date.
    private var accessibilityStatusPhrase: String {
        switch checker.status {
        case .idle:
            return "未检查"
        case .checking:
            return "正在检查"
        case .upToDate:
            return "已是最新"
        case .updateAvailable(let latest):
            return "有新版本 \(latest)"
        case .failed:
            return "检查失败"
        }
    }

    // MARK: - Actions

    private func runCheck(userInitiated: Bool) async {
        if userInitiated {
            AppHaptics.lightImpact()
        }
        await checker.checkForUpdate(userInitiated: userInitiated)
        switch checker.status {
        case .upToDate:
            if userInitiated { AppHaptics.success() }
        case .updateAvailable:
            AppHaptics.mediumImpact()
        case .failed:
            if userInitiated { AppHaptics.warning() }
        default:
            break
        }
    }

    private func openAppStore() {
        guard let url = AppStoreConfig.productURL else { return }
        openURL(url)
    }

    private func openReview() {
        guard let url = AppStoreConfig.reviewURL else { return }
        openURL(url)
    }
}

// MARK: - Creek status dot

struct CreekStatusDot: View {
    let kind: CreekStatusDotKind

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch kind {
        case .neutral:
            return AppColors.textDisabled
        case .available:
            return AppColors.brandPrimary
        case .warning:
            return AppColors.warning
        }
    }
}

#Preview("Version") {
    NavigationStack {
        VersionInfoView(
            checker: AppUpdateChecker(
                currentVersion: "1.0.0",
                buildNumber: "1",
                lookupURL: nil
            )
        )
    }
}
