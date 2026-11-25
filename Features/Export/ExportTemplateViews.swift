import SwiftUI

// MARK: - Share Card Router

struct ExportShareCardView: View {
    let template: ExportTemplate
    let format: ExportFormat
    let assets: ExportAssetsResponse
    let contentOptions: ExportContentOptions
    let loadedImages: [UIImage]
    let copyText: String

    var body: some View {
        switch template {
        case .travelCover:
            TravelCoverExportView(
                format: format,
                trip: assets.trip,
                stats: assets.stats,
                contentOptions: contentOptions,
                visitedPlaces: assets.visitedPlaces,
                coverImage: resolvedCoverImage,
                copyText: copyText
            )
        case .filmCollage:
            FilmCollageExportView(
                format: format,
                trip: assets.trip,
                stats: assets.stats,
                contentOptions: contentOptions,
                photos: loadedImages,
                copyText: copyText,
                watermark: assets.watermark
            )
        case .minimalSummary:
            MinimalSummaryExportView(
                format: format,
                trip: assets.trip,
                stats: assets.stats,
                contentOptions: contentOptions,
                categories: assets.expenseCategoryStats,
                coverImage: resolvedCoverImage,
                copyText: copyText,
                watermark: assets.watermark
            )
        }
    }

    private var resolvedCoverImage: UIImage? {
        if let first = loadedImages.first {
            return first
        }
        return nil
    }
}

// MARK: - Travel Cover

struct TravelCoverExportView: View {
    let format: ExportFormat
    let trip: ExportTripInfo
    let stats: ExportStats
    let contentOptions: ExportContentOptions
    let visitedPlaces: [String]
    let coverImage: UIImage?
    let copyText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                coverSection(height: proxy.size.height * 0.68)
                bottomContent
            }
        }
        .background(AppColors.backgroundGrouped)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func coverSection(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [AppColors.backgroundGrouped, AppColors.subtleSurface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: height)
            }

            LinearGradient(
                colors: [AppColors.backgroundGrouped, AppColors.backgroundGrouped.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: height * 0.35)
            .offset(y: -height * 0.35)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            if contentOptions.showDate {
                Text(ExportFormatting.dateRangeText(startDate: trip.startDate, endDate: trip.endDate))
                    .font(.system(size: captionSize))
                    .foregroundStyle(AppColors.textMuted)
            }

            if !copyText.isEmpty {
                Text(copyText)
                    .font(.system(size: captionSize))
                    .italic()
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if contentOptions.showDays {
                    statLabel("\(trip.totalDays)天")
                }
                if contentOptions.showItineraryCount {
                    statLabel("\(stats.itineraryCount)段行程")
                }
                if contentOptions.showJournalCount {
                    statLabel("\(stats.journalCount)篇日志")
                }
            }

            if contentOptions.showExpense {
                Text("花费 \(ExportFormatting.currencyText(amount: stats.totalExpenseAmount, currency: stats.currency))")
                    .font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }

            if contentOptions.showVisitedPlaces, !visitedPlaces.isEmpty {
                Text(visitedPlaces.joined(separator: " · "))
                    .font(.system(size: captionSize))
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(2)
            }

            if contentOptions.showWatermark {
                watermarkRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: captionSize))
            .foregroundStyle(AppColors.textMuted)
    }

    private var watermarkRow: some View {
        BrandWatermarkView(style: .watermarkDark, logoHeight: 10, wordmarkSize: 8)
            .padding(.top, 4)
    }

    private var titleSize: CGFloat { format == .square ? 18 : 16 }
    private var bodySize: CGFloat { format == .square ? 12 : 11 }
    private var captionSize: CGFloat { format == .square ? 11 : 10 }
}

// MARK: - Film Collage

