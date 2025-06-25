import UIKit
import SwiftUI

struct BallCount {
    var red: Int = 0
    var blue: Int = 0
}

struct ZoneCounts {
    var middle: BallCount = BallCount()
    var outside: BallCount = BallCount()
    
    var total: BallCount {
        BallCount(
            red: middle.red + outside.red,
            blue: middle.blue + outside.blue
        )
    }
}

private struct Ball {
    var center: CGPoint
    var color: BallColor
    var radius: CGFloat
    
    var isInMiddleZone: Bool = false
}

private enum BallColor {
    case red, blue
    
    var uiColor: UIColor {
        switch self {
        case .red: return VRCColors.red
        case .blue: return VRCColors.blue
        }
    }
}

private struct WhiteLine {
    var yPosition: Int
    var xPosition: CGFloat  // Average x position of the line
    var pixels: Set<CGPoint>
}

class BallCounter {
    static let maxTotalBalls = 15
    
    // Detection parameters
    struct Parameters {
        var minClusterSize: Int = 50  // Minimum pixels to consider as potential ball
        var ballRadiusRatio: CGFloat = 0.024  // Ball radius as fraction of image width
        var exclusionRadiusMultiplier: CGFloat = 1.2  // Multiplier for exclusion zone
        var whiteMergeThreshold: Int = 20  // Number of adjacent colored pixels to merge white region
        var imageScale: CGFloat = 0.33     // Scale factor to downsample image for faster processing
    }
    
    private var params: Parameters
    private var imageWidth: Int = 0
    private var imageHeight: Int = 0
    private var visited: [Bool] = []   // Flattened visited array (row-major)
    private var excludedPoints: Set<CGPoint> = []
    private var detectedBalls: [Ball] = []
    private var middleZoneStart: Int = 0
    private var middleZoneEnd: Int = 0
    
    init(parameters: Parameters = Parameters()) {
        self.params = parameters
    }
    
    // Helper to compute 1-D index in visited array
    private func vIndex(x: Int, y: Int) -> Int { y * imageWidth + x }
    
    static func countBalls(in image: UIImage, sensitivity: Double = 1.0) -> ZoneCounts {
        let counter = BallCounter(parameters: .init(
            minClusterSize: Int(50.0 * sensitivity),
            ballRadiusRatio: 0.024,
            exclusionRadiusMultiplier: 1.2,
            whiteMergeThreshold: Int(20.0 * sensitivity)
        ))
        return counter.detectBalls(in: image).zoneCounts
    }
    
    func detectBalls(in image: UIImage) -> (zoneCounts: ZoneCounts, annotatedImage: UIImage?) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let appSettings = AppSettingsManager.shared
        
        if appSettings.debugMode {
            print("\nDEBUG: Starting new ball detection")
        }
        
