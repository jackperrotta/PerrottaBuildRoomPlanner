/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The sample app's main entry point.
This AppDelegate handles the application lifecycle and device compatibility check for RoomPlan.
*/

import UIKit
import RoomPlan // Import RoomPlan to check device compatibility

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Standard application launch method
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // MARK: UISceneSession life cycle

    /// Configure the UISceneSession
    /// This method specifically handles device compatibility for RoomPlan
    /// by checking if the current device supports RoomPlan functionality
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        var configurationName = "Default Configuration"
        
        // Check if the device supports RoomPlan
        // RoomPlan requires:
        // - iOS 16.0 or later
        // - Device with LiDAR scanner (iPhone/iPad Pro models with LiDAR)
        // - ARKit compatibility
        if !RoomCaptureSession.isSupported {
            // If device is not supported, use a different scene configuration
            // that likely shows an unsupported device message
            configurationName = "Unsupported Device"
        }
        
        return UISceneConfiguration(name: configurationName, sessionRole: connectingSceneSession.role)
    }
}

