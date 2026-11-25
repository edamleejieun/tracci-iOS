import SwiftUI

// MARK: - Toast Model

enum TracciToastStyle: Equatable {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .info: "sparkles"
        }
    }

    var iconColor: Color {
        switch self {
        case .success: AppColors.success
        case .error: AppColors.danger
        case .info: AppColors.brandPrimary
        }
    }
}

struct TracciToastMessage: Equatable {
    var text: String
    var style: TracciToastStyle = .info

    static func success(_ text: String) -> Self {
        Self(text: text, style: .success)
    }

    static func error(_ text: String) -> Self {
        Self(text: text, style: .error)
    }

    static func info(_ text: String) -> Self {
        Self(text: text, style: .info)
    }
}

private struct StackedToast: Identifiable, Equatable {
    let id: UUID
    let message: TracciToastMessage
}

// MARK: - Toast Banner

struct TracciToastBanner: View {
    let message: TracciToastMessage
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            toastIcon

            Text(message.text)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.cardSmall)
        .padding(.vertical, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous)
                .fill(AppColors.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(accessibilitySpokenLabel)
    }

    @ViewBuilder
    private var toastIcon: some View {
        if message.style == .success {
            TracciSuccessCheck(size: 22)
        } else {
            Image(systemName: message.style.icon)
                .font(AppTypography.buttonTitle)
                .foregroundStyle(message.style.iconColor)
        }
    }

    private var accessibilitySpokenLabel: String {
        switch message.style {
        case .success: return "成功，\(message.text)"
        case .error: return "错误，\(message.text)"
        case .info: return message.text
        }
    }
}

private struct TracciToastEnterModifier: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .offset(y: AppMotion.toastDistance * progress)
            .scaleEffect(1 - (1 - AppMotion.toastScale) * progress)
            .blur(radius: AppMotion.toastBlur * progress)
    }
}

// MARK: - View Modifier

private struct TracciToastModifier: ViewModifier {
    @Binding var message: TracciToastMessage?
    var bottomPadding: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stack: [StackedToast] = []
    @State private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    ForEach(Array(stack.enumerated()), id: \.element.id) { index, item in
                        TracciToastBanner(message: item.message) {
                            dismiss(id: item.id, clearsBinding: true)
                        }
                        .padding(.horizontal, AppSpacing.pageX)
                        .padding(.bottom, bottomPadding)
                        .scaleEffect(stackScale(for: index), anchor: .bottom)
                        .offset(y: stackOffset(for: index))
                        .opacity(stackOpacity(for: index))
                        .zIndex(Double(stack.count - index))
                        .allowsHitTesting(index == 0)
                        .transition(toastTransition)
                    }
                }
            }
            .onChange(of: message) { _, newValue in
                if let newValue {
                    push(newValue)
                }
            }
            .onAppear {
                if let message, stack.isEmpty {
                    push(message)
                }
            }
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        // 进出同一路径（对称），直接返回 .modifier 即可。
        return .modifier(
            active: TracciToastEnterModifier(progress: 1),
            identity: TracciToastEnterModifier(progress: 0)
        )
    }

    private func stackScale(for index: Int) -> CGFloat {
        1 - CGFloat(index) * AppMotion.toastStackDepthScale
    }

    private func stackOffset(for index: Int) -> CGFloat {
        -CGFloat(index) * AppMotion.toastStackPeek
    }

    private func stackOpacity(for index: Int) -> Double {
        max(0.2, 1 - Double(index) * 0.4)
    }

    private func push(_ message: TracciToastMessage) {
        let item = StackedToast(id: UUID(), message: message)
        withAnimation(AppMotion.animation(AppMotion.toastOpen, reduceMotion: reduceMotion)) {
            stack.insert(item, at: 0)
            while stack.count > AppMotion.toastMaxStack {
                if let dropped = stack.popLast() {
                    dismissTasks[dropped.id]?.cancel()
                    dismissTasks[dropped.id] = nil
                }
            }
        }
        AppHaptics.lightImpact()
        scheduleDismiss(item.id)
    }

    private func scheduleDismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss(id: id, clearsBinding: true)
            }
        }
    }

    private func dismiss(id: UUID, clearsBinding: Bool) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        let wasTop = stack.first?.id == id
        withAnimation(AppMotion.animation(AppMotion.toastClose, reduceMotion: reduceMotion)) {
            stack.removeAll { $0.id == id }
        }
        if clearsBinding, wasTop {
            message = nil
        }
    }
}

extension View {
    /// Presents a branded bottom toast that auto-dismisses after 3 seconds.
    /// Consecutive messages stack (newest in front) instead of replacing.
    func tracciToast(
        _ message: Binding<TracciToastMessage?>,
        bottomPadding: CGFloat = 28
    ) -> some View {
        modifier(TracciToastModifier(message: message, bottomPadding: bottomPadding))
    }

    /// Convenience overload for optional plain-text toasts.
    func tracciToast(
        _ text: Binding<String?>,
        style: TracciToastStyle = .info,
        bottomPadding: CGFloat = 28
    ) -> some View {
        modifier(
            TracciToastModifier(
                message: Binding(
                    get: {
                        guard let text = text.wrappedValue else { return nil }
                        return TracciToastMessage(text: text, style: style)
                    },
                    set: { newValue in
                        text.wrappedValue = newValue?.text
                    }
                ),
                bottomPadding: bottomPadding
            )
        )
    }
}

#if DEBUG
#Preview("Tracci Toast Styles") {
    VStack(spacing: AppSpacing.cardSmall) {
        TracciToastBanner(message: .success("旅程已创建"))
        TracciToastBanner(message: .error("删除失败，请稍后重试"))
        TracciToastBanner(message: .info("你已成功加入旅程"))
    }
    .padding()
    .background(AppColors.backgroundGrouped)
}
#endif
