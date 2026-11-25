import Foundation

struct ItineraryResponse: Decodable, Equatable {
    let tripId: String
    let days: [ItineraryDay]
}
struct ItineraryDay: Decodable, Identifiable, Equatable {
    let id: String
    let dayIndex: Int
    let date: String
    let nodes: [ItineraryNodeDTO]
}

struct ItineraryNodeDTO: Decodable, Equatable {
    let id: String
    let title: String
    let type: ItineraryNodeType?
    let startTime: String?
    let endTime: String?
    let address: String?
    let location: ItineraryLocation?
    let note: String?
    let details: ItineraryNodeDetails?
    let sortOrder: Int?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case startTime
        case endTime
        case address
        case location
        case note
        case details
        case sortOrder
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名行程"
        type = try container.decodeIfPresent(ItineraryNodeType.self, forKey: .type)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        location = try container.decodeIfPresent(ItineraryLocation.self, forKey: .location)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        details = try container.decodeIfPresent(ItineraryNodeDetails.self, forKey: .details)
        sortOrder = try container.decodeItineraryFlexibleIntIfPresent(forKey: .sortOrder)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct ItineraryNodeItem: Identifiable, Equatable, Hashable {
    let id: String
    let tripId: String
    let dayId: String
    let dayIndex: Int
    let title: String
    let type: ItineraryNodeType
    let startTime: String?
    let endTime: String?
    let address: String?
    let location: ItineraryLocation?
    let note: String?
    let details: ItineraryNodeDetails?
    let sortOrder: Int?
    let createdAt: String?
    let updatedAt: String?

    var locationName: String? {
        if let name = location?.name, !name.isEmpty {
            return name
        }
        if let address, !address.isEmpty {
            return address
        }
        return nil
    }

    /// 卡片地址：优先 `location.address`（Saved Place / Place 快照），再回落节点顶层 `address`。
    /// 与导出契约一致；从收藏创建时后端只写 location 快照，顶层 address 常为空。
    var displayAddress: String? {
        let locationAddress = location?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let locationAddress, !locationAddress.isEmpty {
            return locationAddress
        }
        let nodeAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nodeAddress, !nodeAddress.isEmpty {
            return nodeAddress
        }
        return nil
    }

    /// 展示用标题：优先展示地点名称（location.name → address），title 为空时兜底。
    /// 后端存储层允许 title 为空字符串；展示层统一由此属性兜底。
    var displayTitle: String {
        if let name = location?.name, !name.isEmpty {
            return name
        }
        if let address, !address.isEmpty {
            return address
        }
        if !title.isEmpty {
            return title
        }
        return "未命名行程"
    }

    /// 卡片摘要：航班号/车次/确认号等，优先于 note。
    var detailsSummary: String? {
        details?.summaryLine(for: type)
    }

    /// 中间夜投影：不可单独删除。
    var isHotelStayProjection: Bool {
        type == .hotel && (details?.isStayProjection == true)
    }

    /// 连住入住主节点：删除会移除整段住宿。
    var isHotelStayPrimary: Bool {
        type == .hotel && details?.stayGroupId != nil && details?.isStayProjection != true
    }

    /// 类型标签图标：交通节点优先按 mode 展示。
    var typeIcon: String {
        if type == .transport, let mode = details?.transportMode {
            return mode.icon
        }
        return type.icon
    }

    /// 类型标签文案：交通节点优先展示工具名。
    var typeLabel: String {
        if type == .transport, let mode = details?.transportMode {
            return mode.label
        }
        return type.label
    }

    init(
        dto: ItineraryNodeDTO,
        tripId: String,
        dayId: String,
        dayIndex: Int
    ) {
        id = dto.id
        self.tripId = tripId
        self.dayId = dayId
        self.dayIndex = dayIndex
        title = dto.title
        type = dto.type ?? .other
        startTime = dto.startTime
        endTime = dto.endTime
        address = dto.address
        location = dto.location
        note = dto.note
        details = dto.details
        sortOrder = dto.sortOrder
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}

struct ReorderItineraryNodesRequest: Encodable {
    let nodeIds: [String]
}

struct ItineraryDayGroup: Identifiable, Equatable {
    let id: String
    let dayId: String
    let dayIndex: Int
    let date: String
    let nodes: [ItineraryNodeItem]

    var nodeCount: Int {
        nodes.count
    }
}

enum ItineraryNodeDisplayStatus: Equatable {
    case completed
    case current
    case upcoming
    case today

    var label: String {
        switch self {
        case .completed: "已完成"
        case .current: "进行中"
        case .upcoming: "待开始"
        case .today: "今天"
        }
    }
}

struct ItineraryLocation: Codable, Equatable, Hashable {
    let placeId: String?
    let poiId: String?
    let provider: String?
    let providerPlaceId: String?
    let country: String?
    let name: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let adcode: String?
    let cityCode: String?
    let provinceName: String?
    let cityName: String?
    let districtName: String?

    init(name: String) {
        placeId = nil
        poiId = nil
        provider = "MANUAL"
        providerPlaceId = nil
        country = nil
        self.name = name
        address = nil
        latitude = nil
        longitude = nil
        adcode = nil
        cityCode = nil
        provinceName = nil
        cityName = nil
        districtName = nil
    }

    init(
        poiId: String? = nil,
        provider: String?,
        providerPlaceId: String? = nil,
        country: String? = nil,
        name: String?,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        adcode: String? = nil,
        cityCode: String? = nil,
        provinceName: String? = nil,
        cityName: String? = nil,
        districtName: String? = nil,
        placeId: String? = nil
    ) {
        self.poiId = poiId
        self.provider = provider
        self.providerPlaceId = providerPlaceId
        self.country = country
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.adcode = adcode
        self.cityCode = cityCode
        self.provinceName = provinceName
        self.cityName = cityName
        self.districtName = districtName
        self.placeId = placeId
    }

    init(placeSearchResult result: TracciPlaceSearchResult) {
        self.init(
            provider: "APPLE",
            country: result.country,
            name: result.name,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            provinceName: result.provinceName,
            cityName: result.cityName,
            districtName: result.districtName
        )
    }

    static var emptyForClearing: ItineraryLocation {
        ItineraryLocation(provider: nil, name: nil)
    }

    enum CodingKeys: String, CodingKey {
        case poiId
        case provider
        case providerPlaceId
        case country
        case name
        case address
        case latitude
        case longitude
        case adcode
        case cityCode
        case provinceName
        case cityName
        case districtName
        case placeId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        poiId = try container.decodeIfPresent(String.self, forKey: .poiId)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerPlaceId = try container.decodeIfPresent(String.self, forKey: .providerPlaceId)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        latitude = try container.decodeItineraryFlexibleDoubleIfPresent(forKey: .latitude)
        longitude = try container.decodeItineraryFlexibleDoubleIfPresent(forKey: .longitude)
        adcode = try container.decodeIfPresent(String.self, forKey: .adcode)
        cityCode = try container.decodeIfPresent(String.self, forKey: .cityCode)
        provinceName = try container.decodeIfPresent(String.self, forKey: .provinceName)
        cityName = try container.decodeIfPresent(String.self, forKey: .cityName)
        districtName = try container.decodeIfPresent(String.self, forKey: .districtName)
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(poiId, forKey: .poiId)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(providerPlaceId, forKey: .providerPlaceId)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(adcode, forKey: .adcode)
        try container.encodeIfPresent(cityCode, forKey: .cityCode)
        try container.encodeIfPresent(provinceName, forKey: .provinceName)
        try container.encodeIfPresent(cityName, forKey: .cityName)
        try container.encodeIfPresent(districtName, forKey: .districtName)
        // placeId is response-only; never bind ordinary create/update requests to it.
    }
}

enum ItineraryNodeType: String, Codable, CaseIterable, Equatable, Hashable {
    case attraction
    case restaurant
    case transport
    case hotel
    case shopping
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        // Map legacy non-contract values to contract equivalents
        switch rawValue {
        case "cafe":
            self = .restaurant
        case "photo":
            self = .other
        default:
            self = ItineraryNodeType(rawValue: rawValue) ?? .other
        }
    }

    var label: String {
        switch self {
        case .attraction: "景点"
        case .restaurant: "餐饮"
        case .transport: "交通"
        case .hotel: "住宿"
        case .shopping: "购物"
        case .other: "其他"
        }
    }

    var icon: String {
        switch self {
        case .attraction: "star.fill"
        case .restaurant: "fork.knife"
        case .transport: "airplane"
        case .hotel: "bed.double.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis"
        }
    }
}

/// 交通工具（Phase 1 契约）。
enum TransportMode: String, Codable, CaseIterable, Equatable, Hashable {
    case flight
    case train
    case hsr
    case bus
    case driving
    case other

