import SwiftUI
import UIKit
import CoreGraphics

struct MultiGoalCameraView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var capturedImage: UIImage?
    @State private var previousOrientation: UIInterfaceOrientationMask = .all // For restoring
    @State private var showPreview: Bool = true // New state for preview toggle, now ON by default
    // Each line is two endpoints: [ [CGPoint, CGPoint], ... ] in screen coordinates
    @State private var lineEndpoints: [[CGPoint]] = []
    @State private var defaultLineEndpoints: [[CGPoint]] = []
    @State private var dragging: (line: Int, point: Int)? = nil
    @State private var dragStart: CGPoint? = nil // screen coords
    @State private var dragStartEndpoint: CGPoint? = nil // screen coords
    @State private var dragActive: Bool = false
    @State private var isLandscape: Bool = true
    @State private var showLineCropsView: Bool = false
    @State private var currentOrientation: UIDeviceOrientation = UIDevice.current.orientation
    let lineColors: [Color] = [.red, .green, .blue, .orange]
    let lineColorNames: [String] = ["red", "green", "blue", "orange"]
    
    // 1. At the top of MultiGoalCameraView, add haptic generators
    @State private var hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // Add a @State variable to store the true visible area size
    @State private var visibleAreaSize: CGSize = .zero
    
    // MARK: - Constants
    private let perpendicularPaddings: [CGFloat] = [13, 30, 16, 16] // red, green, blue, orange
    private let outwardPadding: CGFloat = 10.0 // Padding at the ends of the line (along the line direction)
    
    var body: some View {
        ZStack {
            OrientationReader { landscape, orientation in
                isLandscape = landscape
                currentOrientation = orientation
            }
            if let image = capturedImage {
                GeometryReader { screenGeometry in
                    let trueSize = screenGeometry.size
                    Color.clear
                        .onAppear { visibleAreaSize = trueSize }
                        .onChange(of: screenGeometry.size) { newSize in visibleAreaSize = newSize }
                    ZStack(alignment: .center) {
                        Color.black.edgesIgnoringSafeArea(.all)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: trueSize.width, height: trueSize.height)
                            .clipped()
                        // Editable lines
                        ForEach(0..<lineEndpoints.count, id: \.self) { i in
                            EditableLine(
                                color: lineColors[i],
                                endpoints: [
                                    lineEndpoints[i][0],
                                    lineEndpoints[i][1]
                                ],
                                highlightedPoint: dragging?.line == i ? dragging?.point : nil,
                                highlightedPosition: dragging?.line == i ? lineEndpoints[i][dragging!.point] : nil
                            )
                        }
                        // Preview overlay (below buttons)
                        if showPreview {
                            VStack {
                                PreviewCropRectangles(
                                    image: image,
                                    lineEndpoints: lineEndpoints,
                                    colors: lineColors,
                                    screenSize: screenGeometry.size,
                                    outwardPadding: outwardPadding,
                                    perpendicularPaddings: perpendicularPaddings
                                )
                            }
                        }
                        // Transparent Rectangle with DragGesture for moving endpoints
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if dragging == nil {
                                            // On drag start, find the closest endpoint among all lines
                                            let touch = value.startLocation
                                            let maxDistance: CGFloat = 100
                                            let allEndpoints: [(line: Int, point: Int, pos: CGPoint)] =
                                                (0..<lineEndpoints.count).flatMap { line in (0..<2).map { pt in (line, pt, lineEndpoints[line][pt]) } }
                                            if let closest = allEndpoints.min(by: { $0.pos.distance(to: touch) < $1.pos.distance(to: touch) }),
                                               closest.pos.distance(to: touch) <= maxDistance {
                                                dragging = (closest.line, closest.point)
                                                dragStart = value.startLocation
                                                dragStartEndpoint = lineEndpoints[closest.line][closest.point]
                                                dragActive = true
                                                // Use only medium haptic for all lines
                                                hapticMedium.impactOccurred()
                                            }
                                        } else if let dragging = dragging, let dragStart = dragStart, let dragStartEndpoint = dragStartEndpoint, dragActive {
                                            // Update the dragged endpoint
                                            let delta = CGPoint(x: value.location.x - dragStart.x, y: value.location.y - dragStart.y)
                                            var newX = dragStartEndpoint.x + delta.x
                                            var newY = dragStartEndpoint.y + delta.y
                                            // Clamp to visible area
                                            newX = min(max(newX, 0), visibleAreaSize.width)
                                            newY = min(max(newY, 0), visibleAreaSize.height)
                                            lineEndpoints[dragging.line][dragging.point] = CGPoint(x: newX, y: newY)
                                        }
                                    }
                                    .onEnded { value in
                                        if let dragging = dragging, dragActive {
                                            let pt = lineEndpoints[dragging.line][dragging.point]
                                            print("\(lineColorNames[dragging.line]) endpoint \(dragging.point) moved to (x=\(String(format: "%.1f", pt.x)), y=\(String(format: "%.1f", pt.y)))")
                                        }
                                        dragStart = nil
                                        dragStartEndpoint = nil
                                        self.dragging = nil
                                        dragActive = false
                                    }
                            )
                        // Buttons on right (topmost)
                        VStack(spacing: 20) {
                            Button("Retake") {
                                capturedImage = nil
                            }
                            .buttonStyle(AppleButtonStyle(color: .red))
                            Button("Reset") {
                                lineEndpoints = defaultLineEndpoints
                            }
                            .buttonStyle(AppleButtonStyle(color: .orange))
                            Button("Detailed") {
                                showPreview.toggle()
                            }
                            .buttonStyle(AppleButtonStyle(color: showPreview ? .blue : .gray))
                            Button("Done") {
                                Logger.debug("Done pressed – navigating to LineCropsView", category: .navigation)
                                showLineCropsView = true
                            }
                            .buttonStyle(AppleButtonStyle(color: .green))
                            Spacer()
                        }
                        .padding(.top, 60)
                        .padding(.trailing, 30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    .frame(width: trueSize.width, height: trueSize.height)
                    .onAppear {
                        // Only initialize endpoints if in landscape
                        if isLandscape && lineEndpoints.isEmpty {
                            let defaults = initializeEndpoints(for: trueSize)
                            lineEndpoints = defaults
                            defaultLineEndpoints = defaults
                        }
                    }
                    .onChange(of: isLandscape) { newIsLandscape in
                        // If switching to landscape, re-initialize endpoints for correct geometry
                        if newIsLandscape {
                            let defaults = initializeEndpoints(for: trueSize)
                            lineEndpoints = defaults
                            defaultLineEndpoints = defaults
                        }
                    }
                }
                .edgesIgnoringSafeArea(.all)
                .fullScreenCover(isPresented: $showLineCropsView) {
                    if let img = capturedImage, visibleAreaSize.width > 0, visibleAreaSize.height > 0 {
                        LineCropsView(isPresented: $showLineCropsView, originalImage: img, lineEndpoints: lineEndpoints, screenSize: visibleAreaSize)
                    } else {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    }
                }
            } else {
                GeometryReader { screenGeometry in
                    ZStack(alignment: .center) {
                        Color.black.edgesIgnoringSafeArea(.all)
                        CustomCameraView(
                            capturedImage: $capturedImage,
                            useWideCamera: true,
                            rotateCapturedImage90Degrees: true,
                            hideNeonLine: true,
                            shutterVerticalFraction: 0.25,
                            hideControls: !isLandscape
                        )
                        .edgesIgnoringSafeArea(.all)
                        .disabled(!isLandscape) // Disable camera interaction in portrait
                        .opacity(isLandscape ? 1.0 : 0.3) // Gray out camera in portrait
                        // Show default neon lines only in landscape mode
                        if isLandscape {
                            ForEach(0..<defaultLineEndpoints.count, id: \.self) { i in
                                EditableLine(
                                    color: lineColors[i],
                                    endpoints: [
                                        defaultLineEndpoints[i][0],
                                        defaultLineEndpoints[i][1]
                                    ],
                                    highlightedPoint: nil, // No highlighting for default lines
                                    highlightedPosition: nil
                                )
                            }
                            // Show bounding boxes overlay before taking a picture
                            PreviewCropRectangles(
                                image: nil,
                                lineEndpoints: defaultLineEndpoints,
                                colors: lineColors,
                                screenSize: screenGeometry.size,
                                outwardPadding: outwardPadding,
                                perpendicularPaddings: perpendicularPaddings
                            )
                        }
                        if !isLandscape {
                            LandscapePopup(orientation: currentOrientation)
                        }
                        // Cancel button always on top
                        if !isLandscape {
                            VStack {
                                HStack {
                                    Button("Cancel") {
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.white)
                                    .padding(.top, 40)
                                    .padding(.leading, 20)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                    }
                    .onAppear {
                        // Only initialize endpoints if in landscape
                        if isLandscape && lineEndpoints.isEmpty {
                            let defaults = initializeEndpoints(for: screenGeometry.size)
                            lineEndpoints = defaults
                            defaultLineEndpoints = defaults
                        }
                    }
                    .onChange(of: isLandscape) { newIsLandscape in
                        // If switching to landscape, re-initialize endpoints for correct geometry
                        if newIsLandscape {
                            let defaults = initializeEndpoints(for: screenGeometry.size)
                            lineEndpoints = defaults
                            defaultLineEndpoints = defaults
                        }
                    }
                }
                .edgesIgnoringSafeArea(.all)
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Force landscape orientation
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
            isLandscape = UIDevice.current.orientation.isLandscape
        }
        .onDisappear {
            // Restore portrait orientation (best effort)
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }
    
    // Helper to initialize endpoints for current geometry
    private func initializeEndpoints(for size: CGSize) -> [[CGPoint]] {
        let w = size.width
        let h = size.height
        return [
            // red
            [CGPoint(x: 0.332 * w, y: 0.288 * h), CGPoint(x: 0.616 * w, y: 0.288 * h)],
            // green
            [CGPoint(x: 0.100 * w, y: 0.800 * h), CGPoint(x: 0.900 * w, y: 0.800 * h)],
            // blue
            [CGPoint(x: 0.420 * w, y: 0.670 * h), CGPoint(x: 0.545 * w, y: 0.590 * h)],
            // orange
            [CGPoint(x: 0.428 * w, y: 0.455 * h), CGPoint(x: 0.554 * w, y: 0.538 * h)]
        ]
    }
}

enum DragState { case start, active, end }

struct EditableLine: View {
    let color: Color
    let endpoints: [CGPoint] // [pt1, pt2] in screen coords
    let highlightedPoint: Int? // 0 or 1 if highlighted, nil otherwise
    let highlightedPosition: CGPoint? // If dragging, show coordinates
    var body: some View {
        ZStack {
            // Aesthetic line: shadow, gradient, rounded ends
            Path { path in
                path.move(to: endpoints[0])
                path.addLine(to: endpoints[1])
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.5), color.opacity(0.25)]),
                    startPoint: .init(x: endpoints[0].x, y: endpoints[0].y),
                    endPoint: .init(x: endpoints[1].x, y: endpoints[1].y)
                ),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: color.opacity(0.15), radius: 8, x: 0, y: 0)
            // Endpoints
            ForEach(0..<2, id: \.self) { idx in
                ZStack {
                    Circle()
                        .fill(color) // Always fully opaque
                        .frame(width: idx == highlightedPoint ? 28 : 18, height: idx == highlightedPoint ? 28 : 18)
                        .shadow(color: color.opacity(idx == highlightedPoint ? 0.5 : 0.2), radius: idx == highlightedPoint ? 10 : 4)
                        .position(endpoints[idx])
                    if idx == highlightedPoint, let pos = highlightedPosition {
                        // VStack(spacing: 2) {
                        //     Text("(\(Int(pos.x)), \(Int(pos.y)))")
                        //         .font(.caption2)
                        //         .foregroundColor(.white)
                        //         .padding(4)
                        //         .background(Color.black.opacity(0.7))
                        //         .cornerRadius(5)
                        //         .shadow(radius: 2)
                        // }
                        // .position(x: pos.x, y: pos.y - 30)
                    }
                }
            }
        }
    }
}

