/*
 EnhancedFloorPlanViewController.swift
 PerrottaBuildRoomPlanner
 
 A UIKit view controller that hosts our SwiftUI EnhancedFloorPlanView.
 This view controller provides the bridge between UIKit and SwiftUI.
 */

import UIKit
import SwiftUI
import RoomPlan

/// UIViewController to host the SwiftUI floor plan view
public class EnhancedFloorPlanViewController: UIViewController {
    
    // Reference to the captured room data
    var capturedRoom: CapturedRoom?
    
    // Option to show or hide dimensions
    var showDimensions: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        
        // Set up navigation bar
        title = "Enhanced 2D Floor Plan"
        
        // Add a close button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close",
            style: .plain,
            target: self,
            action: #selector(dismissView)
        )
        
        // Add a toggle for dimensions
        let dimensionsButton = UIBarButtonItem(
            title: showDimensions ? "Hide Dimensions" : "Show Dimensions",
            style: .plain,
            target: self,
            action: #selector(toggleDimensions)
        )
        navigationItem.rightBarButtonItem = dimensionsButton
    }
    
    // Set up the SwiftUI view
    private func setupView() {
        // If we have room data, show the floor plan view
        if let capturedRoom = capturedRoom {
            // Create the SwiftUI view
            let floorPlanView = EnhancedFloorPlanView(
                capturedRoom: capturedRoom,
                showDimensions: showDimensions
            )
            
            // Create a hosting controller to embed the SwiftUI view
            let hostingController = UIHostingController(rootView: floorPlanView)
            
            // Add the hosting controller as a child view controller
            addChild(hostingController)
            view.addSubview(hostingController.view)
            
            // Make the hosting view fill our view controller's view
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
            
            hostingController.didMove(toParent: self)
        } else {
            // If no room data, show an error message
            let messageLabel = UILabel()
            messageLabel.text = "No room data available"
            messageLabel.textAlignment = .center
            messageLabel.textColor = .gray
            
            view.addSubview(messageLabel)
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }
    
    // Dismiss the view controller
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    // Toggle dimensions visibility
    @objc private func toggleDimensions() {
        showDimensions = !showDimensions
        
        // Update button title
        navigationItem.rightBarButtonItem?.title = showDimensions ? "Hide Dimensions" : "Show Dimensions"
        
        // Recreate the view to reflect the new setting
        view.subviews.forEach { $0.removeFromSuperview() }
        setupView()
    }
    
    // Export the floor plan as an image
    @objc private func exportFloorPlan() {
        // This would be the place to add export functionality
        // For example, rendering the floor plan as a PDF or image
    }
} 