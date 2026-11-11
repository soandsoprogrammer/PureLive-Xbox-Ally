import Cocoa
import CryptoKit
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The red button and ⌘W only hide the window; the app stays in the Dock,
  // recording (A18.2 c6). Quitting is ⌘Q, the Dock's or the menu bar icon's
  // "退出", which Flutter asks first (`AppLifecycleListener.onExitRequested`).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // A click on the Dock icon brings the hidden window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// AES-256-GCM for the channel `pure_live/secret_cipher`
/// (`lib/platform/secret_cipher.dart`, `NativeChannelCipher`), like the
/// Android Keystore cipher: `seal` gives nonce, ciphertext and tag together,
/// `open` takes them back; the secret's name is the associated data. The key
/// is made once: on iOS it is kept in the Keychain (this device only), on
/// macOS — and on iOS when the Keychain refuses, as it can for re-signed
/// builds — in `secret.key` in the app's own Application Support folder.
final class SecretCipher {
  static let shared = SecretCipher()

  private var cached: SymmetricKey?
  private let service = "pure_live.secret_cipher"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any], let ref = arguments["ref"] as? String else {
      result(FlutterError(code: "arguments", message: "ref is missing", details: nil))
      return
    }
    do {
      let aad = Data(ref.utf8)
      switch call.method {
      case "seal":
        guard let plain = arguments["plain"] as? String else { throw CipherError.arguments }
        let box = try AES.GCM.seal(Data(plain.utf8), using: try key(), authenticating: aad)
        guard let combined = box.combined else { throw CipherError.arguments }
        result(FlutterStandardTypedData(bytes: combined))
      case "open":
        guard let sealed = arguments["sealed"] as? FlutterStandardTypedData else { throw CipherError.arguments }
        let box = try AES.GCM.SealedBox(combined: sealed.data)
        let plain = try AES.GCM.open(box, using: try key(), authenticating: aad)
        result(String(decoding: plain, as: UTF8.self))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "cipher", message: "\(error)", details: nil))
    }
  }

  private enum CipherError: Error { case arguments, keyFile }

  private func key() throws -> SymmetricKey {
    if let known = cached { return known }
    #if os(iOS)
    if let data = keychainRead() { return remember(data) }
    #endif
    let url = try keyFileURL()
    if let data = try? Data(contentsOf: url) {
      guard data.count == 32 else { throw CipherError.keyFile }
      return remember(data)
    }
    let made = SymmetricKey(size: .bits256)
    let data = made.withUnsafeBytes { Data($0) }
    #if os(iOS)
    if keychainWrite(data) { return remember(data) }
    #endif
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return remember(data)
  }

  private func remember(_ data: Data) -> SymmetricKey {
    let key = SymmetricKey(data: data)
    cached = key
    return key
  }

  private func keyFileURL() throws -> URL {
    let folder = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    #if os(macOS)
    // path_provider's application support folder on macOS adds the bundle id.
    let base = folder.appendingPathComponent(Bundle.main.bundleIdentifier ?? "pure_live", isDirectory: true)
    #else
    let base = folder
    #endif
    return base.appendingPathComponent("secret.key")
  }

  #if os(iOS)
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "key"]
  }

  private func keychainRead() -> Data? {
    var found: [String: Any] = query
    found[kSecReturnData as String] = true
    found[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(found as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
      data.count == 32
    else { return nil }
    return data
  }

  private func keychainWrite(_ data: Data) -> Bool {
    var added: [String: Any] = query
    added[kSecValueData as String] = data
    added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(added as CFDictionary, nil) == errSecSuccess
  }
  #endif
}
