import SwiftUI

/// 溪线分隔线 — Shape + trim 描边（动画可靠）。
/// - `quiet`：轻弧章节分隔（关于页等）
/// - `stream`：S 形双层流水，登录刊头「溪感」签名
struct CreekDivider: View {
    enum Style {
        /// 轻弧分隔
        case quiet
        /// S 形主溪 + 伴流，更像水道
        case stream
    }

    var style: Style = .quiet
    var opacity: Double = 0.12
    var height: CGFloat = 40
    /// 主线线宽；登录签名可加大。
    var lineWidth: CGFloat = 1.2
    /// quiet 模式中段圆点；stream 改为沿途微点。
    var showsMidDot: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        Group {
            switch style {
            case .quiet:
                quietCreek
            case .stream:
                streamCreek
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                progress = 0
                withAnimation(.easeInOut(duration: style == .stream ? 0.95 : 0.75).delay(0.06)) {
                    progress = 1
                }
            }
        }
    }

    // MARK: Quiet

    private var quietCreek: some View {
        ZStack {
            CreekQuadPath()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColors.brandPrimary.opacity(opacity * 0.45),
                    style: StrokeStyle(lineWidth: lineWidth * 3.2, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 2.5)

            CreekQuadPath()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColors.brandPrimary.opacity(opacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

            if showsMidDot, progress > 0.88 {
                GeometryReader { geo in
                    Circle()
                        .fill(AppColors.brandPrimary.opacity(min(opacity + 0.22, 0.55)))
                        .frame(width: max(5, lineWidth * 2.8), height: max(5, lineWidth * 2.8))
                        .position(x: geo.size.width * 0.52, y: geo.size.height * 0.48)
                        .opacity(Double((progress - 0.88) / 0.12))
                }
            }
        }
    }

    // MARK: Stream（登录刊头）

    private var streamCreek: some View {
        ZStack {
            // 水道软晕
            CreekMeanderPath()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColors.brandPrimary.opacity(opacity * 0.28),
                    style: StrokeStyle(lineWidth: lineWidth * 5.5, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 4)

            // 伴流（略偏、更细、更淡）— 双线才有「水束」感
            CreekMeanderPath(yOffset: 0.10, amplitudeScale: 0.82)
                .trim(from: 0, to: max(progress - 0.06, 0))
                .stroke(
                    AppColors.brandPrimary.opacity(opacity * 0.38),
                    style: StrokeStyle(lineWidth: lineWidth * 0.72, lineCap: .round, lineJoin: .round)
                )

            // 主溪
            CreekMeanderPath()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColors.brandPrimary.opacity(opacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

            // 内侧细线（略偏、更淡，像浅滩与主水道分层）
            CreekMeanderPath(yOffset: -0.05, amplitudeScale: 0.94)
                .trim(from: 0, to: max(progress - 0.04, 0))
                .stroke(
                    AppColors.brandPrimary.opacity(opacity * 0.42),
                    style: StrokeStyle(lineWidth: max(0.7, lineWidth * 0.4), lineCap: .round, lineJoin: .round)
                )

            // 沿途微光点（随水流出现，不是下划线中点）
            if showsMidDot {
                streamSparkles
            }
        }
    }

    private var streamSparkles: some View {
        // 沿 S 形近似采样：(x, y, appearAt)
        let sparks: [(CGFloat, CGFloat, CGFloat)] = [
            (0.20, 0.64, 0.26),
            (0.46, 0.34, 0.50),
            (0.70, 0.60, 0.72),
            (0.90, 0.40, 0.88),
        ]
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ForEach(0..<sparks.count, id: \.self) { index in
                let spark = sparks[index]
                let appear = spark.2
                let local: CGFloat = progress > appear
                    ? min((progress - appear) / 0.12, 1)
                    : 0
                ZStack {
                    Circle()
                        .fill(AppColors.brandPrimary.opacity(opacity * 0.22))
                        .frame(width: 10, height: 10)
                        .blur(radius: 1.2)
                    Circle()
                        .fill(AppColors.brandPrimary.opacity(min(opacity + 0.15, 0.7)))
                        .frame(width: 3.2, height: 3.2)
                }
                .position(x: w * spark.0, y: h * spark.1)
                .opacity(Double(local))
                .scaleEffect(0.75 + 0.25 * local)
            }
        }
    }
}

