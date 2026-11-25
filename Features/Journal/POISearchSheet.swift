import SwiftUI

struct POISearchSheet: View {
    let searchContext: PlaceSearchContext
    let onSelect: (JournalLocation) -> Void
    let onCancel: () -> Void

    var body: some View {
        TracciPlaceSearchSheet(
            scopedPlaceContext: searchContext,
            allowsManualEntry: false,
            onSelect: { result in
                onSelect(JournalLocation(placeSearchResult: result))
            },
            onCancel: onCancel
        )
    }
}