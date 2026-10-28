import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var distributionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so taps on a study reminder reach
    // the app.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerDistributionChannel()
    return launched
  }

  /// Lets Dart tell a TestFlight install from an App Store install.
  /// The receipt name is `sandboxReceipt` for TestFlight and `receipt` for
  /// the public store. The channel is kept so the handler stays registered.
  private func registerDistributionChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "fiveminutekanji/distribution",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "receiptName":
        result(Bundle.main.appStoreReceiptURL?.lastPathComponent)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    distributionChannel = channel
  }
}