/// 轻弧路径（quiet）。
private struct CreekQuadPath: Shape {
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.width * 0.06, y: rect.height * 0.72)
        let end = CGPoint(x: rect.width * 0.94, y: rect.height * 0.28)
        let control = CGPoint(x: rect.width * 0.38, y: rect.height * 0.92)

        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

/// S 形蜿蜒主溪（stream）。`yOffset` / `amplitudeScale` 用于伴流与高光层。
private struct CreekMeanderPath: Shape {
    /// 垂直偏移（相对高度比例，正值偏下）。
    var yOffset: CGFloat = 0
    /// 弯幅缩放（<1 更平缓）。
    var amplitudeScale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let midY = h * (0.50 + yOffset)
        let amp = h * 0.34 * amplitudeScale

        var path = Path()
        // 源头：略收、偏下
        path.move(to: CGPoint(x: w * 0.02, y: midY + amp * 0.15))

        // 第一弯：下探再抬 — 像溪岸回转
        path.addCurve(
            to: CGPoint(x: w * 0.36, y: midY - amp * 0.55),
            control1: CGPoint(x: w * 0.12, y: midY + amp * 1.05),
            control2: CGPoint(x: w * 0.24, y: midY - amp * 1.15)
        )

        // 第二弯：下沉后汇出 — 避免「一字下划线」
        path.addCurve(
            to: CGPoint(x: w * 0.98, y: midY - amp * 0.10),
            control1: CGPoint(x: w * 0.52, y: midY + amp * 0.95),
            control2: CGPoint(x: w * 0.78, y: midY - amp * 0.85)
        )

        return path
    }
}

/// 旅行方式插画 — Canvas 绘制的极简旅人剪影（优化比例版）。
struct TravelSilhouette: View {
    enum Mode {
        case solo
        case group
    }

    var mode: Mode
    var tint: Color = AppColors.brandPrimary

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            switch mode {
            case .solo:
                drawPerson(context: context, at: CGPoint(x: w * 0.5, y: h * 0.48), scale: 1.0)
            case .group:
                drawPerson(context: context, at: CGPoint(x: w * 0.32, y: h * 0.50), scale: 0.82)
                drawPerson(context: context, at: CGPoint(x: w * 0.68, y: h * 0.45), scale: 0.92)
            }

            // 地面溪线
            var ground = Path()
            ground.move(to: CGPoint(x: w * 0.08, y: h * 0.95))
            ground.addQuadCurve(
                to: CGPoint(x: w * 0.92, y: h * 0.95),
                control: CGPoint(x: w * 0.5, y: h * 0.88)
            )
            context.stroke(
                ground,
                with: .color(tint.opacity(0.12)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3, 6])
            )
        }
        .accessibilityHidden(true)
    }

    private func drawPerson(context: GraphicsContext, at center: CGPoint, scale: CGFloat) {
        let s = scale
        // 头（略大更清晰）
        let headRadius: CGFloat = 7 * s
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - headRadius,
                y: center.y - 30 * s,
                width: headRadius * 2,
                height: headRadius * 2
            )),
            with: .color(tint.opacity(0.45))
        )
        // 肩身（梯形更自然）
        var body = Path()
        body.move(to: CGPoint(x: center.x - 9 * s, y: center.y - 22 * s))
        body.addLine(to: CGPoint(x: center.x - 6 * s, y: center.y + 8 * s))
        body.addLine(to: CGPoint(x: center.x + 6 * s, y: center.y + 8 * s))
        body.addLine(to: CGPoint(x: center.x + 9 * s, y: center.y - 22 * s))
        body.closeSubpath()
        context.fill(body, with: .color(tint.opacity(0.30)))
    }
}

