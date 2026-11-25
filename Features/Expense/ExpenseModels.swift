import Foundation

// MARK: - Category

/// 开支分类：系统分类（硬编码）+ 自定义分类（运行时从后端加载）
enum ExpenseCategory: Codable, Identifiable, Equatable {
    case food
    case transport
    case hotel
    case attraction
    case shopping
    case other
    case custom(id: String, name: String)

    /// 系统分类完整列表
    static let allSystemCases: [ExpenseCategory] = [
        .food, .transport, .hotel, .attraction, .shopping, .other
    ]

    /// 自定义分类前缀（与后端 ExpenseCategory.CUSTOM_PREFIX 保持一致）
    static let customPrefix = "custom:"

    var id: String {
        switch self {
        case .food: return "food"
        case .transport: return "transport"
        case .hotel: return "hotel"
        case .attraction: return "attraction"
        case .shopping: return "shopping"
        case .other: return "other"
        case .custom(let id, _): return "\(ExpenseCategory.customPrefix)\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .food: return "餐饮"
        case .transport: return "交通"
        case .hotel: return "住宿"
        case .attraction: return "景点"
        case .shopping: return "购物"
        case .other: return "其他"
        case .custom(_, let name): return name
        }
    }

    var emoji: String {
        switch self {
        case .food: return "🍴"
        case .transport: return "🚇"
        case .hotel: return "🏨"
        case .attraction: return "🎡"
        case .shopping: return "🛍"
        case .other: return "📦"
        case .custom: return "🏷"
        }
    }

    var systemImage: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "tram.fill"
        case .hotel: return "bed.double.fill"
        case .attraction: return "ticket.fill"
        case .shopping: return "bag.fill"
        case .other: return "square.grid.2x2.fill"
        case .custom: return "tag.fill"
        }
    }

    var colorHex: UInt {
        switch self {
        case .food: return 0xE8B87D
        case .transport: return 0x7DB8E8
        case .hotel: return 0xB8A4D9
        case .attraction: return 0x8FD9B6
        case .shopping: return 0xE8D97D
        case .other: return 0xB7B1AA
        case .custom: return ExpenseCategory.autoColorHex(for: id)
        }
    }

    var statsColorHex: UInt {
        switch self {
        case .food: return 0xD9B27F
        case .transport: return 0x88B6D8
        case .hotel: return 0xB5A7CE
        case .attraction: return 0x93CDB4
        case .shopping: return 0xD7CA82
        case .other: return 0xB9B2A8
        case .custom: return ExpenseCategory.autoColorHex(for: id)
        }
    }

    /// 是否为系统分类
    var isSystem: Bool {
        switch self {
        case .custom: return false
        default: return true
        }
    }

    /// 自定义分类 ID（仅 custom case 有值）
    var customId: String? {
        switch self {
        case .custom(let id, _): return id
        default: return nil
        }
    }

    /// 根据标识符自动分配一个稳定的颜色
    static func autoColorHex(for identifier: String) -> UInt {
        let palette: [UInt] = [
            0xB8A4D9, 0x7DB8E8, 0x8FD9B6, 0xE8B87D,
            0xE8D97D, 0xB7B1AA, 0xD9A4B8, 0xA4D9D9
        ]
        let index = abs(identifier.hashValue) % palette.count
        return palette[index]
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let system = ExpenseCategory.allSystemCases.first(where: { $0.id == raw }) {
            self = system
        } else if raw.hasPrefix(ExpenseCategory.customPrefix) {
            let id = String(raw.dropFirst(ExpenseCategory.customPrefix.count))
            self = .custom(id: id, name: raw)
        } else {
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

// MARK: - Custom Expense Category

/// 用户自定义分类（从后端加载）
struct CustomExpenseCategory: Decodable, Identifiable, Equatable {
    let id: String
    let tripId: String
    let name: String
    let sortOrder: Int?

    /// 转换为 ExpenseCategory 枚举
    var asExpenseCategory: ExpenseCategory {
        .custom(id: id, name: name)
    }
}

// MARK: - Currency

enum ExpenseCurrency: String, Codable, CaseIterable, Identifiable {
    case cny = "CNY"
    case usd = "USD"
    case jpy = "JPY"
    case hkd = "HKD"
    case eur = "EUR"
    case thb = "THB"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cny: "¥"
        case .usd: "$"
        case .jpy: "¥"
        case .hkd: "HK$"
        case .eur: "€"
        case .thb: "฿"
        }
    }

    var displayName: String {
        switch self {
        case .cny: "人民币"
        case .usd: "美元"
        case .jpy: "日元"
        case .hkd: "港币"
        case .eur: "欧元"
        case .thb: "泰铢"
        }
    }
}

