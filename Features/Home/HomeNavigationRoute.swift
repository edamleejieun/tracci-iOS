import Foundation

/// Single source of truth for Home tab `NavigationStack` pushes.
/// Do not mix `navigationDestination(isPresented:)` on this stack — it corrupts the path.
enum HomeNavigationRoute: Hashable {
    case allTrips
    case tripDetail(tripId: String, initialTab: TripDetailTab)
    /// Read-only demo journey. Never encode as `tripDetail(tripId: "demo-...")`.
    case demoJourney(scene: DemoJourneySceneKind)
    case tripEdit(tripId: String, access: TripAccessContext?)
    case tripMembers(tripId: String, tripTitle: String, access: TripAccessContext?)
    case activityLog(tripId: String)
    /// Currently pushed only from an itinerary node card inside trip detail.
    /// Wishlist / Profile place detail uses `ProfileRoute.placeDetail` instead.
    case placeDetail(placeId: String)
}