/// Hero 氛围插画 — 替代散落 motif chip 的沉浸式 Canvas 构图。
/// 溪线从四周汇入中央，点缀微光圆点，营造"自然成溪"的品牌意象。
/// 支持入场动画：溪线从边缘汇入中央，微光点逐个亮起（Reduce Motion 兼容）。
struct AboutHeroIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // 溪线：从四周汇入中央（随 progress 逐渐延伸）
            let streams: [(start: CGPoint, end: CGPoint, ctrl: CGPoint, color: Color)] = [
                (CGPoint(x: w * 0.05, y: h * 0.15), CGPoint(x: w * 0.45, y: h * 0.48), CGPoint(x: w * 0.20, y: h * 0.30), AppColors.brandPrimary.opacity(0.18)),
                (CGPoint(x: w * 0.95, y: h * 0.12), CGPoint(x: w * 0.55, y: h * 0.48), CGPoint(x: w * 0.80, y: h * 0.28), AppColors.brandPrimary.opacity(0.15)),
                (CGPoint(x: w * 0.15, y: h * 0.90), CGPoint(x: w * 0.40, y: h * 0.55), CGPoint(x: w * 0.22, y: h * 0.72), AppColors.dawnGold.opacity(0.12)),
                (CGPoint(x: w * 0.85, y: h * 0.88), CGPoint(x: w * 0.60, y: h * 0.55), CGPoint(x: w * 0.78, y: h * 0.70), AppColors.dawnGold.opacity(0.10)),
            ]

            for stream in streams {
                var path = Path()
                let currentEnd = CGPoint(
                    x: stream.start.x + (stream.end.x - stream.start.x) * progress,
                    y: stream.start.y + (stream.end.y - stream.start.y) * progress
                )
                let currentCtrl = CGPoint(
                    x: stream.start.x + (stream.ctrl.x - stream.start.x) * progress,
                    y: stream.start.y + (stream.ctrl.y - stream.start.y) * progress
                )
                path.move(to: stream.start)
                path.addQuadCurve(to: currentEnd, control: currentCtrl)
                context.stroke(path, with: .color(stream.color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }

            // 中央汇入点微光（progress > 0.6 后淡入）
            if progress > 0.6 {
                let fadeInProgress = min((progress - 0.6) / 0.4, 1.0)
                let center = CGPoint(x: w * 0.5, y: h * 0.50)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                    with: .color(AppColors.brandPrimary.opacity(0.25 * fadeInProgress))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)),
                    with: .color(AppColors.brandPrimary.opacity(0.50 * fadeInProgress))
                )
            }

            // 散落微光点（progress > 0.4 后逐个淡入）
            let dots: [(CGPoint, Double)] = [
                (CGPoint(x: w * 0.20, y: h * 0.25), 0.20),
                (CGPoint(x: w * 0.75, y: h * 0.30), 0.18),
                (CGPoint(x: w * 0.30, y: h * 0.75), 0.15),
                (CGPoint(x: w * 0.70, y: h * 0.80), 0.16),
                (CGPoint(x: w * 0.50, y: h * 0.15), 0.12),
            ]
            for (index, dot) in dots.enumerated() {
                let dotTrigger = 0.4 + Double(index) * 0.12
                if progress > dotTrigger {
                    let dotFade = min((progress - dotTrigger) / 0.2, 1.0)
                    context.fill(
                        Path(ellipseIn: CGRect(x: dot.0.x - 1.5, y: dot.0.y - 1.5, width: 3, height: 3)),
                        with: .color(AppColors.brandPrimary.opacity(dot.1 * dotFade))
                    )
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                    progress = 1
                }
            }
        }
    }
}

