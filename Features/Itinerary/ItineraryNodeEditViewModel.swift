import Foundation
import Observation

enum ItineraryNodeEditMutation: Equatable {
    case day
    case type
    case place
    case time
    case title
    case note
    case details
}

@MainActor
@Observable
final class ItineraryNodeEditViewModel {
    private(set) var node: ItineraryNodeItem
    private(set) var form: ItineraryNodeFormState
    private(set) var lastSubmittedForm: ItineraryNodeFormState
    private(set) var activeMutation: ItineraryNodeEditMutation?
    private(set) var mutationError: String?

    let isNoteOnly: Bool
    let itinerary: ItineraryViewModel

    init(node: ItineraryNodeItem, isNoteOnly: Bool, itinerary: ItineraryViewModel) {
        self.node = node
        self.isNoteOnly = isNoteOnly
        self.itinerary = itinerary
        let initial = ItineraryNodeFormState.from(node: node)
        form = initial
        lastSubmittedForm = initial
    }

    var isMutating: Bool {
        activeMutation != nil || itinerary.isSubmitting
    }

    var locationDisplayName: String {
        form.trimmedLocationName
    }

    var timeRangeDisplay: String? {
        ItineraryTimeFormatting.displayRange(start: form.startTime, end: form.endTime)
    }

    func replaceForm(_ value: ItineraryNodeFormState) {
        form = value
    }

    func applyTimeLocally(_ date: Date, for field: ItineraryNodeTimeField) {
        form.applyTime(date, for: field)
    }

    func clearTimeLocally(_ field: ItineraryNodeTimeField) {
        form.clearTime(field)
    }

    @discardableResult
    func updateDay(_ dayIndex: Int) async -> Bool {
        guard dayIndex != form.dayIndex else { return true }
        form.dayIndex = dayIndex
        return await submitStructural(.day)
    }

    @discardableResult
    func updateType(_ type: ItineraryNodeType) async -> Bool {
        guard type != form.type else { return true }
        form.applyType(type)
        return await submitStructural(.type)
    }

    @discardableResult
    func updatePlace(from result: TracciPlaceSearchResult) async -> Bool {
        form.useSelectedLocation(ItineraryLocation(placeSearchResult: result), fallbackName: result.name)
        return await submitStructural(.place)
    }

    @discardableResult
    func updateManualPlace(_ name: String) async -> Bool {
        form.useManualLocation(name)
        return await submitStructural(.place)
    }

    @discardableResult
    func updateSavedPlace(_ savedPlace: SavedPlace) async -> Bool {
        let currentType = form.type
        let currentTitle = form.title
        form.useSavedPlace(savedPlace)
        form.type = currentType
        form.title = currentTitle
        return await submitStructural(.place)
    }

    @discardableResult
    func updateTime(_ date: Date, for field: ItineraryNodeTimeField) async -> Bool {
        form.applyTime(date, for: field)
        return await submitStructural(.time)
    }

    @discardableResult
    func clearTime(_ field: ItineraryNodeTimeField) async -> Bool {
        form.clearTime(field)
        return await submitStructural(.time)
    }

    @discardableResult
    func updateTitle(_ rawTitle: String) async -> Bool {
        form.title = rawTitle
        return await submitStructural(.title)
    }

    @discardableResult
    func updateNote(_ rawNote: String) async -> Bool {
        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 500 else {
            mutationError = "备注不能超过 500 字"
            return false
        }

        if isNoteOnly {
            return await submitNoteOnly(note)
        }

        form.note = rawNote
        return await submitStructural(.note)
    }

    @discardableResult
    func commitDetails() async -> Bool {
        guard form != lastSubmittedForm else { return true }
        return await submitStructural(.details)
    }

    func clearMutationError() {
        mutationError = nil
    }

    private func submitNoteOnly(_ note: String) async -> Bool {
        guard beginMutation(.note) else { return false }
        defer { endMutation(.note) }

        mutationError = nil
        let succeeded = await itinerary.updateNodeNote(node, note: note)
        if succeeded {
            form.note = note
            adoptRefreshedNode()
        } else {
            mutationError = itinerary.errorMessage
        }
        return succeeded
    }

    private func submitStructural(_ mutation: ItineraryNodeEditMutation) async -> Bool {
        guard !isNoteOnly else {
            mutationError = "已结束的旅程只能改备注"
            form = lastSubmittedForm
            return false
        }
        guard beginMutation(mutation) else { return false }
        defer { endMutation(mutation) }

        mutationError = nil
        let succeeded = await itinerary.updateNode(node, form: form)
        if succeeded {
            adoptRefreshedNode()
        } else {
            form = lastSubmittedForm
            mutationError = itinerary.errorMessage
                ?? itinerary.validationMessage(for: .location)
                ?? itinerary.validationMessage(for: .startTime)
                ?? itinerary.validationMessage(for: .endTime)
                ?? itinerary.validationMessage(for: .note)
                ?? itinerary.validationMessage(for: .title)
        }
        return succeeded
    }

    private func adoptRefreshedNode() {
        if let updated = itinerary.nodes.first(where: { $0.id == node.id }) {
            node = updated
            form = ItineraryNodeFormState.from(node: updated)
        }
        lastSubmittedForm = form
    }

    private func beginMutation(_ mutation: ItineraryNodeEditMutation) -> Bool {
        guard activeMutation == nil, !itinerary.isSubmitting else { return false }
        activeMutation = mutation
        return true
    }

    private func endMutation(_ mutation: ItineraryNodeEditMutation) {
        if activeMutation == mutation {
            activeMutation = nil
        }
    }
}