// Helper for CGPoint distance
extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx*dx + dy*dy)
    }
}

// Helper view to detect orientation
struct OrientationReader: View {
    var onChange: (Bool, UIDeviceOrientation) -> Void
    @State private var lastIsLandscape: Bool = UIDevice.current.orientation.isLandscape
    @State private var lastOrientation: UIDeviceOrientation = UIDevice.current.orientation
    var body: some View {
        Color.clear
            .onAppear {
                onChange(UIDevice.current.orientation.isLandscape, UIDevice.current.orientation)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let orientation = UIDevice.current.orientation
                let isLandscape = orientation.isLandscape
                if isLandscape != lastIsLandscape || orientation != lastOrientation {
                    lastIsLandscape = isLandscape
                    lastOrientation = orientation
                    onChange(isLandscape, orientation)
                }
            }
    }
}

struct LandscapePopup: View {
    let orientation: UIDeviceOrientation
    var body: some View {
        ZStack {
            // Full screen overlay to gray out the camera
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "iphone.landscape")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 50)
                            .foregroundColor(.white)
                        if orientation == .faceUp || orientation == .faceDown {
                            Text("Face up or face down (flat) will not work.\n\nPlease hold your phone upright in landscape (sideways) orientation.")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(20)
                        } else {
                            Text("Please rotate your phone to landscape (sideways) orientation.")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(20)
                        }
                    }
                    .padding(40)
                    Spacer()
                }
                
                Spacer()
            }
        }
        .edgesIgnoringSafeArea(.all)
        .transition(.opacity)
        .animation(.easeInOut, value: UUID())
    }
}