// MARK: - Expense Scope

enum ExpenseScope: String, Codable, CaseIterable, Identifiable {
    case personal
    case group

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personal: "个人开支"
        case .group: "AA 分摊"
        }
    }

    /// Backend may serialize Java enum names (`GROUP`) or contract values (`group`).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard let value = ExpenseScope(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown expenseScope: \(raw)"
            )
        }
        self = value
    }
}

// MARK: - Split Method

enum SplitMethod: String, Codable, CaseIterable, Identifiable {
    case equal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equal: "平均分摊"
        }
    }

    /// Backend may serialize Java enum names (`EQUAL`) or contract values (`equal`).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard let value = SplitMethod(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown splitMethod: \(raw)"
            )
        }
        self = value
    }
}

// MARK: - Expense Item

/// Backend error codes for team expense operations (§16.8):
/// - `42229`: team field validation failure (missing payerMemberId, participantMemberIds,
///   members not in trip, splitMethod not "equal", etc.)
/// Generic `error.localizedDescription` passes through the backend Chinese message.

struct Expense: Decodable, Identifiable, Equatable {
    let id: String
    let tripId: String
    let amountInput: String
    let currency: String
    let amountCny: String
    let exchangeRate: String?
    let category: ExpenseCategory
    let note: String?
    let spentAt: String
    let createdAt: String?
    let expenseScope: ExpenseScope?
    let payerMemberId: String?
    let participantMemberIds: [String]?
    let createdByMemberId: String?
    let splitMethod: SplitMethod?

    var amountInputDecimal: Decimal {
        ExpenseFormatters.decimal(from: amountInput) ?? 0
    }

    var amountCnyDecimal: Decimal {
        ExpenseFormatters.decimal(from: amountCny) ?? 0
    }

    var currencyEnum: ExpenseCurrency {
        ExpenseCurrency(rawValue: currency) ?? .cny
    }

    var displayAmount: String {
        ExpenseFormatters.money(amountInputDecimal, symbol: currencyEnum.symbol)
    }

    var displayCnyAmount: String {
        ExpenseFormatters.cny(amountCnyDecimal)
    }

    var spentAtDate: Date? {
        ExpenseFormatters.dateFromAPI(spentAt)
    }

    var displayTime: String {
        guard let date = spentAtDate else { return spentAt }
        return ExpenseFormatters.displayTime(date)
    }

    var isGroupExpense: Bool {
        expenseScope == .group
    }

    let linkedNodeId: String?
    let linkedStayGroupId: String?
    let linkedItinerary: ExpenseLinkedItinerary?

    func linkedTitle(in nodes: [ItineraryNodeItem]) -> String? {
        if let title = linkedItinerary?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let stayGroupId = linkedStayGroupId {
            return nodes.first { $0.details?.stayGroupId == stayGroupId }?.displayTitle
        }
        if let linkedNodeId {
            return nodes.first { $0.id == linkedNodeId }?.displayTitle
        }
        return nil
    }
}

struct ExpenseLinkedItinerary: Decodable, Equatable {
    let nodeId: String?
    let stayGroupId: String?
    let title: String?
    let type: String?
}

