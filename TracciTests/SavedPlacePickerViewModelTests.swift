import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

@MainActor
final class SavedPlacePickerViewModelTests: XCTestCase {
    func testLoadPopulatesItemsAndHidesSearchBelowThreshold() async {
        let service = SavedPlaceServicingStub()
        service.defaultList = PageResponse(
            list: [SavedPlaceFixtures.sample],
            total: 1,
            page: 1,
            pageSize: 20
        )
        let viewModel = SavedPlacePickerViewModel(
            service: service,
            query: SavedPlaceListQuery(usage: .itineraryNode)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.id, "saved-1")
        XCTAssertFalse(viewModel.showsSearch)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(service.recorder.callCount(for: .list), 1)
        XCTAssertEqual(service.queries.first?.usage, .itineraryNode)
    }

    func testShowsSearchWhenTotalExceedsThreshold() async {
        let service = SavedPlaceServicingStub()
        service.defaultList = PageResponse(
            list: [SavedPlaceFixtures.sample],
            total: 9,
            page: 1,
            pageSize: 20
        )
        let viewModel = SavedPlacePickerViewModel(
            service: service,
            query: SavedPlaceListQuery()
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.showsSearch)
    }

    func testLoadFailureSurfacesResolvedErrorMessage() async {
        let service = SavedPlaceServicingStub()
        service.listHandler = { _ in
            throw APIError.business(code: 40423, message: "raw")
        }
        let viewModel = SavedPlacePickerViewModel(
            service: service,
            query: SavedPlaceListQuery()
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "这条收藏已不可用，请刷新后重试")
    }

    func testLoadMoreAppendsNextPageWithoutDuplicates() async throws {
        let service = SavedPlaceServicingStub()
        service.listHandler = { query in
            if query.page == 1 {
                return PageResponse(list: [SavedPlaceFixtures.sample], total: 2, page: 1, pageSize: 20)
            }
            return PageResponse(list: [SavedPlaceFixtures.sample2], total: 2, page: 2, pageSize: 20)
        }
        let viewModel = SavedPlacePickerViewModel(
            service: service,
            query: SavedPlaceListQuery()
        )

        await viewModel.load()
        let first = try XCTUnwrap(viewModel.items.last)
        await viewModel.loadMoreIfNeeded(after: first)

        XCTAssertEqual(viewModel.items.map(\.id), ["saved-1", "saved-2"])
        XCTAssertEqual(service.queries.map(\.page), [1, 2])
    }

    func testDebouncedSearchUsesLatestKeyword() async throws {
        let service = SavedPlaceServicingStub()
        service.listHandler = { query in
            PageResponse(list: [SavedPlaceFixtures.sample], total: 9, page: query.page, pageSize: 20)
        }
        let viewModel = SavedPlacePickerViewModel(
            service: service,
            query: SavedPlaceListQuery()
        )
        await viewModel.load()
        service.resetRecordedCalls()

        viewModel.keyword = "清"
        viewModel.scheduleSearch()
        viewModel.keyword = "清水寺"
        viewModel.scheduleSearch()

        try await Task.sleep(for: .milliseconds(450))

        XCTAssertEqual(service.queries.count, 1)
        XCTAssertEqual(service.queries.first?.keyword, "清水寺")
        XCTAssertNil(viewModel.errorMessage)
    }
}
