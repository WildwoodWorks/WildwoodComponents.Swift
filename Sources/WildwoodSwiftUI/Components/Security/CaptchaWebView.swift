#if os(iOS)
// CAPTCHA widget host: web-based providers (reCAPTCHA / hCaptcha / Turnstile)
// render inside a WKWebView and post the solved token back via a script
// message handler. The site key must permit the configured host origin (R6).

import SwiftUI
import WebKit
import WildwoodCore

public struct CaptchaWebView: UIViewRepresentable {
    private let configuration: CaptchaConfiguration
    /// Origin loaded as the page base URL — provider site keys are domain-bound.
    private let hostOrigin: URL
    private let onToken: (String) -> Void

    public init(
        configuration: CaptchaConfiguration,
        hostOrigin: URL = URL(string: "https://api.wildwoodworks.io")!,
        onToken: @escaping (String) -> Void
    ) {
        self.configuration = configuration
        self.hostOrigin = hostOrigin
        self.onToken = onToken
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "captcha")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: hostOrigin)
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {}

    public final class Coordinator: NSObject, WKScriptMessageHandler {
        private let onToken: (String) -> Void

        init(onToken: @escaping (String) -> Void) {
            self.onToken = onToken
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let token = message.body as? String, !token.isEmpty {
                onToken(token)
            }
        }
    }

    private var html: String {
        let siteKey = configuration.siteKey ?? ""
        switch configuration.providerType.lowercased() {
        case "hcaptcha":
            return """
            <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://js.hcaptcha.com/1/api.js" async defer></script></head>
            <body><div class="h-captcha" data-sitekey="\(siteKey)" data-callback="onSolve"></div>
            <script>function onSolve(t){window.webkit.messageHandlers.captcha.postMessage(t);}</script>
            </body></html>
            """
        case "turnstile":
            return """
            <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script></head>
            <body><div class="cf-turnstile" data-sitekey="\(siteKey)" data-callback="onSolve"></div>
            <script>function onSolve(t){window.webkit.messageHandlers.captcha.postMessage(t);}</script>
            </body></html>
            """
        default: // reCAPTCHA v3 (invisible, executes immediately)
            return """
            <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://www.google.com/recaptcha/api.js?render=\(siteKey)"></script></head>
            <body><script>
            grecaptcha.ready(function() {
              grecaptcha.execute('\(siteKey)', {action: 'submit'}).then(function(token) {
                window.webkit.messageHandlers.captcha.postMessage(token);
              });
            });
            </script></body></html>
            """
        }
    }
}
#endif