struct ExpenseItineraryLink: Equatable, Hashable, Identifiable {
    var nodeId: String?
    var stayGroupId: String?
    var title: String
    var type: ItineraryNodeType
    var dayIndex: Int
    /// ISO day date (`yyyy-MM-dd`) carried from `ItineraryDayGroup.date`; display-only.
    var dayDate: String?

    var id: String {
        if let stayGroupId { return "stay:\(stayGroupId)" }
        return "node:\(nodeId ?? title)"
    }

    var subtitle: String {
        "第 \(dayIndex) 天 · \(type.label)"
    }

    static func from(node: ItineraryNodeItem) -> ExpenseItineraryLink {
        if let stayGroupId = node.details?.stayGroupId, node.type == .hotel {
            return ExpenseItineraryLink(
                nodeId: nil,
                stayGroupId: stayGroupId,
                title: node.displayTitle,
                type: .hotel,
                dayIndex: node.dayIndex,
                dayDate: nil
            )
        }
        return ExpenseItineraryLink(
            nodeId: node.id,
            stayGroupId: nil,
            title: node.displayTitle,
            type: node.type,
            dayIndex: node.dayIndex,
            dayDate: nil
        )
    }

    static func options(from days: [ItineraryDayGroup]) -> [ExpenseItineraryLink] {
        var seenStayGroups = Set<String>()
        var options: [ExpenseItineraryLink] = []
        for day in days {
            for node in day.nodes where !node.isHotelStayProjection {
                var option = ExpenseItineraryLink.from(node: node)
                if let stayGroupId = option.stayGroupId {
                    guard seenStayGroups.insert(stayGroupId).inserted else { continue }
                }
                option.dayDate = day.date
                options.append(option)
            }
        }
        return options
    }

    // `dayDate` is display metadata only: the same node yields links with and without
    // it (node quick-add vs. option list), and both must stay equal for selection.
    //
    // ⚠️ Hand-rolled identity: when adding a new stored property, deliberately decide
    // whether it belongs in `==`/`hash` — the compiler will not include it for you.
    static func == (lhs: ExpenseItineraryLink, rhs: ExpenseItineraryLink) -> Bool {
        lhs.nodeId == rhs.nodeId
            && lhs.stayGroupId == rhs.stayGroupId
            && lhs.title == rhs.title
            && lhs.type == rhs.type
            && lhs.dayIndex == rhs.dayIndex
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(nodeId)
        hasher.combine(stayGroupId)
        hasher.combine(title)
        hasher.combine(type)
        hasher.combine(dayIndex)
    }

    var suggestedCategory: ExpenseCategory {
        switch type {
        case .restaurant: .food
        case .transport: .transport
        case .hotel: .hotel
        case .attraction: .attraction
        case .shopping: .shopping
        case .other: .other
        }
    }
}

enum ExpenseLastCategoryStore {
    static func key(tripId: String) -> String {
        "tracci.expense.lastCategory.\(tripId)"
    }

    static func load(tripId: String) -> String? {
        guard !tripId.isEmpty else { return nil }
        return UserDefaults.standard.string(forKey: key(tripId: tripId))
    }

    static func save(tripId: String, categoryId: String) {
        guard !tripId.isEmpty else { return }
        UserDefaults.standard.set(categoryId, forKey: key(tripId: tripId))
    }
}

enum ExpenseFormDraft {
    struct Defaults: Equatable {
        var amount: String
        var category: ExpenseCategory?
        var expenseScope: ExpenseScope
        var payerMemberId: String?
        var participantIds: Set<String>
    }

