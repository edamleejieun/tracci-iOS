import Foundation

enum AppRadius {
    // MARK: - Component Radii

    /// Small radius: tags, chips, small badges
    static let small: CGFloat = 12

    /// Medium radius: buttons, input fields, small cards
    static let medium: CGFloat = 16

    /// Button radius: primary, secondary, form actions
    static let button: CGFloat = medium

    /// Large radius: standard cards, sheet content
    static let large: CGFloat = 20

    /// Extra large radius: hero cards, featured content
    static let extraLarge: CGFloat = 24

    /// Hero radius: sheet presentation corners, large modals
    static let hero: CGFloat = 28

    /// Sheet radius: native modal presentation corners
    static let sheet: CGFloat = hero

    /// Card radius (alias for large, preferred for card surfaces)
    static let card: CGFloat = large

    // MARK: - V2 Flat Grouped Surfaces

    /// Radius for grouped settings / action-list surfaces.
    static let settingsSurface: CGFloat = 18

    // MARK: - Special

    /// Pill radius: end-page buttons, metric items, hint card icons
    static let pill: CGFloat = 14

    /// Modal radius: launcher, options card, hint card
    static let modal: CGFloat = 18

    /// Floating menu action radius
    static let floatingAction: CGFloat = 18

    /// Launcher radius: StoryReportLauncher outer frame
    static let launcher: CGFloat = 34
}
