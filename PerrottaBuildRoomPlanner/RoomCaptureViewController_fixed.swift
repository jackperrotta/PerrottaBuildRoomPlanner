/*
See the LICENSE.txt file for licensing information.

Abstract:
The main view controller that manages the room scanning process.
This controller handles the RoomPlan scanning functionality, guiding the user
through capturing a room and processing the resulting 3D model.

PerrottaBuildRoomPlanner: A 3D Interior Room Scanner
Created by Perrotta Build
*/

import UIKit
import RoomPlan // Import Apple's RoomPlan framework for 3D room scanning
import RealityKit // Use RealityKit for 3D model rendering
import QuickLook
import ARKit
import Combine
import ModelIO // For mesh generation
import SwiftUI // Import SwiftUI for integration

// Simple SwiftUI view for 2D floor plan
struct FloorPlanView: View {
    let capturedRoom: CapturedRoom
    let showDimensions: Bool
    
    // Scale factor for converting meters to points
    private let scaleFactor: CGFloat = 100
    
    // Padding around the floor plan
    private let padding: CGFloat = 40
    
    // Calculated bounds of the room
    private var roomBounds: (min: CGPoint, max: CGPoint) {
        var minX: CGFloat = .infinity
        var minZ: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxZ: CGFloat = -.infinity
        
        // Calculate bounds from walls
        for wall in capturedRoom.walls {
            let transform = wall.transform
            let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
            
            // Calculate wall endpoints based on orientation and dimensions
            let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))
            let width = CGFloat(wall.dimensions.x)
            
            let startX = position.x - width/2 * cos(rotation)
            let startZ = position.z - width/2 * sin(rotation)
            let endX = position.x + width/2 * cos(rotation)
            let endZ = position.z + width/2 * sin(rotation)
            
