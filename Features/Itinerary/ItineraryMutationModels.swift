import Foundation

struct CreateItineraryNodeRequest: Encodable {
    let savedPlaceId: String?
    let title: String
    let type: ItineraryNodeType
    let startTime: String?
    let endTime: String?
    let address: String?
    let location: ItineraryLocation?
    let note: String?
    let details: ItineraryNodeDetails?

    init(from form: ItineraryNodeFormState) {
        savedPlaceId = form.savedPlaceId
        // title 可选：空字符串直接发送，后端存储空值，展示层用地点名称兜底。
        // 交通强制空标题（表单不展示该字段）。
        if form.type == .transport {
            title = ""
        } else {
            let trimmedTitle = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmedTitle.isEmpty ? "" : trimmedTitle
        }
        type = form.type
        // 住宿：时间轴用入住时间作 startTime；退房只走 details.checkOutTime
        if form.type == .hotel {
            startTime = form.normalizedHotelCheckInTime ?? form.normalizedStartTime
            endTime = nil
        } else {
            startTime = form.normalizedStartTime
            endTime = form.normalizedEndTime
        }

        if form.savedPlaceId != nil {
            address = nil
            location = nil
        } else if let selectedLocation = form.selectedLocation {
            address = selectedLocation.address ?? selectedLocation.name
            location = selectedLocation
        } else if form.trimmedLocationName.isEmpty {
            address = nil
            location = nil
        } else {
            address = form.trimmedLocationName
            location = ItineraryLocation(name: form.trimmedLocationName)
        }

        let trimmedNote = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = trimmedNote.isEmpty ? nil : trimmedNote
        details = ItineraryNodeDetails.forSubmit(type: form.type, form: form)
    }
}

struct UpdateItineraryNodeRequest: Encodable {
    let title: String?
    let type: ItineraryNodeType?
    let startTime: String?
    let endTime: String?
    let address: String?
    let location: ItineraryLocation?
    let note: String?
    /// 全量表单始终发送：nil 表示清空扩展；有值则整体替换。
    let details: ItineraryNodeDetails?

    enum CodingKeys: String, CodingKey {
        case title, type, startTime, endTime, address, location, note, details
    }

    init(from form: ItineraryNodeFormState) {
        // title 可选；交通强制空标题（表单不展示，展示层用地点名兜底）。
        if form.type == .transport {
            title = ""
        } else {
            let trimmedTitle = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmedTitle.isEmpty ? "" : trimmedTitle
        }
        type = form.type
        if form.type == .hotel {
            startTime = form.normalizedHotelCheckInTime ?? form.normalizedStartTime
            // 显式清空 endTime，避免旧值残留
            endTime = ""
        } else {
            startTime = form.normalizedStartTime
            endTime = form.normalizedEndTime
        }

        if let selectedLocation = form.selectedLocation {
            address = selectedLocation.address ?? selectedLocation.name
            location = selectedLocation
        } else if form.trimmedLocationName.isEmpty {
            address = nil
            location = .emptyForClearing
        } else {
            address = form.trimmedLocationName
            location = ItineraryLocation(name: form.trimmedLocationName)
        }

        // 全量表单：始终发送 note。后端语义：null=不改，""=清空，非空=写入。
        note = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        // 全量表单：始终发送 details。无扩展内容时编码为 {} 以清空。
        details = ItineraryNodeDetails.forSubmit(type: form.type, form: form)
    }

    init(
        title: String?,
        type: ItineraryNodeType?,
        startTime: String?,
        endTime: String?,
        address: String?,
        location: ItineraryLocation?,
        note: String?,
        details: ItineraryNodeDetails? = nil
    ) {
        self.title = title
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.address = address
        self.location = location
        self.note = note
        self.details = details
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(note, forKey: .note)
        // 全量表单路径：details 为 nil 时写 {} 清空；noteOnly 路径不编码 details（不修改）。
        if shouldEncodeDetailsAsEmptyObject {
            try container.encode([String: String](), forKey: .details)
        } else if let details {
            try container.encode(details, forKey: .details)
        }
    }

    /// noteOnly 不传 details；全量表单无扩展内容时传 {}。
    private var shouldEncodeDetailsAsEmptyObject: Bool {
        // 仅当本次是「结构字段有提交意图」且 details 为空时清空。
        // noteOnly：title/type/... 全 nil → 不编码 details。
        let hasStructuralIntent = title != nil || type != nil || startTime != nil
            || endTime != nil || address != nil || location != nil
        return hasStructuralIntent && details == nil
    }

    /// 仅修改备注的请求：已结束旅程的节点，后端只允许 note 变化，其余字段必须为 null。
    /// - Note: 空字符串表示**清空备注**（后端 `note != null` 且 normalize 为空 → 写入 null）；
    ///   不要用 `nil` 表示清空，`nil` 表示「不修改该字段」。
    static func noteOnly(note: String) -> UpdateItineraryNodeRequest {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateItineraryNodeRequest(
            title: nil,
            type: nil,
            startTime: nil,
            endTime: nil,
            address: nil,
            location: nil,
            note: trimmedNote,
            details: nil
        )
    }
}

