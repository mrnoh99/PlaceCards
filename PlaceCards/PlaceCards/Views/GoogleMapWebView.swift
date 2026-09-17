import SwiftUI
import WebKit
import UIKit

/// Renders saved place cards on a Google Map, for the "지도" tab's
/// Google option. Implemented as a self-contained HTML page loaded into a
/// WKWebView (same technique Peragra's `GoogleMapWebView` uses) — Google
/// doesn't offer a SwiftUI-native map view, and pulling in their iOS SDK
/// would mean an unreviewable binary dependency, so the JS Maps API in a
/// WebView keeps this consistent with how the rest of this app avoids
/// third-party SDKs. Uses the same key as "Google Places API" in
/// Settings — that Google Cloud project/key needs the "Maps JavaScript
/// API" enabled too (a checkbox in Google Cloud Console, not a new key).
///
/// Sharing that key also decides how it can be locked down. This is a
/// web page, so Google checks it by referer; the Places REST calls are
/// checked by `X-Ios-Bundle-Identifier` (`PlaceSearchService`). A key
/// carries only one application restriction, so restricting it to "iOS
/// apps" leaves this map permanently blank — the 10-second timeout
/// below is all the user would see. Hence the documented setup: leave
/// the key unrestricted and cap it with per-API daily quotas instead.
struct GoogleMapWebView: UIViewRepresentable {
    struct MarkerPlace: Encodable, Equatable {
        let id: String
        let name: String
        let address: String
        let visited: Bool
        let latitude: Double
        let longitude: Double
        /// Precomputed here (rather than in the JS below) since building
        /// these needs `KoreaRegion`/`KakaoMapOpener`/`NaverMapOpener`/
        /// `TmapOpener`/`AppleMapsOpener`, which only exist on the Swift
        /// side — nil when that service isn't available for this place
        /// (outside Korea, say).
        let appleMapUrlString: String?
        let kakaoMapUrlString: String?
        let naverMapUrlString: String?
        let tmapUrlString: String?
    }