struct FilmCollageExportView: View {
    let format: ExportFormat
    let trip: ExportTripInfo
    let stats: ExportStats
    let contentOptions: ExportContentOptions
    let photos: [UIImage]
    let copyText: String
    let watermark: ExportWatermark

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0xF5F2ED)

            VStack(spacing: 0) {
                filmHoles
                    .padding(.top, 8)

                photoCollage
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Spacer(minLength: 0)

                bottomContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                filmHoles
                    .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var filmHoles: some View {
        HStack(spacing: 10) {
            ForEach(0..<holeCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0xE5E0DA))
                    .frame(width: 6, height: 4)
            }
        }
    }

    private var holeCount: Int { format == .square ? 8 : 6 }

    private var photoCollage: some View {
        GeometryReader { proxy in
            ZStack {
                polaroid(image: photos[safe: 0], width: proxy.size.width * 0.55, height: proxy.size.height * 0.88)
                    .rotationEffect(.degrees(-2))
                    .offset(x: -proxy.size.width * 0.12, y: proxy.size.height * 0.04)

                polaroid(image: photos[safe: 1], width: proxy.size.width * 0.45, height: proxy.size.height * 0.52)
                    .rotationEffect(.degrees(3))
                    .offset(x: proxy.size.width * 0.2, y: -proxy.size.height * 0.02)

                polaroid(image: photos[safe: 2], width: proxy.size.width * 0.38, height: proxy.size.height * 0.42)
                    .rotationEffect(.degrees(-1))
                    .offset(x: proxy.size.width * 0.16, y: proxy.size.height * 0.42)
            }
        }
        .frame(height: format == .square ? 150 : 120)
    }

    private func polaroid(image: UIImage?, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white)
                .tracciElevation(.l0)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(hex: 0xE5E0DA)
                }
            }
            .padding(4)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .frame(width: width, height: height)
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.title)
                .font(.system(size: 16, weight: .medium))
                .italic()
                .foregroundStyle(AppColors.textPrimary)

            if contentOptions.showDate {
                Text(ExportFormatting.dateRangeText(startDate: trip.startDate, endDate: trip.endDate))
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textPlaceholder)
            }

            if !copyText.isEmpty {
                Text(copyText)
                    .font(.system(size: 9))
                    .italic()
                    .foregroundStyle(AppColors.textMuted)
            }

            HStack(spacing: 4) {
                if contentOptions.showDays {
                    Text("\(trip.totalDays)天旅程")
                }
                if contentOptions.showJournalCount {
                    Text("· \(stats.journalCount)篇日志")
                }
                if contentOptions.showExpense {
                    Text("· \(ExportFormatting.currencyText(amount: stats.totalExpenseAmount, currency: stats.currency))")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(AppColors.textMuted)

            if contentOptions.showWatermark, watermark.enabled {
                BrandWatermarkView(style: .watermarkDark, logoHeight: 10, wordmarkSize: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Minimal Summary

struct MinimalSummaryExportView: View {
    let format: ExportFormat
    let trip: ExportTripInfo
    let stats: ExportStats
    let contentOptions: ExportContentOptions
    let categories: [ExportExpenseCategoryStat]
    let coverImage: UIImage?
    let copyText: String
    let watermark: ExportWatermark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                if contentOptions.showDate {
                    Text(ExportFormatting.dateRangeText(startDate: trip.startDate, endDate: trip.endDate))
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
            .padding(.horizontal, 20)

            Group {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0xE8E4DE), Color(hex: 0xD4C8B8)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(height: format == .square ? 90 : 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if !copyText.isEmpty {
                Text(copyText)
                    .font(.system(size: 10))
                    .italic()
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            VStack(spacing: 0) {
                if contentOptions.showDays {
                    dataRow(label: "旅行天数", value: "\(trip.totalDays) 天")
                }
                if contentOptions.showItineraryCount {
                    dataRow(label: "行程安排", value: "\(stats.itineraryCount) 段")
                }
                if contentOptions.showJournalCount {
                    dataRow(label: "旅行日志", value: "\(stats.journalCount) 篇")
                }
                if contentOptions.showExpense {
                    dataRow(
                        label: "本次花费",
                        value: ExportFormatting.currencyText(amount: stats.totalExpenseAmount, currency: stats.currency),
                        emphasized: true
                    )
                }
            }
            .padding(.horizontal, 20)

            if contentOptions.showExpenseDistribution, !categories.isEmpty {
                expenseBars
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)

            if contentOptions.showWatermark, watermark.enabled {
                BrandWatermarkView(style: .watermarkDark, logoHeight: 13, wordmarkSize: 9)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .background(Color(hex: 0xFAFAF9))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func dataRow(label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColors.textPlaceholder)
            Spacer()
            Text(value)
                .foregroundStyle(emphasized ? AppColors.textPrimary : AppColors.textSecondary)
                .fontWeight(emphasized ? .medium : .regular)
        }
        .font(.system(size: 11))
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: 0xF0EDE8))
                .frame(height: 0.5)
        }
    }

    private var expenseBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("开支分布")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textPlaceholder)

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(categories) { item in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(categoryColor(item.category))
                            .frame(width: max(4, proxy.size.width * CGFloat(item.percentage / 100)))
                    }
                }
            }
            .frame(height: 8)

            HStack {
                ForEach(categories.prefix(3)) { item in
                    Text(item.categoryName)
                        .font(.system(size: 8))
                        .foregroundStyle(AppColors.textPlaceholder)
                    Spacer(minLength: 4)
                }
            }
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "food": AppColors.catFood
        case "transport": AppColors.catTransport
        case "lodging", "hotel": AppColors.catHotel
        case "attraction": AppColors.catAttraction
        case "shopping": AppColors.catShopping
        default: AppColors.textPlaceholder.opacity(0.5)
        }
    }
}

