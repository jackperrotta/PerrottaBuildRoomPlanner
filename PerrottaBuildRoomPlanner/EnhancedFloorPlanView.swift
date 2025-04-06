/*
 EnhancedFloorPlanView.swift
 PerrottaBuildRoomPlanner
 
 A SwiftUI-based floor plan view that renders RoomPlan data using Canvas.
 This view allows for zooming, panning, and displays architectural elements like walls,
 doors, windows, and furniture with proper dimensions.
 */

import SwiftUI
import RoomPlan

// MARK: - Data Models

/// Represents a wall segment in the floor plan
struct Wall: Identifiable {
    let id = UUID()
    let startPoint: CGPoint  // Starting point
    let endPoint: CGPoint    // Ending point
    let thickness: CGFloat   // Wall thickness
    
    // Optional properties
    let isBoundary: Bool     // Whether this is an exterior wall
    
    init(from point: CGPoint, to endPoint: CGPoint, thickness: CGFloat = 0.1, isBoundary: Bool = true) {
        self.startPoint = point
        self.endPoint = endPoint
        self.thickness = thickness
        self.isBoundary = isBoundary
    }
    
    // Create a wall from RoomPlan wall data
    init(roomPlanWall: CapturedRoom.Wall, origin: CGPoint = .zero, scale: CGFloat = 100) {
        // Extract position and dimensions from the transform
        let position = CGPoint(
            x: CGFloat(roomPlanWall.transform.columns.3.x) * scale + origin.x,
            y: CGFloat(roomPlanWall.transform.columns.3.z) * scale + origin.y
        )
        
        // Extract rotation angle from the transform matrix
        let angle = atan2(
            CGFloat(roomPlanWall.transform.columns.0.z),
            CGFloat(roomPlanWall.transform.columns.0.x)
        )
        
        // Get dimensions from RoomPlan data
        let length = CGFloat(roomPlanWall.dimensions.x) * scale
        let thickness = CGFloat(roomPlanWall.dimensions.y) * scale
        
        // Calculate start and end points based on position, angle, and length
        let halfLength = length / 2
        let deltaX = halfLength * cos(angle)
        let deltaY = halfLength * sin(angle)
        
        self.startPoint = CGPoint(x: position.x - deltaX, y: position.y - deltaY)
        self.endPoint = CGPoint(x: position.x + deltaX, y: position.y + deltaY)
        self.thickness = thickness
        self.isBoundary = true  // Most RoomPlan walls are boundaries
    }
    
    // Get the path for drawing the wall
    func path() -> Path {
        // Calculate the direction vector
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        
        // Normalize direction vector
        let dirX = dx / length
        let dirY = dy / length
        
        // Calculate perpendicular vector (90 degrees rotated)
        let perpX = -dirY
        let perpY = dirX
        
        // Calculate the four corners of the wall
        let halfThickness = thickness / 2
        let p1 = CGPoint(x: startPoint.x + perpX * halfThickness, y: startPoint.y + perpY * halfThickness)
        let p2 = CGPoint(x: startPoint.x - perpX * halfThickness, y: startPoint.y - perpY * halfThickness)
        let p3 = CGPoint(x: endPoint.x - perpX * halfThickness, y: endPoint.y - perpY * halfThickness)
        let p4 = CGPoint(x: endPoint.x + perpX * halfThickness, y: endPoint.y + perpY * halfThickness)
        
        // Create path
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.closeSubpath()
        
        return path
    }
}

/// Represents a door in the floor plan
struct Door: Identifiable {
    let id = UUID()
    let center: CGPoint      // Center point of the door
    let width: CGFloat       // Door width
    let angle: CGFloat       // Rotation angle in radians
    let isOpen: Bool         // Whether the door is shown open
    
    // Create a door from RoomPlan data
    init(roomPlanDoor: CapturedRoom.Door, origin: CGPoint = .zero, scale: CGFloat = 100) {
        // Extract position from transform
        let position = CGPoint(
            x: CGFloat(roomPlanDoor.transform.columns.3.x) * scale + origin.x,
            y: CGFloat(roomPlanDoor.transform.columns.3.z) * scale + origin.y
        )
        
        // Extract angle from transform
        let angle = atan2(
            CGFloat(roomPlanDoor.transform.columns.0.z),
            CGFloat(roomPlanDoor.transform.columns.0.x)
        )
        
        self.center = position
        self.width = CGFloat(roomPlanDoor.dimensions.x) * scale
        self.angle = angle
        
        // Determine if door is open based on confidence
        // This is just a heuristic - RoomPlan doesn't explicitly tell us if a door is open
        self.isOpen = roomPlanDoor.confidence > 0.7
    }
    
