import Foundation

/// Abstraction over Demo Bundle loading so Home can be unit-tested without a live network.
@MainActor
protocol DemoJourneyLoading {
    func loadDisplayableBundle() async -> DemoJourneyService.LoadResult
}

@MainActor
extension DemoJourneyService: DemoJourneyLoading {}