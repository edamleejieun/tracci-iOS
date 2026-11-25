import SwiftUI
import SafariServices

/// A SwiftUI wrapper for SFSafariViewController — opens URLs in-app.
struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - In-App URL Opener Modifier

/// Intercepts `.openURL` environment actions for URLs that should open in-app
/// (e.g. terms, privacy) and presents them via SFSafariViewController instead.
struct InAppBrowserModifier: ViewModifier {
    @State private var safariURL: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                // Open terms / privacy / tracci.cn links in-app
                if url.host()?.contains("tracci.cn") == true {
                    safariURL = url
                    return .handled
                }
                // Fall through to system default (Safari)
                return .systemAction
            })
            .sheet(item: $safariURL) { url in
                InAppSafariView(url: url)
                    .ignoresSafeArea()
            }
    }
}

extension View {
    /// Intercepts tracci.cn URLs and opens them in an in-app Safari view.
    func openTracciLinksInApp() -> some View {
        modifier(InAppBrowserModifier())
    }
}

// MARK: - Identifiable URL for .sheet(item:)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