    var label: String {
        switch self {
        case .flight: "飞机"
        case .train: "火车"
        case .hsr: "高铁"
        case .bus: "大巴"
        case .driving: "自驾"
        case .other: "其他"
        }
    }

    var icon: String {
        switch self {
        case .flight: "airplane"
        case .train: "tram.fill"
        case .hsr: "train.side.front.car"
        case .bus: "bus.fill"
        case .driving: "car.fill"
        case .other: "arrow.triangle.swap"
        }
    }
}

/// 节点类型扩展字段（与后端 `details` 对齐；空时不传/不展示）。
struct ItineraryNodeDetails: Codable, Equatable, Hashable {
    var kind: String?
    var mode: String?
    var flightNo: String?
    var airline: String?
    var trainNo: String?
    var busNo: String?
    var departureName: String?
    var arrivalName: String?
    var seatInfo: String?
    var confirmationCode: String?
    var checkInTime: String?
    var checkOutTime: String?
    // Phase 2 hotel stay（服务端托管字段只读展示；提交时客户端只写 checkOutDate 等用户字段）
    var stayGroupId: String?
    var stayRole: String?
    var checkInDate: String?
    var checkOutDate: String?
    var nightIndex: Int?
    var totalNights: Int?

    var transportMode: TransportMode? {
        guard let mode else { return nil }
        return TransportMode(rawValue: mode.lowercased())
    }

