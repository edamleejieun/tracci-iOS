import SwiftUI

/// Backward-compatible wrapper around `TracciFormField`.
struct TripFormField: View {
    let label: String
    var systemImage: String
    var placeholder: String
    @Binding var text: String
    var errorMessage: String?
    var isOptional = false

    var body: some View {
        TracciFormField(
            label: label,
            systemImage: systemImage,
            placeholder: placeholder,
            text: $text,
            errorMessage: errorMessage,
            isOptional: isOptional
        )
    }
}