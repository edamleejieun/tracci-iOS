import Foundation
import TracciNetworking

// MARK: - Scene

/// Keys match backend Bundle `scenes.planning|ongoing|completed`.
enum DemoJourneySceneKind: String, Codable, CaseIterable, Equatable, Hashable {
    case planning
    case ongoing
    case completed

    /// Maps `defaultScene` values such as `ONGOING`.
    init?(apiValue: String) {
        switch apiValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PLANNING": self = .planning
        case "ONGOING": self = .ongoing
        case "COMPLETED": self = .completed
        default: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .planning: "规划中"
        case .ongoing: "进行中"
        case .completed: "已结束"
        }
    }

    /// One-line tool hint under the scene switcher (not literary).
    var browseHint: String {
        switch self {
        case .planning:
            return "看规划阶段的行程与概况"
        case .ongoing:
            return "看进行中的记录与花费"
        case .completed:
            return "看结束后的回顾与材料"
        }
    }
}

// MARK: - Capabilities

/// Global Demo capability flags. Event-layer mutation guards must re-check these;
/// `Trip.access` alone is not sufficient.
struct DemoJourneyCapabilities: Decodable, Equatable, Sendable {
    let readOnly: Bool
    let canEditTrip: Bool
    let canAddNode: Bool
    let canEditJournal: Bool
    let canManageExpense: Bool
    let canManageMembers: Bool
    let canInvite: Bool
    let canDelete: Bool
    let canShare: Bool
    let canExport: Bool
    let canApplyAiChanges: Bool

    /// All write / share / export / AI apply flags are off.
    var deniesAllMutations: Bool {
        let writeFlags = [
            canEditTrip,
            canAddNode,
            canEditJournal,
            canManageExpense,
            canManageMembers,
            canInvite,
            canDelete,
            canShare,
            canExport,
            canApplyAiChanges
        ]
        return readOnly && writeFlags.allSatisfy { !$0 }
    }

    static let fullyReadOnly = DemoJourneyCapabilities(
        readOnly: true,
        canEditTrip: false,
        canAddNode: false,
        canEditJournal: false,
        canManageExpense: false,
        canManageMembers: false,
        canInvite: false,
        canDelete: false,
        canShare: false,
        canExport: false,
        canApplyAiChanges: false
    )
}

// MARK: - Stats container

/// Production DTO combination for Demo Bundle `stats`.
struct DemoJourneyStats: Decodable {
    let overview: StatsOverviewResponse
    let spendAnalysis: StatsSpendAnalysis
    let recordsAnalysis: StatsRecordsAnalysis
    let footprintAnalysis: StatsFootprintAnalysis
}

// MARK: - Scene payload

/// One self-consistent journey snapshot. Business blocks reuse production models.
struct DemoJourneyScene: Decodable {
    let trip: Trip
    let itinerary: ItineraryResponse
    let journals: PageResponse<JournalEntry>
    let expenses: PageResponse<Expense>
    let expenseSummary: ExpenseSummary
    let expenseSettlement: ExpenseSettlement
    let members: [TripMemberResp]
    let activityLogs: PageResponse<ActivityLogResp>
    let weather: TripWeatherResponse
    let stageOverview: TripStageOverview
    let summary: TripSummaryResponse
    let stats: DemoJourneyStats
    let exportAssets: ExportAssetsResponse
    let itineraryExportAssets: ItineraryExportAssetsResponse
}

// MARK: - Scenes map

struct DemoJourneyScenes: Decodable {
    let planning: DemoJourneyScene
    let ongoing: DemoJourneyScene
    let completed: DemoJourneyScene

    subscript(_ kind: DemoJourneySceneKind) -> DemoJourneyScene {
        switch kind {
        case .planning: planning
        case .ongoing: ongoing
        case .completed: completed
        }
    }
}

// MARK: - Bundle

/// Top-level `GET /api/v1/demo/journey` data payload.
struct DemoJourneyBundle: Decodable {
    let schemaVersion: Int
    let contentVersion: String
    let referenceDate: String
    let enabled: Bool
    let defaultScene: String
    let capabilities: DemoJourneyCapabilities
    /// Present only when `enabled == true`.
    let scenes: DemoJourneyScenes?

    /// Resolves `defaultScene` to a scene kind. Returns `nil` if the value is not
    /// a recognized scene kind — the bundle should then be treated as undisplayable.
    var validDefaultScene: DemoJourneySceneKind? {
        DemoJourneySceneKind(apiValue: defaultScene)
    }

    /// Client may show the demo only when the server enables it, schema is known,
    /// scenes are present, the default scene is valid, and capabilities are fully
    /// read-only.
    var isDisplayable: Bool {
        guard enabled else { return false }
        guard DemoJourneySchema.isSupported(schemaVersion) else { return false }
        guard let scenes else { return false }
        guard validDefaultScene != nil else { return false }
        return capabilities.deniesAllMutations
    }

    func scene(_ kind: DemoJourneySceneKind) -> DemoJourneyScene? {
        scenes?[kind]
    }

    func defaultScenePayload() -> DemoJourneyScene? {
        guard let kind = validDefaultScene else { return nil }
        return scene(kind)
    }
}
