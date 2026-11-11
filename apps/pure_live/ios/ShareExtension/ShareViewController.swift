import UIKit
import UniformTypeIdentifiers

/// 纯粹直播 in other apps' share sheets (A18.1 c8): takes the shared link or
/// text and opens the app with it (`purelive-share://share?text=…`, handled
/// by `ShareInbox` in `Runner/AppDelegate.swift` like Android's shares:
/// a room link opens the room, a share code asks to import). Files are not
/// taken: handing them over needs an app group, which unsigned builds lack.
final class ShareViewController: UIViewController {
  private var done = false

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !done else { return }
    done = true
    Task { @MainActor in
      if let text = await sharedText(), let url = Self.link(for: text) {
        open(url)
      }
      extensionContext?.completeRequest(returningItems: nil)
    }
  }

  /// `purelive-share://share?text=<text>`.
  static func link(for text: String) -> URL? {
    var components = URLComponents()
    components.scheme = "purelive-share"
    components.host = "share"
    components.queryItems = [URLQueryItem(name: "text", value: text)]
    return components.url
  }

  /// The links and texts shared, one per line (a web page's link first).
  private func sharedText() async -> String? {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    var texts: [String] = []
    for item in items {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
          let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
          !url.isFileURL
        {
          texts.append(url.absoluteString)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
        {
          texts.append(text)
        }
      }
      if let content = item.attributedContentText?.string { texts.append(content) }
    }
    var seen = Set<String>()
    let lines = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  /// An extension may not open links itself; the application object up its
  /// responder chain can (`open(_:options:completionHandler:)`, called
  /// through the runtime: the method is marked unavailable to extensions).
  private func open(_ url: URL) {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if current is UIApplication, let method = class_getInstanceMethod(type(of: current), selector)
      {
        typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let call = unsafeBitCast(method_getImplementation(method), to: Open.self)
        call(current, selector, url as NSURL, NSDictionary(), nil)
        return
      }
      responder = current.next
    }
  }
}