    let apiKey: String
    let places: [MarkerPlace]
    /// Called with a place's id (its `MarkerPlace.id`) when a marker's
    /// "카드 보기" button is tapped, via a JS -> Swift message handler.
    let onSelectPlace: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "selectPlace")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectPlace = onSelectPlace
        // SwiftUI calls this on every body re-evaluation of whatever
        // contains this view, not just when the map's own inputs change —
        // reloading unconditionally re-fetches the whole Google Maps JS
        // SDK and loses the user's pan/zoom, so only reload when what's
        // actually shown has changed.
        let signature = Signature(apiKey: apiKey, places: places)
        guard context.coordinator.loadedSignature != signature else { return }
        context.coordinator.loadedSignature = signature
        webView.loadHTMLString(
            Self.html(apiKey: apiKey, places: places),
            baseURL: URL(string: "https://maps.googleapis.com")
        )
    }

    fileprivate struct Signature: Equatable {
        let apiKey: String
        let places: [MarkerPlace]
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Sends taps on the "Open in Google Maps" link out to the system
    /// instead of navigating inside this WebView, which would just
    /// replace the map with a bare page and leave no way back. Also
    /// relays a marker's "카드 보기" button (a JS -> Swift message, since
    /// a WKWebView can't call back into SwiftUI any other way) to
    /// `onSelectPlace`.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate var loadedSignature: Signature?
        fileprivate var onSelectPlace: ((String) -> Void)?

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
    }

    /// The handful of user-facing strings baked into this embedded HTML/JS
    /// page (as opposed to `MarkerPlace.name`/`.address`, which are plain
    /// place data) — resolved here in Swift, via `.localized`, since the
    /// JS template below has no access to the app's own language setting.
    private struct LocalizedStrings: Encodable {
        let loadError: String
        let viewCard: String
        let openGoogleMaps: String
        let openAppleMaps: String
        let openNaverMap: String
        let openKakaoMap: String
        let openTmap: String
    }

    private static func html(apiKey: String, places: [MarkerPlace]) -> String {
        let placesJSON: String
        if let data = try? JSONEncoder().encode(places), let json = String(data: data, encoding: .utf8) {
            placesJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        } else {
            placesJSON = "[]"
        }

        // The balloon is a compact button row now (see `balloonCSS`), so
        // these are the same short provider names the native map menu
        // (`MapOpenMenu`) uses rather than the old "…에서 열기" sentences
        // that suited a stacked list of links.
        let strings = LocalizedStrings(
            loadError: "Google 지도를 불러오지 못했습니다 — 설정의 API 키를 확인해주세요.".localized,
            viewCard: "카드 보기".localized,
            openGoogleMaps: "Google Maps",
            openAppleMaps: "Apple 지도".localized,
            openNaverMap: "Naver Map",
            openKakaoMap: "Kakao Map",
            openTmap: "Tmap"
        )
        let stringsJSON: String
        if let data = try? JSONEncoder().encode(strings), let json = String(data: data, encoding: .utf8) {
            stringsJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        } else {
            stringsJSON = "{}"
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            html, body, #map { margin: 0; height: 100%; width: 100%; }

            /* Matches the Apple map tab's own marker callout
               (`PlacesMapView.appleMapAnnotation`): name, address, then a
               row of controls — a filled primary action and bordered
               secondary ones — instead of the stack of underlined links
               this balloon used to be. Kept byte-identical to the
               PlaceCards Naver page's own copy so all three map tabs read
               the same. */
            .pc-balloon { max-width: 220px; font-family: -apple-system, sans-serif; }
            .pc-name {
              font-size: 15px; font-weight: 600;
              white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
            }
            .pc-address {
              font-size: 12px; color: #737373; margin-top: 2px;
              white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
            }
            .pc-actions { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
            .pc-btn {
              font: 500 12px -apple-system, sans-serif;
              border: none; border-radius: 8px; padding: 5px 10px;
              cursor: pointer; text-decoration: none; display: inline-block;
            }
            .pc-btn-primary { background: #007AFF; color: #ffffff; }
            .pc-btn-secondary { background: rgba(120, 120, 128, 0.16); color: #007AFF; }
          </style>
        </head>
        <body>
          <div id="map"></div>
          <script>
            const places = \(placesJSON);
            const L = \(stringsJSON);
            let mapReady = false;

            // A bad/restricted API key never calls initMap and doesn't
            // surface any error either (Google just logs to the console),
            // so a WKWebView showing this would otherwise stay blank
            // forever with no feedback.
            setTimeout(() => {
              if (mapReady) return;
              const errorDiv = document.createElement("div");
              errorDiv.style.cssText = "display:flex;align-items:center;justify-content:center;" +
                "height:100%;padding:24px;text-align:center;font:14px -apple-system,sans-serif;color:#a3a3a3;";
              errorDiv.textContent = L.loadError;
              document.getElementById("map").replaceWith(errorDiv);
            }, 10000);

            function initMap() {
              mapReady = true;
              const map = new google.maps.Map(document.getElementById("map"), {
                zoom: 13,
                center: { lat: places[0]?.latitude ?? 37.5665, lng: places[0]?.longitude ?? 126.9780 },
              });

              // A plain text label anchored below a marker's own LatLng —
              // `Marker.label` only draws a short glyph centered *inside*
              // the pin icon, not a full name underneath it (which is
              // what Apple's native map annotation shows), so this is a
              // second, click-through overlay per place instead.
              class NameLabelOverlay extends google.maps.OverlayView {
                constructor(position, text) {
                  super();
                  this.position = position;
                  this.text = text;
                  this.div = null;
                }
                onAdd() {
                  const div = document.createElement("div");
                  div.style.position = "absolute";
                  div.style.transform = "translate(-50%, 2px)";
                  div.style.font = "11px -apple-system, sans-serif";
                  div.style.padding = "2px 6px";
                  div.style.background = "rgba(255,255,255,0.9)";
                  div.style.borderRadius = "10px";
                  div.style.maxWidth = "120px";
                  div.style.overflow = "hidden";
                  div.style.textOverflow = "ellipsis";
                  div.style.whiteSpace = "nowrap";
                  div.style.pointerEvents = "none";
                  div.textContent = this.text;
                  this.div = div;
                  this.getPanes().overlayMouseTarget.appendChild(div);
                }
                draw() {
                  const projection = this.getProjection();
                  if (!projection || !this.div) return;
                  const point = projection.fromLatLngToDivPixel(this.position);
                  this.div.style.left = point.x + "px";
                  this.div.style.top = point.y + "px";
                }
                onRemove() {
                  if (this.div) {
                    this.div.parentNode.removeChild(this.div);
                    this.div = null;
                  }
                }
              }

              const bounds = new google.maps.LatLngBounds();
              const infoWindow = new google.maps.InfoWindow();

              places.forEach((place) => {
                const position = { lat: place.latitude, lng: place.longitude };
                const marker = new google.maps.Marker({
                  position,
                  map,
                  opacity: place.visited ? 0.5 : 1,
                });
                new NameLabelOverlay(new google.maps.LatLng(place.latitude, place.longitude), place.name).setMap(map);
                marker.addListener("click", () => {
                  // Built as DOM nodes with textContent, not an HTML
                  // string, so a place name/address can't inject markup
                  // into the page.
                  const content = document.createElement("div");
                  content.className = "pc-balloon";
                  const nameEl = document.createElement("div");
                  nameEl.className = "pc-name";
                  nameEl.textContent = place.name;
                  content.appendChild(nameEl);
                  if (place.address) {
                    const addressEl = document.createElement("div");
                    addressEl.className = "pc-address";
                    addressEl.textContent = place.address;
                    content.appendChild(addressEl);
                  }
                  const actions = document.createElement("div");
                  actions.className = "pc-actions";
                  const viewCardEl = document.createElement("button");
                  viewCardEl.type = "button";
                  viewCardEl.className = "pc-btn pc-btn-primary";
                  viewCardEl.textContent = L.viewCard;
                  viewCardEl.onclick = () => window.webkit.messageHandlers.selectPlace.postMessage(place.id);
                  actions.appendChild(viewCardEl);
                  // Anything falsy (a provider Swift left nil for this
                  // place) is simply skipped, so the row only ever shows
                  // apps that can actually open it.
                  const addMapLink = (href, label) => {
                    if (!href) return;
                    const linkEl = document.createElement("a");
                    linkEl.className = "pc-btn pc-btn-secondary";
                    linkEl.href = href;
                    linkEl.textContent = label;
                    actions.appendChild(linkEl);
                  };
                  const mapsQuery = [place.name, place.address].filter(Boolean).join(", ");
                  addMapLink(
                    "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(mapsQuery),
                    L.openGoogleMaps
                  );
                  addMapLink(place.appleMapUrlString, L.openAppleMaps);
                  addMapLink(place.naverMapUrlString, L.openNaverMap);
                  addMapLink(place.kakaoMapUrlString, L.openKakaoMap);
                  addMapLink(place.tmapUrlString, L.openTmap);
                  content.appendChild(actions);
                  infoWindow.setContent(content);
                  infoWindow.open(map, marker);
                });
                bounds.extend(position);
              });

              if (places.length > 1) {
                map.fitBounds(bounds, 40);
              }
            }
          </script>
          <script async src="https://maps.googleapis.com/maps/api/js?key=\(apiKey)&callback=initMap"></script>
        </body>
        </html>
        """
    }
}