        // Downscale image for faster processing if needed
        let workingImage: UIImage
        if params.imageScale < 1.0 {
            let newSize = CGSize(width: image.size.width * params.imageScale,
                                 height: image.size.height * params.imageScale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            workingImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            workingImage = image
        }
        
        guard let cgImage = workingImage.cgImage else { return (ZoneCounts(), nil) }
        
        imageWidth = cgImage.width
        imageHeight = cgImage.height
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        excludedPoints.removeAll()
        detectedBalls.removeAll()
        
        print("Processing image - Width: \(imageWidth), Height: \(imageHeight)")
        
        // Get pixel data
        let bytesPerPixel = 4
        let bytesPerRow = imageWidth * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: imageWidth * imageHeight * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixelData,
                                    width: imageWidth,
                                    height: imageHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (ZoneCounts(), nil)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        // First, find white lines in middle half horizontally of image
        let middleStartX = imageWidth / 4  // Only search middle half horizontally
        let middleEndX = imageWidth * 3 / 4
        var whiteLines: [WhiteLine] = []
        
        // Reset visited array for white line detection
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        
        for y in 0..<imageHeight {
            for x in middleStartX..<middleEndX {
                let idx = vIndex(x: x, y: y)
                if visited[idx] { continue }
                
                let pixelIndex = (y * imageWidth + x) * bytesPerPixel
                if isWhitePixel(data: pixelData, index: pixelIndex) {
                    let cluster = findWhiteCluster(at: CGPoint(x: x, y: y), in: pixelData)
                    if cluster.pixels.count > params.minClusterSize {
                        whiteLines.append(findWhiteLine(from: cluster))
                    }
                }
            }
        }
        
        // Sort white lines by size and get the two largest
        whiteLines.sort { $0.pixels.count > $1.pixels.count }
        let middleLines = Array(whiteLines.prefix(2))
        
        // Reset visited array for ball detection
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        
        // Calculate ball dimensions
        let ballRadius = CGFloat(imageWidth) * params.ballRadiusRatio
        let minPixelsForBall = Int(Double.pi * pow(Double(ballRadius), 2) * 0.3)
        
        // Scan for colored clusters
        for x in 0..<imageWidth {
            for y in 0..<imageHeight {
                let idx = vIndex(x: x, y: y)
                if visited[idx] || isExcluded(CGPoint(x: x, y: y)) { continue }
                
                let pixelIndex = (y * imageWidth + x) * bytesPerPixel
                let color = getPixelColor(data: pixelData, index: pixelIndex)
                
                if color != nil {
                    let cluster = findCluster(at: CGPoint(x: x, y: y), color: color!, in: pixelData)
                    
                    if cluster.pixels.count >= minPixelsForBall {
                        let centerScaled = calculateClusterCenter(cluster.pixels)
                        let center = CGPoint(x: centerScaled.x / params.imageScale, y: centerScaled.y / params.imageScale)
                        
                        // Check if ball is between white lines (use scaled coordinates)
                        let isInMiddle = middleLines.count == 2 &&
                            centerScaled.x > min(middleLines[0].xPosition, middleLines[1].xPosition) &&
                            centerScaled.x < max(middleLines[0].xPosition, middleLines[1].xPosition) &&
                            !doesBallIntersectLines(center: centerScaled, radius: ballRadius, lines: middleLines)
                        
                        if appSettings.debugMode {
                            print("\nDEBUG: Ball Detection Details:")
                            print("Ball position (scaled): \(centerScaled)")
                            print("Color: \(cluster.color)")
                            print("Middle line check result: \(isInMiddle)")
                            print("Line positions: \(middleLines.map { $0.xPosition })")
                        }
                        
                        let ball = Ball(center: center, color: cluster.color, radius: ballRadius / params.imageScale, isInMiddleZone: isInMiddle)
                        detectedBalls.append(ball)
                        
                        let exclusionRadius = ballRadius * params.exclusionRadiusMultiplier
                        addExclusionZone(center: centerScaled, radius: exclusionRadius)
                    }
                }
            }
        }
        
        // Create zone counts
        var counts = ZoneCounts()
        if appSettings.debugMode {
            print("\nDEBUG: Counting detected balls:")
        }
        for ball in detectedBalls {
            if appSettings.debugMode {
                print("DEBUG: Processing ball at \(ball.center) - Color: \(ball.color), IsMiddle: \(ball.isInMiddleZone)")
            }
            if ball.isInMiddleZone {
                if ball.color == .red {
                    counts.middle.red += 1
                    if appSettings.debugMode {
                        print("DEBUG: Counted as middle red")
                    }
                } else {
                    counts.middle.blue += 1
                    if appSettings.debugMode {
                        print("DEBUG: Counted as middle blue")
                    }
                }
            } else {
                if ball.color == .red {
                    counts.outside.red += 1
                    if appSettings.debugMode {
                        print("DEBUG: Counted as outside red")
                    }
                } else {
                    counts.outside.blue += 1
                    if appSettings.debugMode {
                        print("DEBUG: Counted as outside blue")
                    }
                }
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        print("Ball detection completed in \(String(format: "%.3f", endTime - startTime)) seconds")
        
        if appSettings.debugMode {
            print("DEBUG: Final counts - Middle: Red=\(counts.middle.red), Blue=\(counts.middle.blue)")
            print("DEBUG: Final counts - Outside: Red=\(counts.outside.red), Blue=\(counts.outside.blue)")
        }
        
        // Create annotated image
        let annotatedImage = createAnnotatedImage(originalImage: image, whiteLines: middleLines)
        
        return (counts, annotatedImage)
    }
    
    private func isWhitePixel(data: [UInt8], index: Int) -> Bool {
        let r = data[index]
        let g = data[index + 1]
        let b = data[index + 2]
        return r > 200 && g > 200 && b > 200
    }
    
    private func findWhiteCluster(at start: CGPoint, in pixelData: [UInt8]) -> Cluster {
        var cluster = Cluster(pixels: [], color: .red) // Color doesn't matter for white clusters
        var queue: [CGPoint] = [start]
        
        while !queue.isEmpty {
            let point = queue.removeFirst()
            let x = Int(point.x)
            let y = Int(point.y)
            
            if x < 0 || x >= imageWidth || y < 0 || y >= imageHeight { continue }
            if visited[vIndex(x: x, y: y)] { continue }
            
            visited[vIndex(x: x, y: y)] = true
            
            let pixelIndex = (y * imageWidth + x) * 4
            if isWhitePixel(data: pixelData, index: pixelIndex) {
                cluster.pixels.insert(point)
                
                queue.append(CGPoint(x: x + 1, y: y))
                queue.append(CGPoint(x: x - 1, y: y))
                queue.append(CGPoint(x: x, y: y + 1))
                queue.append(CGPoint(x: x, y: y - 1))
            }
        }
        
        return cluster
    }
    
    private func findWhiteLine(from cluster: Cluster) -> WhiteLine {
        let avgY = Int(cluster.pixels.reduce(0.0) { $0 + $1.y } / CGFloat(cluster.pixels.count))
        let avgX = cluster.pixels.reduce(0.0) { $0 + $1.x } / CGFloat(cluster.pixels.count)
        return WhiteLine(yPosition: avgY, xPosition: avgX, pixels: cluster.pixels)
    }
    
    private func doesBallIntersectLines(center: CGPoint, radius: CGFloat, lines: [WhiteLine]) -> Bool {
        let appSettings = AppSettingsManager.shared
        
        guard lines.count == 2 else {
            if appSettings.debugMode {
                print("DEBUG: Not enough lines found (\(lines.count))")
            }
            return true
        }
        
        // Find the leftmost and rightmost x-coordinates of the lines
        var leftLineX = CGFloat.infinity
        var rightLineX = -CGFloat.infinity
        
        // Calculate average x position for each line
        for line in lines {
            let avgX = line.pixels.reduce(0.0) { $0 + $1.x } / CGFloat(line.pixels.count)
            leftLineX = min(leftLineX, avgX)
            rightLineX = max(rightLineX, avgX)
        }
        
        if appSettings.debugMode {
            print("\nDEBUG: Line Positions:")
            print("Left line: \(leftLineX)")
            print("Right line: \(rightLineX)")
            print("Ball center: \(center.x)")
            print("Ball radius: \(radius)")
            print("Ball left edge: \(center.x - radius)")
            print("Ball right edge: \(center.x + radius)")
        }
        
        // Add a small buffer to avoid edge cases
        let buffer: CGFloat = 2.0
        
        // Check if ball's center is between the lines horizontally
        if center.x < leftLineX + buffer || center.x > rightLineX - buffer {
            if appSettings.debugMode {
                print("DEBUG: Ball center not between lines")
            }
            return true
        }
        
        // Check if ball touches either line
        let ballLeft = center.x - radius
        let ballRight = center.x + radius
        
        if ballLeft < leftLineX + buffer || ballRight > rightLineX - buffer {
            if appSettings.debugMode {
                print("DEBUG: Ball touches lines")
            }
            return true
        }
        
        if appSettings.debugMode {
            print("DEBUG: Ball is in middle zone!")
        }
        return false
    }
    
    private func getPixelColor(data: [UInt8], index: Int) -> BallColor? {
        let r = data[index]
        let g = data[index + 1]
        let b = data[index + 2]
        
        // Match with VRCColors
        if r > 180 && g < 100 && b < 100 {
            return .red
        } else if r < 100 && b > 150 {
            return .blue
        }
        return nil
    }
    
    private struct Cluster {
        var pixels: Set<CGPoint>
        var color: BallColor
    }
    
    private func findCluster(at start: CGPoint, color: BallColor, in pixelData: [UInt8]) -> Cluster {
        var cluster = Cluster(pixels: [], color: color)
        var queue: [CGPoint] = [start]
        
        while !queue.isEmpty {
            let point = queue.removeFirst()
            let x = Int(point.x)
            let y = Int(point.y)
            
            if x < 0 || x >= imageWidth || y < 0 || y >= imageHeight { continue }
            if visited[vIndex(x: x, y: y)] || isExcluded(point) { continue }
            
            visited[vIndex(x: x, y: y)] = true
            
            let pixelIndex = (y * imageWidth + x) * 4
            if getPixelColor(data: pixelData, index: pixelIndex) == color {
                cluster.pixels.insert(point)
                
                // Add adjacent pixels to queue
                queue.append(CGPoint(x: x + 1, y: y))
                queue.append(CGPoint(x: x - 1, y: y))
                queue.append(CGPoint(x: x, y: y + 1))
                queue.append(CGPoint(x: x, y: y - 1))
            }
        }
        
        return cluster
    }
    
    private func calculateClusterCenter(_ pixels: Set<CGPoint>) -> CGPoint {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        
        for point in pixels {
            sumX += point.x
            sumY += point.y
        }
        
        let count = CGFloat(pixels.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }
    
    private func isExcluded(_ point: CGPoint) -> Bool {
        excludedPoints.contains(point)
    }
    
    private func addExclusionZone(center: CGPoint, radius: CGFloat) {
        let radiusInt = Int(radius)
        for dx in -radiusInt...radiusInt {
            for dy in -radiusInt...radiusInt {
                let x = Int(center.x) + dx
                let y = Int(center.y) + dy
                if x >= 0 && x < imageWidth && y >= 0 && y < imageHeight {
                    if CGPoint(x: center.x - CGFloat(x), y: center.y - CGFloat(y)).length <= radius {
                        excludedPoints.insert(CGPoint(x: x, y: y))
                    }
                }
            }
        }
    }
    
    private func createAnnotatedImage(originalImage: UIImage, whiteLines: [WhiteLine]) -> UIImage? {
        let scaleInv: CGFloat = 1.0 / params.imageScale
        
        UIGraphicsBeginImageContextWithOptions(originalImage.size, false, originalImage.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw original image
        originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
        
        // Draw the zone between lines if we have exactly 2 lines
        if whiteLines.count == 2 {
            // Find the leftmost and rightmost x-coordinates of the lines (convert to original scale)
            let leftLineX = whiteLines.min(by: { $0.xPosition < $1.xPosition })!.xPosition * scaleInv
            let rightLineX = whiteLines.max(by: { $0.xPosition < $1.xPosition })!.xPosition * scaleInv
            
            context.setFillColor(UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.2).cgColor) // Semi-transparent yellow
            let rect = CGRect(x: leftLineX, y: 0, width: rightLineX - leftLineX, height: originalImage.size.height)
            context.fill(rect)
        }
        
        // Draw white lines with pink overlay (scale coordinates)
        context.setFillColor(UIColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 0.3).cgColor) // Pink color
        for line in whiteLines {
            for pixel in line.pixels {
                let rect = CGRect(x: pixel.x * scaleInv - 1, y: pixel.y * scaleInv - 1, width: 3, height: 3)
                context.fillEllipse(in: rect)
            }
        }
        
        // Fill ball areas
        for ball in detectedBalls {
            let fillColor = ball.color == .red ? 
                UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.5) : // Orange for red balls
                UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 0.5)   // Green for blue balls
            
            context.setFillColor(fillColor.cgColor)
            let rect = CGRect(x: ball.center.x - ball.radius,
                            y: ball.center.y - ball.radius,
                            width: ball.radius * 2,
                            height: ball.radius * 2)
            context.fillEllipse(in: rect)
            
            // Draw crosshair
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: ball.center.x - 5, y: ball.center.y))
            context.addLine(to: CGPoint(x: ball.center.x + 5, y: ball.center.y))
            context.move(to: CGPoint(x: ball.center.x, y: ball.center.y - 5))
            context.addLine(to: CGPoint(x: ball.center.x, y: ball.center.y + 5))
            context.strokePath()
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Preview
#if DEBUG
struct BallCounterPreview: View {
    // You can replace this path with your local image path
    private static let localImagePath = "/Users/evanboyle/Downloads/test_image.jpg" // Example path
    
