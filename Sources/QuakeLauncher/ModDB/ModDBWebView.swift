import SwiftUI
import WebKit

struct ModDBWebView: NSViewRepresentable {
    let client: ModDBClient

    func makeNSView(context: Context) -> WKWebView {
        client.attachedWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