    static func createDefaults(
        members: [TripMemberResp],
        currentUserId: String?,
        suggestedCategory: ExpenseCategory?,
        lastCategory: ExpenseCategory?,
        duplicate: Expense?
    ) -> Defaults {
        if let duplicate {
            return Defaults(
                amount: duplicate.amountInput,
                category: duplicate.category,
                expenseScope: duplicate.expenseScope ?? .personal,
                payerMemberId: duplicate.payerMemberId,
                participantIds: Set(duplicate.participantMemberIds ?? [])
            )
        }

        let isGroup = members.count >= 2
        let me = currentUserId.flatMap { uid in members.first { $0.userId == uid } }
        return Defaults(
            amount: "",
            category: suggestedCategory ?? lastCategory,
            expenseScope: isGroup ? .group : .personal,
            payerMemberId: isGroup ? me?.id : nil,
            participantIds: isGroup ? Set(members.map(\.id)) : []
        )
    }

    static func category(
        fromStoredId id: String?,
        customCategories: [CustomExpenseCategory]
    ) -> ExpenseCategory? {
        guard let id, !id.isEmpty else { return nil }
        if let system = ExpenseCategory.allSystemCases.first(where: { $0.id == id }) {
            return system
        }
        if id.hasPrefix(ExpenseCategory.customPrefix) {
            let customId = String(id.dropFirst(ExpenseCategory.customPrefix.count))
            if let match = customCategories.first(where: { $0.id == customId }) {
                return match.asExpenseCategory
            }
        }
        return nil
    }
}

// MARK: - Expense Summary

struct ExpenseSummary: Decodable, Equatable {
    let totalCny: String
    let perDayCny: String
    let expenseCount: Int
    let breakdown: [CategoryBreakdown]

    var totalCnyDecimal: Decimal {
        ExpenseFormatters.decimal(from: totalCny) ?? 0
    }

    var perDayCnyDecimal: Decimal {
        ExpenseFormatters.decimal(from: perDayCny) ?? 0
    }
}

struct CategoryBreakdown: Decodable, Identifiable, Equatable {
    let category: ExpenseCategory
    let amountCny: String
    let count: Int
    let ratio: Double

    var id: String { category.id }

    var amountCnyDecimal: Decimal {
        ExpenseFormatters.decimal(from: amountCny) ?? 0
    }

    var percentInt: Int {
        Int((ratio * 100).rounded())
    }
}

// MARK: - Request Types

struct CreateExpenseRequest: Encodable {
    let amountInput: String
    let currency: String
    let category: String
    let note: String?
    let spentAt: String
    let expenseScope: String?
    let payerMemberId: String?
    let participantMemberIds: [String]?
    let splitMethod: String?
    var linkedNodeId: String? = nil
    var linkedStayGroupId: String? = nil
}

struct UpdateExpenseRequest: Encodable {
    let amountInput: String?
    let currency: String?
    let category: String?
    let note: String?
    let spentAt: String?
    let expenseScope: String?
    let payerMemberId: String?
    let participantMemberIds: [String]?
    let splitMethod: String?
    var linkedNodeId: String? = nil
    var linkedStayGroupId: String? = nil

    enum CodingKeys: String, CodingKey {
        case amountInput
        case currency
        case category
        case note
        case spentAt
        case expenseScope
        case payerMemberId
        case participantMemberIds
        case splitMethod
        case linkedNodeId
        case linkedStayGroupId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amountInput, forKey: .amountInput)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(category, forKey: .category)
        if let note {
            try container.encode(note, forKey: .note)
        } else {
            try container.encodeNil(forKey: .note)
        }
        try container.encodeIfPresent(spentAt, forKey: .spentAt)
        try container.encodeIfPresent(expenseScope, forKey: .expenseScope)
        try container.encodeIfPresent(payerMemberId, forKey: .payerMemberId)
        try container.encodeIfPresent(participantMemberIds, forKey: .participantMemberIds)
        try container.encodeIfPresent(splitMethod, forKey: .splitMethod)
        if let linkedNodeId {
            try container.encode(linkedNodeId, forKey: .linkedNodeId)
        }
        if let linkedStayGroupId {
            try container.encode(linkedStayGroupId, forKey: .linkedStayGroupId)
        }
    }
}

// Note: ExpenseFormatters moved to Core/Utils/ExpenseFormatters.swift (cross-cutting utility)