/// 功能清单装饰 — Canvas 绘制的 subtle 背景点线，暗示旅程节点。
/// 支持入场动画：轨迹从上向下绘制，节点逐个亮起。
struct CapabilityDecoration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // 左侧虚线轨迹（从上向下绘制）
            let traceX = w * 0.18
            let traceTop = h * 0.12
            let traceBot = h * 0.88
            let currentBot = traceTop + (traceBot - traceTop) * progress
            var trace = Path()
            trace.move(to: CGPoint(x: traceX, y: traceTop))
            trace.addLine(to: CGPoint(x: traceX, y: currentBot))
            context.stroke(
                trace,
                with: .color(AppColors.brandPrimary.opacity(0.08)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [2, 6])
            )

            // 轨迹上的节点圆点（逐个亮起）
            let nodeYs: [CGFloat] = [0.22, 0.42, 0.62, 0.82]
            for (index, y) in nodeYs.enumerated() {
                let nodeTrigger = Double(index) * 0.25
                if progress > nodeTrigger {
                    let nodeFade = min((progress - nodeTrigger) / 0.2, 1.0)
                    context.fill(
                        Path(ellipseIn: CGRect(x: traceX - 2.5, y: h * y - 2.5, width: 5, height: 5)),
                        with: .color(AppColors.brandPrimary.opacity(0.15 * nodeFade))
                    )
                }
            }

            // 右下角散落微点（progress > 0.6 后出现）
            if progress > 0.6 {
                let dotFade = min((progress - 0.6) / 0.4, 1.0)
                let dots: [(CGPoint, Double)] = [
                    (CGPoint(x: w * 0.85, y: h * 0.85), 0.10),
                    (CGPoint(x: w * 0.90, y: h * 0.90), 0.08),
                    (CGPoint(x: w * 0.88, y: h * 0.80), 0.07),
                ]
                for (pt, alpha) in dots {
                    context.fill(
                        Path(ellipseIn: CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3)),
                        with: .color(AppColors.brandPrimary.opacity(alpha * dotFade))
                    )
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeInOut(duration: 0.9).delay(0.2)) {
                    progress = 1
                }
            }
        }
    }
}

/// 登录页四宫格溪线 — 规划 · 记录 · 协作 · 回忆
/// V4: 2×2 网格布局 + S 形溪线 + 轻量呼吸动效（错峰浮动，不重复文案）
struct LoginFeatureFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let icons = ["map", "square.and.pencil", "person.2", "photo.on.rectangle"]

    @State private var streamProgress: Double = 0
    @State private var iconVisible = [false, false, false, false]
    @State private var floatOffsets: [CGFloat] = [0, 0, 0, 0]

    // 呼吸配置: (周期秒, 幅度pt, 相位秒)
    private let breathConfig: [(Double, CGFloat, Double)] = [
        (3.2, 4, 0),      // 规划
        (2.8, 3.5, 0.8),  // 记录
        (3.6, 4.5, 1.6),  // 协作
        (3.0, 3, 2.4),    // 回忆
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 104
            let mx = w * 0.12
            let my: CGFloat = 18

            // 2×2 位置: TL, TR, BL, BR
            let positions = [
                CGPoint(x: mx, y: my),          // 规划
                CGPoint(x: w - mx, y: my),      // 记录
                CGPoint(x: mx, y: h - my),      // 协作
                CGPoint(x: w - mx, y: h - my),  // 回忆
            ]

            let streamPath = SShapeStreamShape(positions: positions).path(in: CGRect(x: 0, y: 0, width: w, height: h))

            ZStack {
                // 溪线（光晕底层 + 主线）
                streamPath
                    .trimmedPath(from: 0, to: streamProgress)
                    .stroke(AppColors.brandPrimary.opacity(0.06), style: StrokeStyle(lineWidth: 8, lineCap: .round))

                streamPath
                    .trimmedPath(from: 0, to: streamProgress)
                    .stroke(AppColors.brandPrimary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                // 图标层
                ForEach(0..<4, id: \.self) { i in
                    FloatingIcon(systemImage: icons[i])
                        .position(positions[i])
                        .opacity(iconVisible[i] ? 1 : 0)
                        .scaleEffect(iconVisible[i] ? 1 : 0.6)
                        .offset(y: floatOffsets[i])
                }
            }
            .frame(width: w, height: h)
        }
        .frame(height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("规划、记录、协作、回忆")
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        guard !reduceMotion else {
            streamProgress = 1
            iconVisible = [true, true, true, true]
            return
        }

        // 溪线绘制（0.9s）
        withAnimation(.easeInOut(duration: 0.9).delay(0.35)) {
            streamProgress = 1
        }

        // 图标依次弹性入场（错峰 0.1s，带 overshoot）
        for i in 0..<4 {
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.65)
                    .delay(0.45 + Double(i) * 0.1)
            ) {
                iconVisible[i] = true
            }
        }

        // 轻量呼吸浮动（不同周期/幅度/相位，永不重叠）
        for i in 0..<4 {
            let (period, amplitude, phase) = breathConfig[i]
            withAnimation(
                .easeInOut(duration: period)
                    .delay(phase)
                    .repeatForever(autoreverses: true)
            ) {
                floatOffsets[i] = -amplitude
            }
        }
    }
}

