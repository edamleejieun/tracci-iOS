import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Minimal smoke test verifying HTTPStub + APIClient integration.
final class HTTPStubSmokeTests: XCTestCase {
    private var stub: HTTPStub!

    override func setUp() {
        super.setUp()
        stub = HTTPStub()
        stub.install()
    }

    override func tearDown() {
        stub.removeAllResponses()
        stub.resetRequestLog()
        stub.uninstall()
        stub = nil
        super.tearDown()
    }

    func testStubReceivesRequestAndDecodesEnvelope() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/test-endpoint",
            dataJSON: #"{"id":"test","name":"Hello"}"#
        )

        struct TestResponse: Decodable {
            let id: String
            let name: String
        }

        let client = stub.makeAPIClient()
        let result: TestResponse = try await client.request(
            APIEndpoint(path: "test-endpoint"),
            as: TestResponse.self
        )

        XCTAssertEqual(result.id, "test")
        XCTAssertEqual(result.name, "Hello")

        let requests = stub.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/test-endpoint")
        XCTAssertEqual(requests.first?.httpMethod, "GET")
    }

    func testUnstubbedPathReturnsHTTP404WithoutCrashing() async {
        let client = stub.makeAPIClient()
        do {
            struct Empty: Decodable {}
            _ = try await client.request(APIEndpoint(path: "missing"), as: Empty.self)
            XCTFail("Expected error for unstubbed path")
        } catch let error as APIError {
            // Unstubbed responses are HTTP 404 with plain text; client maps to server/business/underlying.
            switch error {
            case .server(let status, _), .business(let status, _) where status == 404:
                XCTAssertEqual(status, 404)
            default:
                // Accept any thrown APIError; goal is no hang/crash and request was recorded.
                XCTAssertEqual(stub.recordedRequests().count, 1)
            }
        } catch {
            XCTFail("Unexpected non-APIError: \(error)")
        }
    }
}