// MARK: - Itinerary Card

struct ItineraryExportCardView: View {
    let trip: ItineraryExportTripInfo
    let days: [ItineraryExportDay]
    let watermark: ExportWatermark
    let maxDaysShown: Int

    var body: some View {
        GeometryReader { proxy in
            let scale = max(0.24, min(1.0, proxy.size.width / 1080))

            ZStack {
                itineraryPaperBackground(scale: scale)

                if watermark.enabled {
                    BrandLogoView(style: .blue, height: scaled(120, scale))
                        .opacity(BrandTokens.watermarkDarkOpacity)
                        .offset(x: scaled(310, scale), y: scaled(360, scale))
                }

                VStack(spacing: scaled(26, scale)) {
                    header(scale: scale)
                    content(scale: scale)
                    Spacer(minLength: scaled(12, scale))
                    footer(scale: scale)
                }
                .padding(.horizontal, scaled(68, scale))
                .padding(.top, scaled(64, scale))
                .padding(.bottom, scaled(54, scale))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xF7FAF9))
    }

    private func header(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(32, scale)) {
            HStack {
                Text("行程单")
                    .font(.system(size: scaled(22, scale), weight: .semibold))
                    .foregroundStyle(Color(hex: 0x202A2E))

                Spacer(minLength: scaled(18, scale))

                Text("ITINERARY")
                    .font(.system(size: scaled(21, scale), weight: .semibold))
                    .tracking(scaled(2.2, scale))
                    .foregroundStyle(Color(hex: 0x7B8589))
            }

            VStack(alignment: .leading, spacing: scaled(18, scale)) {
                Text(trip.title)
                    .font(.system(size: scaled(58, scale), weight: .heavy))
                    .foregroundStyle(Color(hex: 0x151A1D))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: scaled(10, scale)) {
                    infoPill(
                        icon: "mappin.and.ellipse",
                        text: trip.destination,
                        scale: scale
                    )
                    infoPill(
                        icon: "calendar",
                        text: dateRangeText,
                        scale: scale
                    )
                    infoPill(
                        icon: "clock",
                        text: "\(trip.totalDays)天\(max(0, trip.totalDays - 1))晚",
                        scale: scale
                    )
                }
            }

