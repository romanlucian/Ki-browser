import SwiftUI
import WebKit

/// Hands SwiftUI a `BrowserSession`'s existing web view.
///
/// There is nothing to do in `updateNSView`: the web view is owned by the
/// session, not built here, and a representable cannot swap the view it already
/// returned. **A caller that shows different sessions in the same place must key
/// this on the session** — `.id(ObjectIdentifier(session))` — or SwiftUI keeps
/// showing the first one it was given.
struct WebView: NSViewRepresentable {
    @ObservedObject var session: BrowserSession

    func makeNSView(context: Context) -> WKWebView {
        session.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
