import Foundation
import TracciNetworking

// MARK: - Journal Entry

struct JournalEntry: Decodable, Identifiable, Equatable {
    let id: String
    let tripId: String
    let authorId: String?
    let authorName: String?
    let content: String?
    let location: JournalLocation?
    let occurredAt: String?
    let photos: [JournalPhoto]
    let isHighlight: Bool
    let mood: JournalMood?
    let visibility: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tripId
        case authorId
        case authorName
        case content
        case location
        case occurredAt
        case photos
        case isHighlight
        case mood
        case visibility
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tripId = try container.decodeIfPresent(String.self, forKey: .tripId) ?? ""
        authorId = try container.decodeIfPresent(String.self, forKey: .authorId)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        location = try container.decodeIfPresent(JournalLocation.self, forKey: .location)
        occurredAt = try container.decodeIfPresent(String.self, forKey: .occurredAt)
        photos = try container.decodeIfPresent([JournalPhoto].self, forKey: .photos) ?? []
        isHighlight = try container.decodeIfPresent(Bool.self, forKey: .isHighlight) ?? false
        if let moodValue = try container.decodeIfPresent(String.self, forKey: .mood) {
            mood = JournalMood(rawValue: moodValue)
        } else {
            mood = nil
        }
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var isPrivate: Bool {
        visibility == "private"
    }

    var displayContent: String {
        content ?? ""
    }

    var hasPhotos: Bool {
        !photos.isEmpty
    }

    var occurredDate: Date? {
        TracciDateContext.dateTime(from: occurredAt)
    }

    var occurredDateShort: String {
        guard let date = occurredDate else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
    }

    var occurredTimeShort: String {
        guard let date = occurredDate else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var locationName: String? {
        location?.name
    }
}

// MARK: - Journal Photo

struct JournalPhoto: Decodable, Identifiable, Equatable {
    let id: String
    let fileId: String?
    let url: String?
    let sortOrder: Int?
    let thumbnailUrl: String?
    let previewUrl: String?
    let exportUrl: String?
    let storyPortraitUrl: String?
    let storyCardUrl: String?
    let squareUrl: String?
    let watermarkedUrl: String?
    let width: Int?
    let height: Int?
    let userFeatured: Bool

