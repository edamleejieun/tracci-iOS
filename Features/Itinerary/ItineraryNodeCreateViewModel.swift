import Foundation
import Observation

@MainActor
@Observable
final class ItineraryNodeCreateViewModel {
    private(set) var form: ItineraryNodeFormState
    private(set) var baseline: ItineraryNodeFormState

    init(defaultDayIndex: Int) {
        let initial = ItineraryNodeFormState.create(defaultDayIndex: defaultDayIndex)
        form = initial
        baseline = initial
    }

    var hasLocation: Bool { form.hasValidLocation }
    var isDirty: Bool { form != baseline }
    var locationDisplayName: String { form.trimmedLocationName }

    func selectSearchResult(_ result: TracciPlaceSearchResult) {
        form.useSelectedLocation(ItineraryLocation(placeSearchResult: result), fallbackName: result.name)
        applySuggestedType(ItineraryNodeSuggestion.nodeType(for: result))
    }

    func useManualLocation(_ name: String) {
        form.useManualLocation(name)
        applySuggestedType(.other)
    }

    func selectSavedPlace(_ savedPlace: SavedPlace) {
        form.useSavedPlace(savedPlace)
        form.normalizeTypeSpecificState()
    }

    func changeType(_ type: ItineraryNodeType) {
        form.applyType(type)
    }

    func replaceForm(_ value: ItineraryNodeFormState) {
        form = value
    }

    func resetLocation() {
        form.savedPlaceId = nil
        form.selectedLocation = nil
        form.locationName = ""
    }

    private func applySuggestedType(_ type: ItineraryNodeType) {
        form.applyType(type)
    }
}