    var isStayProjection: Bool {
        stayRole == "stay"
    }

    var isStayCheckIn: Bool {
        stayRole == "check_in" || (stayGroupId != nil && stayRole == nil)
    }

    static func transport(
        mode: TransportMode,
        flightNo: String? = nil,
        airline: String? = nil,
        trainNo: String? = nil,
        busNo: String? = nil,
        departureName: String? = nil,
        arrivalName: String? = nil,
        seatInfo: String? = nil
    ) -> ItineraryNodeDetails {
        ItineraryNodeDetails(
            kind: "transport",
            mode: mode.rawValue,
            flightNo: flightNo,
            airline: airline,
            trainNo: trainNo,
            busNo: busNo,
            departureName: departureName,
            arrivalName: arrivalName,
            seatInfo: seatInfo,
            confirmationCode: nil,
            checkInTime: nil,
            checkOutTime: nil,
            stayGroupId: nil,
            stayRole: nil,
            checkInDate: nil,
            checkOutDate: nil,
            nightIndex: nil,
            totalNights: nil
        )
    }

    static func hotel(
        confirmationCode: String? = nil,
        checkInTime: String? = nil,
        checkOutTime: String? = nil,
        checkOutDate: String? = nil
    ) -> ItineraryNodeDetails {
        ItineraryNodeDetails(
            kind: "hotel",
            mode: nil,
            flightNo: nil,
            airline: nil,
            trainNo: nil,
            busNo: nil,
            departureName: nil,
            arrivalName: nil,
            seatInfo: nil,
            confirmationCode: confirmationCode,
            checkInTime: checkInTime,
            checkOutTime: checkOutTime,
            stayGroupId: nil,
            stayRole: nil,
            checkInDate: nil,
            checkOutDate: checkOutDate,
            nightIndex: nil,
            totalNights: nil
        )
    }