    @State private var image: UIImage? = {
        // Try to load from local path first
        if let localImage = UIImage(contentsOfFile: localImagePath) {
            return localImage
        }
        // Fall back to system photo icon if local file not found
        return UIImage(systemName: "photo")
    }()
    @State private var annotatedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var zoneCounts = ZoneCounts()
    
    // Detection parameters
    @State private var minClusterSize: Double = 50
    @State private var ballRadiusRatio: Double = 0.024
    @State private var exclusionRadiusMultiplier: Double = 1.2
    @State private var whiteMergeThreshold: Double = 20
    
    private var detector: BallCounter {
        BallCounter(parameters: .init(
            minClusterSize: Int(minClusterSize),
            ballRadiusRatio: CGFloat(ballRadiusRatio),
            exclusionRadiusMultiplier: CGFloat(exclusionRadiusMultiplier),
            whiteMergeThreshold: Int(whiteMergeThreshold)
        ))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let annotatedImage = annotatedImage {
                    Image(uiImage: annotatedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Button(action: {
                    showImagePicker = true
                }) {
                    Label("Choose Image", systemImage: "photo.on.rectangle")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                
                // Parameter controls
                VStack(spacing: 10) {
                    ParameterSlider(value: $minClusterSize,
                                  range: 10...200,
                                  label: "Min Cluster Size")
                    
                    ParameterSlider(value: $ballRadiusRatio,
                                  range: 0.02...0.1,
                                  label: "Ball Radius Ratio")
                    
                    ParameterSlider(value: $exclusionRadiusMultiplier,
                                  range: 1.0...2.0,
                                  label: "Exclusion Radius")
                    
                    ParameterSlider(value: $whiteMergeThreshold,
                                  range: 5...50,
                                  label: "White Merge Threshold")
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                
                // Ball counts
                VStack(alignment: .leading) {
                    Text("Ball Counts:")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Group {
                        Text("Middle Zone:")
                            .foregroundColor(.white)
                        HStack {
                            Text("Red: \(zoneCounts.middle.red)")
                                .foregroundColor(.red)
                            Text("Blue: \(zoneCounts.middle.blue)")
                                .foregroundColor(.blue)
                        }
                        
                        Text("Outside Zone:")
                            .foregroundColor(.white)
                        HStack {
                            Text("Red: \(zoneCounts.outside.red)")
                                .foregroundColor(.red)
                            Text("Blue: \(zoneCounts.outside.blue)")
                                .foregroundColor(.blue)
                        }
                        
                        Text("Total:")
                            .foregroundColor(.white)
                        HStack {
                            Text("Red: \(zoneCounts.total.red)")
                                .foregroundColor(.red)
                            Text("Blue: \(zoneCounts.total.blue)")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.leading)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                
                // Detect button
                Button(action: detectBalls) {
                    Label("Detect Balls", systemImage: "wand.and.stars")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .disabled(image == nil)
            }
            .padding()
        }
        .background(Color.black)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $image)
        }
        .onChange(of: image) { _ in
            detectBalls()
        }
    }
    
    private func detectBalls() {
        guard let image = image else { return }
        let result = detector.detectBalls(in: image)
        zoneCounts = result.zoneCounts
        annotatedImage = result.annotatedImage
    }
}

struct ParameterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .foregroundColor(.white)
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: "%.3f", value))
                    .foregroundColor(.white)
                    .frame(width: 60)
            }
        }
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    var length: CGFloat {
        sqrt(x * x + y * y)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    BallCounterPreview()
}
#endif 
