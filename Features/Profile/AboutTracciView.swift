import SwiftUI

/// 品牌故事页 — 对齐官网 `brandStory`，竞品式「封面叙事 + 分区卡片」节奏。
/// 插画为 Design System 内矢量装饰（无外链图）；文案可适度精简，不另造故事。
struct AboutTracciView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Hero entrance state (P0)

    @State private var heroLogoVisible = false
    @State private var heroCreekVisible = false
    @State private var heroTitleVisible = false
    @State private var heroLeadVisible = false
    @State private var heroGlowScale: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroStage
                storyBody
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.pageBottom)
            }
        }
        .navigationTitle("关于趣溪")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.backgroundGrouped)
        .onAppear { playHeroEntrance() }
    }

    // MARK: - Hero entrance choreography (P0)

    private func playHeroEntrance() {
        guard !reduceMotion else {
            heroLogoVisible = true
            heroCreekVisible = true
            heroTitleVisible = true
            heroLeadVisible = true
            return
        }

        // ① Brand logo: 0.10s
        withAnimation(.easeOut(duration: 0.40).delay(0.10)) {
            heroLogoVisible = true
        }
        // ② Creek illustration: 0.40s (after logo settles)
        withAnimation(.easeOut(duration: 0.35).delay(0.40)) {
            heroCreekVisible = true
        }
        // ③ Title: 0.55s
        withAnimation(.easeOut(duration: 0.35).delay(0.55)) {
            heroTitleVisible = true
        }
        // ④ Lead: 0.72s
        withAnimation(.easeOut(duration: 0.30).delay(0.72)) {
            heroLeadVisible = true
        }
    }

    // MARK: - Hero（装饰与正文分层，避免图标压字）

    private var heroStage: some View {
        VStack(spacing: 0) {
            // Atmosphere + side motifs only in a dedicated band (no text underneath).
            ZStack {
                heroAtmosphere
                if heroCreekVisible {
                    AboutHeroIllustration()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .frame(height: 148)  // P1: 增加高度，更有沉浸感
            .frame(maxWidth: .infinity)
            .clipped()

            // Clear content column — never overlaid by motifs.
            VStack(spacing: AppSpacing.md) {
                BrandLockupView(style: .primary, showsGlow: true, logoHeight: 56)
                    .opacity(heroLogoVisible ? 1 : 0)
                    .offset(y: heroLogoVisible ? 0 : 8)

                Text(AboutCopy.heroTitle)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.md)
                    .opacity(heroTitleVisible ? 1 : 0)
                    .offset(y: heroTitleVisible ? 0 : 6)

                Text(AboutCopy.heroLead)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.lg)
                    .opacity(heroLeadVisible ? 1 : 0)
                    .offset(y: heroLeadVisible ? 0 : 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.lg)
            .background(AppColors.backgroundGrouped)

            heroWave
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background(AppColors.backgroundGrouped)
        }
        .background(AppColors.backgroundGrouped)
    }

    private var heroAtmosphere: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppColors.brandPrimary.opacity(0.14),
                    AppColors.brandPrimaryLight.opacity(0.07),
                    AppColors.backgroundGrouped
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft glows stay low-opacity and edge-biased so they don't read as covering content.
            // P5: 呼吸动画 — hero 可见时缓慢呼吸
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.brandPrimary.opacity(0.14), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 90
                    )
                )
                .frame(width: 160, height: 160)
                .offset(x: 90, y: -20)
                .scaleEffect(heroGlowScale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.brandPrimaryLight.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 70
                    )
                )
                .frame(width: 120, height: 120)
                .offset(x: -80, y: 10)
                .scaleEffect(heroGlowScale)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AppMotion.atmosphereBreathing.delay(1.5)) {
                heroGlowScale = 1.18
            }
        }
    }

    private var heroWave: some View {
        AboutHeroWave()
            .fill(AppColors.backgroundGrouped)
    }

    // MARK: - Story body

    // MARK: - Card entrance state (P2)

    @State private var bodyVisible = false

    private var storyBody: some View {
        VStack(spacing: AppSpacing.lg) {
            philosophyCard
            CreekDivider()
            waysSection
            bridgeLine
            CreekDivider()
            brandStoryCard
            visionCard
            CreekDivider()
            capabilitySection
            footerSection
        }
        .opacity(bodyVisible ? 1 : 0)
        .offset(y: bodyVisible ? 0 : 8)
        .animation(.easeOut(duration: 0.40).delay(0.85), value: bodyVisible)
        .onAppear {
            // Hero 主体入场后再开始卡片入场
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                bodyVisible = true
            }
        }
    }

    /// 产品理念 — 官网 philosophy，略收紧。
    /// P2: 使用 milestoneSpring 作为首屏核心卡片
    private var philosophyCard: some View {
        AboutStoryCard(
            eyebrow: "产品理念",
            icon: "leaf.fill",
            title: AboutCopy.philosophyTitle
        ) {
            Text(AboutCopy.philosophy)
                .font(AppTypography.narrativeBody)
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Text(AboutCopy.opening)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.xxs)
        }
        .fadeSlideIn(index: 0, animation: AppMotion.milestoneSpring)
    }

    private var waysSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionHeaderBottom) {
            sectionEyebrow("旅行的方式")
            .fadeSlideIn(index: 1)

            // P2: 方式卡水平方向 stagger — solo 从左入，group 从右入
            VStack(spacing: AppSpacing.cozy) {
                AboutModeCard(
                    icon: "person.fill",
                    title: AboutCopy.soloTitle,
                    description: AboutCopy.soloDesc,
                    tint: AppColors.brandPrimary,
                    mode: .solo
                )
                .fadeSlideIn(index: 2, offset: -12)

                AboutModeCard(
                    icon: "person.2.fill",
                    title: AboutCopy.groupTitle,
                    description: AboutCopy.groupDesc,
                    tint: AppColors.dawnGold,
                    mode: .group
                )
                .fadeSlideIn(index: 3, offset: 12)
            }
        }
    }

    private var bridgeLine: some View {
        Text(AboutCopy.bridge)
            .font(AppTypography.cardBody)
            .foregroundStyle(AppColors.textMuted)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, AppSpacing.xs)
            .fadeSlideIn(index: 4)
    }

    private var brandStoryCard: some View {
        AboutStoryCard(
            eyebrow: "趣溪二字",
            icon: "character.book.closed.fill",
            title: nil
        ) {
            Text(AboutCopy.charactersLead)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.cozy) {
                CharacterGlyphCard(glyph: AboutCopy.quChar, meaning: AboutCopy.quMeaning)
                CharacterGlyphCard(glyph: AboutCopy.xiChar, meaning: AboutCopy.xiMeaning)
            }
            .padding(.top, AppSpacing.xs)

            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                    Text(AboutCopy.tracciName)
                        .font(AppFont.system(22, weight: .light))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(AboutCopy.tracciPronunciation)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                Text(AboutCopy.tracciOrigin)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, AppSpacing.md)
        }
        .fadeSlideIn(index: 5)
    }

    private var visionCard: some View {
        AboutStoryCard(
            eyebrow: "我们想做的",
            icon: "sparkles",
            title: nil
        ) {
            Text(AboutCopy.vision)
                .font(AppTypography.narrativeBody)
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Text(AboutCopy.closing)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            pullquote(AboutCopy.invitation)
                .padding(.top, AppSpacing.xxs)
        }
        .fadeSlideIn(index: 6)
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionHeaderBottom) {
            sectionEyebrow("你可以做什么")
            .fadeSlideIn(index: 7)

            ZStack(alignment: .bottomTrailing) {
                CapabilityDecoration()
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)

                AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: 0) {
                    VStack(spacing: 0) {
                        capabilityRow(icon: "map", title: "行程", subtitle: "按天规划节点与路线", showsDivider: true, entranceIndex: 0)
                        capabilityRow(icon: "book", title: "日志", subtitle: "记录瞬间与照片", showsDivider: true, entranceIndex: 1)
                        capabilityRow(icon: "yensign.circle", title: "开支", subtitle: "旅途花费一处整理", showsDivider: true, entranceIndex: 2)
                        capabilityRow(icon: "clock.arrow.circlepath", title: "回顾", subtitle: "旅程结束后回看与分享", showsDivider: false, entranceIndex: 3)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            // P4: 品牌水印收束
            BrandWatermarkView(style: .watermarkDark)
                .padding(.bottom, AppSpacing.xxs)

            Text("© 2026 趣溪 Tracci")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)

            // P4: 备案号链接
            Link(destination: URL(string: ProfileSupportLinks.beianURL)!) {
                Text(ProfileSupportLinks.beianNumber)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.lg)
        .fadeSlideIn(index: 8)
    }

    // MARK: - Shared bits

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.sectionEyebrow)
            .foregroundStyle(AppColors.textPlaceholder)
            .padding(.horizontal, AppSpacing.xxs)
    }

    // MARK: - Pullquote with draw-on border (P3)

    private func pullquote(_ text: String) -> some View {
        PullquoteView(text: text)
    }

    // MARK: - Capability row with individual entrance (P2)

    private func capabilityRow(
        icon: String,
        title: String,
        subtitle: String,
        showsDivider: Bool,
        entranceIndex: Int
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppTypography.listBody)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)，\(subtitle)")

            if showsDivider {
                Divider()
                    .background(AppColors.borderSubtle)
                    .padding(.leading, 76)
            }
        }
        .fadeSlideIn(index: entranceIndex)
    }
}

