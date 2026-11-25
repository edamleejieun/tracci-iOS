import SwiftUI

private enum TracciSwipeRecognitionMetrics {
    /// Start listening early enough that a short thumb swipe feels immediate.
    static let minimumDistance: CGFloat = 6
    /// Accept natural diagonal thumb movement while leaving clear vertical drags to scrolling.
    static let horizontalToVerticalDistanceRatio: CGFloat = 0.72
    /// Once a closed row has passed direction arbitration, a short intentional
    /// drag should be enough to reveal the action on the first attempt.
    static let openDistanceRatio: CGFloat = 0.16
    /// A quick flick should open even when the finger travels only a few points.
    static let openProjectedDistanceRatio: CGFloat = 0.28
    /// An open row stays open until the user has clearly moved it back toward
    /// the resting position; this avoids accidental close on small adjustments.
    static let retainOpenDistanceRatio: CGFloat = 0.55
}

private enum TracciSwipeDragAxis {
    case undecided
    case horizontal
    case vertical
}

private struct TracciSwipeDragState {
    var axis: TracciSwipeDragAxis = .undecided
    var translation: CGFloat = 0
}

// MARK: - Action model

struct TracciSwipeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void

    enum Role {
        case destructive
        case normal
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        systemImage: String,
        role: Role = .normal,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    static func delete(title: String = "删除", action: @escaping () -> Void) -> TracciSwipeAction {
        TracciSwipeAction(
            id: "delete",
            title: title,
            systemImage: "trash.fill",
            role: .destructive,
            action: action
        )
    }
}

// MARK: - Exclusive open coordinator

/// Keeps at most one swipe-open row in a list. Optional — pass `nil` for independent rows.
@MainActor
@Observable
final class TracciSwipeCoordinator {
    var openRowID: String?

    func open(_ id: String) {
        openRowID = id
    }

    func close(_ id: String) {
        if openRowID == id {
            openRowID = nil
        }
    }

    func closeAll() {
        openRowID = nil
    }
}

private struct TracciSwipeCoordinatorKey: EnvironmentKey {
    static let defaultValue: TracciSwipeCoordinator? = nil
}

extension EnvironmentValues {
    var tracciSwipeCoordinator: TracciSwipeCoordinator? {
        get { self[TracciSwipeCoordinatorKey.self] }
        set { self[TracciSwipeCoordinatorKey.self] = newValue }
    }
}

// MARK: - Container

/// Trailing swipe actions for elevation cards inside `ScrollView` / `LazyVStack`.
///
/// Does **not** perform network or confirmation — callers handle that in `action`.
/// Prefer revealing a labeled delete button over full-swipe instant delete.
struct TracciSwipeActions<Content: View>: View {
    @Environment(\.tracciSwipeCoordinator) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isEnabled: Bool = true
    var rowID: String?
    var actionWidth: CGFloat = 76
    var cornerRadius: CGFloat = AppRadius.medium
    var trailingActions: [TracciSwipeAction]
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    /// GestureState resets automatically when the parent ScrollView cancels a
    /// simultaneous drag. A persistent @State translation can strand the card
    /// halfway open and make a second swipe necessary.
    @GestureState private var dragState = TracciSwipeDragState()

    private var totalActionsWidth: CGFloat {
        CGFloat(max(trailingActions.count, 1)) * actionWidth
    }

    private var revealedOffset: CGFloat {
        offset + dragState.translation
    }

    /// Any meaningful open/drag — used to kill card elevation bleed into the action well.
    private var isRevealing: Bool {
        revealedOffset < -2
    }

    var body: some View {
        if !isEnabled || trailingActions.isEmpty {
            content
        } else {
            swipeBody
                .onChange(of: coordinator?.openRowID) { _, openID in
                    guard let rowID else { return }
                    if openID != rowID, offset != 0 {
                        close(animated: true)
                    }
                }
                .accessibilityAction(named: Text(trailingActions.first?.title ?? "删除")) {
                    trailingActions.first?.action()
                }
        }
    }

