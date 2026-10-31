import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // The engine is created here (not by a storyboard) so plugins can be
  // registered before any scene exists; SceneDelegate attaches it to a window.
  lazy var flutterEngine = FlutterEngine(name: "main")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
