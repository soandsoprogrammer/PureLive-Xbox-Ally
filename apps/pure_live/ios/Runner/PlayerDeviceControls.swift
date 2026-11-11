import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// The same explicit brightness and media-volume actions as Android.
/// Reading either value never changes the user's device settings.
final class PlayerDeviceControls {
  private let registrar: FlutterPluginRegistrar
  private var originalBrightness: CGFloat?
  private var requestedBrightness: CGFloat?
  private var brightnessOverridden = false
  private var volumeView: MPVolumeView?
  private var observers: [NSObjectProtocol] = []

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) {
        [weak self] _ in self?.restoreBrightness(keepRequest: true)
      })
    observers.append(
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
        [weak self] _ in
        guard let self, let requested = self.requestedBrightness else { return }
        self.originalBrightness = self.screen.brightness
        self.screen.brightness = requested
        self.brightnessOverridden = true
      })
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  private var screen: UIScreen {
    registrar.viewController?.viewIfLoaded?.window?.windowScene?.screen ?? UIScreen.main
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getVolume":
      result(Double(AVAudioSession.sharedInstance().outputVolume))
    case "getBrightness":
      result(Double(screen.brightness))
    case "resetBrightness":
      restoreBrightness(keepRequest: false)
      result(nil)
    case "setVolume", "setBrightness":
      guard let arguments = call.arguments as? [String: Any],
        let number = arguments["value"] as? NSNumber, number.doubleValue.isFinite
      else {
        result(FlutterError(code: "arguments", message: "A finite value is required", details: nil))
        return
      }
      let value = min(1, max(0, number.doubleValue))
      if call.method == "setBrightness" {
        if !brightnessOverridden { originalBrightness = screen.brightness }
        requestedBrightness = CGFloat(value)
        screen.brightness = CGFloat(value)
        brightnessOverridden = true
        result(nil)
      } else {
        setVolume(Float(value), result: result)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func restoreBrightness(keepRequest: Bool) {
    if brightnessOverridden, let original = originalBrightness { screen.brightness = original }
    brightnessOverridden = false
    if !keepRequest {
      originalBrightness = nil
      requestedBrightness = nil
    }
  }

  private func setVolume(_ value: Float, result: @escaping FlutterResult) {
    guard let host = registrar.viewController?.view else {
      result(FlutterError(code: "volume_unavailable", message: "The player window is unavailable", details: nil))
      return
    }
    let control: MPVolumeView
    if let existing = volumeView {
      control = existing
    } else {
      control = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
      control.showsRouteButton = false
      control.isUserInteractionEnabled = false
      volumeView = control
    }
    if control.superview !== host {
      control.removeFromSuperview()
      host.addSubview(control)
    }
    control.layoutIfNeeded()
    // MPVolumeView is Apple's system-volume control. Its UISlider uses
    // public UIControl actions; there is no private audio-service API.
    guard let slider = control.subviews.compactMap({ $0 as? UISlider }).first else {
      result(FlutterError(code: "volume_unavailable", message: "The media-volume control is unavailable", details: nil))
      return
    }
    DispatchQueue.main.async {
      slider.setValue(value, animated: false)
      slider.sendActions(for: .touchUpInside)
      result(nil)
    }
  }
}
