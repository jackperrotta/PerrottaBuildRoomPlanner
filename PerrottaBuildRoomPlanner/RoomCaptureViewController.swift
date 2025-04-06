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

// This view controller implements two important delegate protocols:
// - RoomCaptureViewDelegate: For UI events and visual feedback during scanning
// - RoomCaptureSessionDelegate: For managing the scanning session
class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    
    @IBOutlet var exportButton: UIButton? // Button to export the captured room data
    
    // View button from storyboard
    @IBOutlet var viewButton: UIButton?
    
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
    
    // View the 3D model in the app
    @IBAction func viewModel(_ sender: UIButton) {
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
        let transform = simd_float4x4(object.transform)
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
        }, completion: { complete in
            self.exportButton?.isHidden = true
            self.viewButton?.isHidden = true
        })
    }
    
    // Update UI for completed scanning state
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        self.viewButton?.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.cancelButton?.tintColor = .systemBlue
            self.doneButton?.tintColor = .systemBlue
            self.exportButton?.alpha = 1.0
            self.viewButton?.alpha = 1.0
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
            let transform = simd_float4x4(wall.transform)
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
            let transform = simd_float4x4(object.transform)
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

