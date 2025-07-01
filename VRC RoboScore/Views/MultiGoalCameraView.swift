import SwiftUI
import UIKit

struct MultiGoalCameraView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var capturedImage: UIImage?
    @State private var previousOrientation: UIInterfaceOrientationMask = .all // For restoring
    // Each line is two endpoints: [ [CGPoint, CGPoint], ... ]
    @State private var lineEndpoints: [[CGPoint]] = [
        // red
        [CGPoint(x: 0.332, y: 0.288), CGPoint(x: 0.616, y: 0.288)],
        // green
        [CGPoint(x: 0.100, y: 0.800), CGPoint(x: 0.900, y: 0.800)],
        // blue
        [CGPoint(x: 0.420, y: 0.670), CGPoint(x: 0.540, y: 0.570)],
        // orange
        [CGPoint(x: 0.428, y: 0.455), CGPoint(x: 0.554, y: 0.538)]
    ] // relative (0-1) positions
    let defaultLineEndpoints: [[CGPoint]] = [
        [CGPoint(x: 0.332, y: 0.288), CGPoint(x: 0.616, y: 0.288)],
        [CGPoint(x: 0.100, y: 0.800), CGPoint(x: 0.900, y: 0.800)],
        [CGPoint(x: 0.420, y: 0.670), CGPoint(x: 0.540, y: 0.570)],
        [CGPoint(x: 0.428, y: 0.455), CGPoint(x: 0.554, y: 0.538)]
    ]
    @State private var dragging: (line: Int, point: Int)? = nil
    @State private var dragStart: CGPoint? = nil // screen coords
    @State private var dragStartEndpoint: CGPoint? = nil // relative coords
    @State private var dragActive: Bool = false
    @State private var isLandscape: Bool = true
    @State private var showLineCropsView: Bool = false
    let lineColors: [Color] = [.red, .green, .blue, .orange]
    let lineColorNames: [String] = ["red", "green", "blue", "orange"]
    
    var body: some View {
        ZStack {
            OrientationReader { landscape in
                isLandscape = landscape
            }
            if let image = capturedImage {
                GeometryReader { screenGeometry in
                    ZStack(alignment: .center) {
                        Color.black.edgesIgnoringSafeArea(.all)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
                            .clipped()
                        // Editable lines
                        ForEach(0..<4, id: \.self) { i in
                            EditableLine(
                                color: lineColors[i],
                                endpoints: [
                                    CGPoint(x: lineEndpoints[i][0].x * screenGeometry.size.width, y: lineEndpoints[i][0].y * screenGeometry.size.height),
                                    CGPoint(x: lineEndpoints[i][1].x * screenGeometry.size.width, y: lineEndpoints[i][1].y * screenGeometry.size.height)
                                ],
                                onDrag: { pointIdx, dragState, value in
                                    let allEndpoints: [(line: Int, point: Int, pos: CGPoint)] =
                                        (0..<4).flatMap { line in (0..<2).map { pt in (line, pt, CGPoint(x: lineEndpoints[line][pt].x * screenGeometry.size.width, y: lineEndpoints[line][pt].y * screenGeometry.size.height)) } }
                                    if dragState == .start {
                                        // Find closest endpoint to the touch
                                        let touch = value.startLocation
                                        if let closest = allEndpoints.min(by: { $0.pos.distance(to: touch) < $1.pos.distance(to: touch) }),
                                           closest.line == i, closest.point == pointIdx {
                                            dragging = (i, pointIdx)
                                            dragStart = value.startLocation
                                            dragStartEndpoint = lineEndpoints[i][pointIdx]
                                            dragActive = true
                                        }
                                    } else if dragState == .active, dragActive, dragging?.line == i, dragging?.point == pointIdx, let dragStart = dragStart, let dragStartEndpoint = dragStartEndpoint {
                                        let delta = CGPoint(x: value.location.x - dragStart.x, y: value.location.y - dragStart.y)
                                        let relX = min(max(dragStartEndpoint.x + delta.x / screenGeometry.size.width, 0), 1)
                                        let relY = min(max(dragStartEndpoint.y + delta.y / screenGeometry.size.height, 0), 1)
                                        lineEndpoints[i][pointIdx] = CGPoint(x: relX, y: relY)
                                    } else if dragState == .end, dragActive, dragging?.line == i, dragging?.point == pointIdx {
                                        let pt = lineEndpoints[i][pointIdx]
                                        print("\(lineColorNames[i]) endpoint \(pointIdx) moved to (x=\(String(format: "%.3f", pt.x)), y=\(String(format: "%.3f", pt.y)))")
                                        dragStart = nil
                                        dragStartEndpoint = nil
                                        dragging = nil
                                        dragActive = false
                                    }
                                }
                            )
                        }
                    }
                    .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
                    // Buttons on right
                    VStack(spacing: 20) {
                        Button("Retake") {
                            capturedImage = nil
                        }
                        .buttonStyle(AppleButtonStyle(color: .red))
                        Button("Reset") {
                            lineEndpoints = defaultLineEndpoints
                        }
                        .buttonStyle(AppleButtonStyle(color: .orange))
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
                .edgesIgnoringSafeArea(.all)
            } else {
                GeometryReader { screenGeometry in
                    ZStack(alignment: .center) {
                        Color.black.edgesIgnoringSafeArea(.all)
                        CustomCameraView(
                            capturedImage: $capturedImage,
                            useWideCamera: true,
                            rotateCapturedImage90Degrees: true,
                            hideNeonLine: true,
                            shutterVerticalFraction: 0.25
                        )
                        .edgesIgnoringSafeArea(.all)
                        // Show default neon lines, not draggable
                        ForEach(0..<4, id: \.self) { i in
                            EditableLine(
                                color: lineColors[i],
                                endpoints: [
                                    CGPoint(x: defaultLineEndpoints[i][0].x * screenGeometry.size.width, y: defaultLineEndpoints[i][0].y * screenGeometry.size.height),
                                    CGPoint(x: defaultLineEndpoints[i][1].x * screenGeometry.size.width, y: defaultLineEndpoints[i][1].y * screenGeometry.size.height)
                                ],
                                onDrag: { _,_,_ in }
                            )
                        }
                        if !isLandscape {
                            LandscapePopup()
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
        .fullScreenCover(isPresented: $showLineCropsView) {
            if let img = capturedImage {
                LineCropsView(originalImage: img, lineEndpoints: lineEndpoints)
            }
        }
    }
}

enum DragState { case start, active, end }

struct EditableLine: View {
    let color: Color
    let endpoints: [CGPoint] // [pt1, pt2] in screen coords
    let onDrag: (Int, DragState, DragGesture.Value) -> Void // (pointIdx, dragState, value)
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: endpoints[0])
                path.addLine(to: endpoints[1])
            }
            .stroke(color.opacity(0.6), lineWidth: 3)
            // Draggable endpoints (large hit area)
            ForEach(0..<2, id: \.self) { idx in
                ZStack {
                    Circle()
                        .fill(color.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .position(endpoints[idx])
                    Circle()
                        .fill(Color.clear)
                        .contentShape(Circle())
                        .frame(width: 150, height: 150)
                        .position(endpoints[idx])
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if value.startLocation == value.location {
                                        onDrag(idx, .start, value)
                                    } else {
                                        onDrag(idx, .active, value)
                                    }
                                }
                                .onEnded { value in
                                    onDrag(idx, .end, value)
                                }
                        )
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
    var onChange: (Bool) -> Void
    @State private var lastIsLandscape: Bool = UIDevice.current.orientation.isLandscape
    var body: some View {
        Color.clear
            .onAppear { onChange(UIDevice.current.orientation.isLandscape) }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let isLandscape = UIDevice.current.orientation.isLandscape
                if isLandscape != lastIsLandscape {
                    lastIsLandscape = isLandscape
                    onChange(isLandscape)
                }
            }
    }
}

struct LandscapePopup: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "iphone.landscape")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 40)
                        .foregroundColor(.white)
                    Text("Please rotate your phone to landscape")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                }
                .padding(32)
                Spacer()
            }
            Spacer()
        }
        .background(Color.black.opacity(0.001))
        .edgesIgnoringSafeArea(.all)
        .transition(.opacity)
        .animation(.easeInOut, value: UUID())
    }
} 