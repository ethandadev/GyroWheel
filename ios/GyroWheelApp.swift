import SwiftUI
import UIKit

@main
struct GyroWheelApp: App {
    // Lock orientation via the app delegate (see AppDelegate below).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // A single AppSettings instance is shared with the GameController and the views.
    @StateObject private var settings: AppSettings
    @StateObject private var controller: GameController
    @StateObject private var discovery = Discovery()
    @StateObject private var store = Store()

    init() {
        let shared = AppSettings()
        _settings = StateObject(wrappedValue: shared)
        _controller = StateObject(wrappedValue: GameController(settings: shared))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(controller)
                .environmentObject(discovery)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Forces the app into landscape only. Combine with the Info.plist orientation
/// keys (see Info-plist-additions.xml) so the launch screen is landscape too.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
}