            minX = min(minX, startX, endX)
            minZ = min(minZ, startZ, endZ)
            maxX = max(maxX, startX, endX)
            maxZ = max(maxZ, startZ, endZ)
        }
        
        // If there are no walls, use objects as fallback
        if capturedRoom.walls.isEmpty && !capturedRoom.objects.isEmpty {
            for object in capturedRoom.objects {
                let transform = object.transform
                let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
                let halfWidth = CGFloat(object.dimensions.x) / 2
                let halfDepth = CGFloat(object.dimensions.z) / 2
                
                minX = min(minX, position.x - halfWidth)
                minZ = min(minZ, position.z - halfDepth)
                maxX = max(maxX, position.x + halfWidth)
                maxZ = max(maxZ, position.z + halfDepth)
            }
        }
        
        // If no elements were found, use default bounds
        if minX == .infinity {
            return (CGPoint(x: -1, y: -1), CGPoint(x: 1, y: 1))
        }
        
        return (CGPoint(x: minX, y: minZ), CGPoint(x: maxX, y: maxZ))
    }
    
    // Calculate canvas size
    private var canvasSize: CGSize {
        let width = (roomBounds.max.x - roomBounds.min.x) * scaleFactor + padding * 2
        let height = (roomBounds.max.z - roomBounds.min.z) * scaleFactor + padding * 2
        return CGSize(width: max(width, 300), height: max(height, 300))
    }
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                // White background with border
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .shadow(radius: 2)
                
                Canvas { context, size in
                    // Transform to flip the z-axis and apply scale/translation
                    let transform = CGAffineTransform.identity
                        .translatedBy(x: padding - roomBounds.min.x * scaleFactor, 
                                     y: size.height - padding + roomBounds.min.z * scaleFactor)
                        .scaledBy(x: scaleFactor, y: -scaleFactor)
                    
                    // Draw walls
                    for wall in capturedRoom.walls {
                        let wallPath = createWallPath(wall: wall)
                        context.stroke(
                            wallPath.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                            with: .color(.black),
                            lineWidth: 2
                        )
                    }
                    
                    // Draw doors and windows using objects with appropriate categories
                    for object in capturedRoom.objects {
                        let categoryString = String(describing: object.category)
                        
                        if categoryString.contains("door") {
                            let doorPath = createDoorPath(object: object)
                            context.stroke(
                                doorPath.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                                with: .color(.brown),
                                lineWidth: 1.5
                            )
                        } else if categoryString.contains("window") {
                            let windowPath = createWindowPath(object: object)
                            context.stroke(
                                windowPath.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                                with: .color(.blue),
                                lineWidth: 1.5
                            )
                        } else {
                            // Regular furniture objects
                            let objectPath = createObjectPath(object: object)
                            
                            // Use different colors for different furniture types
                            var color: Color = .gray
                            if categoryString.contains("storage") || categoryString.contains("television") {
                                color = .brown
                            } else if categoryString.contains("seating") {
                                color = .indigo
                            } else if categoryString.contains("bed") {
                                color = .purple
                            } else if categoryString.contains("table") {
                                color = .orange
                            }
                            
                            context.fill(
                                objectPath.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                                with: .color(color.opacity(0.5))
                            )
                            context.stroke(
                                objectPath.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                                with: .color(color),
                                lineWidth: 1
                            )
                        }
                    }
                    
                    // Draw dimensions if enabled
                    if showDimensions {
                        drawDimensions(context: context, size: size, transform: transform)
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .padding()
        }
        .background(Color(.systemBackground))
    }
    
    // Create path for a wall
    private func createWallPath(wall: CapturedRoom.Surface) -> Path {
        let transform = wall.transform
        let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
        let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))
        let width = CGFloat(wall.dimensions.x)
        
        var path = Path()
        let startX = position.x - width/2 * cos(rotation)
        let startZ = position.z - width/2 * sin(rotation)
        let endX = position.x + width/2 * cos(rotation)
        let endZ = position.z + width/2 * sin(rotation)
        
        path.move(to: CGPoint(x: startX, y: startZ))
        path.addLine(to: CGPoint(x: endX, y: endZ))
        
        return path
    }
    
    // Create path for a door
    private func createDoorPath(object: CapturedRoom.Object) -> Path {
        let transform = object.transform
        let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
        let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))
        let width = CGFloat(object.dimensions.x)
        
        var path = Path()
        let startX = position.x - width/2 * cos(rotation)
        let startZ = position.z - width/2 * sin(rotation)
        let endX = position.x + width/2 * cos(rotation)
        let endZ = position.z + width/2 * sin(rotation)
        
        // Door swing arc
        path.move(to: CGPoint(x: startX, y: startZ))
        path.addLine(to: CGPoint(x: endX, y: endZ))
        
        // Add door swing arc
        let arcRadius = width * 0.8
        path.move(to: CGPoint(x: startX, y: startZ))
        path.addArc(center: CGPoint(x: startX, y: startZ), 
                   radius: arcRadius, 
                   startAngle: Angle(radians: Double(rotation)), 
                   endAngle: Angle(radians: Double(rotation + .pi/2)), 
                   clockwise: false)
        
        return path
    }
    
    // Create path for a window
    private func createWindowPath(object: CapturedRoom.Object) -> Path {
        let transform = object.transform
        let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
        let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))
        let width = CGFloat(object.dimensions.x)
        
        var path = Path()
        let startX = position.x - width/2 * cos(rotation)
        let startZ = position.z - width/2 * sin(rotation)
        let endX = position.x + width/2 * cos(rotation)
        let endZ = position.z + width/2 * sin(rotation)
        
        // Window line
        path.move(to: CGPoint(x: startX, y: startZ))
        path.addLine(to: CGPoint(x: endX, y: endZ))
        
        // Add perpendicular lines to indicate window
        let perpLength = 0.1 // 10cm lines perpendicular to the window
        let perpX = perpLength * sin(rotation)
        let perpZ = -perpLength * cos(rotation)
        
        // First perpendicular line
        path.move(to: CGPoint(x: startX, y: startZ))
        path.addLine(to: CGPoint(x: startX + perpX, y: startZ + perpZ))
        
        // Middle perpendicular line
        let midX = (startX + endX) / 2
        let midZ = (startZ + endZ) / 2
        path.move(to: CGPoint(x: midX, y: midZ))
        path.addLine(to: CGPoint(x: midX + perpX, y: midZ + perpZ))
        
        // End perpendicular line
        path.move(to: CGPoint(x: endX, y: endZ))
        path.addLine(to: CGPoint(x: endX + perpX, y: endZ + perpZ))
        
        return path
    }
    
    // Create path for a furniture object
    private func createObjectPath(object: CapturedRoom.Object) -> Path {
        let transform = object.transform
        let position = CGPoint(x: CGFloat(transform.columns.3.x), y: CGFloat(transform.columns.3.z))
        let rotation = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))
        let width = CGFloat(object.dimensions.x)
        let depth = CGFloat(object.dimensions.z)
        
        var path = Path()
        
        // Draw rectangle for the object, accounting for rotation
        let halfWidth = width / 2
        let halfDepth = depth / 2
        
        // Calculate the four corners of the rectangle
        let tl = rotatePoint(x: -halfWidth, y: -halfDepth, angle: rotation)
        let tr = rotatePoint(x: halfWidth, y: -halfDepth, angle: rotation)
        let br = rotatePoint(x: halfWidth, y: halfDepth, angle: rotation)
        let bl = rotatePoint(x: -halfWidth, y: halfDepth, angle: rotation)
        
        // Draw rectangle
        path.move(to: CGPoint(x: position.x + tl.x, y: position.z + tl.y))
        path.addLine(to: CGPoint(x: position.x + tr.x, y: position.z + tr.y))
        path.addLine(to: CGPoint(x: position.x + br.x, y: position.z + br.y))
        path.addLine(to: CGPoint(x: position.x + bl.x, y: position.z + bl.y))
        path.closeSubpath()
        
        return path
    }
    
    // Helper function to rotate a point around the origin
    private func rotatePoint(x: CGFloat, y: CGFloat, angle: CGFloat) -> CGPoint {
        let cos = cos(angle)
        let sin = sin(angle)
        return CGPoint(
            x: x * cos - y * sin,
            y: x * sin + y * cos
        )
    }
    
    // Draw dimensions on the floor plan
    private func drawDimensions(context: GraphicsContext, size: CGSize, transform: CGAffineTransform) {
        // Find two longest walls for main dimensions
        let sortedWalls = capturedRoom.walls.sorted { 
            $0.dimensions.x > $1.dimensions.x 
        }
        
        if sortedWalls.count >= 2 {
            let wall1 = sortedWalls[0]
            let transform1 = wall1.transform
            let pos1 = CGPoint(x: CGFloat(transform1.columns.3.x), y: CGFloat(transform1.columns.3.z))
            let rot1 = atan2(CGFloat(transform1.columns.0.z), CGFloat(transform1.columns.0.x))
            let width1 = CGFloat(wall1.dimensions.x)
            
            // Draw dimension line parallel to but offset from the wall
            let offset: CGFloat = 0.3 // 30cm offset
            let perpX = offset * sin(rot1)
            let perpZ = -offset * cos(rot1)
            
            let startX1 = pos1.x - width1/2 * cos(rot1) + perpX
            let startZ1 = pos1.z - width1/2 * sin(rot1) + perpZ
            let endX1 = pos1.x + width1/2 * cos(rot1) + perpX
            let endZ1 = pos1.z + width1/2 * sin(rot1) + perpZ
            
            var dimensionPath = Path()
            dimensionPath.move(to: CGPoint(x: startX1, y: startZ1))
            dimensionPath.addLine(to: CGPoint(x: endX1, y: endZ1))
            
            // Add perpendicular end lines
            let endLineLen: CGFloat = 0.1
            dimensionPath.move(to: CGPoint(x: startX1, y: startZ1))
            dimensionPath.addLine(to: CGPoint(x: startX1 - perpX * (endLineLen/offset), y: startZ1 - perpZ * (endLineLen/offset)))
            
            dimensionPath.move(to: CGPoint(x: endX1, y: endZ1))
            dimensionPath.addLine(to: CGPoint(x: endX1 - perpX * (endLineLen/offset), y: endZ1 - perpZ * (endLineLen/offset)))
            
            // Draw dimension lines
            context.stroke(
                dimensionPath.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                with: .color(.red),
                lineWidth: 1
            )
            
            // Draw dimension text
            let midX = (startX1 + endX1) / 2
            let midZ = (startZ1 + endZ1) / 2
            let dimensionText = formatLength(Float(width1))
            
            let textRect = CGRect(
                x: CGFloat(midX * scaleFactor + padding - roomBounds.min.x * scaleFactor) - 50,
                y: CGFloat(size.height - midZ * scaleFactor - padding + roomBounds.min.z * scaleFactor) - 15,
                width: 100,
                height: 30
            )
            
            let textBackgroundPath = Path(roundedRect: textRect, cornerRadius: 4)
            context.fill(textBackgroundPath, with: .color(.white.opacity(0.8)))
            
            context.draw(
                Text(dimensionText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.red),
                in: textRect
            )
            
            // If we have more walls, show a second dimension
            if sortedWalls.count > 1 {
                let wall2 = sortedWalls[1]
                // Only show if the wall is perpendicular to the first one
                let transform2 = wall2.transform
                let rot2 = atan2(CGFloat(transform2.columns.0.z), CGFloat(transform2.columns.0.x))
                
                // Check if walls are roughly perpendicular
                let angle = abs(sin(rot1 - rot2))
                if angle > 0.7 { // Close enough to perpendicular
                    let pos2 = CGPoint(x: CGFloat(transform2.columns.3.x), y: CGFloat(transform2.columns.3.z))
                    let width2 = CGFloat(wall2.dimensions.x)
                    
                    let perp2X = offset * sin(rot2)
                    let perp2Z = -offset * cos(rot2)
                    
                    let start2X = pos2.x - width2/2 * cos(rot2) + perp2X
                    let start2Z = pos2.z - width2/2 * sin(rot2) + perp2Z
                    let end2X = pos2.x + width2/2 * cos(rot2) + perp2X
                    let end2Z = pos2.z + width2/2 * sin(rot2) + perp2Z
                    
                    var dimension2Path = Path()
                    dimension2Path.move(to: CGPoint(x: start2X, y: start2Z))
                    dimension2Path.addLine(to: CGPoint(x: end2X, y: end2Z))
                    
                    dimension2Path.move(to: CGPoint(x: start2X, y: start2Z))
                    dimension2Path.addLine(to: CGPoint(x: start2X - perp2X * (endLineLen/offset), y: start2Z - perp2Z * (endLineLen/offset)))
                    
                    dimension2Path.move(to: CGPoint(x: end2X, y: end2Z))
                    dimension2Path.addLine(to: CGPoint(x: end2X - perp2X * (endLineLen/offset), y: end2Z - perp2Z * (endLineLen/offset)))
                    
                    context.stroke(
                        dimension2Path.path(in: CGRect(origin: .zero, size: size)).transform(transform),
                        with: .color(.red),
                        lineWidth: 1
                    )
                    
                    // Draw second dimension text
                    let mid2X = (start2X + end2X) / 2
                    let mid2Z = (start2Z + end2Z) / 2
                    let dimension2Text = formatLength(Float(width2))
                    
                    let text2Rect = CGRect(
                        x: CGFloat(mid2X * scaleFactor + padding - roomBounds.min.x * scaleFactor) - 50,
                        y: CGFloat(size.height - mid2Z * scaleFactor - padding + roomBounds.min.z * scaleFactor) - 15,
                        width: 100,
                        height: 30
                    )
                    
                    let text2BackgroundPath = Path(roundedRect: text2Rect, cornerRadius: 4)
                    context.fill(text2BackgroundPath, with: .color(.white.opacity(0.8)))
                    
                    context.draw(
                        Text(dimension2Text)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red),
                        in: text2Rect
                    )
                }
            }
        }
    }
    
    // Convert meters to user-friendly imperial units
    private func formatLength(_ meters: Float) -> String {
        let inches = meters * 39.3701
        let feet = Int(inches / 12)
        let remainingInches = Int(inches.truncatingRemainder(dividingBy: 12))
        
        if feet > 0 {
            return "\(feet)'\(remainingInches)\""
        } else {
            return "\(remainingInches)\""
        }
    }
}