// 3. Update PreviewCropRectangles to accept outwardPadding and perpendicularPadding as parameters and use them in its drawing logic
struct PreviewCropRectangles: View {
    let image: UIImage? // Made optional
    let lineEndpoints: [[CGPoint]]
    let colors: [Color]
    let screenSize: CGSize
    let outwardPadding: CGFloat
    let perpendicularPaddings: [CGFloat]
    
    var body: some View {
        GeometryReader { _ in
            ForEach(0..<min(4, lineEndpoints.count), id: \.self) { i in
                let rel = lineEndpoints[i]
                if rel.count == 2 {
                    let p0 = CGPoint(
                        x: rel[0].x,
                        y: rel[0].y
                    )
                    let p1 = CGPoint(
                        x: rel[1].x,
                        y: rel[1].y
                    )
                    let dx = p1.x - p0.x
                    let dy = p1.y - p0.y
                    let lineLength = sqrt(dx * dx + dy * dy)
                    let angle = atan2(dy, dx)
                    let sin = CGFloat(sinf(Float(angle)))
                    let cos = CGFloat(cosf(Float(angle)))
                    let halfHeight = perpendicularPaddings[i]
                    let halfWidth = (lineLength / 2) + outwardPadding
                    let center = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                    let corners = [
                        CGPoint(
                            x: center.x - halfWidth * cos - halfHeight * sin,
                            y: center.y - halfWidth * sin + halfHeight * cos
                        ),
                        CGPoint(
                            x: center.x + halfWidth * cos - halfHeight * sin,
                            y: center.y + halfWidth * sin + halfHeight * cos
                        ),
                        CGPoint(
                            x: center.x + halfWidth * cos + halfHeight * sin,
                            y: center.y + halfWidth * sin - halfHeight * cos
                        ),
                        CGPoint(
                            x: center.x - halfWidth * cos + halfHeight * sin,
                            y: center.y - halfWidth * sin - halfHeight * cos
                        )
                    ]
                    Path { path in
                        // Draw the rotated rectangle
                        path.move(to: corners[0])
                        path.addLine(to: corners[1])
                        path.addLine(to: corners[2])
                        path.addLine(to: corners[3])
                        path.closeSubpath()
                    }
                    .fill(colors[i].opacity(0.2))
                    .overlay(
                        Path { path in
                            path.move(to: corners[0])
                            path.addLine(to: corners[1])
                            path.addLine(to: corners[2])
                            path.addLine(to: corners[3])
                            path.closeSubpath()
                        }
                        .stroke(colors[i], lineWidth: 2)
                    )
                }
            }
        }
    }
} 