    // Get the path for drawing the door
    func path() -> Path {
        let halfWidth = width / 2
        
        var path = Path()
        
        if isOpen {
            // Draw an open door (a door with a swing arc)
            let swingRadius = width * 0.9
            
            // Door frame
            path.move(to: rotate(point: CGPoint(x: -halfWidth, y: 0), angle: angle, around: center))
            path.addLine(to: rotate(point: CGPoint(x: halfWidth, y: 0), angle: angle, around: center))
            
            // Door swing arc
            path.move(to: rotate(point: CGPoint(x: halfWidth, y: 0), angle: angle, around: center))
            path.addArc(
                center: rotate(point: CGPoint(x: halfWidth, y: 0), angle: angle, around: center),
                radius: swingRadius,
                startAngle: .degrees(Double(angle * 180 / .pi)),
                endAngle: .degrees(Double(angle * 180 / .pi) + 90),
                clockwise: false
            )
        } else {
            // Draw a closed door (a simple rectangle)
            let thickness = width * 0.1
            
            // Create rectangle for door
            path.move(to: rotate(point: CGPoint(x: -halfWidth, y: -thickness/2), angle: angle, around: center))
            path.addLine(to: rotate(point: CGPoint(x: halfWidth, y: -thickness/2), angle: angle, around: center))
            path.addLine(to: rotate(point: CGPoint(x: halfWidth, y: thickness/2), angle: angle, around: center))
            path.addLine(to: rotate(point: CGPoint(x: -halfWidth, y: thickness/2), angle: angle, around: center))
            path.closeSubpath()
        }
        
        return path
    }
    
    // Helper to rotate a point around a center
    private func rotate(point: CGPoint, angle: CGFloat, around center: CGPoint) -> CGPoint {
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let x = (point.x * cosAngle - point.y * sinAngle) + center.x
        let y = (point.x * sinAngle + point.y * cosAngle) + center.y
        return CGPoint(x: x, y: y)
    }
}

/// Represents a window in the floor plan
struct Window: Identifiable {
    let id = UUID()
    let center: CGPoint      // Center point
    let width: CGFloat       // Width of the window
    let thickness: CGFloat   // Thickness/depth
    let angle: CGFloat       // Rotation in radians
    
    // Create a window from RoomPlan data
    init(roomPlanWindow: CapturedRoom.Opening, origin: CGPoint = .zero, scale: CGFloat = 100) {
        // Extract position
        let position = CGPoint(
            x: CGFloat(roomPlanWindow.transform.columns.3.x) * scale + origin.x,
            y: CGFloat(roomPlanWindow.transform.columns.3.z) * scale + origin.y
        )
        
        // Extract angle
        let angle = atan2(
            CGFloat(roomPlanWindow.transform.columns.0.z),
            CGFloat(roomPlanWindow.transform.columns.0.x)
        )
        
        self.center = position
        self.width = CGFloat(roomPlanWindow.dimensions.x) * scale
        self.thickness = CGFloat(max(roomPlanWindow.dimensions.y, 0.05)) * scale
        self.angle = angle
    }
    
    // Get the path for drawing the window
    func path() -> Path {
        let halfWidth = width / 2
        let halfThickness = thickness / 2
        
        // Create the window rectangle
        let p1 = rotate(point: CGPoint(x: -halfWidth, y: -halfThickness), angle: angle, around: center)
        let p2 = rotate(point: CGPoint(x: halfWidth, y: -halfThickness), angle: angle, around: center)
        let p3 = rotate(point: CGPoint(x: halfWidth, y: halfThickness), angle: angle, around: center)
        let p4 = rotate(point: CGPoint(x: -halfWidth, y: halfThickness), angle: angle, around: center)
        
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.closeSubpath()
        
        // Add window panes (just visual detail)
        let midX = (p1.x + p3.x) / 2
        let midY = (p1.y + p3.y) / 2
        
        path.move(to: CGPoint(x: midX, y: p1.y))
        path.addLine(to: CGPoint(x: midX, y: p3.y))
        
        return path
    }
    
    // Helper to rotate a point around a center
    private func rotate(point: CGPoint, angle: CGFloat, around center: CGPoint) -> CGPoint {
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let x = (point.x * cosAngle - point.y * sinAngle) + center.x
        let y = (point.x * sinAngle + point.y * cosAngle) + center.y
        return CGPoint(x: x, y: y)
    }
}

