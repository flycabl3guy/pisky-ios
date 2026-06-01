import SwiftUI
import WebKit
import os

/// `TarWebView` — the iOS port of the Android `TarWebView.kt` (`AndroidView` + `WebView`).
///
/// PRIMARY map backend. A `WKWebView` wrapped in a `UIViewRepresentable` that loads the live
/// tar1090 instance served from the L2 nginx front door (the receiver's `connectionConfig.baseUrl`,
/// e.g. `http://192.168.1.207:8088/`). The same browser engine renders the same Leaflet/OpenLayers
/// UI as a desktop browser, so this is the highest-fidelity path (PORTING_NOTES §2).
///
/// Bridge wiring (mirrors the Android `@JavascriptInterface` named `PiSky`):
///   web → native: a `WKScriptMessageHandler` named **`PiSky`** receives `{event:"aircraftSelected",
///                 hex:"…"}` posts; `aircraftSelected(hex)` → `onAircraftTap(hex)` → `vm.selectAircraft`.
///   native → web: `controller.selectAircraft(hex)` runs
///                 `evaluateJavaScript("selectPlaneByHex('<hex>', false)")`.
///
/// A `WKUserScript` injected at `.atDocumentEnd` (the analog of Android's `onPageFinished`
/// `evaluateJavascript(buildInjection())`):
///   1. Seeds sane tar1090 localStorage defaults once per `SEED_REV` (iconScale 0.5, imperial units,
///      carto_dark, mapDim/darkerColors/showLabels true).
///   2. Wraps `selectPlaneByHex` so every selection posts back through the `PiSky` message handler.
///   3. Installs the PiSky OpenLayers VectorLayer: geodesic range rings (statute miles) + 3-letter
///      regional airport markers — ported verbatim from the Android OL injection.
struct TarWebView: UIViewRepresentable {
    /// Base URL of the tar1090 instance — `container.connectionConfig.baseUrl`.
    let baseURL: URL
    /// Fired on the main actor when the user taps a plane (JS → native).
    var onAircraftTap: (String) -> Void = { _ in }
    /// Handed back once the page is ready so the screen can drive native → web commands.
    var onControllerReady: (TarMapController) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAircraftTap: onAircraftTap, onControllerReady: onControllerReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()

        // web → native bridge, named "PiSky" to match the Android @JavascriptInterface name.
        userContent.add(context.coordinator, name: "PiSky")

        // One-shot injection at end of document load — seeds localStorage, wraps selectPlaneByHex,
        // installs the OL range-ring + airport overlay.
        let script = WKUserScript(
            source: Self.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContent.addUserScript(script)
        config.userContentController = userContent
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Desktop-equivalent rendering — tar1090's responsive layout picks the desktop tabs panel.
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.allowedHost = baseURL.host
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color(hex: 0x0A1428))
        webView.scrollView.backgroundColor = UIColor(Color(hex: 0x0A1428))
        // Desktop UA so tar1090 serves the desktop layout (matches Android's UA override).
        webView.customUserAgent =
            "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

        context.coordinator.webView = webView
        webView.load(URLRequest(url: baseURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep the latest closures so callbacks fire into the current view state.
        context.coordinator.onAircraftTap = onAircraftTap
        context.coordinator.onControllerReady = onControllerReady
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "PiSky")
        coordinator.webView = nil
    }

    // MARK: - Coordinator (navigation delegate + message handler)

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private static let log = Logger(subsystem: "com.pisky.mobile", category: "TarWebView")

        var onAircraftTap: (String) -> Void
        var onControllerReady: (TarMapController) -> Void
        weak var webView: WKWebView?

        init(onAircraftTap: @escaping (String) -> Void,
             onControllerReady: @escaping (TarMapController) -> Void) {
            self.onAircraftTap = onAircraftTap
            self.onControllerReady = onControllerReady
        }

        // web → native. Payload is `{ event: "aircraftSelected"|"ready", hex?: "…" }`.
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "PiSky" else { return }
            let event: String
            var hex: String?
            if let dict = message.body as? [String: Any] {
                event = dict["event"] as? String ?? ""
                hex = dict["hex"] as? String
            } else if let s = message.body as? String {
                event = s
            } else { return }