// StoryboardUpdater class for UI updates
class StoryboardUpdater {
    // Update the view button text and segment control
    static func updateViewControls(button: UIButton) {
        // Update button title to reflect it's now for viewing models (not just 3D)
        button.setTitle("View Model", for: .normal)
        
        // Create and configure the segment control if needed
        let existingSegmentControl = button.superview?.subviews.first(where: { $0 is UISegmentedControl }) as? UISegmentedControl
        
        if existingSegmentControl == nil {
            let segmentControl = UISegmentedControl(items: ["2D", "3D"])
            segmentControl.selectedSegmentIndex = 1 // Default to 3D
            
            // Add to view
            button.superview?.addSubview(segmentControl)
            segmentControl.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                segmentControl.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                segmentControl.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 8),
                segmentControl.widthAnchor.constraint(equalToConstant: 120)
            ])
            
            // Initially hidden until scan completes
            segmentControl.isHidden = true
            segmentControl.alpha = 0
        }
    }
}

// Floor plan view controller to host the SwiftUI FloorPlanView
class FloorPlanViewController: UIViewController {
    // Reference to the captured room data
    var capturedRoom: CapturedRoom?
    
    // Option to show or hide dimensions
    var showDimensions: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        
        // Add a back/close button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close",
            style: .plain,
            target: self,
            action: #selector(dismissView)
        )
    }
    
    private func setupView() {
        // Set up the navigation bar
        navigationItem.title = "2D Floor Plan"
        
        // Add a toggle for dimensions
        let dimensionsButton = UIBarButtonItem(
            title: showDimensions ? "Hide Dimensions" : "Show Dimensions",
            style: .plain,
            target: self,
            action: #selector(toggleDimensions)
        )
        navigationItem.rightBarButtonItem = dimensionsButton
        
        // Add the SwiftUI view if we have room data
        if let capturedRoom = capturedRoom {
            // If FloorPlanView is defined in this file, we need to use the fully qualified name
            let floorPlanView = FloorPlanView(capturedRoom: capturedRoom, showDimensions: showDimensions)
            let hostingController = UIHostingController(rootView: floorPlanView)
            
            // Add the hosting controller as a child view controller
            addChild(hostingController)
            view.addSubview(hostingController.view)
            
            // Set up constraints for the hosting view
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
            
            hostingController.didMove(toParent: self)
        } else {
            // Display a message if no room data is available
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
    
    @objc private func toggleDimensions() {
        showDimensions.toggle()
        
        // Update the button title
        navigationItem.rightBarButtonItem?.title = showDimensions ? "Hide Dimensions" : "Show Dimensions"
        
        // Refresh the view with the new setting
        setupView()
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    // Method to update the room data and refresh the view
    func updateRoomData(_ newRoomData: CapturedRoom) {
        capturedRoom = newRoomData
        
        // Refresh the view to show the new data
        if isViewLoaded {
            for subview in view.subviews {
                subview.removeFromSuperview()
            }
            setupView()
        }
    }
}

// This view controller implements two important delegate protocols:
// - RoomCaptureViewDelegate: For UI events and visual feedback during scanning
// - RoomCaptureSessionDelegate: For managing the scanning session
class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    
    @IBOutlet var exportButton: UIButton? // Button to export the captured room data
    
    // View button from storyboard
    @IBOutlet var viewButton: UIButton?
    
    // View 2D Model button
    @IBOutlet var view2DButton: UIButton?
    
    // Segment control to switch between 2D and 3D view modes
    @IBOutlet var viewModeSegmentControl: UISegmentedControl?
    
    // Container view for the floor plan or 3D model
    @IBOutlet var contentContainerView: UIView?
    
    @IBOutlet var doneButton: UIBarButtonItem? // Button to finish scanning
    @IBOutlet var cancelButton: UIBarButtonItem? // Button to cancel scanning
    @IBOutlet var activityIndicator: UIActivityIndicatorView? // Activity indicator shown during processing
    
    private var isScanning: Bool = false // Tracks whether scanning is in progress
    
    // RoomCaptureView is the main UI component provided by RoomPlan SDK
    // It displays the AR camera feed and visualizes the scanning process
    private var roomCaptureView: RoomCaptureView!
    
    // Configuration for the capture session - can be customized with various options
    // such as object detection types, session optimization goals, etc.
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    
    // This will hold the final processed room data after scanning is complete
    private var finalResults: CapturedRoom?
    
    // Properties for model viewing and unit conversion
    private var exportedURL: URL?
    private var showDimensions: Bool = true
    
    // Reference to the floor plan view controller
    private var floorPlanViewController: FloorPlanViewController?
    
    // Current view mode (2D or 3D)
    private enum ViewMode {
        case floorPlan2D
        case model3D
    }
    private var currentViewMode: ViewMode = .model3D
    
    // RealityKit properties
    private var arView: ARView?
    private var modelEntity: ModelEntity?
    private var measurementEntities: [Entity] = []
    private var rootAnchor: AnchorEntity?
    
    // Custom billboard component
    struct BillboardComponent: Component {
        static let query = EntityQuery(where: .has(BillboardComponent.self))
    }
    
    // Private property to store cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // Enum for dimension types
    enum DimensionAxis {
        case width   // X-axis
        case height  // Y-axis
        case depth   // Z-axis
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up after loading the view.
        setupRoomCaptureView()
        
        // Update the UI controls
        if let viewButton = viewButton {
            StoryboardUpdater.updateViewControls(button: viewButton)
            viewModeSegmentControl = viewButton.superview?.subviews.first(where: { $0 is UISegmentedControl }) as? UISegmentedControl
            viewModeSegmentControl?.addTarget(self, action: #selector(viewModeChanged(_:)), for: .valueChanged)
        }
        
        // Disable buttons initially until scanning is complete
        exportButton?.isEnabled = false
        viewButton?.isEnabled = false
        view2DButton?.isEnabled = false
        
        activityIndicator?.stopAnimating()
    }
    
    // Initialize and configure the RoomCaptureView
    private func setupRoomCaptureView() {
        // Create the RoomCaptureView to fill the screen
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        
        // Set up delegates to receive callbacks:
        // - captureSession.delegate handles the data capture events
        // - delegate handles UI-related events
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        
        // Add the RoomCaptureView to the view hierarchy
        view.insertSubview(roomCaptureView, at: 0)
    }
    
    // Handle segment control changes
    @objc private func viewModeChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            currentViewMode = .floorPlan2D
            showFloorPlanView()
        } else {
            currentViewMode = .model3D
            showModelView()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession() // Automatically start scanning when view appears
    }
    
    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession() // Stop scanning when view disappears to clean up resources
    }
    
    // Start the RoomPlan scanning session
    private func startSession() {
        isScanning = true
        
        // run() starts the AR session with the specified configuration
        // This begins the process of capturing the room data
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        
        setActiveNavBar() // Update UI to reflect scanning in progress
    }
    
    // Stop the RoomPlan scanning session
    private func stopSession() {
        isScanning = false
        
        // stop() ends the AR session and begins processing the captured data
        roomCaptureView?.captureSession.stop()
        
        setCompleteNavBar() // Update UI to reflect scanning completion
    }
    
    // MARK: - RoomCaptureViewDelegate Methods
    
    // This delegate method is called when RoomPlan has collected enough data
    // Return true to proceed with processing the data, or false to cancel
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true // Always process the captured data in this example
    }
    
    // This delegate method is called when RoomPlan has finished processing
    // the captured data into a final 3D model
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        // Store the processed results for export
        finalResults = processedResult
        
        // Update UI to show export is now available
        self.exportButton?.isEnabled = true
        self.viewButton?.isEnabled = true
        self.view2DButton?.isEnabled = true
        self.viewModeSegmentControl?.isHidden = false
        self.activityIndicator?.stopAnimating()
    }
    
    // Handle the "Done" button tap
    @IBAction func doneScanning(_ sender: UIBarButtonItem) {
        if isScanning { 
            stopSession() // If scanning, stop the session and process results
        } else { 
            cancelScanning(sender) // If already stopped, just dismiss the view
        }
        self.exportButton?.isEnabled = false
        self.viewButton?.isEnabled = false
        self.view2DButton?.isEnabled = false
        self.activityIndicator?.startAnimating() // Show loading indicator during processing
    }

    // Handle the "Cancel" button tap
    @IBAction func cancelScanning(_ sender: UIBarButtonItem) {
        navigationController?.dismiss(animated: true)
    }
    
    // Export the captured room data
    // RoomPlan supports different export formats:
    // - .parametric: Structured model with walls, doors, windows as separate objects
    // - .mesh: Simple 3D mesh representation
    // - .all: Both parametric and mesh models
    @IBAction func exportResults(_ sender: UIButton) {
        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
        let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
        let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")
        
        do {
            // Create export directory
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            
            // Export the CapturedRoom data as JSON for potential future use
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(finalResults)
            try jsonData.write(to: capturedRoomURL)
            
            // Export the 3D model as a USDZ file (Universal Scene Description Zip)
            // Using .parametric to get a structured model with distinct architectural elements
            try finalResults?.export(to: destinationURL, exportOptions: .parametric)
            
            // Save the exported URL for viewing
            self.exportedURL = destinationURL
            
            // Show iOS share sheet to allow user to share or save the exported files
            let activityVC = UIActivityViewController(activityItems: [destinationFolderURL], applicationActivities: nil)
            activityVC.modalPresentationStyle = .popover
            
            present(activityVC, animated: true, completion: nil)
            if let popOver = activityVC.popoverPresentationController {
                popOver.sourceView = self.exportButton
            }
        } catch {
            print("Error = \(error)")
        }
    }
    
    // View the room data visualization (2D or 3D)
    @IBAction func viewModel(_ sender: UIButton) {
        // Determine which view to show based on the current mode
        if currentViewMode == .floorPlan2D {
            showFloorPlanView()
        } else {
            showModelView()
        }
    }
    
    // Handle the View 2D Model button
    @IBAction func view2DModel(_ sender: UIButton) {
        // Check if we have room data
        guard let finalResults = self.finalResults else {
            print("No room data available for 2D floor plan view")
            return
        }
        
        // Create and configure the enhanced floor plan view controller
        let floorPlanVC = EnhancedFloorPlanViewController()
        floorPlanVC.capturedRoom = finalResults
        floorPlanVC.showDimensions = true
        
        // Create a navigation controller
        let navController = UINavigationController(rootViewController: floorPlanVC)
        navController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        
        // Present the controller
        present(navController, animated: true)
    }
    
    // Show the 2D floor plan view
    private func showFloorPlanView() {
        guard let finalResults = self.finalResults else {
            print("No room data available for floor plan view")
            return
        }
        
        // Create and configure the floor plan view controller
        let floorPlanVC = FloorPlanViewController()
        floorPlanVC.capturedRoom = finalResults
        floorPlanVC.showDimensions = showDimensions
        
        // Store a reference to the controller
        self.floorPlanViewController = floorPlanVC
        
        // Create a navigation controller
        let navController = UINavigationController(rootViewController: floorPlanVC)
        navController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        
        // Present the controller
        present(navController, animated: true)
    }
    
    // Show the 3D model view
    private func showModelView() {
        // If we already have exported the model
        if let exportedURL = self.exportedURL {
            // Add debug print to verify the file exists
            let fileExists = FileManager.default.fileExists(atPath: exportedURL.path)
            print("Model file exists: \(fileExists), at path: \(exportedURL.path)")
            
            // Try using QuickLook if we're having RealityKit issues
            let previewController = QLPreviewController()
            previewController.dataSource = self
            previewController.delegate = self
            present(previewController, animated: true)
            
            // After using QuickLook, attempt to use our custom viewer
            // displayModel(exportedURL)
        } else {
            // Export the model first if it hasn't been exported yet
            let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
            let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
            
            do {
                // Create export directory
                try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
                
                // Export the 3D model - use mesh instead of parametric for better visualization
                try finalResults?.export(to: destinationURL, exportOptions: .mesh)
                
                // Verify the file was created
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                print("Model file was created: \(fileExists), at path: \(destinationURL.path)")
                print("File size: \(try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] ?? 0)")
                
                // Save the exported URL and display the model
                self.exportedURL = destinationURL
                
                // Try using QuickLook if we're having RealityKit issues
                let previewController = QLPreviewController()
                previewController.dataSource = self
                previewController.delegate = self
                present(previewController, animated: true)
                
                // After using QuickLook, attempt to use our custom viewer
                // displayModel(destinationURL)
            } catch {
                print("Error exporting model: \(error)")
                
                // Show error alert
                let alert = UIAlertController(
                    title: "Export Error",
                    message: "Could not export 3D model: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
    
    // Display the 3D model using RealityKit
    private func displayModel(_ url: URL) {
        print("Displaying model from URL: \(url)")
        
        // Create view controller to display the 3D model
        let modelViewController = UIViewController()
        
        // Create a RealityKit ARView for displaying the 3D model
        let arView = ARView(frame: modelViewController.view.bounds)
        arView.automaticallyConfigureSession = false // We're not using AR tracking
        arView.environment.background = .color(.systemBackground) // Set background color
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        modelViewController.view.addSubview(arView)
        self.arView = arView
        
        // Debug info overlay
        addDebugOverlay(to: arView)
        
        // Create UI buttons
        setupModelViewButtons(on: modelViewController)
        
        // Create root anchor for the scene
        let modelAnchor = AnchorEntity(world: .zero)
        arView.scene.anchors.append(modelAnchor)
        self.rootAnchor = modelAnchor
        
        // Add a loading indicator
        let loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = arView.center
        loadingIndicator.startAnimating()
        arView.addSubview(loadingIndicator)
        
        // Present the view controller before loading the model to show loading indicator
        modelViewController.modalPresentationStyle = .fullScreen
        present(modelViewController, animated: true) {
            // Load the USDZ model using RealityKit after presenting
            self.loadRealityKitModel(url, anchor: modelAnchor, in: arView) {
                loadingIndicator.stopAnimating()
                loadingIndicator.removeFromSuperview()
            }
        }
    }
    
    // Add debug information overlay to help diagnose issues
    private func addDebugOverlay(to arView: ARView) {
        let debugLabel = UILabel()
        debugLabel.frame = CGRect(x: 10, y: 100, width: arView.bounds.width - 20, height: 100)
        debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        debugLabel.textColor = .white
        debugLabel.numberOfLines = 0
        debugLabel.font = .systemFont(ofSize: 12)
        debugLabel.text = "Debug info will appear here"
        debugLabel.isHidden = true // Hidden by default
        debugLabel.layer.cornerRadius = 5
        debugLabel.layer.masksToBounds = true
        debugLabel.textAlignment = .left
        arView.addSubview(debugLabel)
        
        // Debug button
        let debugButton = UIButton(type: .system)
        debugButton.setTitle("Debug", for: .normal)
        debugButton.backgroundColor = .darkGray
        debugButton.setTitleColor(.white, for: .normal)
        debugButton.layer.cornerRadius = 8
        debugButton.frame = CGRect(x: arView.bounds.width - 100, y: 90, width: 80, height: 30)
        debugButton.autoresizingMask = [.flexibleLeftMargin]
        
        // Add tap gesture to toggle debug overlay
        debugButton.addAction(UIAction { _ in
            debugLabel.isHidden = !debugLabel.isHidden
            if !debugLabel.isHidden {
                if let modelEntity = self.modelEntity {
                    let bounds = modelEntity.visualBounds(relativeTo: nil)
                    let size = bounds.max - bounds.min
                    debugLabel.text = "Model loaded: \(self.modelEntity != nil)\n"
                    debugLabel.text! += "Bounds: min=(\(bounds.min)), max=(\(bounds.max))\n"
                    debugLabel.text! += "Size: width=\(size.x), height=\(size.y), depth=\(size.z)\n"
                    debugLabel.text! += "Children count: \(modelEntity.children.count)"
                } else {
                    debugLabel.text = "Model not loaded or is nil"
                    
                    // Add a fallback visualization button if model is nil
                    let fallbackButton = UIButton(type: .system)
                    fallbackButton.setTitle("Show Fallback", for: .normal)
                    fallbackButton.backgroundColor = .systemRed
                    fallbackButton.setTitleColor(.white, for: .normal)
                    fallbackButton.layer.cornerRadius = 8
                    fallbackButton.frame = CGRect(x: 10, y: 210, width: 150, height: 40)
                    fallbackButton.addAction(UIAction { _ in
                        self.showModelLoadFailureOptions()
                    }, for: .touchUpInside)
                    
                    // Remove existing fallback button if any
                    arView.subviews.forEach { view in
                        if view.tag == 999 {
                            view.removeFromSuperview()
                        }
                    }
                    
                    fallbackButton.tag = 999
                    arView.addSubview(fallbackButton)
                }
            }
        }, for: .touchUpInside)
        
        arView.addSubview(debugButton)
    }
    
    // Set up UI buttons for model viewing
    private func setupModelViewButtons(on viewController: UIViewController) {
        // Add a close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.backgroundColor = .systemBlue
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.layer.cornerRadius = 8
        closeButton.frame = CGRect(x: 20, y: 40, width: 70, height: 40)
        closeButton.addTarget(self, action: #selector(dismissModelView), for: .touchUpInside)
        viewController.view.addSubview(closeButton)
        
        // Add a show dimensions button
        let dimensionsButton = UIButton(type: .system)
        dimensionsButton.setTitle("Show Dimensions", for: .normal)
        dimensionsButton.backgroundColor = .systemBlue
        dimensionsButton.setTitleColor(.white, for: .normal)
        dimensionsButton.layer.cornerRadius = 8
        dimensionsButton.frame = CGRect(x: viewController.view.bounds.width - 170, y: 40, width: 150, height: 40)
        dimensionsButton.addTarget(self, action: #selector(showDimensionsOverlay), for: .touchUpInside)
        dimensionsButton.autoresizingMask = [.flexibleLeftMargin]
        viewController.view.addSubview(dimensionsButton)
    }
    
    // Load the USDZ model using RealityKit
    private func loadRealityKitModel(_ url: URL, anchor: AnchorEntity, in arView: ARView, completion: @escaping () -> Void) {
        // Asynchronously load the model
        print("Loading model from URL: \(url)")
        
        // Try a different approach for loading the model
        do {
            // Check if the file exists and is readable
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            print("Model file exists before loading: \(fileExists), path: \(url.path)")
            
            if !fileExists {
                print("File doesn't exist at path: \(url.path)")
                throw NSError(domain: "FileError", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found"])
            }
            
            // Check file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? UInt64 {
                print("Model file size: \(fileSize) bytes")
                if fileSize < 100 {
                    print("Warning: File size is suspiciously small")
                }
            }
            
            // Try to load directly with synchronous method for debugging
            let entity = try Entity.load(contentsOf: url)
            print("Synchronously loaded entity: \(entity)")
            
            // Add entity to scene
            DispatchQueue.main.async {
                // Add to anchor
                anchor.addChild(entity)
                
                // Store reference to the model
                if let modelEntity = entity as? ModelEntity {
                    self.modelEntity = modelEntity
                    print("Entity is a ModelEntity")
                } else {
                    print("Entity is not a ModelEntity, type: \(type(of: entity))")
                    
                    // Try to find the first ModelEntity child
                    let modelEntities = entity.children.compactMap { $0 as? ModelEntity }
                    if let firstModelEntity = modelEntities.first {
                        print("Found ModelEntity child: \(firstModelEntity)")
                        self.modelEntity = firstModelEntity
                    } else {
                        print("No ModelEntity children found")
                        // Create a default visible entity to confirm anchoring works
                        let defaultEntity = ModelEntity(mesh: .generateBox(size: 0.5))
                        var material = PhysicallyBasedMaterial()
                        material.baseColor = .init(tint: .blue)
                        defaultEntity.model?.materials = [material]
                        entity.addChild(defaultEntity)
                    }
                }
                
                // Debug model structure
                self.debugEntityHierarchy(entity, level: 0)
                
                // Continue with setup as before
                self.configureModelEntity(entity, in: arView)
                self.configureCameraForModel(entity, in: arView)
                self.addBoundingBoxDebug(for: entity, in: anchor)
                self.setupLighting(for: arView)
                
                completion()
            }
        } catch {
            print("Error loading model synchronously: \(error)")
            
            // Fall back to async loading
            Entity.loadAsync(contentsOf: url).sink(
                receiveCompletion: { loadCompletion in
                    if case .failure(let error) = loadCompletion {
                        print("Error loading model asynchronously: \(error)")
                        
                        // Show an error alert if model loading fails
                        let alert = UIAlertController(title: "Loading Error", 
                                                    message: "Could not load 3D model: \(error.localizedDescription)", 
                                                    preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        arView.window?.rootViewController?.present(alert, animated: true)
                    }
                    completion()
                },
                receiveValue: { [weak self] entity in
                    guard let self = self else { return }
                    
                    print("Successfully loaded model entity asynchronously")
                    
                    DispatchQueue.main.async {
                        // Add to the scene directly
                        anchor.addChild(entity)
                        self.modelEntity = entity as? ModelEntity
                        
                        // Debug entity
                        self.debugEntityHierarchy(entity, level: 0)
                        
                        // Configure model and camera
                        self.configureModelEntity(entity, in: arView)
                        self.configureCameraForModel(entity, in: arView)
                        self.addBoundingBoxDebug(for: entity, in: anchor)
                        self.setupLighting(for: arView)
                    }
                }
            ).store(in: &cancellables)
        }
    }
    
    // Debug helper to print entity hierarchy
    private func debugEntityHierarchy(_ entity: Entity, level: Int) {
        let indent = String(repeating: "  ", count: level)
        let entityType = type(of: entity)
        
        if let modelEntity = entity as? ModelEntity {
            let hasMesh = modelEntity.model != nil
            let hasMaterials = modelEntity.model?.materials.count ?? 0 > 0
            print("\(indent)- \(entityType): hasMesh=\(hasMesh), materials=\(hasMaterials)")
            
            if let mesh = modelEntity.model?.mesh {
                print("\(indent)  - Mesh: bounds=\(mesh.bounds != nil)")
            }
        } else {
            print("\(indent)- \(entityType)")
        }
        
        // Print children recursively
        for (index, child) in entity.children.enumerated() {
            print("\(indent)  Child \(index):")
            debugEntityHierarchy(child, level: level + 1)
        }
    }
    
    // Setup lighting for the scene
    private func setupLighting(for arView: ARView) {
        // Add a directional light
        let directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(directionalLight)
        lightAnchor.position = [0, 2, 2]
        arView.scene.addAnchor(lightAnchor)
        
        // Add ambient light as well
        let ambientLight = PointLight()
        ambientLight.light.intensity = 500
        ambientLight.light.attenuationRadius = 10
        let ambientAnchor = AnchorEntity(world: .zero)
        ambientAnchor.addChild(ambientLight)
        ambientAnchor.position = [0, 0, 0]
        arView.scene.addAnchor(ambientAnchor)
        
        // Enhance the scene with additional lights
        enhanceSceneLighting(in: arView)
    }
    
    // Add a visual debugging box around the model
    private func addBoundingBoxDebug(for entity: Entity, in parent: Entity) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let size = bounds.max - bounds.min
        
        // Create box to show bounds - make it less obtrusive
        let boxMesh = MeshResource.generateBox(size: size)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .green.withAlphaComponent(0.1))
        material.metallic = 0.0
        material.roughness = 1.0
        
        let boxEntity = ModelEntity(mesh: boxMesh, materials: [material])
        boxEntity.position = (bounds.min + bounds.max) / 2
        
        // Add to parent
        parent.addChild(boxEntity)
    }
    
    // Configure the model entity for display
    private func configureModelEntity(_ entity: Entity, in arView: ARView) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let size = bounds.max - bounds.min
        
        print("Model size: \(size)")
        
        // Center the model - make sure it's at the origin for proper viewing
        let centeringOffset = (bounds.min + bounds.max) / 2
        entity.position = -centeringOffset
        
        // Auto-scale the model to fit the view nicely
        let maxDimension = max(size.x, max(size.y, size.z))
        
        // Scale to reasonable size in view (1.5 meter max dimension)
        if maxDimension > 1.5 {
            let scale = 1.5 / maxDimension
            entity.scale = [scale, scale, scale]
            print("Scaling model by \(scale)")
        } else if maxDimension < 0.5 {
            // If model is too small, scale it up
            let scale = 1.0 / maxDimension
            entity.scale = [scale, scale, scale]
            print("Scaling up small model by \(scale)")
        }
        
        // Add gesture interactions for manipulating the model
        setupGestureInteractions(for: arView)
    }
    
    // Set up gesture interactions for the 3D model
    private func setupGestureInteractions(for arView: ARView) {
        // Add rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        arView.addGestureRecognizer(rotationGesture)
        
        // Add pinch gesture for zooming
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)
        
        // Add pan gesture for moving the model
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        arView.addGestureRecognizer(panGesture)
    }
    
    // Handle rotation gesture
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let rootAnchor = self.rootAnchor else { return }
        
        if gesture.state == .changed {
            // Apply rotation to the root anchor
            rootAnchor.transform.rotation *= simd_quatf(angle: Float(gesture.rotation), axis: [0, 1, 0])
            gesture.rotation = 0
        }
    }
    
    // Handle pinch gesture
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let rootAnchor = self.rootAnchor else { return }
        
        if gesture.state == .changed {
            // Apply scale based on pinch
            let scale = Float(gesture.scale)
            rootAnchor.transform.scale *= scale
            gesture.scale = 1.0
        }
    }
    
    // Handle pan gesture
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let rootAnchor = self.rootAnchor else { return }
        
        if gesture.state == .changed {
            let translation = gesture.translation(in: gesture.view)
            
            // Convert screen points to 3D space
            // Scale factor to control sensitivity
            let translationScale: Float = 0.01
            
            // Apply translation to the root anchor
            rootAnchor.transform.translation += [
                Float(translation.x) * translationScale,
                -Float(translation.y) * translationScale,
                0
            ]
            
            gesture.setTranslation(.zero, in: gesture.view)
        }
    }
    
    // Configure the camera for viewing the model
    private func configureCameraForModel(_ entity: Entity, in arView: ARView) {
        let bounds = entity.visualBounds(relativeTo: nil)
        
        // Calculate a good camera position based on the model size
        let size = bounds.max - bounds.min
        let maxDimension = max(size.x, max(size.y, size.z))
        let cameraDistance = maxDimension * 1.5 // Closer view of the model
        
        // Position the camera for a nice view of the room
        let cameraEntity = PerspectiveCamera()
        cameraEntity.camera.fieldOfViewInDegrees = 60
        
        let cameraAnchor = AnchorEntity()
        cameraAnchor.addChild(cameraEntity)
        
        // Position at an angle for better view (isometric-like view)
        cameraAnchor.position = [
            cameraDistance * 0.8,  // X: Slightly to the right
            cameraDistance * 0.6,  // Y: Above the model
            cameraDistance * 0.8   // Z: In front of the model
        ]
        
        // Look at the center of the model
        cameraAnchor.look(at: [0, 0, 0], from: cameraAnchor.position, relativeTo: nil)
        
        arView.scene.addAnchor(cameraAnchor)
        
        // Enhance the scene with better lighting
        enhanceSceneLighting(in: arView)
    }
    
    // Add enhanced lighting to the scene for better visibility
    private func enhanceSceneLighting(in arView: ARView) {
        // Add multiple lights for better visibility
        
        // Add a fill light from the opposite side
        let fillLight = DirectionalLight()
        fillLight.light.intensity = 800
        let fillLightAnchor = AnchorEntity(world: .zero)
        fillLightAnchor.addChild(fillLight)
        fillLightAnchor.position = [-2, 2, -2]
        fillLightAnchor.look(at: [0, 0, 0], from: fillLightAnchor.position, relativeTo: nil)
        arView.scene.addAnchor(fillLightAnchor)
        
        // Add a rim light for highlighting edges
        let rimLight = SpotLight()
        rimLight.light.intensity = 700
        rimLight.light.innerAngleInDegrees = 30
        rimLight.light.outerAngleInDegrees = 60
        let rimLightAnchor = AnchorEntity(world: .zero)
        rimLightAnchor.addChild(rimLight)
        rimLightAnchor.position = [0, 3, -2]
        rimLightAnchor.look(at: [0, 0, 0], from: rimLightAnchor.position, relativeTo: nil)
        arView.scene.addAnchor(rimLightAnchor)
    }
    
    // Show dimensions in a simple 2D overlay
    @objc private func showDimensionsOverlay() {
        // Create alert with dimensions
        let alert = UIAlertController(title: "Room Dimensions", message: buildDimensionsText(), preferredStyle: .actionSheet)
        
        // For iPad compatibility
        if let popoverController = alert.popoverPresentationController {
            if let arView = self.arView {
                popoverController.sourceView = arView
                popoverController.sourceRect = CGRect(x: arView.bounds.midX, y: arView.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
        }
        
        // Add actions for different view options
        alert.addAction(UIAlertAction(title: "Show 3D Measurements", style: .default, handler: { [weak self] _ in
            self?.showMeasurementsIn3D()
        }))
        
        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
        
        if let arView = self.arView, let presenter = arView.window?.rootViewController {
            presenter.present(alert, animated: true)
        } else if let rootVC = UIApplication.shared.windows.first?.rootViewController {
            // Fallback to using the root view controller
            rootVC.present(alert, animated: true)
        }
    }
    
    // Build a text representation of dimensions
    private func buildDimensionsText() -> String {
        var text = "Room Dimensions:\n\n"
        
        // Room dimensions from model entity
        if let modelEntity = self.modelEntity {
            let bounds = modelEntity.visualBounds(relativeTo: nil)
            let size = bounds.max - bounds.min
            
            text += "Overall Room Dimensions:\n"
            text += "Width: \(convertToImperial(size.x))\n"
            text += "Height: \(convertToImperial(size.y))\n"
            text += "Depth: \(convertToImperial(size.z))\n\n"
        }
        
        // Detailed dimensions from RoomPlan data
        if let finalResults = finalResults {
            // Wall dimensions
            if !finalResults.walls.isEmpty {
                text += "Walls:\n"
                for (index, wall) in finalResults.walls.enumerated() {
                    text += "Wall \(index+1): \(convertToImperial(wall.dimensions.x)) × \(convertToImperial(wall.dimensions.y))\n"
                }
                text += "\n"
            }
            
            // Object dimensions
            if !finalResults.objects.isEmpty {
                text += "Furniture & Objects:\n"
                for (index, object) in finalResults.objects.enumerated() {
                    text += "\(object.category) \(index+1): \(convertToImperial(object.dimensions.x)) × \(convertToImperial(object.dimensions.y)) × \(convertToImperial(object.dimensions.z))\n"
                }
            }
        } else {
            text += "No detailed dimension data available from RoomPlan."
        }
        
        return text
    }
    
    // Show measurements in 3D space
    private func showMeasurementsIn3D() {
        guard let arView = self.arView, let rootAnchor = self.rootAnchor else { return }
        
        // Clear any existing measurement entities
        for entity in measurementEntities {
            entity.removeFromParent()
        }
        measurementEntities.removeAll()
        
        // Show a message to the user
        let alert = UIAlertController(
            title: "Measurements in 3D",
            message: "Adding 3D measurement indicators to the model. Note that these are simplified placeholders - in a production app, we would use custom materials with text textures.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let presenter = arView.window?.rootViewController {
            presenter.present(alert, animated: true) { [weak self] in
                self?.addMeasurementIndicators()
            }
        } else {
            addMeasurementIndicators()
        }
    }
    
    // Add simple measurement indicators to the model
    private func addMeasurementIndicators() {
        guard let rootAnchor = self.rootAnchor, let modelEntity = self.modelEntity else { return }
        
        // Add indicators at the corners of the model
        let bounds = modelEntity.visualBounds(relativeTo: nil)
        let min = bounds.min
        let max = bounds.max
        
        // Create corner indicators
        let corners = [
            SIMD3(min.x, min.y, min.z),
            SIMD3(max.x, min.y, min.z),
            SIMD3(min.x, max.y, min.z),
            SIMD3(max.x, max.y, min.z),
            SIMD3(min.x, min.y, max.z),
            SIMD3(max.x, min.y, max.z),
            SIMD3(min.x, max.y, max.z),
            SIMD3(max.x, max.y, max.z)
        ]
        
        // Add dimension indicators
        let width = max.x - min.x
        let height = max.y - min.y
        let depth = max.z - min.z
        
        // Add width indicator
        addDimensionIndicator(
            from: SIMD3(min.x, min.y, min.z),
            to: SIMD3(max.x, min.y, min.z),
            label: "Width: \(convertToImperial(width))",
            in: rootAnchor
        )
        
        // Add height indicator
        addDimensionIndicator(
            from: SIMD3(min.x, min.y, min.z),
            to: SIMD3(min.x, max.y, min.z),
            label: "Height: \(convertToImperial(height))",
            in: rootAnchor
        )
        
        // Add depth indicator
        addDimensionIndicator(
            from: SIMD3(min.x, min.y, min.z),
            to: SIMD3(min.x, min.y, max.z),
            label: "Depth: \(convertToImperial(depth))",
            in: rootAnchor
        )
        
        // Add indicators for furniture if available
        if let finalResults = finalResults {
            for object in finalResults.objects {
                addObjectIndicator(object, to: rootAnchor)
            }
        }
    }
    
    // Add a dimension indicator between two points
    private func addDimensionIndicator(from start: SIMD3<Float>, to end: SIMD3<Float>, label: String, in parent: Entity) {
        // Create a sphere at each end
        let startSphere = createSphereIndicator(color: .systemBlue)
        startSphere.position = start
        parent.addChild(startSphere)
        
        let endSphere = createSphereIndicator(color: .systemBlue)
        endSphere.position = end
        parent.addChild(endSphere)
        
        // Create a line between them
        let lineMesh = MeshResource.generateBox(size: 0.01)
        var lineMaterial = PhysicallyBasedMaterial()
        lineMaterial.baseColor = .init(tint: .white)
        lineMaterial.metallic = 0.0
        lineMaterial.roughness = 1.0
        
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
        let midPoint = (start + end) / 2
        lineEntity.position = midPoint
        
        // Calculate rotation and scale to make the box into a line
        let distance = length(end - start)
        let direction = normalize(end - start)
        
        // Set up orientation to align with the direction
        if abs(direction.y) > 0.99 {
            // Vertical line
            lineEntity.transform.scale = [0.01, distance, 0.01]
        } else if abs(direction.z) > 0.99 {
            // Depth line
            lineEntity.transform.scale = [0.01, 0.01, distance]
        } else {
            // Width line
            lineEntity.transform.scale = [distance, 0.01, 0.01]
        }
        
        parent.addChild(lineEntity)
        measurementEntities.append(startSphere)
        measurementEntities.append(endSphere)
        measurementEntities.append(lineEntity)
        
        // Add a label at the midpoint
        let labelEntity = createTextModelEntity(text: label, color: .white)
        labelEntity.position = midPoint + SIMD3(0, 0.05, 0)
        labelEntity.scale = [0.3, 0.3, 0.3]
        addBillboardConstraint(to: labelEntity)
        
        parent.addChild(labelEntity)
        measurementEntities.append(labelEntity)
    }
    
    // Add an indicator for a furniture object
    private func addObjectIndicator(_ object: CapturedRoom.Object, to parent: Entity) {
        let transform = object.transform
        let position = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // Create indicator for object
        let indicator = createSphereIndicator(color: .systemGreen)
        indicator.position = position
        
        // Add a label
        let label = "\(object.category): \(convertToImperial(object.dimensions.x)) × \(convertToImperial(object.dimensions.y)) × \(convertToImperial(object.dimensions.z))"
        let labelEntity = createTextModelEntity(text: label, color: .white)
        labelEntity.position = position + SIMD3(0, object.dimensions.y/2 + 0.1, 0)
        labelEntity.scale = [0.3, 0.3, 0.3]
        addBillboardConstraint(to: labelEntity)
        
        parent.addChild(indicator)
        parent.addChild(labelEntity)
        measurementEntities.append(indicator)
        measurementEntities.append(labelEntity)
    }
    
    // Create a sphere indicator
    private func createSphereIndicator(color: UIColor) -> ModelEntity {
        let sphereMesh = MeshResource.generateSphere(radius: 0.02)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = 0.0
        material.roughness = 1.0
        return ModelEntity(mesh: sphereMesh, materials: [material])
    }
    
    // Add billboard constraint to make text always face the camera
    private func addBillboardConstraint(to entity: Entity) {
        // Add a billboard constraint - this makes the entity always face the camera
        entity.components.set(BillboardComponent())
        
        // Subscribe to scene updates
        if let arView = self.arView {
            arView.scene.subscribe(to: SceneEvents.Update.self) { [weak entity] event in
                guard let entity = entity else { return }
                
                // Make entity face the camera - BillboardComponent isn't always reliable
                // Use the camera position from the ARView
                let camera = arView.cameraTransform.translation
                let entityWorldPosition = entity.position(relativeTo: nil)
                
                // Create a look-at transform that orients the entity toward the camera
                entity.look(
                    at: camera,
                    from: entityWorldPosition,
                    relativeTo: nil
                )
            }.store(in: &cancellables)
        }
    }
    
    // Create a text entity using a simple approach (works with RealityKit)
    private func createTextModelEntity(text: String, color: UIColor) -> ModelEntity {
        // Calculate approx size needed for text
        let textSize = text.size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium)
        ])
        
        // Add some padding
        let width = Float(textSize.width + 20) / 1000
        let height = Float(textSize.height + 16) / 1000
        
        // Create a background plane
        let backgroundMesh = MeshResource.generatePlane(width: width, height: height)
        var backgroundMaterial = PhysicallyBasedMaterial()
        backgroundMaterial.baseColor = .init(tint: .black.withAlphaComponent(0.7))
        backgroundMaterial.metallic = 0.0
        backgroundMaterial.roughness = 1.0
        
        // Create the entity with the background
        let entity = ModelEntity(mesh: backgroundMesh, materials: [backgroundMaterial])
        
        // Create a text entity as a child with the supplied text
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.01, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        var textMaterial = PhysicallyBasedMaterial()
        textMaterial.baseColor = .init(tint: color)
        textMaterial.metallic = 0.0
        textMaterial.roughness = 1.0
        
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = [0, 0, 0.001] // Position slightly in front of background
        entity.addChild(textEntity)
        
        return entity
    }
    
    // Convert meters to imperial units (feet and inches) with precision to 1/16th inch
    private func convertToImperial(_ meters: Float) -> String {
        let totalInches = meters * 39.3701
        let feet = Int(totalInches / 12)
        let wholeInches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        
        // Calculate fractional inches to 1/16th precision
        let fractionDenominator = 16
        let fractionNumerator = Int(round((totalInches - floor(totalInches)) * Float(fractionDenominator)))
        
        // Simplify the fraction if possible
        var simplifiedNumerator = fractionNumerator
        var simplifiedDenominator = fractionDenominator
        
        // If numerator is 0, don't show fraction
        if simplifiedNumerator == 0 {
            if feet > 0 {
                return "\(feet)'\(wholeInches)\""
            } else {
                return "\(wholeInches)\""
            }
        }
        
        // If numerator equals denominator, add to whole inches
        if simplifiedNumerator == simplifiedDenominator {
            let adjustedInches = wholeInches + 1
            if adjustedInches == 12 {
                return "\(feet + 1)'0\""
            }
            if feet > 0 {
                return "\(feet)'\(adjustedInches)\""
            } else {
                return "\(adjustedInches)\""
            }
        }
        
        // Simplify the fraction
        func gcd(_ a: Int, _ b: Int) -> Int {
            var a = a
            var b = b
            while b != 0 {
                let temp = b
                b = a % b
                a = temp
            }
            return a
        }
        
        let divisor = gcd(simplifiedNumerator, simplifiedDenominator)
        if divisor > 1 {
            simplifiedNumerator /= divisor
            simplifiedDenominator /= divisor
        }
        
        // Format the result
        if feet > 0 {
            return "\(feet)'\(wholeInches) \(simplifiedNumerator)/\(simplifiedDenominator)\""
        } else {
            return "\(wholeInches) \(simplifiedNumerator)/\(simplifiedDenominator)\""
        }
    }
    
    // Dismiss the model view
    @objc private func dismissModelView() {
        dismiss(animated: true)
    }
    
    // Update UI for active scanning state
    private func setActiveNavBar() {
        UIView.animate(withDuration: 1.0, animations: {
            self.cancelButton?.tintColor = .white
            self.doneButton?.tintColor = .white
            self.exportButton?.alpha = 0.0
            self.viewButton?.alpha = 0.0
            self.viewModeSegmentControl?.alpha = 0.0
        }, completion: { complete in
            self.exportButton?.isHidden = true
            self.viewButton?.isHidden = true
            self.viewModeSegmentControl?.isHidden = true
        })
    }
    
    // Update UI for completed scanning state
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        self.viewButton?.isHidden = false
        self.viewModeSegmentControl?.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.cancelButton?.tintColor = .systemBlue
            self.doneButton?.tintColor = .systemBlue
            self.exportButton?.alpha = 1.0
            self.viewButton?.alpha = 1.0
            self.viewModeSegmentControl?.alpha = 1.0
        }
    }
    
    // MARK: - QLPreviewControllerDataSource
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return exportedURL != nil ? 1 : 0
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return exportedURL! as QLPreviewItem
    }
    
    // MARK: - QLPreviewControllerDelegate
    
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        // Ask if user wants to try the custom viewer
        let alert = UIAlertController(
            title: "Try Custom Viewer",
            message: "Would you like to try our custom 3D viewer with dimension markers?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { [weak self] _ in
            if let url = self?.exportedURL {
                self?.displayModel(url)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "No", style: .cancel))
        
        present(alert, animated: true)
    }
    
    // Create a fallback visualization if the model doesn't load properly
    private func createFallbackVisualization() {
        guard let rootAnchor = self.rootAnchor, let arView = self.arView, let finalResults = self.finalResults else {
            print("Cannot create fallback - missing required objects")
            return
        }
        
        print("Creating fallback visualization from RoomPlan data")
        
        // Debug print object categories to find available ones
        if !finalResults.objects.isEmpty {
            print("Available object categories:")
            for obj in finalResults.objects {
                print("- \(obj.category)")
            }
        }
        
        // Create a basic floor
        // Get dimensions from the walls to approximate floor size
        var maxX: Float = 0
        var maxZ: Float = 0
        
        // Look through walls to estimate room size
        for wall in finalResults.walls {
            maxX = max(maxX, wall.dimensions.x)
            maxZ = max(maxZ, wall.dimensions.z)
        }
        
        // Create floor with estimated dimensions
        let floorMesh = MeshResource.generatePlane(width: maxX > 0 ? maxX : 3.0, depth: maxZ > 0 ? maxZ : 3.0)
        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: .lightGray)
        floorMaterial.metallic = 0.0
        floorMaterial.roughness = 0.8
        
        let floorEntity = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        rootAnchor.addChild(floorEntity)
        
        print("Added floor with estimated size: \(floorEntity.scale.x) x \(floorEntity.scale.z)")
        
        // Create walls
        for (index, wall) in finalResults.walls.enumerated() {
            let wallMesh = MeshResource.generatePlane(width: wall.dimensions.x, height: wall.dimensions.y)
            var wallMaterial = PhysicallyBasedMaterial()
            wallMaterial.baseColor = .init(tint: .white)
            wallMaterial.metallic = 0.0
            wallMaterial.roughness = 0.9
            
            let wallEntity = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
            
            // Position based on transform
            let transform = wall.transform
            wallEntity.transform.matrix = transform
            
            rootAnchor.addChild(wallEntity)
            print("Added wall \(index): \(wall.dimensions.x) x \(wall.dimensions.y)")
        }
        
        // Create objects (furniture)
        for (index, object) in finalResults.objects.enumerated() {
            // Create a box for each piece of furniture
            let objMesh = MeshResource.generateBox(
                width: object.dimensions.x,
                height: object.dimensions.y,
                depth: object.dimensions.z
            )
            
            // Choose color based on category string rather than enum
            var color: UIColor
            let categoryString = String(describing: object.category)
            if categoryString.contains("storage") || categoryString.contains("television") {
                color = .brown
            } else if categoryString.contains("furniture") {
                color = .blue
            } else if categoryString.contains("opening") {
                color = .purple
            } else if categoryString.contains("door") {
                color = .orange
            } else if categoryString.contains("window") {
                color = .cyan
            } else {
                color = .darkGray
            }
            
            var objMaterial = PhysicallyBasedMaterial()
            objMaterial.baseColor = .init(tint: color.withAlphaComponent(0.7))
            objMaterial.metallic = 0.1
            objMaterial.roughness = 0.8
            
            let objEntity = ModelEntity(mesh: objMesh, materials: [objMaterial])
            
            // Position based on transform
            let transform = object.transform
            objEntity.transform.matrix = transform
            
            rootAnchor.addChild(objEntity)
            print("Added object \(index): \(object.category) - \(object.dimensions.x) x \(object.dimensions.y) x \(object.dimensions.z)")
            
            // Add label
            let labelText = "\(object.category)"
            let labelEntity = createTextModelEntity(text: labelText, color: .white)
            labelEntity.position = [0, object.dimensions.y/2 + 0.05, 0] 
            labelEntity.scale = [0.2, 0.2, 0.2]
            addBillboardConstraint(to: labelEntity)
            objEntity.addChild(labelEntity)
        }
        
        // Set ourselves as the model entity
        if let firstEntity = rootAnchor.children.first as? ModelEntity {
            self.modelEntity = firstEntity
        }
        
        // Set up lighting
        setupLighting(for: arView)
        
        // Setup camera
        let entity = rootAnchor
        configureCameraForModel(entity, in: arView)
    }
    
    // Add fallback alert dialog that gives options when model doesn't load
    private func showModelLoadFailureOptions() {
        guard let arView = self.arView else { return }
        
        let alert = UIAlertController(
            title: "Model Loading Issues",
            message: "The 3D model could not be properly loaded. How would you like to proceed?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Try Basic Visualization", style: .default, handler: { [weak self] _ in
            self?.createFallbackVisualization()
        }))
        
        alert.addAction(UIAlertAction(title: "Return to QuickLook", style: .default, handler: { [weak self] _ in
            if let url = self?.exportedURL {
                let previewController = QLPreviewController()
                previewController.dataSource = self
                previewController.delegate = self
                arView.window?.rootViewController?.present(previewController, animated: true)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Close Viewer", style: .cancel, handler: { [weak self] _ in
            self?.dismiss(animated: true)
        }))
        
        arView.window?.rootViewController?.present(alert, animated: true)
    }
}