// MARK: - Pullquote (P3: draws its left border on appear)

private struct PullquoteView: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var borderDrawn = false

    var body: some View {
        Text(text)
            .font(AppTypography.narrativeBody)
            .italic()
            .foregroundStyle(AppColors.textPrimary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.35))
                    .frame(width: 3)
                    .scaleEffect(y: borderDrawn ? 1 : 0, anchor: .top)
            }
            .onAppear {
                guard !reduceMotion else { borderDrawn = true; return }
                withAnimation(.easeOut(duration: 0.30).delay(0.15)) {
                    borderDrawn = true
                }
            }
    }
}


// MARK: - Copy（对齐 tracci-website `brandStory`，适度精简）

private enum AboutCopy {
    /// 官网 brandStory.title
    static let heroTitle = "「趣溪」这个名字，\n来自我们对旅行的理解"
    static let heroLead = "旅行规划与记录工具。理行程、记照片和开支，也能和朋友一起协作。"

    static let philosophyTitle = "不只好用，也留得住"
    /// 产品理念：旅行工具 + 轻陪伴
    static let philosophy =
        "旅行不只有待办清单和打卡。它可以很实用，也可以很轻松。"
    /// 出发的契机
    static let opening =
        "出发的原因各有不同，趣溪陪你把灵感变成行程。"

