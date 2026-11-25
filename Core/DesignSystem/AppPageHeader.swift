import SwiftUI

/// Unified page header for Tracci screens.
///
/// Replaces ad-hoc title + subtitle combinations across pages with a single,
/// consistent component. Supports large title (default) and inline title modes,
/// matching NavigationStack conventions.
///
/// **Usage:**
/// ```swift
/// // Large title (default) — used in NavigationView with .large title
/// AppPageHeader(title: "我的旅程")
///
/// // With subtitle
/// AppPageHeader(title: "我的旅程", subtitle: "3 个进行中的旅程")
///
/// // Inline title — used in NavigationView with .inline title
/// AppPageHeader(title: "编辑旅程", style: .inline)
/// ```
struct AppPageHeader: View {
    let title: String
    var subtitle: String?
    var style: Style = .large

    enum Style {
        case large
        case inline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(style == .large ? AppTypography.pageTitle : AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.pageSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, style == .large ? AppSpacing.pageTop : AppSpacing.sm)
        .padding(.bottom, style == .large ? AppSpacing.xs : AppSpacing.sm)
    }
}

// MARK: - Tab Page Header

/// Shared header for main tab screens (洞察 / 回忆 / 我的).
///
/// Supports a leading SF Symbol, optional subtitle, title-row accessories
/// (e.g. refresh indicator), and trailing actions (e.g. scope picker, wordmark).
struct AppTabPageHeader<Trailing: View, TitleAccessory: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @ViewBuilder var titleAccessory: () -> TitleAccessory
    @ViewBuilder var trailing: () -> Trailing

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder titleAccessory: @escaping () -> TitleAccessory,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = titleAccessory
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.pageHeaderSubtitleSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                    Image(systemName: systemImage)
                        .font(AppTypography.buttonIcon)
                        .foregroundStyle(AppColors.brandPrimary)
                    Text(title)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                titleAccessory()
                Spacer(minLength: 12)
                trailing()
            }

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.pageSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AppTabPageHeader where Trailing == EmptyView, TitleAccessory == EmptyView {
    init(systemImage: String, title: String, subtitle: String? = nil) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            titleAccessory: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

extension AppTabPageHeader where TitleAccessory == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            titleAccessory: { EmptyView() },
            trailing: trailing
        )
    }
}

extension AppTabPageHeader where Trailing == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder titleAccessory: @escaping () -> TitleAccessory
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            titleAccessory: titleAccessory,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Preview

#Preview("AppPageHeader — Large") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
            AppPageHeader(title: "我的旅程")
            AppPageHeader(title: "我的旅程", subtitle: "3 个进行中的旅程")
        }
    }
    .tracciPageBackground()
}

#Preview("AppTabPageHeader — Tab Screens") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
            AppTabPageHeader(
                systemImage: "chart.bar.doc.horizontal",
                title: "洞察",
                subtitle: "看看今天过得怎样"
            )
            AppTabPageHeader(
                systemImage: "book.pages",
                title: "回忆",
                subtitle: "查看路上的照片和文字"
            )
            AppTabPageHeader(
                systemImage: "person.fill",
                title: "我的",
                trailing: {
                    BrandWordmarkView(style: .primary, size: BrandTokens.profileTopWordmarkSize)
                        .opacity(BrandTokens.profileTopWordmarkOpacity)
                }
            )
        }
        .padding(.horizontal, AppSpacing.pageX)
    }
    .tracciPageBackground()
}

#Preview("AppPageHeader — Inline") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                AppPageHeader(title: "编辑旅程", style: .inline)
                AppPageHeader(title: "编辑旅程", subtitle: "修改旅程详情", style: .inline)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