    private var swipeBody: some View {
        // Do **not** clip the outer ZStack: elevated cards draw soft shadows outside
        // their bounds; an outer clip leaves "ghost" shadow fragments in the delete well.
        // While revealing, suppress elevation on the sliding face and clip it so no
        // residual L1/L2 shadow smears into the trailing action area.
        ZStack(alignment: .trailing) {
            actionsBackground
                .opacity(isRevealing ? 1 : 0)

            content
                // Drop elevation while open so soft shadows cannot smear into the action well.
                .environment(\.tracciElevationSuppressed, isRevealing)
                // Timeline and archive cards intentionally use translucent fills.
                // During reveal they need an opaque moving face, otherwise the
                // destructive action well bleeds through as a pink “shadow”.
                .background {
                    if isRevealing {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppColors.cardBackground)
                    }
                }
                .modifier(TracciSwipeRevealClip(isRevealing: isRevealing, cornerRadius: cornerRadius))
                .offset(x: revealedOffset)
                .simultaneousGesture(tapToCloseGesture)
        }
        // Keep the moving face inside its original card lane while open. This
        // prevents itinerary cards from sliding over the fixed timeline number
        // and creek spine; closed cards remain unclipped so L1/L2 depth survives.
        .modifier(TracciSwipeRevealClip(isRevealing: isRevealing, cornerRadius: cornerRadius))
        // Simultaneous recognition keeps the vertical ScrollView native. Direction
        // locking below moves the row only after horizontal intent is clear.
        .simultaneousGesture(dragGesture)
    }

    private var actionsBackground: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(trailingActions) { action in
                Button {
                    AppHaptics.warning()
                    close(animated: true)
                    action.action()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.systemImage)
                            .font(AppTypography.bodyMedium)
                        Text(action.title)
                            .font(AppTypography.chipSemibold)
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.role == .destructive ? AppColors.danger : AppColors.brandPrimary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
        // Match card radius so the delete well sits flush under the sliding face.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func rubberBandedTranslation(_ translation: CGFloat) -> CGFloat {
        let next = offset + translation
        if next > 0 {
            return translation * 0.2 - offset
        }
        if next < -totalActionsWidth {
            let overflow = next + totalActionsWidth
            return (-totalActionsWidth - offset) + overflow * 0.2
        }
        return translation
    }

    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: TracciSwipeRecognitionMetrics.minimumDistance,
            coordinateSpace: .local
        )
        .updating($dragState) { value, state, _ in
            let dx = value.translation.width
            let dy = value.translation.height

            if state.axis == .undecided {
                let horizontalIntent = abs(dx)
                    > abs(dy) * TracciSwipeRecognitionMetrics.horizontalToVerticalDistanceRatio
                let allowedDirection = offset < -8 || dx < 0

                if horizontalIntent, allowedDirection {
                    state.axis = .horizontal
                } else if abs(dy) > abs(dx) {
                    state.axis = .vertical
                } else {
                    return
                }
            }

            guard state.axis == .horizontal else { return }
            state.translation = rubberBandedTranslation(dx)
        }
        .onEnded { value in
            let dx = value.translation.width
            let dy = value.translation.height
            let horizontalIntent = abs(dx)
                > abs(dy) * TracciSwipeRecognitionMetrics.horizontalToVerticalDistanceRatio
            let allowedDirection = offset < -8 || dx < 0
            guard horizontalIntent, allowedDirection else { return }

            finishDrag(
                translation: dx,
                projectedTranslation: value.predictedEndTranslation.width
            )
        }
    }

    private func finishDrag(translation: CGFloat, projectedTranslation: CGFloat) {
        let projected = offset + projectedTranslation
        let shouldOpen: Bool
        if offset < -8 {
            shouldOpen = projected
                < -totalActionsWidth * TracciSwipeRecognitionMetrics.retainOpenDistanceRatio
        } else {
            let crossedDistance = translation
                < -totalActionsWidth * TracciSwipeRecognitionMetrics.openDistanceRatio
            let flickedLeft = projectedTranslation
                < -totalActionsWidth * TracciSwipeRecognitionMetrics.openProjectedDistanceRatio
            shouldOpen = crossedDistance || flickedLeft
        }
        settle(open: shouldOpen)
    }

    private var tapToCloseGesture: some Gesture {
        TapGesture().onEnded {
            guard offset < -8 else { return }
            close(animated: true)
        }
    }

    private func settle(open: Bool) {
        let animation = AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)
        withAnimation(animation) {
            offset = open ? -totalActionsWidth : 0
        }
        if open {
            if let rowID {
                coordinator?.open(rowID)
            }
            AppHaptics.selection()
        } else if let rowID {
            coordinator?.close(rowID)
        }
    }

    private func close(animated: Bool) {
        let animation = animated
            ? AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)
            : nil
        withAnimation(animation) {
            offset = 0
        }
        if let rowID {
            coordinator?.close(rowID)
        }
    }
}

// MARK: - Reveal clip

/// Clips only while revealing so closed rows keep normal elevation shadows.
private struct TracciSwipeRevealClip: ViewModifier {
    let isRevealing: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isRevealing {
            content
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}

// MARK: - Convenience

extension View {
    /// Trailing swipe-to-reveal delete. `onDelete` should open confirm / call VM — not hard-delete silently.
    func tracciSwipeToDelete(
        isEnabled: Bool = true,
        rowID: String? = nil,
        title: String = "删除",
        cornerRadius: CGFloat = AppRadius.medium,
        onDelete: @escaping () -> Void
    ) -> some View {
        TracciSwipeActions(
            isEnabled: isEnabled,
            rowID: rowID,
            cornerRadius: cornerRadius,
            trailingActions: [.delete(title: title, action: onDelete)]
        ) {
            self
        }
    }
}

#if DEBUG
#Preview("Swipe delete") {
    VStack(spacing: 12) {
        TracciSwipeActions(
            trailingActions: [.delete { print("delete") }]
        ) {
            AppElevationCard(level: .l1, role: .content, radius: AppRadius.medium, padding: 16) {
                Text("左滑删除示例")
                    .font(AppTypography.bodyMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    .padding()
    .tracciAtmosphere(.creek)
}
#endif
