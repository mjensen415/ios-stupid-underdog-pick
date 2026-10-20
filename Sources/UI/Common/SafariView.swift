import SwiftUI
import SafariServices

/// In-app Safari sheet for the website's own pages (Terms, Privacy, etc.).
/// SFSafariViewController rather than a WKWebView: it's Apple's sanctioned
/// way to show web content you don't control inside an app, keeps Safari's
/// address bar visible so people can see it's the real site, and needs no
/// navigation handling of our own.
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let vc = SFSafariViewController(url: url)
    vc.preferredControlTintColor = UIColor(BoldTheme.Colors.green)
    vc.dismissButtonStyle = .done
    return vc
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Wraps a URL so it can drive `.sheet(item:)`.
struct IdentifiableURL: Identifiable {
  let url: URL
  var id: String { url.absoluteString }
}