            routeSeparator(scale: scale)
        }
    }

    private func content(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(30, scale)) {
            ForEach(days.prefix(maxDaysShown)) { day in
                daySection(day, scale: scale)
            }

            if days.count > maxDaysShown {
                Text("还有 \(days.count - maxDaysShown) 天行程...")
                    .font(.system(size: scaled(24, scale), weight: .semibold))
                    .foregroundStyle(Color(hex: 0x8F999D))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, scaled(4, scale))
            }
        }
    }

    private func daySection(_ day: ItineraryExportDay, scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: scaled(26, scale)) {
            VStack(spacing: scaled(4, scale)) {
                Text(shortDate(day.date))
                    .font(.system(size: scaled(38, scale), weight: .heavy))
                    .foregroundStyle(Color(hex: 0x151A1D))
                    .monospacedDigit()

                Text(weekday(day.date))
                    .font(.system(size: scaled(20, scale), weight: .semibold))
                    .foregroundStyle(Color(hex: 0x8D969A))
            }
            .frame(width: scaled(130, scale), alignment: .topLeading)

            VStack(alignment: .leading, spacing: scaled(17, scale)) {
                ForEach(day.nodes) { node in
                    nodeRow(node, scale: scale)
                }

                if day.nodes.isEmpty {
                    Text("这一天还没有行程节点")
                        .font(.system(size: scaled(27, scale), weight: .semibold))
                        .foregroundStyle(Color(hex: 0xA8B0B4))
                }
            }
            .padding(.top, scaled(3, scale))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, scaled(28, scale))
        .overlay(alignment: .bottom) {
            routeSeparator(scale: scale)
        }
    }

    private func nodeRow(_ node: ItineraryExportNode, scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: scaled(18, scale)) {
            VStack(alignment: .leading, spacing: scaled(4, scale)) {
                Text(node.displayTitle)
                    .font(.system(size: scaled(30, scale), weight: .bold))
                    .foregroundStyle(Color(hex: 0x171C1F))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let locationName = node.locationName, !locationName.isEmpty {
                    Text(locationName)
                        .font(.system(size: scaled(18, scale), weight: .medium))
                        .foregroundStyle(Color(hex: 0x9AA3A7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(node.startTime?.isEmpty == false ? node.startTime ?? "" : "未设置时间")
                .font(.system(size: scaled(23, scale), weight: .medium))
                .foregroundStyle(Color(hex: 0x9AA3A7))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .frame(width: scaled(150, scale), alignment: .trailing)
        }
    }

    private func footer(scale: CGFloat) -> some View {
        HStack(alignment: .bottom) {
            Spacer()

            if watermark.enabled {
                BrandWatermarkView(
                    style: .watermarkDark,
                    logoHeight: scaled(18, scale),
                    wordmarkSize: scaled(16, scale)
                )
            }
        }
        .padding(.top, scaled(18, scale))
    }

    private func itineraryPaperBackground(scale: CGFloat) -> some View {
        LinearGradient(
            colors: [Color(hex: 0xEAF7FA), Color(hex: 0xFBFCFB), Color(hex: 0xF7F6F2)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: scaled(96, scale), style: .continuous)
                .stroke(.white.opacity(0.38), lineWidth: scaled(18, scale))
                .frame(width: scaled(560, scale), height: scaled(360, scale))
                .rotationEffect(.degrees(-18))
                .offset(x: scaled(-170, scale), y: scaled(250, scale))
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppColors.brandPrimary.opacity(0.08))
                .frame(width: scaled(380, scale), height: scaled(380, scale))
                .offset(x: scaled(120, scale), y: scaled(-80, scale))
        }
    }

    private func infoPill(icon: String, text: String, scale: CGFloat) -> some View {
        HStack(spacing: scaled(7, scale)) {
            Image(systemName: icon)
                .font(.system(size: scaled(16, scale), weight: .semibold))
            Text(text)
                .font(.system(size: scaled(19, scale), weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(Color(hex: 0x626B70))
        .padding(.horizontal, scaled(18, scale))
        .padding(.vertical, scaled(12, scale))
        .background(.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: scaled(22, scale), style: .continuous))
    }

    private func routeSeparator(scale: CGFloat) -> some View {
        DottedSeparator(
            color: Color(hex: 0xAAB4B8).opacity(0.72),
            dot: scaled(5, scale),
            gap: scaled(9, scale)
        )
        .frame(height: scaled(7, scale))
    }

    private var dateRangeText: String {
        "\(shortDate(trip.startDate))至\(shortDate(trip.endDate))"
    }

    private func scaled(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
        value * scale
    }

    private func shortDate(_ value: String) -> String {
        guard let date = Self.apiDateFormatter.date(from: value) else {
            let parts = value.split(separator: "-")
            guard parts.count == 3 else { return value }
            return "\(parts[1]).\(parts[2])"
        }
        return Self.shortDateFormatter.string(from: date)
    }

    private func weekday(_ value: String) -> String {
        guard let date = Self.apiDateFormatter.date(from: value) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

private struct DottedSeparator: View {
    let color: Color
    let dot: CGFloat
    let gap: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, Int(proxy.size.width / (dot + gap)))
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(color)
                        .frame(width: dot, height: dot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
