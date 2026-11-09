import SwiftUI
import WebKit

// A thin shell around the studio website. The games themselves live on GitHub Pages,
// so updating a game never needs a new build of this app.
//
// Pages open under the app's own address, studio://app/<path>. Every request for it comes to
// SiteLoader below, which fetches the same file from https://tomenden.github.io/<path>.
// Screen Time limits websites by the address a page opens at, so with no web address
// there is no website to count against her daily limit (the app itself is "Always Allowed").

let site = "https://tomenden.github.io"
let scheme = "studio"
let home = URL(string: "studio://app/studio/")!
let gamesURL = URL(string: "\(site)/studio/games.json")!

@main
struct StudioApp: App {
    var body: some Scene {
        WindowGroup {
            StudioWebView().ignoresSafeArea()
        }
    }
}

/// Only the studio and its games may open — otherwise the app would be a browser that skips Screen Time.
/// The list comes from games.json on the site (every game not marked "hidden"), so adding,
/// archiving or hiding a game is a change on the site, never a new build.
enum Allow {
    static let defaultsKey = "allowedPaths"
    static var paths: [String] = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? ["/studio/", "/kefel/", "/milim/"]

    static func refresh() {
        let req = URLRequest(url: gamesURL, cachePolicy: .reloadIgnoringLocalCacheData)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let games = root["games"] as? [[String: Any]] else { return }
            let list = ["/studio/"] + games.compactMap { g -> String? in
                guard (g["status"] as? String) != "hidden", let href = g["href"] as? String else { return nil }
                return href.hasSuffix("/") ? href : href + "/"
            }
            DispatchQueue.main.async {
                paths = list
                UserDefaults.standard.set(list, forKey: defaultsKey)
            }
        }.resume()
    }

    static func permitsPath(_ path: String) -> Bool {
        let p = path.hasSuffix("/") ? path : path + "/"
        return paths.contains { p.hasPrefix($0) }
    }
}

/// Serves studio://app/<path> from the website. Keeps a copy (URLCache), so a game opened once
/// still works without internet.
final class SiteLoader: NSObject, WKURLSchemeHandler {
    private var live = Set<ObjectIdentifier>()   // tasks WebKit hasn't stopped; touched on the main thread only

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let remote = URL(string: site + url.path + (url.query.map { "?" + $0 } ?? "")) else {
            return task.didFailWithError(URLError(.badURL))
        }
        let id = ObjectIdentifier(task)
        live.insert(id)
        // Pages and the game list revalidate so updates show up; other files use normal caching.
        let page = url.path.hasSuffix("/") || url.path.hasSuffix(".html") || url.path.hasSuffix(".json")
        fetch(remote, policy: page ? .reloadRevalidatingCacheData : .useProtocolCachePolicy) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.live.remove(id) != nil else { return }
                switch result {
                case .success(let (data, http)):
                    var headers = ["Content-Type": http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
                                   "Cache-Control": "no-cache"]
                    if http.statusCode >= 400 { headers["Content-Type"] = "text/plain" }
                    let response = HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                case .failure(let error):
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task))
    }

    /// Network first; when offline, fall back to the saved copy.
    private func fetch(_ url: URL, policy: URLRequest.CachePolicy, done: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: policy)) { data, response, error in
            if let data, let http = response as? HTTPURLResponse { return done(.success((data, http))) }
            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)) { data, response, _ in
                if let data, let http = response as? HTTPURLResponse { done(.success((data, http))) }
                else { done(.failure(error ?? URLError(.notConnectedToInternet))) }
            }.resume()
        }.resume()
    }
}

/// window.webkit.messageHandlers.haptic.postMessage("soft" | "light" | "medium" | "rigid")
final class Haptics: NSObject, WKScriptMessageHandler {
    private let styles: [String: UIImpactFeedbackGenerator.FeedbackStyle] =
        ["soft": .soft, "light": .light, "medium": .medium, "rigid": .rigid, "heavy": .heavy]
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        UIImpactFeedbackGenerator(style: styles[message.body as? String ?? ""] ?? .soft).impactOccurred()
    }
}

struct StudioWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        URLCache.shared = URLCache(memoryCapacity: 20 << 20, diskCapacity: 200 << 20)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SiteLoader(), forURLScheme: scheme)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // The games look for "YaelStudio" to show their "back to the studio" button.
        config.applicationNameForUserAgent = "Mobile/15E148 YaelStudio/1"
        // Her progress-sync code, baked in at build time from the git-ignored Local.xcconfig.
        // The games read it from localStorage, so she never has to type it.
        if let code = Bundle.main.object(forInfoDictionaryKey: "KidSyncCode") as? String,
           code.range(of: "^[a-z0-9-]{6,40}$", options: .regularExpression) != nil {
            let js = "try{localStorage.setItem('kidsync-code','\(code)')}catch(e){}"
            config.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        // Pages ask for a tap of the phone's haptic engine (the squishies use it).
        config.userContentController.add(Haptics(), name: "haptic")

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "LaunchBG")
        web.scrollView.backgroundColor = web.backgroundColor
        #if DEBUG
        web.isInspectable = true
        #endif

        Allow.refresh()
        web.load(URLRequest(url: home))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            switch url.scheme {
            case "about":
                decisionHandler(.allow)
            case scheme:
                decisionHandler(Allow.permitsPath(url.path) ? .allow : .cancel)
            case "https" where url.host == "tomenden.github.io" && Allow.permitsPath(url.path):
                // A full web link to one of the games opens under the app's own address instead.
                decisionHandler(.cancel)
                var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                c.scheme = scheme; c.host = "app"
                if let local = c.url { webView.load(URLRequest(url: local)) }
            default:
                decisionHandler(.cancel)
            }
        }

        // Links that ask for a new window open in place, under the same rules.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, url.scheme == scheme, Allow.permitsPath(url.path) { webView.load(action.request) }
            return nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let code = (error as NSError).code
            if code == NSURLErrorCancelled || code == 102 /* frame load interrupted by a cancelled policy */ { return }
            webView.loadHTMLString(offlinePage, baseURL: nil)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if webView.url == nil { webView.load(URLRequest(url: home)) } else { webView.reload() }
        }
    }
}

let offlinePage = """
<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>
body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;
font:18px/1.5 -apple-system,system-ui,sans-serif;text-align:center;padding:24px;box-sizing:border-box;background:#FFF3F6;color:#3A1838}
@media (prefers-color-scheme:dark){body{background:#170C20;color:#FBEAF3}}
b{font-size:24px}
a{background:#E8337F;color:#fff;text-decoration:none;font-weight:700;padding:14px 28px;border-radius:99px}
</style></head><body>
<b>אין חיבור לאינטרנט</b>
<span>הסטודיו צריך אינטרנט כדי לפתוח את המשחקים.<br>אפשר לבדוק את ה-Wi-Fi ולנסות שוב.</span>
<a href="studio://app/studio/">לנסות שוב</a>
</body></html>
"""