// MARK: - S 形溪线（连接 2×2 四角）

private struct SShapeStreamShape: Shape {
    var positions: [CGPoint]

    var animatableData: CGFloat { 1 }

    func path(in rect: CGRect) -> Path {
        guard positions.count == 4 else { return Path() }
        let tl = positions[0], tr = positions[1], bl = positions[2], br = positions[3]
        let w = rect.width, h = rect.height

        var path = Path()
        path.move(to: tl)

        // TL → TR: 向上拱起
        path.addQuadCurve(
            to: tr,
            control: CGPoint(x: w / 2, y: -4)
        )
        // TR → BR: 向右弧出再回
        path.addQuadCurve(
            to: br,
            control: CGPoint(x: tr.x + (w - tr.x) * 0.15 + 6, y: h / 2)
        )
        // BR → BL: 向下拱起
        path.addQuadCurve(
            to: bl,
            control: CGPoint(x: w / 2, y: h + 4)
        )

        return path
    }
}

// MARK: - 浮动图标（柔和光晕 + 呼吸浮动）

private struct FloatingIcon: View {
    let systemImage: String

    var body: some View {
        ZStack {
            // 柔和光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.brandPrimary.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: 26
                    )
                )
                .frame(width: 52, height: 52)

            // 图标圆底
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.brandPrimaryBackground, AppColors.brandPrimary.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
                .overlay {
                    Circle()
                        .stroke(AppColors.brandPrimary.opacity(0.12), lineWidth: 0.8)
                }

            // 图标
            Image(systemName: systemImage)
                .font(AppFont.system(16, weight: .medium))
                .foregroundStyle(AppColors.brandPrimary)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LoginFeatureFlow") {
    VStack(spacing: 16) {
        LoginFeatureFlow()
            .padding(.horizontal, 24)
        Text("规划 · 记录 · 协作 · 回忆")
            .font(AppFont.system(12, weight: .medium))
            .foregroundStyle(AppColors.textMuted)
            .tracking(0.18)
    }
    .padding(.vertical, 20)
    .background(AppColors.backgroundGrouped)
}

#Preview("CreekDivider") {
    VStack(spacing: 28) {
        CreekDivider()
        CreekDivider(style: .stream, opacity: 0.36, height: 48, lineWidth: 1.9)
    }
    .padding()
    .background(AppColors.backgroundGrouped)
}

#Preview("TravelSilhouette") {
    HStack(spacing: 40) {
        TravelSilhouette(mode: .solo)
            .frame(width: 80, height: 60)
        TravelSilhouette(mode: .group)
            .frame(width: 80, height: 60)
    }
    .padding()
}

#Preview("AboutHeroIllustration") {
    AboutHeroIllustration()
        .frame(height: 112)
        .background(AppColors.backgroundGrouped)
        .padding()
}

#Preview("CapabilityDecoration") {
    CapabilityDecoration()
        .frame(height: 200)
        .background(AppColors.cardBackground)
        .padding()
}
#endif
