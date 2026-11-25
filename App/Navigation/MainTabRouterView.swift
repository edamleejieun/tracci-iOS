import SwiftUI

/// Owns the platform `TabView` shell. Feature assembly stays in `MainTabView`.
struct MainTabRouterView<Content: View>: View {
    @Binding var selectedTab: AppTab
    /// 底栏实际占位的四格，由 `MainTabCoordinator.visibleTabs` 决定。
    let tabs: [AppTab]
    let content: (AppTab) -> Content

    var body: some View {
        Group {
            if #available(iOS 18, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .tint(AppColors.brandPrimary)
        .tracciTabBarVisibility(.hidden)
    }

    @available(iOS 18, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    content(tab)
                        .tracciTabBarVisibility(.hidden)
                }
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                content(tab)
                    .tracciTabBarVisibility(.hidden)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
    }
}
