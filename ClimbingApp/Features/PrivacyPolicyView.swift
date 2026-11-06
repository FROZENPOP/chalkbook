import SwiftUI
import WebKit

/// Bundled so the policy opens offline. The same file is what gets hosted for App Store Connect.
struct PrivacyPolicyView: View {
    var body: some View {
        PolicyPage().ignoresSafeArea(edges: .bottom).navigationTitle("Privacy Policy").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PolicyPage: UIViewRepresentable {
    final class Links: NSObject, WKNavigationDelegate {
        // The contact link is mailto, which a web view can't open by itself.
        @MainActor func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, !url.isFileURL else { return .allow }
            await UIApplication.shared.open(url)
            return .cancel
        }
    }
    func makeCoordinator() -> Links { Links() }
    func makeUIView(context: Context) -> WKWebView {
        let page = WKWebView()
        page.navigationDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: "privacy", withExtension: "html") { page.loadFileURL(url, allowingReadAccessTo: url) }
        return page
    }
    func updateUIView(_ page: WKWebView, context: Context) {}
}
