import Flutter
import UIKit
import AVFoundation
import Speech

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let controller = engineBridge.pluginRegistry.viewController
    let channel = FlutterMethodChannel(name: "com.kolo.ai/phone_control",
                                       binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {

      // ── Check if Speech Recognition is available ──
      case "isSpeechAvailable":
        if #available(iOS 10.0, *) {
          result(SFSpeechRecognizer.authorizationStatus() != .notDetermined)
        } else {
          result(false)
        }

      // ── Request Speech Recognition permission ──
      case "requestSpeechPermission":
        if #available(iOS 10.0, *) {
          SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
              result(status == .authorized)
            }
          }
        } else {
          result(false)
        }

      // ── Request Microphone permission ──
      case "requestMicrophonePermission":
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async {
            result(granted)
          }
        }

      // ── Launch app by URL scheme ──
      case "launchApp":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["urlScheme"] as? String,
              let url = URL(string: urlString) else {
          result(FlutterError(code: "INVALID", message: "urlScheme is required", details: nil))
          return
        }
        if UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        } else {
          result(FlutterError(code: "APP_NOT_FOUND", message: "Cannot open URL scheme: \(urlString)", details: nil))
        }

      // ── Device info ──
      case "deviceInfo":
        var accessibilityEnabled = false
        if #available(iOS 14.0, *) {
          // On iOS, "accessibility" equivalent = VoiceControl/AssistiveTouch
          // We check if Speech is authorized as proxy
          accessibilityEnabled = SFSpeechRecognizer.authorizationStatus() == .authorized
        }
        let screenSize = UIScreen.main.bounds
        result([
          "manufacturer": "Apple",
          "model": UIDevice.current.model,
          "version": UIDevice.current.systemVersion,
          "width": Int(screenSize.width),
          "height": Int(screenSize.height),
          "accessibilityEnabled": accessibilityEnabled,
          "overlayEnabled": true // iOS doesn't need overlay permission
        ] as [String: Any])

      // ── Overlay methods (no-op on iOS — Flutter overlay widget used instead) ──
      case "showAction", "phoneControlStart", "phoneControlDone", "phoneControlStatus",
           "startController", "stopController":
        result(true) // Acknowledge but actual UI is handled by Flutter overlay widget

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}