/// Represents furniture in the floor plan
struct Furniture: Identifiable {
    let id = UUID()
    let center: CGPoint      // Center position
    let width: CGFloat       // Width
    let depth: CGFloat       // Depth
    let angle: CGFloat       // Rotation angle
    let category: String     // Furniture category (bed, table, etc.)
    
    // Create furniture from RoomPlan object data
    init(roomPlanObject: CapturedRoom.Object, origin: CGPoint = .zero, scale: CGFloat = 100) {
        // Extract position
        let position = CGPoint(
            x: CGFloat(roomPlanObject.transform.columns.3.x) * scale + origin.x,
            y: CGFloat(roomPlanObject.transform.columns.3.z) * scale + origin.y
        )
        
        // Extract angle
        let angle = atan2(
            CGFloat(roomPlanObject.transform.columns.0.z),
            CGFloat(roomPlanObject.transform.columns.0.x)
        )
        
        self.center = position
        self.width = CGFloat(roomPlanObject.dimensions.x) * scale
        self.depth = CGFloat(roomPlanObject.dimensions.z) * scale
        self.angle = angle
        self.category = String(describing: roomPlanObject.category)
    }
    
    // Get the path for drawing the furniture
    func path() -> Path {
        let halfWidth = width / 2
        let halfDepth = depth / 2
        
        // Create a rectangle for the furniture
        let p1 = rotate(point: CGPoint(x: -halfWidth, y: -halfDepth), angle: angle, around: center)
        let p2 = rotate(point: CGPoint(x: halfWidth, y: -halfDepth), angle: angle, around: center)
        let p3 = rotate(point: CGPoint(x: halfWidth, y: halfDepth), angle: angle, around: center)
        let p4 = rotate(point: CGPoint(x: -halfWidth, y: halfDepth), angle: angle, around: center)
        
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.closeSubpath()
        
        // Depending on the category, add details to the path
        switch category {
        case "bed":
            // Add a pillow shape
            let pillow1 = rotate(point: CGPoint(x: -halfWidth + width * 0.2, y: -halfDepth + depth * 0.2), angle: angle, around: center)
            let pillow2 = rotate(point: CGPoint(x: 0, y: -halfDepth + depth * 0.2), angle: angle, around: center)
            
            path.move(to: p1)
            path.addLine(to: pillow1)
            path.addLine(to: pillow2)
            path.addLine(to: p2)
            
        case "table", "desk":
            // Add a simple cross to represent a table
            let center1 = rotate(point: CGPoint(x: -halfWidth * 0.5, y: 0), angle: angle, around: center)
            let center2 = rotate(point: CGPoint(x: halfWidth * 0.5, y: 0), angle: angle, around: center)
            
            path.move(to: center1)
            path.addLine(to: center2)
            
        case "chair", "sofa":
            // Add a simple back rest line
            let back1 = rotate(point: CGPoint(x: -halfWidth + width * 0.2, y: -halfDepth + depth * 0.2), angle: angle, around: center)
            let back2 = rotate(point: CGPoint(x: halfWidth - width * 0.2, y: -halfDepth + depth * 0.2), angle: angle, around: center)
            
            path.move(to: back1)
            path.addLine(to: back2)
            
        default:
            // No special details
            break
        }
        
        return path
    }
    
    // Helper to rotate a point around a center
    private func rotate(point: CGPoint, angle: CGFloat, around center: CGPoint) -> CGPoint {
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let x = (point.x * cosAngle - point.y * sinAngle) + center.x
        let y = (point.x * sinAngle + point.y * cosAngle) + center.y
        return CGPoint(x: x, y: y)
    }
}

/// Represents a dimension marker
struct DimensionMarker: Identifiable {
    let id = UUID()
    let startPoint: CGPoint
    let endPoint: CGPoint
    let text: String
    let offset: CGFloat = 15
    
    // Get the path for drawing the dimension line
    func path() -> Path {
        var path = Path()
        
        // Draw main dimension line
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        
        // Calculate perpendicular vector for dimension ticks
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        
        // Guard against division by zero
        guard length > 0 else { return path }
        
        // Normalize and rotate 90 degrees for perpendicular vector
        let perpX = -dy / length * offset
        let perpY = dx / length * offset
        
        // Draw ticks at start and end
        path.move(to: startPoint)
        path.addLine(to: CGPoint(x: startPoint.x + perpX, y: startPoint.y + perpY))
        
        path.move(to: endPoint)
        path.addLine(to: CGPoint(x: endPoint.x + perpX, y: endPoint.y + perpY))
        
        return path
    }
    