    var displayURL: URL? {
        [squareUrl, thumbnailUrl, previewUrl, url]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    /// Prefers uncropped variants so collage layouts can keep portrait photos intact.
    /// 契约语义：preview 宽 1080 / thumbnail 720 / url 原图均为等比不裁剪，square 为智能裁剪（仅作兜底）。
    var collageDisplayURL: URL? {
        [previewUrl, url, thumbnailUrl, squareUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    var isPortrait: Bool {
        guard let aspectRatio else { return false }
        return aspectRatio < 0.92
    }

    var previewDisplayURL: URL? {
        [previewUrl, storyPortraitUrl, url, thumbnailUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    var storyCardDisplayURL: URL? {
        [storyCardUrl, previewUrl, url, thumbnailUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }
}

// MARK: - Journal Location

struct JournalLocation: Codable, Equatable {
    let poiId: String?
    let name: String?
    let provider: String?
    let providerPlaceId: String?
    let country: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let adcode: String?
    let cityCode: String?
    let provinceName: String?
    let cityName: String?
    let districtName: String?

    init(
        poiId: String? = nil,
        name: String?,
        provider: String? = nil,
        providerPlaceId: String? = nil,
        country: String? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        adcode: String? = nil,
        cityCode: String? = nil,
        provinceName: String? = nil,
        cityName: String? = nil,
        districtName: String? = nil
    ) {
        self.poiId = poiId
        self.name = name
        self.provider = provider
        self.providerPlaceId = providerPlaceId
        self.country = country
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.adcode = adcode
        self.cityCode = cityCode
        self.provinceName = provinceName
        self.cityName = cityName
        self.districtName = districtName
    }

    init(placeSearchResult result: TracciPlaceSearchResult) {
        self.init(
            name: result.name,
            provider: "APPLE",
            providerPlaceId: result.providerPlaceId,
            country: result.country,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            provinceName: result.provinceName,
            cityName: result.cityName,
            districtName: result.districtName
        )
    }
}

// MARK: - Request Models

struct CreateJournalRequest: Encodable {
    let content: String?
    let location: JournalLocation?
    let occurredAt: String?
    let fileIds: [String]?
    let isHighlight: Bool?
    let mood: String?
    let visibility: String?

    init(
        content: String?,
        location: JournalLocation? = nil,
        occurredAt: String?,
        fileIds: [String]?,
        isHighlight: Bool? = nil,
        mood: JournalMood? = nil,
        visibility: String? = nil
    ) {
        self.content = content
        self.location = location
        self.occurredAt = occurredAt
        self.fileIds = fileIds
        self.isHighlight = isHighlight
        self.mood = mood?.rawValue
        self.visibility = visibility
    }
}

struct UpdateJournalRequest: Encodable {
    let content: String?
    let location: JournalLocation?
    let occurredAt: String?
    let fileIds: [String]?
    let isHighlight: Bool?
    let mood: String?
    let visibility: String?

    init(
        content: String?,
        location: JournalLocation? = nil,
        occurredAt: String?,
        fileIds: [String]?,
        isHighlight: Bool? = nil,
        mood: JournalMood? = nil,
        visibility: String? = nil
    ) {
        self.content = content
        self.location = location
        self.occurredAt = occurredAt
        self.fileIds = fileIds
        self.isHighlight = isHighlight
        self.mood = mood?.rawValue
        self.visibility = visibility
    }
}

// MARK: - Journal Form State

struct JournalDayGroup: Identifiable, Equatable {
    let dayIndex: Int
    let date: Date
    let entries: [JournalEntry]

    var id: String { "\(dayIndex)-\(JournalFormatting.shortDate(date))" }

    var dateLabel: String {
        JournalFormatting.shortDate(date)
    }

    var weekdayLabel: String {
        JournalFormatting.weekday(date)
    }
}

struct JournalFeaturedPhoto: Identifiable, Equatable {
    let id: String
    let url: URL?
    let caption: String?
    let journalId: String
}

enum JournalGrouping {
    static func dayGroups(from entries: [JournalEntry], tripStartDate: Date?, tripEndDate: Date?) -> [JournalDayGroup] {
        let calendar = TracciDateContext.calendar
        let referenceStart = tripStartDate ?? entries.compactMap(\.occurredDate).min()

        var grouped: [Int: (date: Date, entries: [JournalEntry])] = [:]

        for entry in entries {
            guard let occurred = entry.occurredDate else { continue }
            let occurredDay = calendar.startOfDay(for: occurred)

            let dayIndex: Int
            if let referenceStart {
                let startDay = calendar.startOfDay(for: referenceStart)
                let offset = calendar.dateComponents([.day], from: startDay, to: occurredDay).day ?? 0
                dayIndex = max(offset + 1, 1)
            } else {
                dayIndex = 1
            }

            if var existing = grouped[dayIndex] {
                existing.entries.append(entry)
                grouped[dayIndex] = existing
            } else {
                grouped[dayIndex] = (date: occurredDay, entries: [entry])
            }
        }

        return grouped
            .map { dayIndex, value in
                JournalDayGroup(
                    dayIndex: dayIndex,
                    date: value.date,
                    entries: value.entries.sorted {
                        ($0.occurredDate ?? .distantPast) > ($1.occurredDate ?? .distantPast)
                    }
                )
            }
            .sorted { $0.dayIndex > $1.dayIndex }
    }

    static func featuredPhotos(from entries: [JournalEntry]) -> [JournalFeaturedPhoto] {
        entries
            .flatMap { entry in
                entry.photos.filter(\.userFeatured).map { photo in
                    JournalFeaturedPhoto(
                        id: photo.id,
                        url: photo.displayURL,
                        caption: entry.locationName ?? JournalFormatting.previewCaption(from: entry.displayContent),
                        journalId: entry.id
                    )
                }
            }
    }
}

enum JournalFormatting {
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func editorialDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func editorialWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func previewCaption(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 12 { return trimmed }
        return String(trimmed.prefix(12)) + "…"
    }
}

struct JournalFormState: Equatable {
    var content: String
    var location: JournalLocation?
    var isHighlight: Bool
    var isPrivate: Bool
    var mood: JournalMood?
    var fileIds: [String]
    var existingPhotos: [ExistingPhoto]
    var localImages: [LocalImage]
    /// Override date for journal entry (used when creating from a specific day).
    var defaultOccurredDate: Date?
    /// Capture time from the first selected photo, if any.
    var occurredAtOverride: Date?

    struct ExistingPhoto: Identifiable, Equatable {
        let id: String
        let fileId: String?
        let displayURL: URL?
        var userFeatured: Bool

        init(id: String, fileId: String?, displayURL: URL?, userFeatured: Bool) {
            self.id = id
            self.fileId = fileId
            self.displayURL = displayURL
            self.userFeatured = userFeatured
        }
    }

    struct LocalImage: Identifiable, Equatable {
        let id: String
        let data: Data
        let fileName: String
        let contentType: String
        let width: Int?
        let height: Int?
        let capturedAt: Date?
        var fileId: String?
        var isUploading: Bool
        var uploadError: String?

        init(
            id: String = UUID().uuidString,
            data: Data,
            fileName: String = "journal-photo.jpg",
            contentType: String = "image/jpeg",
            width: Int? = nil,
            height: Int? = nil,
            capturedAt: Date? = nil,
            fileId: String? = nil,
            isUploading: Bool = false,
            uploadError: String? = nil
        ) {
            self.id = id
            self.data = data
            self.fileName = fileName
            self.contentType = contentType
            self.width = width
            self.height = height
            self.capturedAt = capturedAt
            self.fileId = fileId
            self.isUploading = isUploading
            self.uploadError = uploadError
        }
    }

    static func empty(defaultOccurredDate: Date? = nil) -> JournalFormState {
        JournalFormState(
            content: "",
            location: nil,
            isHighlight: false,
            isPrivate: false,
            mood: nil,
            fileIds: [],
            existingPhotos: [],
            localImages: [],
            defaultOccurredDate: defaultOccurredDate,
            occurredAtOverride: nil
        )
    }

    static func from(entry: JournalEntry) -> JournalFormState {
        let existingPhotos = entry.photos.map { photo in
            ExistingPhoto(
                id: photo.id,
                fileId: photo.fileId,
                displayURL: photo.displayURL,
                userFeatured: photo.userFeatured
            )
        }

        return JournalFormState(
            content: entry.content ?? "",
            location: entry.location,
            isHighlight: entry.isHighlight,
            isPrivate: entry.isPrivate,
            mood: entry.mood,
            fileIds: entry.photos.compactMap(\.fileId),
            existingPhotos: existingPhotos,
            localImages: [],
            defaultOccurredDate: nil,
            occurredAtOverride: nil
        )
    }

    var uploadedFileIds: [String] {
        localImages.compactMap(\.fileId)
    }

    var allFileIds: [String] {
        var ids = existingPhotos.compactMap(\.fileId)
        ids.append(contentsOf: uploadedFileIds)
        return ids
    }

    var isUploading: Bool {
        localImages.contains { $0.isUploading }
    }

    var hasUploadError: Bool {
        localImages.contains { $0.uploadError != nil }
    }
}

/// Resolves create-time `occurredAt` from photo capture time, the selected Day, and trip bounds.
enum JournalOccurrenceDate {
    static func resolveCreate(
        capturedAt: Date?,
        dayAnchor: Date?,
        tripStartDate: Date?,
        tripEndDate: Date?,
        now: Date = Date()
    ) -> Date {
        let calendar = TracciDateContext.calendar

        if let capturedAt, isWithinTrip(capturedAt, start: tripStartDate, end: tripEndDate, calendar: calendar) {
            return capturedAt
        }

        let clock = capturedAt ?? now
        if let dayAnchor {
            return TracciCalendarFormatting.mergeTime(clock, preservingDateFrom: dayAnchor)
        }
        return clampToTrip(clock, start: tripStartDate, end: tripEndDate, calendar: calendar)
    }

    static func isWithinTrip(
        _ date: Date,
        start: Date?,
        end: Date?,
        calendar: Calendar = TracciDateContext.calendar
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let start, day < calendar.startOfDay(for: start) { return false }
        if let end, day > calendar.startOfDay(for: end) { return false }
        return true
    }

    private static func clampToTrip(
        _ date: Date,
        start: Date?,
        end: Date?,
        calendar: Calendar
    ) -> Date {
        let today = calendar.startOfDay(for: date)
        if let start, today < calendar.startOfDay(for: start) {
            return TracciCalendarFormatting.mergeTime(date, preservingDateFrom: start)
        }
        if let end, today > calendar.startOfDay(for: end) {
            return TracciCalendarFormatting.mergeTime(date, preservingDateFrom: end)
        }
        return date
    }
}

// FileUploadCredentials / FileConfirmResponse: Packages/TracciNetworking (Stage G)
