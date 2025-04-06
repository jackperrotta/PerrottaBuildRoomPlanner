/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view controller for the app's first screen that explains what to do.
This is a simple onboarding screen that introduces users to the RoomPlan functionality
and provides a button to start the room scanning process.
*/

import UIKit

/// The OnboardingViewController serves as the entry point for the app, allowing users
/// to start a new room scan or potentially view existing scans.
class OnboardingViewController: UIViewController {
    /// View for displaying existing scans (not implemented in this example)
    @IBOutlet var existingScanView: UIView!

    /// Starts the room scanning process by presenting the RoomCaptureViewController
    /// This action is triggered when the user taps the "Start Scan" button
    @IBAction func startScan(_ sender: UIButton) {
        // Instantiate the RoomCaptureViewNavigationController from the storyboard
        // This controller contains the RoomCaptureViewController which handles the scanning process
        if let viewController = self.storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController") {
            viewController.modalPresentationStyle = .fullScreen
            present(viewController, animated: true)
        }
    }
}
