import Foundation
import TracciNetworking

#if DEBUG
enum JournalPreviewFixtures {
    static let sampleEntry = JournalEntry(
        id: "preview-1",
        tripId: "trip-1",
        content: "傍晚的洱海风很舒服，骑到一半刚好看到日落。",
        location: JournalLocation(
            poiId: nil,
            name: "洱海东岸",
            address: nil,
            latitude: nil,
            longitude: nil,
            adcode: nil,
            cityCode: nil,
            provinceName: nil,
            cityName: nil,
            districtName: nil
        ),
        occurredAt: "2026-05-03T11:30:00Z",
        photos: [],
        isHighlight: true,
        mood: .peaceful,
        createdAt: nil,
        updatedAt: nil
    )

    static let privateCollaborativeEntry = JournalEntry(
        id: "preview-2",
        tripId: "trip-1",
        authorId: "user-liz",
        authorName: "小李",
        content: "只想自己留着的一句。",
        location: JournalLocation(
            poiId: nil,
            name: "祗园",
            address: nil,
            latitude: nil,
            longitude: nil,
            adcode: nil,
            cityCode: nil,
            provinceName: nil,
            cityName: nil,
            districtName: nil
        ),
        occurredAt: "2026-05-03T18:10:00Z",
        photos: [],
        isHighlight: false,
        mood: .thoughtful,
        visibility: "private",
        createdAt: nil,
        updatedAt: nil
    )

    static func photo(
        id: String,
        width: Int,
        height: Int
    ) -> JournalPhoto {
        JournalPhoto(
            id: id,
            fileId: id,
            url: nil,
            sortOrder: nil,
            thumbnailUrl: nil,
            previewUrl: nil,
            exportUrl: nil,
            storyPortraitUrl: nil,
            storyCardUrl: nil,
            squareUrl: nil,
            watermarkedUrl: nil,
            width: width,
            height: height,
            userFeatured: false
        )
    }

    @MainActor
    static var journalService: JournalService {
        let apiClient = APIClient(
            config: .development,
            tokenProvider: AuthSession(tokenStore: KeychainTokenStore())
        )
        return JournalService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
    }

    @MainActor
    static var emptyViewModel: JournalViewModel {
        JournalViewModel(tripId: "trip-1", tripStartDate: "2026-05-01", journalService: journalService)
    }
}

extension JournalEntry {
    init(
        id: String,
        tripId: String,
        authorId: String? = nil,
        authorName: String? = nil,
        content: String?,
        location: JournalLocation?,
        occurredAt: String?,
        photos: [JournalPhoto],
        isHighlight: Bool,
        mood: JournalMood? = nil,
        visibility: String? = nil,
        createdAt: String?,
        updatedAt: String?
    ) {
        self.id = id
        self.tripId = tripId
        self.authorId = authorId
        self.authorName = authorName
        self.content = content
        self.location = location
        self.occurredAt = occurredAt
        self.photos = photos
        self.isHighlight = isHighlight
        self.mood = mood
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
#endif
