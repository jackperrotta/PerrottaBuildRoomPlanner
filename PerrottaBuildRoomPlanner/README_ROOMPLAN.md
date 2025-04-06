# RoomPlan Example App Documentation

This document provides an in-depth explanation of Apple's RoomPlan SDK and how it's used in this example project.

## What is RoomPlan?

RoomPlan is an Apple framework introduced in iOS 16 that uses the device's LiDAR Scanner and camera to create 3D floor plans of interior rooms. The framework provides a structured scanning experience that guides users to capture rooms, recognizing architectural elements like:

- Walls
- Windows
- Doors
- Openings between rooms
- Furniture items (tables, sofas, beds, etc.)

## Requirements

To use RoomPlan, you need:

1. iOS 16.0 or later
2. A device with a LiDAR Scanner (iPhone Pro or iPad Pro models with LiDAR)
3. ARKit compatibility

## Project Structure

This example app demonstrates how to use RoomPlan through a simple flow:

1. **OnboardingViewController**: The entry point where users can start a new scan
2. **RoomCaptureViewController**: The main controller that handles the scanning process
3. **Export functionality**: Allows users to save and share the captured room model

## Key RoomPlan Components

### RoomCaptureView

`RoomCaptureView` is the main UI component that provides the AR camera feed and visualizes the scanning process. It displays:

- Live camera feed with AR overlays
- Visual feedback of detected architectural elements and objects
- Guiding instructions for the user

```swift
// Create a RoomCaptureView
let roomCaptureView = RoomCaptureView(frame: view.bounds)
```

### RoomCaptureSession

`RoomCaptureSession` manages the actual room scanning process. It controls:

- Starting and stopping the scan
- Processing the captured data
- Providing the results

```swift
// Configure and start a room capture session
let configuration = RoomCaptureSession.Configuration()
roomCaptureView.captureSession.run(configuration: configuration)

// Stop the session when done
roomCaptureView.captureSession.stop()
```

### RoomCaptureSession.Configuration

This class allows you to customize the scanning experience with options like:

- Types of objects to detect
- Optimization priorities (speed vs. accuracy)
- Scan quality settings

The default configuration works well for most cases, but you can customize it:

```swift
let configuration = RoomCaptureSession.Configuration()
// Customize configuration properties if needed
```

### Delegate Protocols

There are two key delegate protocols:

1. **RoomCaptureViewDelegate**: For UI-related events and visual guidance
   - `captureView(shouldPresent:error:)`: Decide whether to process the captured data
   - `captureView(didPresent:error:)`: Access the final processed results

2. **RoomCaptureSessionDelegate**: For data capture events (not used in this example)
   - Can receive callbacks about the ongoing scanning process

### Data Models

RoomPlan provides structured data models:

- **CapturedRoomData**: Raw data collected during scanning
- **CapturedRoom**: Processed final model containing:
  - Surfaces (walls, floors, ceilings)
  - Openings (doors, windows)
  - Objects (furniture)

### Export Options

RoomPlan can export 3D models in USDZ format with different options:

- `.parametric`: Structured model with distinct architectural elements (walls, doors, etc.)
- `.mesh`: Simple 3D mesh representation
- `.all`: Both parametric and mesh models

```swift
// Export the room model
try capturedRoom.export(to: fileURL, exportOptions: .parametric)
```

## Implementation Flow

1. The app checks if the device supports RoomPlan
2. The user taps "Start Scan" in the onboarding screen
3. The RoomCaptureViewController is presented
4. The room scanning session begins automatically
5. The user scans the room, guided by AR feedback
6. The user taps "Done" to finish scanning
7. RoomPlan processes the captured data
8. The user can export the 3D model as a USDZ file

## Building Your Own App with RoomPlan

When building your own app with RoomPlan, consider:

1. **User guidance**: Provide clear instructions for the scanning process
2. **Feedback**: Show visual cues about what's been detected and what's still needed
3. **Processing**: Handle the time needed to process room data (it may take several seconds)
4. **Export and usage**: Decide how to use the exported model in your app's context
5. **Error handling**: Account for scanning failures or unsupported devices

## Additional Resources

- [Apple Developer Documentation: RoomPlan](https://developer.apple.com/documentation/roomplan)
- [WWDC22 Session: Create parametric 3D room scans with RoomPlan](https://developer.apple.com/videos/play/wwdc2022/10127/)
- [Apple Human Interface Guidelines for Scanning](https://developer.apple.com/design/human-interface-guidelines/technologies/augmented-reality/scanning)

## Customizing This Example

To extend this example app, you might:

1. Add persistence to save scanned rooms
2. Implement a gallery to view past scans
3. Add custom visualization of the room model
4. Implement additional processing of the captured data
5. Integrate with other apps or services 