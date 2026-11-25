import SwiftUI
import UIKit

/// Owns create / join presentation lifecycles while `MainTabView` keeps root layout.
struct MainScenePresentationModifier: ViewModifier {
    @Environment(AuthSession.self) private var authSession

    @Bindable var coordinator: MainTabCoordinator
    @Bindable var sceneViewModel: MainSceneViewModel
    let dependencies: MainSceneDependencies
    /// 「我的」里的想去地点列表要「加入行程」，所以底栏 Tab 版也要拿到同一个 provider。
    let savedPlaceTripProvider: SavedPlaceTripProvider

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.selectedTab) { _, _ in
                coordinator.handleSelectedTabChange()
            }
            .onChange(of: coordinator.shouldShowTabBar) { _, visible in
                coordinator.handleTabBarVisibilityChange(isVisible: visible)
            }
            .onChange(of: coordinator.showingCreateOptions) { _, showing in
                coordinator.handleCreateOptionsChange(isShowing: showing)
            }
            .onChange(of: coordinator.showingCreateTrip) { _, isShowing in
                coordinator.handleCreateTripPresentationChange(isShowing: isShowing)
                if !isShowing { clearKeyboardOverlayState() }
            }
            .onChange(of: coordinator.showingJoinTrip) { _, isShowing in
                if !isShowing { clearKeyboardOverlayState() }
            }
            // One item-based cover only. Multiple `.fullScreenCover` on the same
            // view can swallow a second presentation.
            .fullScreenCover(item: fullScreenCoverBinding) { route in
                switch route {
                case .createTrip:
                    TripCreateView(
                        tripService: dependencies.tripService,
                        seed: coordinator.createTripSeed
                    ) { trip in
                        sceneViewModel.handleTripCreated(trip)
                    }
                case .joinTrip:
                    JoinTripView(
                        collaborationService: dependencies.collaborationService,
                        initialCode: "",
                        onCancel: { coordinator.showingJoinTrip = false }
                    ) { result in
                        coordinator.showingJoinTrip = false
                        sceneViewModel.handleTripJoined(tripId: result.tripId)
                    }
                }
            }
            .task(id: authSession.currentUser?.id) {
                sceneViewModel.updateCurrentUser(id: authSession.currentUser?.id)
            }
    }

    private var presentedFullScreenCover: MainSceneFullScreenCover? {
        if coordinator.showingCreateTrip { return .createTrip }
        if coordinator.showingJoinTrip { return .joinTrip }
        return nil
    }

    private var fullScreenCoverBinding: Binding<MainSceneFullScreenCover?> {
        Binding(
            get: { presentedFullScreenCover },
            set: { newValue in
                guard newValue == nil else { return }
                coordinator.showingCreateTrip = false
                coordinator.showingJoinTrip = false
            }
        )
    }

    private func clearKeyboardOverlayState() {
        // Sheet dismissal callbacks run inside SwiftUI's presentation update.
        // Resigning synchronously from that callback posts keyboard notifications,
        // which can re-enter SheetBridge layout before its exclusive write ends.
        // Move responder cleanup to the next MainActor turn instead.
        TracciSheetUIUpdateScheduler.afterCurrentUpdate {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

/// Exclusive full-screen destinations for the main scene.
/// Sharing one `fullScreenCover(item:)` avoids SwiftUI dropping a second cover.
private enum MainSceneFullScreenCover: Identifiable {
    case createTrip
    case joinTrip

    var id: String {
        switch self {
        case .createTrip: "createTrip"
        case .joinTrip: "joinTrip"
        }
    }
}
