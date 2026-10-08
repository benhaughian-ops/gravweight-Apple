import SwiftUI
import WebKit

struct SessionAnalysisWebView: UIViewRepresentable {
    let sessionData: Data
    
    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            if let url = URL(string: "https://wodwire.com/#embed-session") {
                let request = URLRequest(url: url)
                webView.load(request)
            }
        }
        
        // Use a slight delay to ensure the page is loaded and window.gwLoadNativeSession is attached.
        // In a perfect world, we'd use WKScriptMessageHandler, but this is simple and robust enough.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let jsonString = String(data: sessionData, encoding: .utf8) {
                let js = "if (window.gwLoadNativeSession) { window.gwLoadNativeSession(`\(jsonString.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "\\", with: "\\\\"))`); } else { window.__gwNativeSessionPendingData = `\(jsonString.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "\\", with: "\\\\"))`; }"
                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        print("Failed to inject session data: \(error)")
                    }
                }
            }
        }
    }
}