    static let soloTitle = "一个人的旅行"
    static let soloDesc = "需要的是不打扰的陪伴：帮你整理想法、规划路线、记录路上发生的事。"
    static let groupTitle = "一群人的旅行"
    static let groupDesc = "需要的是清晰的协作：一起编辑行程、记录开支、分摊花费，也留下共同的回忆。"

    static let bridge = "这就是趣溪想做的事。"
    static let charactersLead = "「趣溪」二字，藏着我们对旅行的理解。"
    static let quChar = "趣"
    static let quMeaning = "出发的兴趣、探索的好奇和旅途中的小确幸。"
    static let xiChar = "溪"
    static let xiMeaning = "不断流动的路线、片段、照片、花费与回忆。"

    static let tracciName = "Tracci"
    static let tracciPronunciation = "/ˈtreɪsi/"
    static let tracciOrigin = "Tracci 源自意大利语「traccia」，意为痕迹、路径与轨迹。"
    /// companion 精简
    static let tracciCompanion =
        "发音接近「Tracy」，像一位亲切旅伴的名字。"

    /// vision 精简版
    static let vision =
        "旅前把灵感整理成行程，旅中记录日志、照片和开支，旅后把零散瞬间汇成回顾。"
    static let closing = "无论是一个人出发，还是和一群人同行，旅行都不该只被匆匆经过。"
    /// 官网 invitation
    static let invitation = "「趣溪」也像一句轻轻的邀请：去嬉，去玩，去探索。"
}

// MARK: - Hero wave shape

private struct AboutHeroWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.45))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.35),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.85)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Story card shell

private struct AboutStoryCard<Content: View>: View {
    let eyebrow: String
    let icon: String
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: icon)
                        .font(AppTypography.listBody)
                        .foregroundStyle(AppColors.brandPrimary)
                        .frame(width: 32, height: 32)
                        .background(AppColors.brandPrimaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                    Text(eyebrow)
                        .font(AppTypography.editorialMeta)
                        .tracking(1.1)
                        .foregroundStyle(AppColors.textMuted)
                }

                if let title {
                    Text(title)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Mode cards

private struct AboutModeCard: View {
    let icon: String
    let title: String
    let description: String
    var tint: Color = AppColors.brandPrimary
    var mode: TravelSilhouette.Mode = .solo

    var body: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: 0) {
            ZStack(alignment: .bottomTrailing) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(AppTypography.listBody)
                            .foregroundStyle(tint)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AppSpacing.tight) {
                        Text(title)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(description)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.card)

                TravelSilhouette(mode: mode, tint: tint)
                    .frame(width: 80, height: 60)
                    .opacity(0.6)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(description)")
    }
}