            switch event {
            case "aircraftSelected":
                if let hex, !hex.isEmpty {
                    DispatchQueue.main.async { [weak self] in self?.onAircraftTap(hex) }
                }
            case "ready":
                if let wv = webView {
                    let controller = TarMapController(webView: wv)
                    DispatchQueue.main.async { [weak self] in self?.onControllerReady(controller) }
                }
            default:
                break
            }
        }

        /// Trap any off-LAN navigation (the analog of `shouldOverrideUrlLoading`). Allow only the
        /// receiver host (`allowedHost`), `about:`, and the initial load; block external links.
        var allowedHost: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "about" {
                decisionHandler(.allow)
            } else if let host = url.host, host == allowedHost {
                decisionHandler(.allow)
            } else if allowedHost == nil {
                // First load (before host pinned) — allow and pin.
                allowedHost = url.host
                decisionHandler(.allow)
            } else {
                Self.log.debug("blocked off-host navigation: \(url.absoluteString, privacy: .public)")
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Self.log.error("navigation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Injection (ported from `buildInjection()` in TarWebView.kt)

    /// Cowden home site — `HOME_LAT`/`HOME_LON`/`INITIAL_ZOOM` from the Android source.
    private static let homeLat = 39.24640
    private static let homeLon = -88.86230

    private static var injectionScript: String {
        let ringsJs = TarOverlayData.ringsMi.map(String.init).joined(separator: ",")
        let airportsJs = TarOverlayData.airports
            .map { "{c:'\($0.code)',y:\($0.lat),x:\($0.lon)}" }
            .joined(separator: ",")
        return """
        (function() {
          // ── Hook plane-select → native bridge ──────────────────────────────
          try {
            if (typeof selectPlaneByHex === 'function' && !window.__pisky_wrapped) {
              var _orig = selectPlaneByHex;
              window.selectPlaneByHex = function(hex, autoFollow) {
                try { if (hex) window.webkit.messageHandlers.PiSky.postMessage({event:'aircraftSelected', hex: hex}); } catch (e) {}
                return _orig.apply(this, arguments);
              };
              window.__pisky_wrapped = true;
            }
          } catch (e) {}

          // ── Seed sane tar1090 defaults once per SEED_REV ───────────────────
          try {
            var SEED_REV = '2026-05-02-r1';
            if (localStorage.getItem('__pisky_seed_rev__') !== SEED_REV) {
              var seed = {
                'iconScale':     '0.5',
                'displayUnits':  'imperial',
                'mapType':       'carto_dark',
                'mapDim':        'true',
                'darkerColors':  'true',
                'showLabels':    'true',
                'tableInView':   'false',
                'multiSelect':   'false',
              };
              for (var k in seed) localStorage.setItem(k, seed[k]);
              localStorage.setItem('__pisky_seed_rev__', SEED_REV);
            }
          } catch (e) {}

          // ── PiSky overlay: range rings + 3-letter regional airports ────────
          var RINGS_MI  = [\(ringsJs)];
          var AIRPORTS  = [\(airportsJs)];
          var HOME_LAT  = \(homeLat);
          var HOME_LON  = \(homeLon);
          var LAYER_TAG = 'pisky-overlay';

          function destPoint(lat, lon, brgDeg, distNm) {
            var R = 3440.065;
            var brg  = brgDeg * Math.PI / 180;
            var d    = distNm / R;
            var lat1 = lat * Math.PI / 180;
            var lon1 = lon * Math.PI / 180;
            var lat2 = Math.asin(Math.sin(lat1)*Math.cos(d) + Math.cos(lat1)*Math.sin(d)*Math.cos(brg));
            var lon2 = lon1 + Math.atan2(Math.sin(brg)*Math.sin(d)*Math.cos(lat1),
                                         Math.cos(d) - Math.sin(lat1)*Math.sin(lat2));
            return [lon2 * 180 / Math.PI, lat2 * 180 / Math.PI];
          }

          function ringCoords(lat, lon, distNm) {
            var pts = [];
            for (var b = 0; b <= 360; b += 3) {
              pts.push(ol.proj.fromLonLat(destPoint(lat, lon, b, distNm)));
            }
            return pts;
          }

          function buildPiskyLayer() {
            var lat = (typeof SitePosition !== 'undefined' && SitePosition && SitePosition.length >= 2)
                        ? SitePosition[0] : HOME_LAT;
            var lon = (typeof SitePosition !== 'undefined' && SitePosition && SitePosition.length >= 2)
                        ? SitePosition[1] : HOME_LON;
            var feats = [];
            RINGS_MI.forEach(function(mi, idx) {
              var nm  = mi / 1.15078;
              var ring = new ol.Feature({ geometry: new ol.geom.Polygon([ ringCoords(lat, lon, nm) ]) });
              ring.setStyle(new ol.style.Style({
                stroke: new ol.style.Stroke({
                  color: idx === 0 ? 'rgba(184,224,255,0.75)' : 'rgba(184,224,255,0.45)',
                  width: idx === 0 ? 1.6 : 1.0,
                }),
              }));
              feats.push(ring);
              var lblLL = destPoint(lat, lon, 315, nm);
              var lbl = new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat(lblLL)) });
              lbl.setStyle(new ol.style.Style({
                text: new ol.style.Text({
                  text: mi + ' mi',
                  font: 'bold 11px monospace',
                  fill: new ol.style.Fill({ color: '#B8E0FF' }),
                  stroke: new ol.style.Stroke({ color: '#000000', width: 3 }),
                }),
              }));
              feats.push(lbl);
            });
            AIRPORTS.forEach(function(a) {
              var f = new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([a.x, a.y])) });
              f.setStyle(new ol.style.Style({
                image: new ol.style.Circle({
                  radius: 3.5,
                  fill: new ol.style.Fill({ color: 'rgba(255,208,96,0.9)' }),
                  stroke: new ol.style.Stroke({ color: '#000000', width: 1 }),
                }),
                text: new ol.style.Text({
                  text: a.c,
                  font: 'bold 12px monospace',
                  fill: new ol.style.Fill({ color: '#FFD060' }),
                  stroke: new ol.style.Stroke({ color: '#000000', width: 3 }),
                  offsetY: -12,
                }),
              }));
              feats.push(f);
            });
            var src   = new ol.source.Vector({ features: feats });
            var layer = new ol.layer.Vector({ source: src });
            layer.set('name', LAYER_TAG);
            layer.setZIndex(50);
            OLMap.getLayers().getArray().slice().forEach(function(l) {
              if (l.get && l.get('name') === LAYER_TAG) OLMap.removeLayer(l);
            });
            OLMap.addLayer(layer);
          }

          function tryInstallOverlay(retries) {
            if (typeof ol === 'undefined' || !ol.layer || typeof OLMap === 'undefined' || !OLMap.addLayer) {
              if (retries > 0) setTimeout(function() { tryInstallOverlay(retries - 1); }, 250);
              return;
            }
            try { buildPiskyLayer(); } catch (e) {}
          }
          setTimeout(function() { tryInstallOverlay(60); }, 500);

          try { window.webkit.messageHandlers.PiSky.postMessage({event:'ready'}); } catch (e) {}
        })();
        """
    }
}

/// Native → web control surface — the iOS port of `TarMapController` in TarWebView.kt.
/// Held by the screen; commands run JS in the live `WKWebView`. Safe before the page is ready (no-ops).
final class TarMapController {
    private weak var webView: WKWebView?

    init(webView: WKWebView) { self.webView = webView }

    /// Center + highlight a plane by ICAO24 hex — `evaluateJavaScript("selectPlaneByHex('<hex>', false)")`.
    func selectAircraft(_ hex: String) {
        let h = hex.lowercased()
        let js = """
        (function() {
          try {
            if (typeof selectPlaneByHex === 'function') { selectPlaneByHex('\(h)', false); }
          } catch (e) {}
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Pan the view back to the receiver's home position.
    func recenter() {
        let js = """
        (function() {
          try {
            if (typeof OLMap !== 'undefined' && OLMap.getView) {
              OLMap.getView().setCenter(ol.proj.fromLonLat([\(TarOverlayData.homeLon), \(TarOverlayData.homeLat)]));
              OLMap.getView().setZoom(8);
            }
          } catch (e) {}
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// Static overlay data — port of `TarOverlayData.kt` (range rings + 3-letter regional airports).
enum TarOverlayData {
    static let homeLat = 39.24640
    static let homeLon = -88.86230

    static let ringsMi: [Int] = [25, 50, 75, 100, 125, 150, 175, 200]

    struct Airport { let code: String; let lat: Double; let lon: Double }

    static let airports: [Airport] = [
        // Illinois
        Airport(code: "ORD", lat: 41.9786, lon: -87.9047),
        Airport(code: "MDW", lat: 41.7861, lon: -87.7525),
        Airport(code: "RFD", lat: 42.1954, lon: -89.0972),
        Airport(code: "PIA", lat: 40.6642, lon: -89.6933),
        Airport(code: "MLI", lat: 41.4485, lon: -90.5075),
        Airport(code: "BMI", lat: 40.4772, lon: -88.9159),
        Airport(code: "CMI", lat: 40.0394, lon: -88.2780),
        Airport(code: "DEC", lat: 39.8346, lon: -88.8657),
        Airport(code: "SPI", lat: 39.8441, lon: -89.6779),
        // Missouri
        Airport(code: "STL", lat: 38.7487, lon: -90.3600),
        Airport(code: "MCI", lat: 39.2976, lon: -94.7139),
        Airport(code: "SGF", lat: 37.2457, lon: -93.3886),
        Airport(code: "COU", lat: 38.8181, lon: -92.2196),
        Airport(code: "SUS", lat: 38.6622, lon: -90.6520),
        // Indianapolis
        Airport(code: "IND", lat: 39.7173, lon: -86.2944),
        // Wisconsin
        Airport(code: "MKE", lat: 42.9472, lon: -87.8966),
        Airport(code: "MSN", lat: 43.1399, lon: -89.3375),
        Airport(code: "GRB", lat: 44.4851, lon: -88.1296),
        Airport(code: "ATW", lat: 44.2581, lon: -88.5191),
        Airport(code: "OSH", lat: 43.9844, lon: -88.5570),
        Airport(code: "LSE", lat: 43.8790, lon: -91.2566),
    ]
}
