import SwiftUI

/// Hero 地图态下，点选 marker 后显示的紧凑节点信息胶囊。
struct TripHeroNodeCard: View {
    let title: String
    let timeText: String?
    let locationName: String?
    let onNavigate: () -> Void

    var body: some View {
        // 使用 GeometryReader 的父级会传全宽 proposal，
        // 用 .fixedSize() 让 HStack 按内容自适应，不撑满宽度
        HStack(spacing: 10) {
            // P2：左侧品牌竖线（与 AppCompanionCard 左 bar 呼应）
            LinearGradient(
                colors: [AppColors.brandPrimary, AppColors.brandPrimary.opacity(0.4)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 3)
            .clipShape(Capsule())
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let timeText, !timeText.isEmpty {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // 导航按钮：图标 + 文字，明确操作意图
            Button(action: onNavigate) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right")
                        .font(.caption2.weight(.semibold))
                    Text("导航")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(AppColors.brandPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(AppColors.brandPrimary.opacity(0.14))
                }
                .overlay {
                    Capsule()
                        .stroke(AppColors.brandPrimary.opacity(0.20), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始导航")
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .fixedSize()  // 关键：让卡片按内容尺寸布局，不响应父级全宽 proposal
        .tracciMediaChromeGlass(
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            wash: .white.opacity(0.08),
            // 深色文字卡片:Reduce Transparency 实底回退用亮色。
            opaqueFallback: .white.opacity(0.92)
        )
    }
}

// MARK: - Preview

#Preview("Hero Node Card") {
    TripHeroNodeCard(
        title: "故宫博物院",
        timeText: "09:00",
        locationName: nil,
        onNavigate: {}
    )
    .padding()
    .background(Color.gray.opacity(0.3))
    .preferredColorScheme(.light)
}
