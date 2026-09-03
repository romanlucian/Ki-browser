import SwiftUI
import WebKit
import LimeghostShared

/// Hands SwiftUI a `BrowserSession`'s existing web view.
///
/// There is nothing to do in `updateUIView`: the web view is owned by the
/// session, not built here, and a representable cannot swap the view it already
/// returned. **Key this on `session.instanceID`** where different sessions
/// appear in the same place — never on the object's address, which is reused
/// after a free. This is the iOS twin of the Mac's `WebView`, which is an
/// `NSViewRepresentable` and so could not be shared; it is the whole of the
/// difference between the two platforms' page display.
struct WebViewHost: UIViewRepresentable {
    let session: BrowserSession

    func makeUIView(context: Context) -> WKWebView { session.webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
