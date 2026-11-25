import Foundation

/// Trip Detail 的场景组装边界。根 View 只持有此工厂，不再保存或逐层转发具体 Service。
@MainActor
struct TripDetailSceneFactory {
    let routeProvider: any TripRouteProviding

    private let tripService: TripService
    private let itineraryService: ItineraryService
    private let savedPlaceService: SavedPlaceService?
    private let journalService: JournalService
    private let expenseService: ExpenseService
    private let exportService: ExportService
    private let collaborationService: CollaborationService

    init(
        tripService: TripService,
        itineraryService: ItineraryService,
        savedPlaceService: SavedPlaceService?,
        journalService: JournalService,
        expenseService: ExpenseService,
        exportService: ExportService,
        collaborationService: CollaborationService,
        routeProvider: any TripRouteProviding
    ) {
        self.tripService = tripService
        self.itineraryService = itineraryService
        self.savedPlaceService = savedPlaceService
        self.journalService = journalService
        self.expenseService = expenseService
        self.exportService = exportService
        self.collaborationService = collaborationService
        self.routeProvider = routeProvider
    }

    func makeViewModel(
        trip: Trip,
        initialTab: TripDetailTab,
        journeyContext: JourneyContext
    ) -> TripDetailViewModel {
        TripDetailViewModel(
            trip: trip,
            tripService: tripService,
            itineraryService: itineraryService,
            savedPlaceService: savedPlaceService,
            journalService: journalService,
            expenseService: expenseService,
            collaborationService: collaborationService,
            routeProvider: routeProvider,
            initialTab: initialTab,
            journeyContext: journeyContext
        )
    }

    func makeJournalForm(
        mode: JournalFormMode,
        tripId: String,
        searchContext: PlaceSearchContext,
        defaultDate: Date?,
        initialSection: JournalFormInitialSection,
        dayWeather: TripWeatherDisplayItem? = nil,
        onToggleFeaturedPhoto: @escaping (JournalFormState.ExistingPhoto) async -> String?,
        onSave: @escaping (JournalFormState) async -> String?,
        onCancel: @escaping () -> Void
    ) -> JournalFormView {
        var form = JournalFormView(
            mode: mode,
            journalService: journalService,
            tripId: tripId,
            searchContext: searchContext,
            defaultDate: defaultDate,
            initialSection: initialSection,
            onToggleFeaturedPhoto: onToggleFeaturedPhoto,
            onSave: onSave,
            onCancel: onCancel
        )
        form.dayWeather = dayWeather
        return form
    }

    func makeItineraryExport(
        tripId: String,
        tripTitle: String,
        dateRangeText: String,
        onToast: @escaping (String, Bool) -> Void
    ) -> TripItineraryExportSheet {
        TripItineraryExportSheet(
            tripId: tripId,
            tripTitle: tripTitle,
            dateRangeText: dateRangeText,
            exportService: exportService,
            onToast: onToast
        )
    }

    func makeActivityLog(
        tripId: String,
        demoLogs: [ActivityLogResp]?
    ) -> ActivityLogView {
        ActivityLogView(
            tripId: tripId,
            collaborationService: collaborationService,
            demoLogs: demoLogs
        )
    }

    func makeMembers(
        tripId: String,
        tripTitle: String,
        currentUserId: String?,
        currentUserAccess: TripAccessContext?,
        demoMembers: [TripMemberResp]?
    ) -> TripMembersView {
        TripMembersView(
            tripId: tripId,
            tripTitle: tripTitle,
            collaborationService: collaborationService,
            currentUserId: currentUserId,
            currentUserAccess: currentUserAccess,
            demoMembers: demoMembers
        )
    }

    func makeSettlement(
        tripId: String,
        currentUserMemberId: String?,
        demoSettlement: ExpenseSettlement?
    ) -> SettlementView {
        SettlementView(
            tripId: tripId,
            expenseService: expenseService,
            currentUserMemberId: currentUserMemberId,
            demoSettlement: demoSettlement
        )
    }

    func makeInviteViewModel(
        tripId: String,
        tripTitle: String,
        currentUserId: String?,
        currentUserAccess: TripAccessContext?
    ) -> CollaborationViewModel {
        CollaborationViewModel(
            tripId: tripId,
            tripTitle: tripTitle,
            collaborationService: collaborationService,
            currentUserId: currentUserId,
            currentUserAccess: currentUserAccess
        )
    }

    func makeMemoryStoryViewModel(
        tripId: String,
        tripTitle: String
    ) -> MemoryStoryViewModel {
        MemoryStoryViewModel(
            tripId: tripId,
            tripTitle: tripTitle,
            exportService: exportService
        )
    }
}
