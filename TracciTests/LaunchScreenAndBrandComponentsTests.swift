import XCTest
@testable import Tracci

/// G1 高级感专项回归防护：启动叙事配置、品牌加载指示与按钮触感不回退。
final class LaunchScreenAndBrandComponentsTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    // MARK: - 启动叙事（G1.1）

    func testLaunchScreenDictIsConfiguredWithBrandCanvasAndLogo() throws {
        let plistURL = repositoryRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        // 空 <dict/> 会回到白屏冷启动，这里锁死品牌底色 + Logo 配置。
        let launchScreen = try XCTUnwrap(
            plist?["UILaunchScreen"] as? [String: Any],
            "UILaunchScreen 必须是已配置的字典"
        )
        XCTAssertEqual(launchScreen["UIColorName"] as? String, "BrandColors/LaunchBackground")
        XCTAssertEqual(launchScreen["UIImageName"] as? String, "Brand/BrandLogoBlue")
    }

    func testLaunchAssetsExist() {
        let assets = repositoryRoot
            .appendingPathComponent("Resources/Assets.xcassets")

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: assets.appendingPathComponent("BrandColors/LaunchBackground.colorset").path
            ),
            "缺少 LaunchBackground 色值（应与系统分组底一致）"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: assets.appendingPathComponent("Brand/BrandLogoBlue.imageset").path
            )
        )
    }

    func testLaunchBackgroundColorResolvesFromMainBundle() {
        // `BrandColors` folder provides a namespace, so the lookup needs the full path.
        XCTAssertNotNil(UIColor(named: "BrandColors/LaunchBackground"))
    }

    // MARK: - 品牌加载指示与按钮触感（G1.2 / G1.4）

    func testBrandButtonsNeverFallBackToPlainStyle() throws {
        let buttons = try source("Core/DesignSystem/AppButtons.swift")
        XCTAssertFalse(
            buttons.contains(".buttonStyle(.plain)"),
            "品牌按钮不得回退到无按压反馈的 .plain 样式"
        )
    }

    func testBrandButtonsUseBrandedProgressIndicator() throws {
        let buttons = try source("Core/DesignSystem/AppButtons.swift")
        let stateViews = try source("Core/DesignSystem/AppStateViews.swift")

        XCTAssertFalse(buttons.contains("ProgressView()"))
        XCTAssertFalse(stateViews.contains("ProgressView()"))
        XCTAssertTrue(buttons.contains("AppProgressIndicator"))
        XCTAssertTrue(stateViews.contains("AppProgressIndicator"))
    }

    /// 媒体浮层玻璃按钮必须保留按压反馈：`.plain` 在 iOS 26 以下零反馈，
    /// 且它离 Button 更近时会覆盖外层显式指定的按压样式（按压缩样式失效）。
    func testMediaOverlayButtonsKeepPressFeedback() throws {
        let modeToggle = try source("Features/Trip/Components/TripHeroModeToggle.swift")
        let mapSurface = try source("Features/Trip/Components/TripMapExploreSurface.swift")
        let header = try source("Features/Trip/Components/TripDetailHeader.swift")

        for (name, source) in [
            ("TripHeroModeToggle", modeToggle),
            ("TripMapExploreSurface", mapSurface),
            ("TripDetailHeader", header),
        ] {
            XCTAssertFalse(
                source.contains(".buttonStyle(.plain)"),
                "\(name) 的媒体浮层按钮不得回退到无按压反馈的 .plain 样式"
            )
        }
        XCTAssertTrue(modeToggle.contains("TracciPressableButtonStyle"))
        XCTAssertTrue(mapSurface.contains("TracciPressableButtonStyle"))
        // 路线总览按钮显式指定的按压样式不得再被 .plain 覆盖。
        XCTAssertTrue(header.contains(".pressableCardStyle(scale: 0.96, opacity: 0.88)"))
    }

    /// 死样式组合防护：离 Button 更近的 .plain 会静默覆盖外层显式指定的按压
    /// 样式。扫描各行后 3 行窗口，.plain 之后不得紧跟 pressableCardStyle。
    func testPressStylesAreNotSilencedByPlainStyle() throws {
        for path in [
            "Features/Home/HomeView.swift",
            "Features/Memory/MemoryYearlyReportViews.swift",
            "Features/Memory/MemoryCompanionViews.swift",
            "Features/Memory/MemoryTripListViews.swift",
            "Features/Trip/Components/TripDetailHeader.swift",
        ] {
            let lines = try source(path).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() where line.contains(".buttonStyle(.plain)") {
                let window = lines[(i + 1)...min(i + 3, lines.count - 1)]
                XCTAssertFalse(
                    window.contains { $0.contains("pressableCardStyle(") },
                    "\(path):\(i + 1) 的 .plain 覆盖了紧随其后的按压样式（死样式组合）"
                )
            }
        }
    }

    // MARK: - 空态（G1.5 · 2026-08-22 降级定稿）

    /// 空态采用「安静大图标」：单符号、无色底圆盘；溪流插画只属于品牌时刻
    /// （首页空态 / 关于页 / 登录页），不得回潮到工具卡与空态页。
    func testEmptyStatesStayQuietWithoutIllustrations() throws {
        let stateViews = try source("Core/DesignSystem/AppStateViews.swift")
        let companion = try source("Core/DesignSystem/AppCards.swift")
        let dayEmpty = try source("Features/Trip/Components/TripDayEmptyStateView.swift")
        let expenseEmpty = try source("Features/Expense/ExpenseEmptyStateView.swift")
        let allTrips = try source("Features/Trip/AllTripsView.swift")

        for (name, source) in [
            ("AppStateViews", stateViews),
            ("AppCards", companion),
            ("TripDayEmptyStateView", dayEmpty),
            ("ExpenseEmptyStateView", expenseEmpty),
            ("AllTripsView", allTrips),
        ] {
            XCTAssertFalse(
                source.contains("AppEmptyStateIllustration"),
                "\(name) 不得接入空态插画（2026-08-22 降级决策）"
            )
        }

        // 安静空态：无浅蓝圆盘底（brandPrimaryBackground 圆底为旧「未设计」样式）。
        XCTAssertFalse(stateViews.contains("brandPrimaryBackground.opacity(0.72)"))
        XCTAssertTrue(stateViews.contains("symbolRenderingMode(.hierarchical)"))
    }

    func testEmptyStateIllustrationComponentIsRemoved() {
        let componentPath = repositoryRoot
            .appendingPathComponent("Core/DesignSystem/AppEmptyStateIllustration.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: componentPath.path),
            "AppEmptyStateIllustration 已删除，若恢复需重新走设计评审"
        )
    }

    // MARK: - G2.1 Serif Display 试点

    func testSerifPilotTokensExistAndAreWired() throws {
        let typography = try source("Core/DesignSystem/AppTypography.swift")
        XCTAssertTrue(typography.contains("storyTitleSerif"))
        XCTAssertTrue(typography.contains("yearMarkSerif"))

        let tripList = try source("Features/Memory/MemoryTripListViews.swift")
        XCTAssertTrue(tripList.contains("storyTitleSerif"), "回忆页故事标题应使用 serif 试点 token")

        let yearly = try source("Features/Memory/MemoryYearlyReportViews.swift")
        XCTAssertTrue(yearly.contains("yearMarkSerif"), "年度报告年份应使用 serif 试点 token")
    }

    /// Serif 只允许出现在批准的 Display 位；按钮与表单等工具面不得引入。
    func testSerifStaysOutOfToolSurfaces() throws {
        let buttons = try source("Core/DesignSystem/AppButtons.swift")
        let forms = try source("Core/DesignSystem/TracciFormField.swift")

        XCTAssertFalse(buttons.contains(".serif"))
        XCTAssertFalse(forms.contains(".serif"))
    }

    // MARK: - G2.2 主 CTA 质感

    func testPrimaryCTAUsesTexturedFill() throws {
        let buttons = try source("Core/DesignSystem/AppButtons.swift")
        let stateViews = try source("Core/DesignSystem/AppStateViews.swift")

        XCTAssertTrue(buttons.contains("TracciCTABackground"))
        XCTAssertTrue(stateViews.contains("TracciCTABackground"))
        // 平涂主 CTA 禁止回潮。
        XCTAssertFalse(buttons.contains(".background(AppColors.brandPrimary)"))
        XCTAssertFalse(stateViews.contains(".background(AppColors.brandPrimary)"))
    }

    // MARK: - G2.3 AppIcon 变体

    func testAppIconHasDarkAndTintedVariants() throws {
        let contents = try source("Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
        XCTAssertTrue(contents.contains("\"value\" : \"dark\""))
        XCTAssertTrue(contents.contains("\"value\" : \"tinted\""))

        let dir = repositoryRoot.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AppIcon-dark-1024.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AppIcon-tinted-1024.png").path))
    }

    // MARK: - G3 关键时刻动效

    /// 第一批共享动效原语：滑动 pill / 成功勾 / 表单 shake / 骨架揭开。
    func testSharedMotionPrimitivesStayWired() throws {
        let motion = try source("Core/DesignSystem/AppMotion.swift")
        XCTAssertTrue(motion.contains("selectionPillDuration"))
        XCTAssertTrue(motion.contains("pressDuration"))
        XCTAssertTrue(motion.contains("static var enter"))
        XCTAssertTrue(motion.contains("static var press"))
        XCTAssertEqual(AppMotion.pressDuration, 0.16, accuracy: 0.001)
        XCTAssertTrue(motion.contains("skeletonRevealDuration"))
        XCTAssertTrue(motion.contains("errorShakeSegmentDuration"))
        XCTAssertTrue(motion.contains("successCheckDuration"))
        XCTAssertTrue(motion.contains("tracciErrorShake"))
        XCTAssertTrue(motion.contains("revealTransition"))
        XCTAssertTrue(motion.contains("accessibilityReduceMotion"))

        let controls = try source("Core/DesignSystem/TracciFormControls.swift")
        XCTAssertTrue(controls.contains("TracciSlidingSelectionPill"))
        XCTAssertTrue(controls.contains("matchedGeometryEffect"))
        XCTAssertTrue(controls.contains("AppMotion.selectionPill"))

        let buttons = try source("Core/DesignSystem/AppButtons.swift")
        XCTAssertTrue(buttons.contains("TracciSuccessCheck"))
        XCTAssertTrue(buttons.contains("TracciSuccessCheckPath"))
        XCTAssertFalse(buttons.contains("checkmark.circle.fill"))

        let fields = try source("Core/DesignSystem/TracciFormField.swift")
        XCTAssertTrue(fields.contains(".tracciErrorShake(errorMessage)"))

        let otp = try source("Core/DesignSystem/TracciOTPCodeField.swift")
        XCTAssertTrue(otp.contains(".tracciErrorShake(errorMessage)"))

        let segmentedAuth = try source("Features/Auth/AuthLandingView.swift")
        XCTAssertTrue(segmentedAuth.contains("TracciSlidingSelectionPill"))

        let allTrips = try source("Features/Trip/AllTripsView.swift")
        XCTAssertTrue(allTrips.contains("TracciSlidingSelectionPill"))
        XCTAssertTrue(allTrips.contains("tracciRevealTransition"))

        let heroToggle = try source("Features/Trip/Components/TripHeroModeToggle.swift")
        XCTAssertTrue(heroToggle.contains("TracciSlidingSelectionPill"))
    }

    func testSecondBatchMotionPrimitivesStayWired() throws {
        let motion = try source("Core/DesignSystem/AppMotion.swift")
        XCTAssertTrue(motion.contains("morphOpenDuration"))
        XCTAssertTrue(motion.contains("morphCloseDuration"))
        XCTAssertTrue(motion.contains("TracciNumberPopIn"))
        XCTAssertTrue(motion.contains("tracciTextsReveal"))
        XCTAssertTrue(motion.contains("toastOpenDuration"))
        XCTAssertLessThan(AppMotion.morphCloseDuration, AppMotion.morphOpenDuration)
        XCTAssertLessThan(AppMotion.toastCloseDuration, AppMotion.toastOpenDuration)

        let fab = try source("Features/Trip/Components/TripDetailFABChrome.swift")
        XCTAssertTrue(fab.contains("AppMotion.morphOpen"))
        XCTAssertTrue(fab.contains("AppMotion.morphClose"))

        // 新建菜单无白色底板：卡片直接浮在全屏 scrim 上（决策 2026-09-22），morph 底板不得回归。
        let create = try source("App/CreateFlow/CreateOptionsOverlay.swift")
        XCTAssertFalse(create.contains("createMorphPlate"))
        XCTAssertTrue(create.contains("AppMotion.morphOpen"))

        let createAction = try source("App/GlobalCreateAction.swift")
        XCTAssertTrue(createAction.contains("AppMotion.morphOpen"))

        let toast = try source("Core/DesignSystem/TracciToast.swift")
        XCTAssertTrue(toast.contains("toastMaxStack"))
        XCTAssertTrue(toast.contains("TracciSuccessCheck"))

        let empty = try source("Core/DesignSystem/AppStateViews.swift")
        XCTAssertTrue(empty.contains("tracciTextsReveal(index:"))

        let checkbox = try source("Core/DesignSystem/AppButtons.swift")
        XCTAssertTrue(checkbox.contains("TracciStrokeCheckbox"))

        let consent = try source("Features/Auth/RegisterView.swift")
        XCTAssertTrue(consent.contains("TracciStrokeCheckbox"))

        let switchThumb = try source("Core/DesignSystem/TracciFormControls.swift")
        XCTAssertTrue(switchThumb.contains("AppMotion.switchOn"))
    }

    /// Hero zoom 转场必须保持 iOS 18 门控与 Reduce Motion 回退（部署目标不提高）。
    func testHeroZoomTransitionStaysGatedAndWired() throws {
        let motion = try source("Core/DesignSystem/AppMotion.swift")
        XCTAssertTrue(motion.contains("tracciHeroZoomSource"))
        XCTAssertTrue(motion.contains("tracciHeroZoomDestination"))
        XCTAssertTrue(motion.contains("#available(iOS 18.0, *)"))

        let home = try source("Features/Home/HomeView.swift")
        XCTAssertTrue(home.contains(".tracciHeroZoomSource(id: trip.id"))
        XCTAssertTrue(home.contains(".tracciHeroZoomDestination(id: tripId"))

        let allTrips = try source("Features/Trip/AllTripsView.swift")
        XCTAssertTrue(allTrips.contains(".tracciHeroZoomSource(id: trip.id"))
        XCTAssertTrue(home.contains("tripDetailZoomNamespace: tripDetailZoomNamespace"))
    }

    func testThirdBatchMotionPrimitivesStayWired() throws {
        let motion = try source("Core/DesignSystem/AppMotion.swift")
        XCTAssertTrue(motion.contains("joinSuccessHoldDuration"))
        XCTAssertTrue(motion.contains("TracciClearDissolve"))
        XCTAssertTrue(motion.contains("inputClearDuration"))
        XCTAssertTrue(motion.contains("badgePop"))

        let join = try source("Features/Collaboration/JoinTripView.swift")
        XCTAssertTrue(join.contains("joinSuccessOverlay"))
        XCTAssertTrue(join.contains("TracciSuccessCheck"))
        XCTAssertTrue(join.contains("TracciNumberPopIn"))

        let otp = try source("Core/DesignSystem/TracciOTPCodeField.swift")
        XCTAssertTrue(otp.contains("TracciNumberPopIn"))

        let photos = try source("Features/Journal/JournalPhotoGrid.swift")
        XCTAssertTrue(photos.contains("tracciHeroZoomSource"))
        XCTAssertTrue(photos.contains("tracciHeroZoomDestination"))
        XCTAssertTrue(photos.contains("collageDisplayURL"))
        XCTAssertTrue(photos.contains("contentMode: .fit"))
        XCTAssertFalse(photos.contains(".aspectRatio(1, contentMode: .fill)"))

        let memory = try source("Features/Memory/MemoryView.swift")
        XCTAssertTrue(memory.contains("memoryLaunchNamespace"))

        let badge = try source("Features/Memory/MemoryTripListViews.swift")
        XCTAssertTrue(badge.contains("AppMotion.badgePop"))

        let sceneVM = try source("App/Scene/MainSceneViewModel.swift")
        XCTAssertTrue(sceneVM.contains("handleTripJoined(tripId:"))
        XCTAssertTrue(sceneVM.contains("markNewlyCreated(tripId: tripId)"))
    }

    func testJournalReadSurfaceHasNoEnglishKickers() throws {
        let card = try source("Features/Journal/JournalEntryCard.swift")
        let page = try source("Features/Trip/Components/TripCreekContentSections.swift")
        XCTAssertFalse(card.contains("TRAVEL NOTE"))
        XCTAssertFalse(card.contains("FEATURED MEMORY"))
        XCTAssertFalse(page.contains("TRAVEL NOTE"))
        XCTAssertFalse(page.contains("FEATURED MEMORY"))
        XCTAssertTrue(card.contains("仅自己"))
        XCTAssertTrue(card.contains("精选"))
        XCTAssertTrue(page.contains("editorialDate"))

        let forbidden = ["TRAVEL NOTE", "FEATURED MEMORY"]
        let journalRoot = repositoryRoot.appendingPathComponent("Features/Journal")
        let enumerator = FileManager.default.enumerator(
            at: journalRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    text.contains(token),
                    "\(url.lastPathComponent) 不得出现英文 kicker「\(token)」"
                )
            }
        }
    }

    func testJournalPhotoCollageDoesNotCropPortraitHero() {
        let portrait = JournalPhoto(
            id: "p1",
            fileId: nil,
            url: nil,
            sortOrder: nil,
            thumbnailUrl: "https://example.com/t.jpg",
            previewUrl: nil,
            exportUrl: nil,
            storyPortraitUrl: nil,
            storyCardUrl: nil,
            squareUrl: "https://example.com/sq.jpg",
            watermarkedUrl: nil,
            width: 1200,
            height: 1800,
            userFeatured: false
        )
        XCTAssertEqual(JournalPhotoCollage.aspectRatio(for: portrait), 1200.0 / 1800.0, accuracy: 0.001)
        XCTAssertTrue(portrait.isPortrait)
        XCTAssertEqual(portrait.collageDisplayURL?.absoluteString, "https://example.com/t.jpg")

        let size = JournalPhotoCollage.heroSize(containerWidth: 320, photo: portrait, compact: false)
        XCTAssertEqual(size.height, JournalPhotoCollage.maxHeroHeight)
        XCTAssertLessThan(size.width, 320)
    }

    func testJournalWriteSurfaceIsOneUnlabeledPage() throws {
        let form = try source("Features/Journal/JournalFormView.swift")
        XCTAssertTrue(form.contains("写一句今天的事就好"))
        XCTAssertFalse(form.contains("记录今天发生的事或备忘"))
        XCTAssertFalse(form.contains("label: \"日志内容\""))
        XCTAssertTrue(form.contains("心情与可见性"))
        XCTAssertTrue(form.contains("autoPresentOnAppear"))
        XCTAssertTrue(form.contains("chrome: .canvas"))
    }

    func testPhotoFirstJournalEntryIsReachableFromFAB() throws {
        let fab = try source("Features/Trip/Components/TripDetailFABChrome.swift")
        XCTAssertTrue(fab.contains("记照片"))
        XCTAssertTrue(fab.contains("onAddPhotoJournal()"))

        let detail = try source("Features/Trip/TripDetailView.swift")
        let fabStart = try XCTUnwrap(detail.range(of: "TripDetailFABChrome("))
        let fabInit = String(detail[fabStart.lowerBound...].prefix(1600))
        XCTAssertTrue(fabInit.contains("onAddPhotoJournal:"))
        XCTAssertTrue(fabInit.contains("journalFormInitialSection = .photos"))
    }

    func testExpenseRowOffersDuplicateAction() throws {
        let row = try source("Features/Expense/ExpenseListItemView.swift")
        XCTAssertTrue(row.contains("再来一笔"))
        let form = try source("Features/Expense/ExpenseFormView.swift")
        XCTAssertTrue(form.contains("垫付、日期与备注"))
        XCTAssertTrue(form.contains("focusedField = .amount"))
        XCTAssertFalse(form.contains("isAmountFocused ? .l2"))
        XCTAssertFalse(form.contains("isAmountFocused ? .l1"))
    }

    /// 创建成功的里程碑编排：success 触感 + 新卡片入场，且状态位为瞬态（自动清理）。
    func testCreateSuccessMilestoneChoreography() throws {
        let sceneVM = try source("App/Scene/MainSceneViewModel.swift")
        XCTAssertTrue(sceneVM.contains("AppHaptics.success()"))
        XCTAssertTrue(sceneVM.contains("markNewlyCreated(tripId:"))

        let homeVM = try source("Features/Home/HomeViewModel.swift")
        XCTAssertTrue(homeVM.contains("newlyCreatedTripId"))

        let home = try source("Features/Home/HomeView.swift")
        XCTAssertTrue(home.contains(".milestoneEntrance(active: viewModel.newlyCreatedTripId == trip.id)"))
    }

    /// G3 真机回归修复：dock 显隐不得回退为整段底部滑入（`.move(edge: .bottom)`）——
    /// 它在返回动画（尤其 iOS 18 zoom）期间被离场详情页遮住，读作"TabBar 出现延迟"。
    func testDockTransitionStaysFadeBased() throws {
        let chrome = try source("App/Navigation/MainTabChromeView.swift")
        XCTAssertFalse(chrome.contains(".move(edge: .bottom)"))
        XCTAssertTrue(chrome.contains("dockTransition"))
        XCTAssertTrue(chrome.contains("AppMotion.fadeSlideOffset"))
    }

    // MARK: - G5 Liquid Glass 深化

    /// 媒体浮层玻璃助手必须保持 iOS 26 门控 + Reduce Transparency 回退。
    func testMediaChromeGlassStaysGated() throws {
        let cards = try source("Core/DesignSystem/AppCards.swift")
        XCTAssertTrue(cards.contains("tracciMediaChromeGlass"))
        XCTAssertTrue(cards.contains("#available(iOS 26, *), !reduceTransparency"))
        XCTAssertTrue(cards.contains(".ultraThinMaterial"))
    }

    /// G5.1 接线：Hero 顶部 Chrome / 地图控制组 / 节点卡 / 模式切换器使用共享玻璃助手。
    func testMediaOverlaySurfacesUseSharedGlass() throws {
        let header = try source("Features/Trip/Components/TripDetailHeader.swift")
        let mapSurface = try source("Features/Trip/Components/TripMapExploreSurface.swift")
        let nodeCard = try source("Features/Trip/Components/TripHeroNodeCard.swift")
        let modeToggle = try source("Features/Trip/Components/TripHeroModeToggle.swift")

        XCTAssertGreaterThanOrEqual(header.components(separatedBy: "tracciMediaChromeGlass").count - 1, 4)
        XCTAssertGreaterThanOrEqual(mapSurface.components(separatedBy: "tracciMediaChromeGlass").count - 1, 2)
        XCTAssertTrue(nodeCard.contains("tracciMediaChromeGlass"))
        XCTAssertTrue(modeToggle.contains("tracciMediaChromeGlass"))
    }

    /// G5.2：详情 Tab 选中指示带玻璃镜头分支，且保留 legacy 下划线回退。
    func testDetailTabLensHasFallback() throws {
        let tabBar = try source("Features/Trip/Components/TripDetailTabBar.swift")
        XCTAssertTrue(tabBar.contains("glassEffectID(\"day-view-lens\""))
        XCTAssertTrue(tabBar.contains("legacyUnderline"))
        XCTAssertTrue(tabBar.contains("GlassEffectContainer"))
    }

    /// G5.4：子页面导航栏最小化保持 iOS 26 门控。
    func testSubpageNavMinimizeStaysGated() throws {
        let visibility = try source("Core/Utils/TracciTabBarVisibility.swift")
        XCTAssertTrue(visibility.contains("tracciNavigationBarMinimizeOnScroll"))
        XCTAssertTrue(visibility.contains("#available(iOS 26, *)"))

        for path in [
            "Features/Trip/TripEditView.swift",
            "Features/SavedPlaces/PlaceDetailView.swift",
            "Features/Collaboration/ActivityLogView.swift",
            "Features/Trip/TripMembersView.swift",
        ] {
            XCTAssertTrue(
                try source(path).contains(".tracciNavigationBarMinimizeOnScroll()"),
                "\(path) 应接入导航栏最小化"
            )
        }
    }

    /// G5.6：行背景无缝延伸助手保持 iOS 26 门控，旧系统 no-op。
    func testRowBackgroundExtensionStaysGated() throws {
        let cards = try source("Core/DesignSystem/AppCards.swift")
        XCTAssertTrue(cards.contains("func tracciBackgroundExtension"))
        XCTAssertTrue(cards.contains("backgroundExtensionEffect"))
        XCTAssertTrue(cards.contains("#available(iOS 26, *)"))
    }
}
