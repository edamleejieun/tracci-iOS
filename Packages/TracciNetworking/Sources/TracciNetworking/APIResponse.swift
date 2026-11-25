import Foundation

public struct APIResponse<T: Decodable>: Decodable {
    public let code: Int
    public let message: String
    public let data: T?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case msg
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .msg)
            ?? ""
        data = try container.decodeIfPresent(T.self, forKey: .data)
    }
}

public struct PageResponse<T: Decodable>: Decodable {
    public let list: [T]
    public let total: Int
    public let page: Int
    public let pageSize: Int

    public init(list: [T], total: Int, page: Int, pageSize: Int) {
        self.list = list
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    enum CodingKeys: String, CodingKey {
        case list
        case items
        case records
        case total
        case page
        case current
        case pageSize
        case size
    }

    public init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            var items: [T] = []
            while !arrayContainer.isAtEnd {
                items.append(try arrayContainer.decode(T.self))
            }

            list = items
            total = items.count
            page = 1
            pageSize = items.count
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = try container.decodeIfPresent([T].self, forKey: .list)
            ?? container.decodeIfPresent([T].self, forKey: .items)
            ?? container.decodeIfPresent([T].self, forKey: .records)
            ?? []
        total = try container.decodeFlexibleIntIfPresent(forKey: .total) ?? list.count
        page = try container.decodeFlexibleIntIfPresent(forKey: .page)
            ?? container.decodeFlexibleIntIfPresent(forKey: .current)
            ?? 1
        pageSize = try container.decodeFlexibleIntIfPresent(forKey: .pageSize)
            ?? container.decodeFlexibleIntIfPresent(forKey: .size)
            ?? list.count
    }
}

public struct EmptyResponse: Codable, Sendable {
    public init() {}
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }

        return nil
    }
}
