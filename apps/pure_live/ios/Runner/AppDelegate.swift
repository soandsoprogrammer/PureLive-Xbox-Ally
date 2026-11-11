import CryptoKit
import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The key commands Dart gave (A18.1 c10): `id`, `title`, `input`, `group`.
  private var pureLiveKeys: [[String: Any]] = []
  private var keyCommandsTitle = ""
  private var keyCommandsChannel: FlutterMethodChannel?
  /// A room is on top: its ⌘R is offered.
  private var roomOpen = false
  private var deviceControls: PlayerDeviceControls?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveDeviceControls") {
      let controls = PlayerDeviceControls(registrar: registrar)
      deviceControls = controls
      FlutterMethodChannel(name: "pure_live/device_controls", binaryMessenger: registrar.messenger())
        .setMethodCallHandler(controls.handle)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveSecretCipher") {
      FlutterMethodChannel(name: "pure_live/secret_cipher", binaryMessenger: registrar.messenger())
        .setMethodCallHandler(SecretCipher.shared.handle)
    }
    // Whether the clipboard has new text, without reading it (no "允许粘贴"
    // prompt; A18.1 c9): the pasteboard's change count, -1 without text.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveClipboard") {
      FlutterMethodChannel(name: "pure_live/clipboard", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "changeCount" else {
            result(FlutterMethodNotImplemented)
            return
          }
          let board = UIPasteboard.general
          result(board.hasStrings ? board.changeCount : -1)
        }
    }
    // Shares from other apps (A18.1 c8): the share extension opens
    // `purelive-share://share?text=…`, and the text goes to Dart as
    // Android's shares do (`pure_live/share_intake`, `ShareChannel`).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveShareIntake") {
      ShareInbox.shared.attach(
        FlutterMethodChannel(name: "pure_live/share_intake", binaryMessenger: registrar.messenger()))
      registrar.addSceneDelegate(ShareInbox.shared)
    }
    // The ⌘ commands as the system's key commands (A18.1 c10): holding ⌘
    // lists them; `lib/app/commands.dart` (`IosKeyCommands`).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PureLiveKeyCommands") {
      let channel = FlutterMethodChannel(name: "pure_live/key_commands", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "set":
          let arguments = call.arguments as? [String: Any]
          self.pureLiveKeys = arguments?["commands"] as? [[String: Any]] ?? []
          self.keyCommandsTitle = arguments?["title"] as? String ?? ""
          UIMenuSystem.main.setNeedsRebuild()
          result(true)
        case "room":
          self.roomOpen = call.arguments as? Bool ?? false
          UIMenuSystem.main.setNeedsRevalidate()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      keyCommandsChannel = channel
    }
  }

  /// The app's own menu of key commands, one inline section per group.
  override func buildMenu(with builder: UIMenuBuilder) {
    super.buildMenu(with: builder)
    guard builder.system == .main, !pureLiveKeys.isEmpty else { return }
    var order: [String] = []
    var groups: [String: [UIKeyCommand]] = [:]
    for entry in pureLiveKeys {
      guard let id = entry["id"] as? String, let title = entry["title"] as? String,
        let input = entry["input"] as? String, let group = entry["group"] as? String
      else { continue }
      let command = UIKeyCommand(
        title: title, action: #selector(runPureLiveCommand(_:)), input: input, modifierFlags: .command,
        propertyList: id)
      if #available(iOS 15.0, *) { command.wantsPriorityOverSystemBehavior = true }
      if groups[group] == nil { order.append(group) }
      groups[group, default: []].append(command)
    }
    let sections = order.map {
      UIMenu(title: "", identifier: UIMenu.Identifier("pure_live.keys.\($0)"), options: .displayInline,
        children: groups[$0] ?? [])
    }
    let menu = UIMenu(title: keyCommandsTitle, identifier: UIMenu.Identifier("pure_live.keys"), children: sections)
    // Before the system's "窗口" menu where there is one (iPadOS's menu bar),
    // else at the end of the main menu.
    if builder.menu(for: .window) != nil {
      builder.insertSibling(menu, beforeMenu: .window)
    } else {
      builder.insertChild(menu, atEndOfMenu: .root)
    }
  }

  @objc func runPureLiveCommand(_ sender: UIKeyCommand) {
    guard let id = sender.propertyList as? String else { return }
    keyCommandsChannel?.invokeMethod("run", arguments: id)
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(runPureLiveCommand(_:)) {
      if (sender as? UIKeyCommand)?.propertyList as? String == "refresh" { return roomOpen }
      return true
    }
    return super.canPerformAction(action, withSender: sender)
  }
}

/// What other apps share with 纯粹直播 (A18.1 c8). The share extension
/// (`ShareExtension/ShareViewController.swift`) cannot hand files or data
/// to the app without an app group, so it opens
/// `purelive-share://share?text=<the link or text>`; the text reaches Dart
/// through `pure_live/share_intake` like Android's shares: `listen` returns
/// what came before Dart listened, then each one comes as `shared`.
final class ShareInbox: NSObject, FlutterSceneLifeCycleDelegate {
  static let shared = ShareInbox()
  static let scheme = "purelive-share"

  private var channel: FlutterMethodChannel?
  private var pending: [[String: Any]] = []
  private var listening = false

  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "listen":
        self.listening = true
        result(self.pending)
        self.pending.removeAll()
      default:
        // The clipboard stamp and the launcher's recent rooms are Android's.
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return receive(contexts)
  }

  @objc(scene:openURLContexts:)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    receive(URLContexts)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in contexts {
      guard let payload = Self.payload(context.url) else { continue }
      handled = true
      if listening, let channel {
        channel.invokeMethod("shared", arguments: payload)
      } else {
        pending.append(payload)
      }
    }
    return handled
  }

  /// `{text}` from a `purelive-share` link, or nil.
  static func payload(_ url: URL) -> [String: Any]? {
    guard url.scheme == scheme,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      let text = items.first(where: { $0.name == "text" })?.value,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return ["text": text]
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
