import SwiftUI
import WebKit
import UIKit

/// Renders saved place cards on a Naver Map, for the "지도" tab's Naver
/// option. Unlike `GoogleMapWebView` (which embeds a self-contained HTML
/// string via `loadHTMLString`), this navigates the WKWebView to a real
/// page — because Naver's tile-serving endpoints validate the calling
/// page's actual origin, and `loadHTMLString(_:baseURL:)` only fakes that
/// origin for resolving relative URLs: the map script initializes fine
/// against a faked one, but every tile request fails silently.
///
/// The page (`web/public/naver-map-embed.html` in the Peragra repo) is
/// shared with Peragra's own iOS app, which loads it too — **so changing
/// it changes both apps' marker balloons.** This app briefly kept a fork
/// of it to avoid that; the fork was dropped once reshaping Peragra's
/// balloon was approved, since two diverging copies of one page is the
/// worse problem. The page needs no branch per app: every field only one
/// of them sends (`strings`, `appleMapUrlString`) has a default there.
///
/// **That NCP application's Web Service URL must include
/// `mrnoh99.github.io`** or every tile request will fail the same way
/// `loadHTMLString` did.
///
/// The page takes its Naver Client ID, its user-facing labels and its
/// place data entirely from the JS payload injected below
/// (`window.renderNaverMap`).
struct NaverMapWebView: UIViewRepresentable {
    struct MarkerPlace: Encodable, Equatable {
        let id: String
        let name: String
        let address: String
        /// The embed page's marker icon concatenates this directly into
        /// the marker's HTML content (`place.emoji`, in
        /// `naver-map-embed.html`). Despite the name — the shared page's
        /// payload shape comes from Peragra, where this really is an
        /// emoji character — this is populated
        /// with `PlacesMapView.naverMarkerContentHTML(for:)` — an
        /// inline-SVG outline icon (`PlaceCategoryIcon.markerGlyphHTML`)
        /// plus the place's own name as a label underneath, not a
        /// literal emoji character — since the page only ever uses it as
        /// raw HTML, never as text.
        let emoji: String
        let visited: Bool
        let latitude: Double
        let longitude: Double
        /// Precomputed here rather than on the page, since building
        /// these needs `KoreaRegion`/`AppleMapsOpener`/`KakaoMapOpener`/
        /// `NaverMapOpener`/`TmapOpener`, which only exist on the Swift
        /// side — nil when that provider isn't available for this place
        /// (outside Korea, say), which the page skips.
        let appleMapUrlString: String?
        let kakaoMapUrlString: String?
        let naverMapUrlString: String?
        let tmapUrlString: String?
    }

    /// The page's own user-facing labels. Resolved here, via `.localized`,
    /// because the page has no access to the app's language setting.
    /// Peragra sends no `strings` at all and gets the page's English
    /// defaults, which is what it has always shown. The button labels are
    /// the same short provider names the native menu (`MapOpenMenu`) uses.
    private struct LocalizedStrings: Encodable {
        let loadError = "Naver 지도를 불러오지 못했습니다 — 설정의 Client ID를 확인해주세요.".localized
        let authError = "Naver 지도가 이 Client ID를 거부했습니다 — 설정에서 확인해주세요.".localized
        let scriptError = "Naver 지도 스크립트를 불러오지 못했습니다.".localized
        let close = "닫기".localized
        let viewCard = "카드 보기".localized
        let openGoogleMaps = "Google Maps"
        let openAppleMaps = "Apple 지도".localized
        let openNaverMap = "Naver Map"
        let openKakaoMap = "Kakao Map"
        let openTmap = "Tmap"
    }

    let clientId: String
    let places: [MarkerPlace]
    /// Called with a place's id (its `MarkerPlace.id`) when a marker's
    /// "카드 보기" button is tapped, via a JS -> Swift message handler.
    let onSelectPlace: (String) -> Void

    private static let embedURL = URL(string: "https://mrnoh99.github.io/Peragra/naver-map-embed.html")!

    private struct Payload: Encodable {
        let clientId: String
        let strings = LocalizedStrings()
        let places: [MarkerPlace]
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // `isScrollEnabled = false` (GoogleMapWebView's own approach) was
        // tried here too, but it left the map fully frozen — no pan, no
        // pinch-zoom, everything else (tiles, markers) rendering fine.
        // Google's JS SDK apparently drives its own drag/pinch handling
        // regardless of the surrounding UIScrollView, but Naver's touch
        // gestures got swallowed: with scrolling off, WKWebView's own pan/
        // pinch gesture recognizers are still present and still grab the
        // touch, just no longer produce any visible scroll/zoom effect —
        // starving whatever Naver's SDK listens for underneath. Turning
        // scrolling back on fixed drag (the pan gesture recognizer steps
        // aside once it has somewhere to actually scroll to), but pinch
        // stayed broken: pinning the zoom range to 1 (tried first) still
        // left the *pinch gesture recognizer itself* alive to claim the
        // touch before Naver's own handler ever saw it — recognizing the
        // gesture and then simply producing no visible zoom, the same
        // "recognized but inert" trap as scrolling before. Disabling that
        // recognizer outright removes the competing claimant entirely, so
        // the multi-touch reaches Naver's SDK. `bounces = false` alone
        // still keeps the page itself from rubber-banding (nothing to
        // scroll to anyway — html/body/#map are all a fixed 100%).
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "selectPlace")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectPlace = onSelectPlace
        let signature = Signature(clientId: clientId, places: places)
        guard context.coordinator.loadedSignature != signature else { return }
        context.coordinator.loadedSignature = signature
        let payload = Payload(clientId: clientId, places: places)
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
