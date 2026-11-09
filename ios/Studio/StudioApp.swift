import SwiftUI
import WebKit

// A thin shell around the studio website. The games themselves live on GitHub Pages,
// so updating a game never needs a new build of this app.

let home = URL(string: "https://tomenden.github.io/studio/")!
let gamesURL = URL(string: "https://tomenden.github.io/studio/games.json")!
let host = "tomenden.github.io"

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

    static func permits(_ url: URL) -> Bool {
        if url.scheme == "about" { return true }
        guard url.scheme == "https", url.host == host else { return false }
        let path = url.path.hasSuffix("/") ? url.path : url.path + "/"
        return paths.contains { path.hasPrefix($0) }
    }
}

struct StudioWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // The games look for "YaelStudio" to show their "back to the studio" button.
        config.applicationNameForUserAgent = "Mobile/15E148 YaelStudio/1"

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
        // Revalidate on launch so a game updated on the site shows up right away.
        web.load(URLRequest(url: home, cachePolicy: .reloadRevalidatingCacheData))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            decisionHandler(Allow.permits(url) ? .allow : .cancel)
        }

        // Links that ask for a new window open in place, under the same rules.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, Allow.permits(url) { webView.load(action.request) }
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
<a href="https://tomenden.github.io/studio/">לנסות שוב</a>
</body></html>
"""
