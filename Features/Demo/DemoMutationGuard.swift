import Foundation

/// Central write gate for Demo Journey. UI may hide controls, but every mutation
/// path must call this before invoking live services.
enum DemoMutationGuard {
    /// Returns `true` when the context allows live mutations.
    static func allowsMutation(_ context: JourneyContext) -> Bool {
        switch context {
        case .live:
            return true
        case .demo:
            return false
        }
    }

    /// Returns `true` when Demo capabilities (if any) forbid the named action.
    static func allows(_ capability: DemoCapabilityKey, in context: JourneyContext) -> Bool {
        guard case let .demo(bundle, _) = context else {
            return true
        }

        let caps = bundle.capabilities
        switch capability {
        case .editTrip: return caps.canEditTrip
        case .addNode: return caps.canAddNode
        case .editJournal: return caps.canEditJournal
        case .manageExpense: return caps.canManageExpense
        case .manageMembers: return caps.canManageMembers
        case .invite: return caps.canInvite
        case .delete: return caps.canDelete
        case .share: return caps.canShare
        case .export: return caps.canExport
        case .applyAiChanges: return caps.canApplyAiChanges
        }
    }

    enum DemoCapabilityKey {
        case editTrip
        case addNode
        case editJournal
        case manageExpense
        case manageMembers
        case invite
        case delete
        case share
        case export
        case applyAiChanges
    }

    /// User-facing reason when a mutation is blocked in Demo.
    static func rejectionMessage(for capability: DemoCapabilityKey? = nil) -> String {
        switch capability {
        case .share:
            return DemoReadOnlyCopy.shareUnavailable
        case .export:
            return DemoReadOnlyCopy.exportUnavailable
        case .invite, .manageMembers:
            return DemoReadOnlyCopy.inviteUnavailable
        case .none, .editTrip, .addNode, .editJournal, .manageExpense, .delete, .applyAiChanges:
            return DemoReadOnlyCopy.toast
        }
    }
}