    /// 是否有任何可展示/可提交的扩展内容。
    var isEmpty: Bool {
        let scalars = [
            mode, flightNo, airline, trainNo, busNo,
            departureName, arrivalName, seatInfo,
            confirmationCode, checkInTime, checkOutTime, checkOutDate
        ]
        return scalars.allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func summaryLine(for type: ItineraryNodeType) -> String? {
        switch type {
        case .transport:
            var parts: [String] = []
            if let mode = transportMode {
                // 卡片 type 标签已展示工具名时，摘要优先工具号
                if mode == .flight, let flightNo = nonEmpty(flightNo) {
                    parts.append(flightNo)
                    if let airline = nonEmpty(airline) { parts.append(airline) }
                } else if mode == .train || mode == .hsr, let trainNo = nonEmpty(trainNo) {
                    parts.append(trainNo)
                } else if mode == .bus, let busNo = nonEmpty(busNo) {
                    parts.append(busNo)
                }
            }
            if let dep = nonEmpty(departureName), let arr = nonEmpty(arrivalName) {
                parts.append("\(dep) → \(arr)")
            } else if let dep = nonEmpty(departureName) {
                parts.append("出发：\(dep)")
            } else if let arr = nonEmpty(arrivalName) {
                parts.append("到达：\(arr)")
            }
            if let seat = nonEmpty(seatInfo) {
                parts.append(seat)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .hotel:
            var parts: [String] = []
            if let total = totalNights, total > 0 {
                if let night = nightIndex, total > 1 {
                    parts.append("第 \(night)/\(total) 晚")
                } else if total > 1 {
                    parts.append("住 \(total) 晚")
                } else {
                    parts.append("住 1 晚")
                }
            }
            if let outDate = nonEmpty(checkOutDate) {
                parts.append("离店 \(Self.shortDate(outDate))")
            }
            if let code = nonEmpty(confirmationCode) {
                parts.append("确认号 \(code)")
            }
            if let out = nonEmpty(checkOutTime) {
                parts.append("退房 \(out)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        default:
            return nil
        }
    }

    private static func shortDate(_ yyyyMMdd: String) -> String {
        let parts = yyyyMMdd.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else {
            return yyyyMMdd
        }
        return "\(m)月\(d)日"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 按节点 type 生成可提交的 details；无内容返回 nil（create 可不传）。
    static func forSubmit(type: ItineraryNodeType, form: ItineraryNodeFormState) -> ItineraryNodeDetails? {
        switch type {
        case .transport:
            guard let mode = form.transportMode else { return nil }
            // 自驾/其他不提交座位
            let seatAllowed: Bool = {
                switch mode {
                case .flight, .train, .hsr, .bus: return true
                case .driving, .other: return false
                }
            }()
            let details = ItineraryNodeDetails.transport(
                mode: mode,
                flightNo: mode == .flight ? form.trimmedOptional(form.flightNo) : nil,
                airline: mode == .flight ? form.trimmedOptional(form.airline) : nil,
                trainNo: (mode == .train || mode == .hsr) ? form.trimmedOptional(form.trainNo) : nil,
                busNo: mode == .bus ? form.trimmedOptional(form.busNo) : nil,
                departureName: form.trimmedOptional(form.departureName),
                arrivalName: form.trimmedOptional(form.arrivalName),
                seatInfo: seatAllowed ? form.trimmedOptional(form.seatInfo) : nil
            )
            // mode 必填：有 mode 即提交（即使其它字段为空）
            return details
        case .hotel:
            let details = ItineraryNodeDetails.hotel(
                confirmationCode: form.trimmedOptional(form.confirmationCode),
                checkInTime: form.normalizedHotelCheckInTime,
                checkOutTime: form.normalizedHotelCheckOutTime,
                checkOutDate: form.trimmedOptional(form.hotelCheckOutDate)
            )
            // 有离店日也视为有 details（驱动跨天物化）
            return details.isEmpty ? nil : details
        default:
            return nil
        }
    }
}
