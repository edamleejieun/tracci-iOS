import Foundation

enum AppSpacing {
    // MARK: - Page

    static let pageX: CGFloat = 20
    static let pageTop: CGFloat = 24
    static let pageBottom: CGFloat = 124
    /// Title row to subtitle in tab page headers.
    static let pageHeaderSubtitleSpacing: CGFloat = 8
    /// Tab page header to first content block.
    static let pageHeaderToContent: CGFloat = lg

    // MARK: - Card

    static let card: CGFloat = 20
    static let cardSmall: CGFloat = 16

    // MARK: - Picker Sheet

    /// Drag bar to sheet top edge.
    static let pickerChromeTop: CGFloat = 16
    /// Drag bar to title row.
    static let pickerDragToTitle: CGFloat = 22
    /// Title row to subtitle.
    static let pickerTitleToSubtitle: CGFloat = pageHeaderSubtitleSpacing
    /// Picker header block (title + subtitle) to first content block.
    static let pickerHeaderToContent: CGFloat = 24
    /// Picker content blocks (preview → calendar / wheel).
    static let pickerSectionGap: CGFloat = sectionSpacingCompact
    /// Picker footer bottom inset.
    static let pickerFooterBottom: CGFloat = lg

    // MARK: - Form / Input

    static let formFieldSpacing: CGFloat = 16
    static let formSectionSpacing: CGFloat = 24
    /// Standard single-line form control minimum height (grows with Dynamic Type).
    static let formFieldHeight: CGFloat = 48

    // MARK: - Settings / V2 Flat Grouped Rows

    /// Minimum touch target for settings rows (grows with Dynamic Type via minHeight).
    static let settingsRowMinHeight: CGFloat = 44
    /// Horizontal padding inside a settings row.
    static let settingsRowHorizontalPadding: CGFloat = 16
    /// Leading inset for the divider between settings rows (16 pad + 28 glyph + 10 spacing).
    static let settingsDividerLeadingInset: CGFloat = 54
    /// Vertical padding between settings row content and its divider.
    static let settingsRowVerticalPadding: CGFloat = 12

    // MARK: - Editor Sheet

    /// Content padding inside an editor sheet body.
    static let editorContentPadding: CGFloat = 16

    // MARK: - Fixed Bottom CTA

    /// Fixed bottom CTA container top padding (gap above the button).
    static let fixedCTATopPadding: CGFloat = 12
    /// Fixed bottom CTA container bottom padding baseline before safe-area addition.
    static let fixedCTABottomPadding: CGFloat = 8

    // MARK: - Section

    static let sectionSpacing: CGFloat = 28
    static let sectionSpacingCompact: CGFloat = 20
    static let sectionHeaderBottom: CGFloat = 10

    // MARK: - Scale

    /// 4pt — badge/chip inset, hairline gaps inside dense rows.
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    /// 8pt — tight VStack/HStack rhythm (most common list gap).
    static let tight: CGFloat = 8
    static let sm: CGFloat = 10
    /// 12pt — row internal padding, medium stacks.
    static let cozy: CGFloat = 12
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}
