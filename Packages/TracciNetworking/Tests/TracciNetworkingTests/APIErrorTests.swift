import XCTest
@testable import TracciNetworking

final class APIErrorTests: XCTestCase {
    func testBusinessErrorSurfacesServerMessage() {
        let error = APIError.business(code: 40401, message: "Not Found")
        XCTAssertEqual(error.errorDescription, "Not Found")
    }

    func testUnauthorizedMessageIsLocalized() {
        XCTAssertEqual(APIError.unauthorized.errorDescription, "登录已过期，请重新登录")
    }
}