    // Get the position for drawing the dimension text
    func textPosition() -> CGPoint {
        let midX = (startPoint.x + endPoint.x) / 2
        let midY = (startPoint.y + endPoint.y) / 2
        
        // Calculate perpendicular offset for text positioning
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        
        // Guard against division by zero
        guard length > 0 else { return CGPoint(x: midX, y: midY) }
        
        // Calculate perpendicular vector
        let perpX = -dy / length * offset * 1.5
        let perpY = dx / length * offset * 1.5
        
        return CGPoint(x: midX + perpX, y: midY + perpY)
    }
}

/// Wrapper for a collection of floor plan elements
struct FloorPlanData {
    var walls: [Wall] = []
    var doors: [Door] = []
    var windows: [Window] = []
    var furniture: [Furniture] = []
    var dimensions: [DimensionMarker] = []
    var bounds: CGRect = .zero
    
    // Create from RoomPlan captured room data
    init(capturedRoom: CapturedRoom, origin: CGPoint = .zero, scale: CGFloat = 100, showDimensions: Bool = true) {
        // Process walls
        walls = capturedRoom.walls.map { Wall(roomPlanWall: $0, origin: origin, scale: scale) }
        
        // Process doors
        doors = capturedRoom.doors.map { Door(roomPlanDoor: $0, origin: origin, scale: scale) }
        
        // Process windows
        windows = capturedRoom.openings.map { Window(roomPlanWindow: $0, origin: origin, scale: scale) }
        
        // Process furniture
        furniture = capturedRoom.objects.map { Furniture(roomPlanObject: $0, origin: origin, scale: scale) }
        
        // Calculate bounds
        calculateBounds()
        
        // Create dimension markers if requested
        if showDimensions {
            createDimensions()
        }
    }
    
    // Create empty floor plan data
    init() {}
    
    // Calculate the bounds of the floor plan
    mutating func calculateBounds() {
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        // Check walls
        for wall in walls {
            minX = min(minX, wall.startPoint.x, wall.endPoint.x)
            minY = min(minY, wall.startPoint.y, wall.endPoint.y)
            maxX = max(maxX, wall.startPoint.x, wall.endPoint.x)
            maxY = max(maxY, wall.startPoint.y, wall.endPoint.y)
        }
        
        // Check doors
        for door in doors {
            let halfWidth = door.width / 2
            minX = min(minX, door.center.x - halfWidth)
            minY = min(minY, door.center.y - halfWidth)
            maxX = max(maxX, door.center.x + halfWidth)
            maxY = max(maxY, door.center.y + halfWidth)
        }
        
        // Check windows
        for window in windows {
            let halfWidth = window.width / 2
            minX = min(minX, window.center.x - halfWidth)
            minY = min(minY, window.center.y - halfWidth)
            maxX = max(maxX, window.center.x + halfWidth)
            maxY = max(maxY, window.center.y + halfWidth)
        }
        
        // Check furniture
        for item in furniture {
            let halfWidth = item.width / 2
            let halfDepth = item.depth / 2
            minX = min(minX, item.center.x - halfWidth)
            minY = min(minY, item.center.y - halfDepth)
            maxX = max(maxX, item.center.x + halfWidth)
            maxY = max(maxY, item.center.y + halfDepth)
        }
        
        // Add some padding
        let padding: CGFloat = 50
        bounds = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }
    
    // Create dimension markers for the floor plan
    mutating func createDimensions() {
        dimensions = []
        
        // Find major dimensions - for simplicity, we just find the min and max X/Y coordinates
        guard !walls.isEmpty else { return }
        
        // Calculate the overall width and height of the room
        let minX = bounds.minX + 25
        let maxX = bounds.maxX - 25
        let minY = bounds.minY + 25
        let maxY = bounds.maxY - 25
        
        // Add width dimension (along bottom)
        let widthInMeters = (maxX - minX) / 100 // Convert back to meters
        dimensions.append(DimensionMarker(
            startPoint: CGPoint(x: minX, y: maxY + 30),
            endPoint: CGPoint(x: maxX, y: maxY + 30),
            text: String(format: "%.1f m", widthInMeters)
        ))
        
        // Add height dimension (along right side)
        let heightInMeters = (maxY - minY) / 100 // Convert back to meters
        dimensions.append(DimensionMarker(
            startPoint: CGPoint(x: maxX + 30, y: minY),
            endPoint: CGPoint(x: maxX + 30, y: maxY),
            text: String(format: "%.1f m", heightInMeters)
        ))
    }
}

// MARK: - Enhanced Floor Plan View
struct EnhancedFloorPlanView: View {
    let floorPlanData: FloorPlanData
    
