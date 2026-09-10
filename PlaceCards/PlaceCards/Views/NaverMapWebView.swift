import SwiftUI
import WebKit
import UIKit

/// Renders saved place cards on a Naver Map, for the "지도" tab's Naver
/// option. Unlike `GoogleMapWebView` (which embeds a self-contained HTML
/// string via `loadHTMLString`), this navigates the WKWebView to a real
/// page — reusing the same generic, data-driven embed page Peragra
/// already deployed at
/// https://mrnoh99.github.io/Peragra/naver-map-embed.html — because
/// Naver's tile-serving endpoints validate the calling page's actual
/// origin, and `loadHTMLString(_:baseURL:)` only fakes that origin for
/// resolving relative URLs: the map script initializes fine against a
/// faked one, but every tile request fails silently. The page takes its
/// Naver Client ID and place data entirely from the JS payload injected
/// below (`window.renderNaverMap`), so it works for PlaceCards' own NCP
/// application the same way it already does for Peragra's — **but that
/// application's Web Service URL must include `mrnoh99.github.io`
/// (or PlaceCards needs its own copy of the page hosted somewhere its
/// own NCP application allows) or every tile request will fail the same
/// way `loadHTMLString` did.**
struct NaverMapWebView: UIViewRepresentable {
    struct MarkerPlace: Encodable, Equatable {
        let id: String
        let name: String
        let address: String
        /// The embed page's marker icon concatenates this directly into
        /// the marker's HTML content (`place.emoji`, in
        /// `naver-map-embed.html`) — without it, every marker's icon
        /// literally reads "undefined" (a bare string concatenation with
        /// no nil-check on the page's side, since it was written for
        /// Peragra, where this field is never missing). Despite the name
        /// (kept to match that page's payload shape), this is populated
        /// with `PlacesMapView.naverMarkerContentHTML(for:)` — an
        /// inline-SVG outline icon (`PlaceCategoryIcon.markerGlyphHTML`)
        /// plus the place's own name as a label underneath, not a
        /// literal emoji character — since the page only ever uses it as
        /// raw HTML, never as text.
        let emoji: String
        let visited: Bool
        let latitude: Double
        let longitude: Double
        let kakaoMapUrlString: String?
        let naverMapUrlString: String?
        let tmapUrlString: String?
    }

    let clientId: String
    let places: [MarkerPlace]
    /// Called with a place's id (its `MarkerPlace.id`) when a marker's
    /// "카드 보기" button is tapped, via a JS -> Swift message handler.
    let onSelectPlace: (String) -> Void

    private static let embedURL = URL(string: "https://mrnoh99.github.io/Peragra/naver-map-embed.html")!

    private struct Payload: Encodable {
        let clientId: String
        let tripDestination: String
        let places: [MarkerPlace]
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "selectPlace")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectPlace = onSelectPlace
        let signature = Signature(clientId: clientId, places: places)
        guard context.coordinator.loadedSignature != signature else { return }
        context.coordinator.loadedSignature = signature
        // The embed page's payload has a tripDestination field (Peragra's
        // own per-trip fallback for a marker's "Open in Google Maps"
        // link) — PlaceCards has no equivalent, so this is always empty;
        // the page's own name+address fallback still works fine without it.
        let payload = Payload(clientId: clientId, tripDestination: "", places: places)
        context.coordinator.pendingPayloadJSON = Self.jsonString(for: payload)
        webView.load(URLRequest(url: Self.embedURL))
    }

    fileprivate struct Signature: Equatable {
        let clientId: String
        let places: [MarkerPlace]
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func jsonString(for payload: Payload) -> String? {
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// Sends taps on an "Open in ... Map" link out to the system instead
    /// of navigating inside this WebView. Also relays a marker's "카드
    /// 보기" button (a JS -> Swift message) to `onSelectPlace`, and
    /// injects the place data into the embed page once it finishes
    /// loading (`window.renderNaverMap`).
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate var loadedSignature: Signature?
        fileprivate var onSelectPlace: ((String) -> Void)?
        fileprivate var pendingPayloadJSON: String?
        private var contentProcessCrashCount = 0

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "selectPlace", let placeID = message.body as? String else { return }
            onSelectPlace?(placeID)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let json = pendingPayloadJSON else { return }
            webView.evaluateJavaScript("window.renderNaverMap(\(json));")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportLoadFailure(error, on: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportLoadFailure(error, on: webView)
        }

        private func reportLoadFailure(_ error: Error, on webView: WKWebView) {
            let message = "Naver 지도 페이지에 연결할 수 없습니다 — 인터넷 연결을 확인해주세요.".localized
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            webView.loadHTMLString(
                """
                <body style="display:flex;align-items:center;justify-content:center;height:100%;margin:0;padding:24px;text-align:center;font:14px -apple-system,sans-serif;color:#a3a3a3;">\(message)</body>
                """,
                baseURL: nil
            )
        }

        // A one-off content-process kill (memory pressure, say) recovers
        // with a reload — didFinish fires again and re-injects the last
        // payload — past that, leave it rather than risk a silent loop
        // against something genuinely crashing the process.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            contentProcessCrashCount += 1
            guard contentProcessCrashCount <= 1 else { return }
            webView.reload()
        }
    }
}
