import SwiftUI

struct ItineraryFormatPicker: View {
    @Binding var format: ItineraryExportFormat

    var body: some View {
        TracciChoiceMenuButton(
            title: "导出格式",
            triggerTitle: "格式",
            triggerValue: format.title,
            triggerIcon: format.systemImage,
            items: ItineraryExportFormat.allCases.map {
                TracciChoiceItem(id: $0.rawValue, title: $0.title, systemImage: $0.systemImage)
            },
            selectedID: format.rawValue,
            onSelect: { item in
                if let match = ItineraryExportFormat.allCases.first(where: { $0.rawValue == item.id }) {
                    format = match
                }
            }
        )
    }
}