    // State for zooming and panning
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    // Color scheme
    private let wallColor = Color.black
    private let doorColor = Color.blue
    private let windowColor = Color.cyan
    private let furnitureColor = Color.gray
    private let dimensionColor = Color.red
    
    init(capturedRoom: CapturedRoom, showDimensions: Bool = true) {
        // Calculate the center point to offset the floor plan
        let origin = CGPoint(x: 0, y: 0)
        
        // Create floor plan data from RoomPlan data
        self.floorPlanData = FloorPlanData(
            capturedRoom: capturedRoom,
            origin: origin,
            scale: 100,
            showDimensions: showDimensions
        )
    }
    
    var body: some View {
        VStack {
            // Title and instructions
            Text("Floor Plan View")
                .font(.title)
                .padding(.top)
            
            Text("Pinch to zoom, drag to pan")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Floor plan canvas with zoom and pan gestures
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Rectangle()
                        .fill(Color.white)
                    
                    // Floor plan drawing
                    Canvas { context, size in
                        // Apply zoom and pan transforms
                        var transform = CGAffineTransform.identity
                        transform = transform.translatedBy(
                            x: geometry.size.width / 2 + offset.width,
                            y: geometry.size.height / 2 + offset.height
                        )
                        transform = transform.scaledBy(x: scale, y: scale)
                        
                        // Center the floor plan
                        transform = transform.translatedBy(
                            x: -floorPlanData.bounds.midX,
                            y: -floorPlanData.bounds.midY
                        )
                        
                        // Draw walls
                        for wall in floorPlanData.walls {
                            var path = wall.path()
                            path = path.applying(transform)
                            context.stroke(path, with: .color(wallColor), lineWidth: 2)
                            context.fill(path, with: .color(wallColor.opacity(0.2)))
                        }
                        
                        // Draw doors
                        for door in floorPlanData.doors {
                            var path = door.path()
                            path = path.applying(transform)
                            context.stroke(path, with: .color(doorColor), style: StrokeStyle(lineWidth: 2))
                        }
                        
                        // Draw windows
                        for window in floorPlanData.windows {
                            var path = window.path()
                            path = path.applying(transform)
                            context.stroke(path, with: .color(windowColor), style: StrokeStyle(lineWidth: 2))
                        }
                        
                        // Draw furniture
                        for item in floorPlanData.furniture {
                            var path = item.path()
                            path = path.applying(transform)
                            context.stroke(path, with: .color(furnitureColor), lineWidth: 1)
                            context.fill(path, with: .color(furnitureColor.opacity(0.1)))
                            
                            // Add text label for furniture type if scale is large enough
                            if scale > 0.7 {
                                context.draw(
                                    Text(item.category)
                                        .font(.system(size: 8 / scale))
                                        .foregroundColor(.black),
                                    at: CGPoint(
                                        x: item.center.x * transform.a + transform.tx,
                                        y: item.center.y * transform.d + transform.ty
                                    )
                                )
                            }
                        }
                        
                        // Draw dimensions
                        for dimension in floorPlanData.dimensions {
                            var path = dimension.path()
                            path = path.applying(transform)
                            context.stroke(path, with: .color(dimensionColor), style: StrokeStyle(
                                lineWidth: 1,
                                dash: [5, 3]
                            ))
                            
                            // Draw dimension text
                            let textPos = dimension.textPosition()
                            let transformedPos = CGPoint(
                                x: textPos.x * transform.a + transform.tx,
                                y: textPos.y * transform.d + transform.ty
                            )
                            
                            context.draw(
                                Text(dimension.text)
                                    .font(.system(size: 10 / scale))
                                    .foregroundColor(dimensionColor)
                                    .background(Color.white.opacity(0.7))
                                    .cornerRadius(2),
                                at: transformedPos
                            )
                        }
                    }
                    .gesture(
                        // Magnification (pinch) gesture for zooming
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(0.1, min(5.0, lastScale * value))
                            }
                            .onEnded { value in
                                lastScale = scale
                            }
                    )
                    .simultaneousGesture(
                        // Drag gesture for panning
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                lastOffset = offset
                            }
                    )
                }
            }
            
            // Reset button
            Button("Reset View") {
                withAnimation {
                    scale = 1.0
                    offset = .zero
                    lastScale = 1.0
                    lastOffset = .zero
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.bottom)
        }
    }
}

// MARK: - Preview

// Struct for SwiftUI preview
struct EnhancedFloorPlanView_Previews: PreviewProvider {
    static var previews: some View {
        // This is just a placeholder - in a real app we would
        // use a real CapturedRoom object from RoomPlan
        Text("Preview not available - needs real RoomPlan data")
            .padding()
    }
} 