// MARK: - 字解卡（趣 / 溪）

private struct CharacterGlyphCard: View {
    let glyph: String
    let meaning: String

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Text(glyph)
                .font(AppFont.system(44, weight: .light))
                .tracking(44 * BrandTokens.wordmarkTrackingRatio)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppColors.brandPrimaryBackground.opacity(0.55))
                )

            Text(meaning)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.cardSmall)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 0.8)
        }
        .tracciElevation(.l0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(glyph)，\(meaning)")
    }
}

// MARK: - Legal（同文件保留）

struct LegalPrivacyView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.cardSmall) {
                introCard
                sdkListCard
                linksCard
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.cardSmall)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .navigationTitle("协议与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
    }

    private var introCard: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: AppSpacing.card) {
            HStack(alignment: .top, spacing: AppSpacing.cozy) {
                Image(systemName: "lock.shield")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("你的数据由你掌握")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("这里可以查看趣溪的用户协议、隐私政策以及已接入的第三方 SDK 清单。外部页面会通过系统方式打开。")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - 第三方 SDK 清单

    private var sdkListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("第三方 SDK 清单")
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.horizontal, AppSpacing.card)
                .padding(.top, AppSpacing.card)
                .padding(.bottom, AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                sdkRow(
                    icon: "simcard",
                    title: "阿里云号码认证服务（PNVS）",
                    subtitle: "本机号码一键登录与认证",
                    privacyTitle: "查看隐私政策",
                    privacyURL: ProfileSupportLinks.aliyunPrivacy
                )
            }
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: 0.8)
            )
        }
    }

    private func sdkRow(
        icon: String,
        title: String,
        subtitle: String,
        privacyTitle: String,
        privacyURL: String
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppTypography.listBody)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.top, AppSpacing.md)

            Divider()
                .background(AppColors.borderSubtle)
                .padding(.leading, 76)
                .padding(.top, AppSpacing.sm)

            Button {
                guard let url = URL(string: privacyURL) else { return }
                openURL(url)
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text(privacyTitle)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.brandPrimary)
                    Image(systemName: "arrow.up.forward")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.card)
                .padding(.vertical, AppSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, AppSpacing.xs)
        }
    }

    // MARK: - 协议链接

    private var linksCard: some View {
        VStack(spacing: 0) {
            legalRow(icon: "doc.text", title: "用户协议", subtitle: "查看服务使用规则", url: ProfileSupportLinks.terms)
            legalDivider
            legalRow(icon: "shield", title: "隐私政策", subtitle: "了解信息收集与使用方式", url: ProfileSupportLinks.privacy)
        }
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .tracciElevation(.l0)
    }

    private func legalRow(icon: String, title: String, subtitle: String, url: String) -> some View {
        Button {
            guard let url = URL(string: url) else { return }
            openURL(url)
        } label: {
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

                Image(systemName: "arrow.up.forward")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var legalDivider: some View {
        Divider()
            .background(AppColors.borderSubtle)
            .padding(.leading, 76)
    }
}

/// Shared support / legal / App Store links for Profile subpages.
enum ProfileSupportLinks {
    static let terms = "https://tracci.cn/terms"
    static let privacy = "https://tracci.cn/privacy"
    static let aliyunPrivacy = "https://terms.aliyun.com/legal-agreement/terms/suit_bu1_ali_cloud/suit_bu1_ali_cloud202112211045_86198.html"
    static let mail = "mailto:support@tracci.cn"
    static let supportEmailDisplay = "support@tracci.cn"
    static let beianURL = "https://beian.miit.gov.cn/"
    static let beianNumber = "沪ICP备2026021308号-3A"

    static var shareItems: [Any] {
        var items: [Any] = ["我在用「趣溪」规划和记录旅行，行程、日志、花费都能放一起。"]
        if let url = AppStoreConfig.productURL {
            items.append(url)
        }
        return items
    }
}

#if DEBUG
#Preview("关于趣溪 · iPhone 17") {
    NavigationStack {
        AboutTracciView()
    }
}

#Preview("关于趣溪 · iPhone Air") {
    NavigationStack {
        AboutTracciView()
    }
    .previewDevice("iPhone Air")
}

#Preview("Hero 溪线动画") {
    AboutHeroIllustration()
        .frame(height: 112)
        .background(AppColors.backgroundGrouped)
        .padding()
}
#endif
