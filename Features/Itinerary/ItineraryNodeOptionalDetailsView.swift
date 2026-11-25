import SwiftUI
import UIKit

struct ItineraryNodeOptionalDetailsView: View {
    enum Kind {
        case transport
        case hotel

        var title: String { self == .transport ? "交通信息" : "住宿信息" }
    }

    let kind: Kind
    @Binding var form: ItineraryNodeFormState
    let days: [ItineraryDayGroup]
    var isReadOnly: Bool = false
    let onSelectTime: (ItineraryNodeTimeField) -> Void
    let onDone: () -> Void

    @FocusState private var focusedField: FocusedField?

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: kind.title,
                cancelTitle: "返回",
                showsSaveButton: false,
                presentation: .pushed,
                onCancel: finish
            )

            ScrollView {
                Group {
                    if kind == .transport { transportContent } else { hotelContent }
                }
                .disabled(isReadOnly)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppColors.pageBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .tracciDismissKeyboardOnBlankTap()
    }

    private var transportContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionSpacingCompact) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                TracciFormLabel(title: "交通工具", systemImage: "tram.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.tight) {
                        ForEach(TransportMode.allCases, id: \.self) { mode in
                            compactChoice(title: mode.label, icon: mode.icon, isSelected: form.transportMode == mode) {
                                form.transportMode = mode
                                clearTransportFields(for: mode)
                            }
                        }
                    }
                }
            }

            if form.transportMode == .flight {
                field("航班号", icon: "number", placeholder: "选填，如 MU523", text: $form.flightNo, focus: .flightNo)
                field("航司", icon: "building.2", placeholder: "选填", text: $form.airline, focus: .airline)
            } else if form.transportMode == .train || form.transportMode == .hsr {
                field("车次", icon: "number", placeholder: "选填，如 G123", text: $form.trainNo, focus: .trainNo)
            } else if form.transportMode == .bus {
                field("班次", icon: "number", placeholder: "选填", text: $form.busNo, focus: .busNo)
            }

            field("出发地备注", icon: "arrow.up.right", placeholder: "选填，如航站楼或上车点", text: $form.departureName, focus: .departureName)
            field("到达地备注", icon: "arrow.down.right", placeholder: "选填", text: $form.arrivalName, focus: .arrivalName)

            if showsSeatField {
                field("座位", icon: "chair", placeholder: "选填", text: $form.seatInfo, focus: .seatInfo)
            }
        }
    }

    private var hotelContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionSpacingCompact) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                TracciFormLabel(title: "离店日期", systemImage: "calendar.badge.clock", isOptional: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.tight) {
                        if !form.hotelCheckOutDate.isEmpty {
                            compactChoice(title: "不跨天", icon: "xmark", isSelected: false) {
                                form.hotelCheckOutDate = ""
                            }
                        }
                        ForEach(checkOutDateChoices) { item in
                            compactChoice(
                                title: item.title,
                                icon: item.systemImage,
                                isSelected: form.hotelCheckOutDate == item.id
                            ) {
                                form.hotelCheckOutDate = item.id
                            }
                        }
                    }
                }
                if form.hotelCheckOutDate.isEmpty {
                    Text("不跨天时无需选择")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }

            field("确认号", icon: "number", placeholder: "选填", text: $form.confirmationCode, focus: .confirmationCode)

            HStack(spacing: AppSpacing.cozy) {
                timePickerField(label: "入住时间", field: .hotelCheckIn)
                timePickerField(label: "退房时间", field: .hotelCheckOut)
            }
        }
    }

    private func field(
        _ label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        focus: FocusedField
    ) -> some View {
        TracciFocusableFormField(
            label: label,
            systemImage: icon,
            placeholder: placeholder,
            text: text,
            errorMessage: nil,
            isOptional: true,
            focus: focus,
            focusedField: $focusedField,
            submitLabel: .next,
            onSubmit: { focusedField = nil }
        )
    }

    private func timePickerField(label: String, field: ItineraryNodeTimeField) -> some View {
        let value = form.timeValue(for: field)

        return VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)

            HStack(spacing: AppSpacing.tight) {
                Button {
                    dismissKeyboard()
                    AppHaptics.lightImpact()
                    onSelectTime(field)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(value.isEmpty ? "选择时间" : value)
                            .font(value.isEmpty ? AppTypography.formValue : AppTypography.formValueMonospaced)
                            .foregroundStyle(value.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textDisabled)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !value.isEmpty {
                    Button {
                        AppHaptics.lightImpact()
                        form.clearTime(field)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.listTitleMedium)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除\(label)")
                }
            }
            .padding(.horizontal, AppSpacing.cozy)
            .frame(minHeight: 48)
            .background(AppColors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func compactChoice(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(AppTypography.label)
                .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textMuted)
                .padding(.horizontal, AppSpacing.cozy)
                .frame(minHeight: 38)
                .background(isSelected ? AppColors.brandPrimary.opacity(0.1) : AppColors.subtleBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var showsSeatField: Bool {
        switch form.transportMode {
        case .flight, .train, .hsr, .bus: true
        case .driving, .other, .none: false
        }
    }

    private func clearTransportFields(for mode: TransportMode) {
        switch mode {
        case .flight:
            form.trainNo = ""; form.busNo = ""
        case .train, .hsr:
            form.flightNo = ""; form.airline = ""; form.busNo = ""
        case .bus:
            form.flightNo = ""; form.airline = ""; form.trainNo = ""
        case .driving, .other:
            form.flightNo = ""; form.airline = ""; form.trainNo = ""; form.busNo = ""; form.seatInfo = ""
        }
    }

    private var checkOutDateChoices: [TracciChoiceItem] {
        guard let checkIn = days.first(where: { $0.dayIndex == form.dayIndex }),
              let inDate = TripDateFormatting.date(from: checkIn.date) else { return [] }
        let calendar = TracciDateContext.calendar
        var items = days.compactMap { day -> TracciChoiceItem? in
            guard let date = TripDateFormatting.date(from: day.date), date > inDate else { return nil }
            let nights = calendar.dateComponents([.day], from: inDate, to: date).day ?? 0
            return TracciChoiceItem(
                id: day.date,
                title: "\(ItineraryTimeFormatting.displayDate(day.date)) · 住 \(nights) 晚",
                systemImage: "bed.double"
            )
        }
        if let lastDay = days.last,
           let lastDate = TripDateFormatting.date(from: lastDay.date),
           lastDate >= inDate,
           let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDate) {
            let value = TripDateFormatting.apiString(from: nextDay)
            let nights = calendar.dateComponents([.day], from: inDate, to: nextDay).day ?? 0
            if !items.contains(where: { $0.id == value }) {
                items.append(TracciChoiceItem(
                    id: value,
                    title: "\(ItineraryTimeFormatting.displayDate(value)) · 住 \(nights) 晚",
                    systemImage: "bed.double"
                ))
            }
        }
        return items
    }

    private func finish() {
        dismissKeyboard()
        onDone()
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private enum FocusedField: Hashable {
        case flightNo
        case airline
        case trainNo
        case busNo
        case departureName
        case arrivalName
        case seatInfo
        case confirmationCode
    }
}
