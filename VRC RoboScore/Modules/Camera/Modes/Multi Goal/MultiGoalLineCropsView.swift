import SwiftUI
import UIKit
import Photos
import OSLog
import CoreGraphics
import Foundation
import NotificationCenter

struct LineCrop {
    let image: UIImage
    let color: Color
    let label: String
    let angleRadians: CGFloat
}

// Add these helper functions before the main struct or as extensions

// Move this to the top-level, before greenGoalParameters and LineCropsView
// func greenGoalParameters() -> BallCounter.Parameters {
//     return parametersForGoal(at: 1) // 1 = green goal
// }

struct LineCropsView: View {
    @Binding var isPresented: Bool
    let originalImage: UIImage
    let lineEndpoints: [[CGPoint]] // screen coordinates matching originalImage orientation (landscape)
    let screenSize: CGSize

    // MARK: - State
    @State private var processedCrops: [LineCrop] = []
    @State private var isProcessing: Bool = true
    @State private var showShareSheet: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var hasAnalyzed: Bool = false
    
    // Detection parameters (shared across all crops)
    @State private var redThreshold: CGFloat = 0.25
    @State private var blueThreshold: CGFloat = 0.37
    @State private var whiteThreshold: CGFloat = 0.26
    
    // Analysis results for each crop
    @State private var analysisResults: [CropAnalysisResult] = []
    
    // Make the per-goal detection configs stateful for runtime editing
    @State private var goalDetectionConfigs: [GoalDetectionConfig] = defaultGoalDetectionConfigs

    // MARK: - Constants
    private let perpendicularPaddings: [CGFloat] = [13, 30, 16, 16] // red, green, blue, orange
    private let outwardPadding: CGFloat = 10.0 // Padding at the ends of the line (along the line direction)
    private let colors: [Color] = [.red, .green, .blue, .orange]
    private let labels: [String] = ["Red Line", "Green Line", "Blue Line", "Orange Line"]

    // Helper to get BallCounter.Parameters for a given goal index
    private func parametersForGoal(at index: Int) -> BallCounter.Parameters {
        let config = goalDetectionConfigs[index]
        return BallCounter.Parameters(
            minWhiteLineSize: config.minWhiteLineSize,
            ballRadiusRatio: config.ballRadiusRatio,
            exclusionRadiusMultiplier: config.exclusionRadiusMultiplier,
            whiteMergeThreshold: config.whiteMergeThreshold,
            imageScale: config.imageScale,
            ballAreaPercentage: config.ballAreaPercentage,
            maxBallsInCluster: config.maxBallsInCluster,
            clusterSplitThreshold: config.clusterSplitThreshold,
            minClusterSeparation: config.minClusterSeparation,
            whitePixelConversionDistance: config.whitePixelConversionDistance,
            maxClustersToExpand: config.maxClustersToExpand,
            minClusterSizeToExpand: config.minClusterSizeToExpand,
            pipeType: config.pipeType
        )
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if isProcessing {
                ProgressView("Processing…")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            } else {
                VStack {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Display each crop with its analysis
                            ForEach(0..<processedCrops.count, id: \.self) { idx in
                                CropAnalysisSection(
                                    crop: processedCrops[idx],
                                    analysisResult: idx < analysisResults.count ? analysisResults[idx] : nil,
                                    redThreshold: $redThreshold,
                                    blueThreshold: $blueThreshold,
                                    whiteThreshold: $whiteThreshold
                                )
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)

                    // Control buttons
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            Button(action: { isPresented = false }) {
                                Label("Back", systemImage: "arrow.left")
                            }
                            .buttonStyle(ControlButtonStyle(color: .red))

                            Button(action: saveAll) {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(ControlButtonStyle(color: .green))

                            Button(action: { showShareSheet = true }) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(ControlButtonStyle(color: .blue))
                            
                            Button(action: {
                                Task {
                                    await runAnalysis()
                                }
                            }) {
                                if isAnalyzing {
                                    HStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Analyzing...")
                                    }
                                } else {
                                    Label("Analyze", systemImage: "magnifyingglass")
                                }
                            }
                            .disabled(isAnalyzing)
                            .buttonStyle(ControlButtonStyle(color: .purple))

                            // Add button to return to calculator
                            if hasAnalyzed {
                                Button(action: {
                                    // Extract detected scores from analysisResults (order: Red, Green, Blue, Orange)
                                    guard analysisResults.count == 4 else { return }
                                    let red = analysisResults[0].ballCounts
                                    let green = analysisResults[1].ballCounts
                                    let blue = analysisResults[2].ballCounts
                                    let orange = analysisResults[3].ballCounts

                                    // For long goals, use total counts
                                    let topLongRed = red.total.red
                                    let topLongBlue = red.total.blue
                                    let bottomLongRed = green.total.red
                                    let bottomLongBlue = green.total.blue

                                    // For control: difference in middle zone
                                    let topLongControlDiff = red.middle.blue - red.middle.red
                                    let bottomLongControlDiff = green.middle.blue - green.middle.red

                                    // Short goals (orange = top short, blue = bottom short)
                                    let orangeShortRed = orange.total.red
                                    let orangeShortBlue = orange.total.blue
                                    let blueShortRed = blue.total.red
                                    let blueShortBlue = blue.total.blue

                                    let detected = DetectedGoalScores(
                                        topLongRed: topLongRed,
                                        topLongBlue: topLongBlue,
                                        topLongControlDiff: topLongControlDiff,
                                        bottomLongRed: bottomLongRed,
                                        bottomLongBlue: bottomLongBlue,
                                        bottomLongControlDiff: bottomLongControlDiff,
                                        orangeShortRed: orangeShortRed,
                                        orangeShortBlue: orangeShortBlue,
                                        blueShortRed: blueShortRed,
                                        blueShortBlue: blueShortBlue
                                    )
                                    NotificationCenter.default.post(name: Notification.Name("DetectedGoalScores"), object: nil, userInfo: ["scores": detected])
                                    NotificationCenter.default.post(name: Notification.Name("NavigateToCalculatorHome"), object: nil)
                                    isPresented = false
                                }) {
                                    Label("Add", systemImage: "plus")
                                }
                                .buttonStyle(ControlButtonStyle(color: .orange))
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .sheet(isPresented: $showShareSheet) {
                    ImageShareSheet(crops: processedCrops.enumerated().map { (idx, crop) in
                        // Map color to string (Red, Green, Blue, Orange)
                        let colorNames = ["Red", "Green", "Blue", "Orange"]
                        let colorName = idx < colorNames.count ? colorNames[idx] : "Unknown"
                        return ExportableCrop(image: crop.image, colorName: colorName, angleRadians: crop.angleRadians)
                    })
                }
            }
        }
        .onAppear {
            Task {
                await processImages()
            }
        }
    }

    // MARK: - Actions

    private func saveAll() {
        Logger.debug("Saving all cropped images to photo library", category: .export)
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                Logger.error("Photo library access not authorised", category: .export)
                return
            }
            for crop in processedCrops {
                UIImageWriteToSavedPhotosAlbum(crop.image, nil, nil, nil)
            }
        }
    }
    
    private func runAnalysis() async {
        guard !processedCrops.isEmpty else {
            Logger.error("Cannot analyze - no processed crops available", category: .imageProcessing)
            return
        }
        
        Logger.debug("Starting analysis of \(processedCrops.count) crops", category: .imageProcessing)
        await MainActor.run { isAnalyzing = true }

        // Move the analysis work off the main thread
        let crops = self.processedCrops
        let redThreshold = self.redThreshold
        let blueThreshold = self.blueThreshold
        let whiteThreshold = self.whiteThreshold
        let goalDetectionConfigs = self.goalDetectionConfigs

        let results: [CropAnalysisResult] = await Task.detached(priority: .userInitiated) {
            var results: [CropAnalysisResult] = []

            for (idx, crop) in crops.enumerated() {
                Logger.debug("Analyzing crop \(idx) (\(crop.label))", category: .imageProcessing)

                // Lower white threshold for red goal (idx 0), else use default
                let customWhiteThreshold: CGFloat = (idx == 0) ? 0.18 : whiteThreshold
                // Quantize the image
                guard let quantizedImage = ColorQuantizer.quantize(
                    image: crop.image,
                    redThreshold: redThreshold,
                    blueThreshold: blueThreshold,
                    whiteThreshold: customWhiteThreshold
                ) else {
                    Logger.error("Failed to quantize crop \(idx)", category: .imageProcessing)
                    results.append(CropAnalysisResult(
                        quantizedImage: nil,
                        detectionResult: (zoneCounts: ZoneCounts(), annotatedImage: nil),
                        ballCounts: ZoneCounts()
                    ))
                    continue
                }

                let config = goalDetectionConfigs[idx]
                let params = BallCounter.Parameters(
                    minWhiteLineSize: config.minWhiteLineSize,
                    ballRadiusRatio: config.ballRadiusRatio,
                    exclusionRadiusMultiplier: config.exclusionRadiusMultiplier,
                    whiteMergeThreshold: config.whiteMergeThreshold,
                    imageScale: config.imageScale,
                    ballAreaPercentage: config.ballAreaPercentage,
                    maxBallsInCluster: config.maxBallsInCluster,
                    clusterSplitThreshold: config.clusterSplitThreshold,
                    minClusterSeparation: config.minClusterSeparation,
                    whitePixelConversionDistance: config.whitePixelConversionDistance,
                    maxClustersToExpand: config.maxClustersToExpand,
                    minClusterSizeToExpand: config.minClusterSizeToExpand,
                    pipeType: config.pipeType
                )
                Logger.debug("Params for goal \(idx): \(params)", category: .imageProcessing)
                let detector = BallCounter(parameters: params)
                let detectionResult = detector.detectBalls(in: quantizedImage, pipeType: params.pipeType)

                results.append(CropAnalysisResult(
                    quantizedImage: quantizedImage,
                    detectionResult: detectionResult,
                    ballCounts: detectionResult.zoneCounts
                ))
            }
            return results
        }.value

        await MainActor.run {
            analysisResults = results
            isAnalyzing = false
            hasAnalyzed = true
            Logger.debug("Analysis complete", category: .imageProcessing)
        }
    }


    
    // MARK: - Image Processing

    private func processImages() async {
        Logger.debug("Starting image processing for cropped lines", category: .imageProcessing)
        let uiImage = originalImage
        let imageSize = uiImage.size
        Logger.debug("LineCropsView: originalImage size = \(imageSize.width) x \(imageSize.height)", category: .imageProcessing)

        // Process on background thread for performance
        let crops = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.createCrops(from: uiImage, lineEndpoints: self.lineEndpoints, screenSize: self.screenSize)
                continuation.resume(returning: result)
            }
        }

        await MainActor.run {
            self.processedCrops = crops
            self.isProcessing = false
            Logger.debug("Finished image processing - created \(crops.count) crops", category: .imageProcessing)
        }
    }
    
    // MARK: - Cropping Implementation
    
    private func createCrops(from image: UIImage, lineEndpoints: [[CGPoint]], screenSize: CGSize) -> [LineCrop] {
        var crops: [LineCrop] = []
        let imageSize = image.size
        
        Logger.debug("=== CROP CREATION START ===", category: .imageProcessing)
        Logger.debug("Image size: \(imageSize), Screen size: \(screenSize)", category: .imageProcessing)
        
        // Calculate and log conversion factors
        let imageAspect = imageSize.width / imageSize.height
        let screenAspect = screenSize.width / screenSize.height
        Logger.debug("Aspect ratios - Image: \(imageAspect), Screen: \(screenAspect)", category: .imageProcessing)
        
        // Process each line
        for (index, endpoints) in lineEndpoints.enumerated() {
            guard endpoints.count == 2 else {
                Logger.error("Invalid endpoints for line \(index) - expected 2 points, got \(endpoints.count)", category: .imageProcessing)
                continue
            }
            
            let p0 = endpoints[0]
            let p1 = endpoints[1]
            
            // Only show detailed logging for the first line
            let showDetailedLogging = (index == 0)
            
            if showDetailedLogging {
                Logger.debug("=== LINE \(index) (\(labels[index])) - DETAILED LOGGING ===", category: .imageProcessing)
                Logger.debug("Original endpoints: \(p0) to \(p1)", category: .imageProcessing)
            }
            
            // Calculate crop rectangle corners using the same logic as PreviewCropRectangles
            let cropCorners = calculateCropCorners(p0: p0, p1: p1, outwardPadding: outwardPadding, perpendicularPadding: perpendicularPaddings[index], showLogging: showDetailedLogging)
            
            if showDetailedLogging {
                Logger.debug("Calculated screen corners: \(cropCorners)", category: .imageProcessing)
            }
            
            // Convert screen coordinates to image coordinates using .scaledToFill logic
            let imageCorners = cropCorners.map { screenPoint in
                let pt = screenToImagePoint(screenPoint, imageSize: imageSize, screenSize: screenSize, showLogging: showDetailedLogging)
                return CGPoint(x: min(max(pt.x, 0), imageSize.width), y: min(max(pt.y, 0), imageSize.height))
            }
            
            if showDetailedLogging {
                Logger.debug("Final image corners: \(imageCorners)", category: .imageProcessing)
            }
            
            // Calculate angle in radians
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let angleRadians = atan2(dy, dx)
            
            // Create cropped image
            if let croppedImage = cropImageTight(image, withCorners: imageCorners, showLogging: showDetailedLogging) {
                let crop = LineCrop(
                    image: croppedImage,
                    color: colors[index],
                    label: labels[index],
                    angleRadians: angleRadians
                )
                crops.append(crop)
                Logger.debug("✓ Successfully created crop for \(labels[index]) - Size: \(croppedImage.size)", category: .imageProcessing)
            } else {
                Logger.error("✗ Failed to create crop for \(labels[index])", category: .imageProcessing)
            }
            
            if showDetailedLogging {
                Logger.debug("=== END DETAILED LOGGING FOR LINE \(index) ===", category: .imageProcessing)
            }
        }
        
        Logger.debug("=== CROP CREATION COMPLETE - Created \(crops.count) crops ===", category: .imageProcessing)
        return crops
    }
    
    /// Converts a point in screen coordinates to image coordinates, accounting for .scaledToFill
    private func screenToImagePoint(_ screenPoint: CGPoint, imageSize: CGSize, screenSize: CGSize, showLogging: Bool = false) -> CGPoint {
        let imageAspect = imageSize.width / imageSize.height
        let screenAspect = screenSize.width / screenSize.height
        var scale: CGFloat
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        
        if showLogging {
            Logger.debug("Coordinate conversion for screen point: \(screenPoint)", category: .imageProcessing)
            Logger.debug("  Image aspect: \(imageAspect), Screen aspect: \(screenAspect)", category: .imageProcessing)
        }
        
        if imageAspect > screenAspect {
            // Image is wider than screen: height fits, width overflows
            scale = screenSize.height / imageSize.height
            let scaledImageWidth = imageSize.width * scale
            xOffset = (scaledImageWidth - screenSize.width) / 2
            if showLogging {
                Logger.debug("  Image wider than screen - Scale: \(scale), X offset: \(xOffset)", category: .imageProcessing)
            }
        } else {
            // Image is taller than screen: width fits, height overflows (letterboxing)
            scale = screenSize.width / imageSize.width
            let scaledImageHeight = imageSize.height * scale
            yOffset = (scaledImageHeight - screenSize.height) / 2
            
            // Check if there's any horizontal centering needed
            let scaledImageWidth = imageSize.width * scale
            if scaledImageWidth < screenSize.width {
                xOffset = (screenSize.width - scaledImageWidth) / 2
            }
            
            if showLogging {
                Logger.debug("  Image taller than screen - Scale: \(scale), Y offset: \(yOffset)", category: .imageProcessing)
                Logger.debug("  Scaled image height: \(scaledImageHeight), Screen height: \(screenSize.height)", category: .imageProcessing)
                Logger.debug("  Scaled image width: \(scaledImageWidth), Screen width: \(screenSize.width), X offset: \(xOffset)", category: .imageProcessing)
            }
        }
        
        // Map screen point to image point
        // For letterboxing: the image is displayed with an offset, so add the offset
        let adjustedScreenX = screenPoint.x + xOffset
        let adjustedScreenY = screenPoint.y + yOffset
        let imageX = adjustedScreenX / scale
        let imageY = adjustedScreenY / scale
        
        if showLogging {
            Logger.debug("  Adjusted screen: (\(adjustedScreenX), \(adjustedScreenY))", category: .imageProcessing)
            Logger.debug("  Final image: (\(imageX), \(imageY))", category: .imageProcessing)
        }
        
        return CGPoint(x: imageX, y: imageY)
    }
    
    private func calculateCropCorners(p0: CGPoint, p1: CGPoint, outwardPadding: CGFloat, perpendicularPadding: CGFloat, showLogging: Bool = false) -> [CGPoint] {
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let lineLength = sqrt(dx * dx + dy * dy)
        let angle = atan2(dy, dx)
        
        let sin = CGFloat(sinf(Float(angle)))
        let cos = CGFloat(cosf(Float(angle)))
        
        let halfHeight = perpendicularPadding
        let halfWidth = (lineLength / 2) + outwardPadding
        
        let center = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        
        if showLogging {
            Logger.debug("Corner calculation - Line: \(p0) to \(p1)", category: .imageProcessing)
            Logger.debug("  Line length: \(lineLength), Outward padding: \(outwardPadding), Perpendicular padding: \(perpendicularPadding), Angle: \(angle)", category: .imageProcessing)
            Logger.debug("  Center: \(center), Half-width: \(halfWidth), Half-height: \(halfHeight)", category: .imageProcessing)
            Logger.debug("  Trig values - sin: \(sin), cos: \(cos)", category: .imageProcessing)
        }
        
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
        
        if showLogging {
            Logger.debug("  Calculated corners: \(corners)", category: .imageProcessing)
        }
        
        return corners
    }
    
    /// Crops the image to the tight bounding box of the rotated crop, so no extra black space is included
    private func cropImageTight(_ image: UIImage, withCorners corners: [CGPoint], showLogging: Bool = false) -> UIImage? {
        guard corners.count == 4 else {
            Logger.error("Invalid number of corners for cropping - expected 4, got \(corners.count)", category: .imageProcessing)
            return nil
        }
        let imageSize = image.size
        // Find bounding box
        let minX = corners.map { $0.x }.min() ?? 0
        let maxX = corners.map { $0.x }.max() ?? imageSize.width
        let minY = corners.map { $0.y }.min() ?? 0
        let maxY = corners.map { $0.y }.max() ?? imageSize.height
        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        
        if showLogging {
            Logger.debug("Crop bounds calculation:", category: .imageProcessing)
            Logger.debug("  Input corners: \(corners)", category: .imageProcessing)
            Logger.debug("  Min/Max X: \(minX) to \(maxX)", category: .imageProcessing)
            Logger.debug("  Min/Max Y: \(minY) to \(maxY)", category: .imageProcessing)
            Logger.debug("  Bounding box: \(cropRect)", category: .imageProcessing)
            Logger.debug("  Image size: \(imageSize)", category: .imageProcessing)
        }
        
        // Create graphics context for the tight crop
        UIGraphicsBeginImageContextWithOptions(cropRect.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else {
            Logger.error("Failed to create graphics context for cropping", category: .imageProcessing)
            return nil
        }
        // Move context so that cropRect's origin is at (0,0)
        context.translateBy(x: -cropRect.origin.x, y: -cropRect.origin.y)
        // Create clipping path from corners
        let path = CGMutablePath()
        path.move(to: corners[0])
        for i in 1..<corners.count {
            path.addLine(to: corners[i])
        }
        path.closeSubpath()
        context.addPath(path)
        context.clip()
        // Draw the original image (this will be clipped to the path)
        image.draw(in: CGRect(origin: .zero, size: imageSize))
        // Get the cropped image
        guard let croppedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            Logger.error("Failed to get cropped image from graphics context", category: .imageProcessing)
            return nil
        }
        
        if showLogging {
            Logger.debug("Crop result - Original: \(imageSize), Crop rect: \(cropRect.size), Final: \(croppedImage.size)", category: .imageProcessing)
        }
        
        return croppedImage
    }
}

// MARK: - Data Structures

struct CropAnalysisResult {
    let quantizedImage: UIImage?
    let detectionResult: (zoneCounts: ZoneCounts, annotatedImage: UIImage?)
    let ballCounts: ZoneCounts
}

// MARK: - Crop Analysis Section

struct CropAnalysisSection: View {
    let crop: LineCrop
    let analysisResult: CropAnalysisResult?
    @Binding var redThreshold: CGFloat
    @Binding var blueThreshold: CGFloat
    @Binding var whiteThreshold: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Crop label with angle in radians
            Text("\(crop.label) - \(String(format: "%.2f", crop.angleRadians)) rad")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.leading, 8)
            
            // Original crop
            Image(uiImage: crop.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(crop.color, lineWidth: 4)
                )
                .cornerRadius(8)
            
            // Detection overlay and ball counts (quantized image removed)
            if let analysisResult = analysisResult {
                let detectionResult = analysisResult.detectionResult
                if let annotatedImage = detectionResult.annotatedImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detection")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                        Image(uiImage: annotatedImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .background(Color.black)
                            .cornerRadius(8)
                    }
                }
                // Compact ball counts
                CompactBallCountsDisplay(ballCounts: analysisResult.ballCounts)
            }
        }
    }
}

// MARK: - Compact Ball Counts Display

struct CompactBallCountsDisplay: View {
    let ballCounts: ZoneCounts
    
    var body: some View {
        HStack(spacing: 16) {
            // Middle zone
            VStack(alignment: .leading, spacing: 4) {
                Text("Middle")
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.red)
                            .frame(width: 8, height: 8)
                        Text("\(ballCounts.middle.red)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.blue)
                            .frame(width: 8, height: 8)
                        Text("\(ballCounts.middle.blue)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Outside zone
            VStack(alignment: .leading, spacing: 4) {
                Text("Outside")
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.red)
                            .frame(width: 8, height: 8)
                        Text("\(ballCounts.outside.red)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.blue)
                            .frame(width: 8, height: 8)
                        Text("\(ballCounts.outside.blue)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Total
            VStack(alignment: .leading, spacing: 4) {
                Text("Total")
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.red)
                            .frame(width: 8, height: 8)
                        Text("\(ballCounts.total.red)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.blue)
                            .frame(width: 8, height: 8)
                        Text("\(ballCounts.total.blue)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Control Button Style
struct ControlButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(color.opacity(configuration.isPressed ? 0.6 : 0.9))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

// MARK: - Image Share Sheet
// New struct to hold image and metadata for export
struct ExportableCrop {
    let image: UIImage
    let colorName: String
    let angleRadians: CGFloat
}

struct ImageShareSheet: UIViewControllerRepresentable {
    let crops: [ExportableCrop]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        Logger.debug("Presenting ImageShareSheet with \(crops.count) images as PNGs", category: .export)
        // Convert images to PNG data and write to temporary files with custom names
        let tempURLs: [URL] = crops.compactMap { crop in
            guard let pngData = crop.image.pngData() else { return nil }
            let tempDir = FileManager.default.temporaryDirectory
            let angleString = String(format: "%.2f", crop.angleRadians)
            let filename = "\(crop.colorName)Goal_\(angleString).png"
            let fileURL = tempDir.appendingPathComponent(filename)
            do {
                try pngData.write(to: fileURL)
                return fileURL
            } catch {
                Logger.error("Failed to write PNG file: \(error)", category: .export)
                return nil
            }
        }
        return UIActivityViewController(activityItems: tempURLs, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 

// MARK: - Preview
#Preview {
    GoalImagesPreviewView()
}

// MARK: - Goal Images Preview View
struct GoalImagesPreviewView: View {
    // Load the goal images from assets - these are already cropped
    let goalImageSetNames = ["GoalRed", "GoalGreen", "GoalBlue", "GoalOrange"]
    let goalImages: [UIImage] = [
        UIImage(named: "GoalRed") ?? UIImage(),
        UIImage(named: "GoalGreen") ?? UIImage(),
        UIImage(named: "GoalBlue") ?? UIImage(),
        UIImage(named: "GoalOrange") ?? UIImage()
    ]
    // Principal angles for each goal image (in radians)
    let goalAngles: [CGFloat] = [
        /* Red,   Green,   Blue,   Orange */
           0.01,    0.00,   -0.36,   0.30
    ]
    
    let colors: [Color] = [.red, .green, .blue, .orange]
    let labels: [String] = ["Red Goal", "Green Goal", "Blue Goal", "Orange Goal"]
    
    // Analysis state
    @State private var analysisResults: [CropAnalysisResult] = []
    @State private var isAnalyzing: Bool = false
    @State private var showShareSheet: Bool = false
    
    // Detection parameters (shared across all crops)
    @State private var redThreshold: CGFloat = 0.25
    @State private var blueThreshold: CGFloat = 0.37
    @State private var whiteThreshold: CGFloat = 0.26
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(0..<goalImages.count, id: \.self) { idx in
                            VStack(alignment: .leading, spacing: 16) {
                                // Goal label
                                Text(labels[idx])
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.leading, 8)
                                
                                // Goal image
                                Image(uiImage: goalImages[idx])
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(colors[idx], lineWidth: 4)
                                    )
                                    .cornerRadius(8)
                                
                                // Analysis results if available
                                if idx < analysisResults.count {
                                    let result = analysisResults[idx]
                                    // Detection overlay and ball counts (quantized image removed)
                                    let detectionResult = result.detectionResult
                                    if let annotatedImage = detectionResult.annotatedImage {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Detection")
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                                .padding(.leading, 8)
                                            Image(uiImage: annotatedImage)
                                                .resizable()
                                                .interpolation(.high)
                                                .aspectRatio(contentMode: .fit)
                                                .background(Color.black)
                                                .cornerRadius(8)
                                        }
                                    }
                                    // Compact ball counts
                                    CompactBallCountsDisplay(ballCounts: result.ballCounts)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black)
                
                // Control buttons
                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        Button(action: saveAll) {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(ControlButtonStyle(color: .green))
                        
                        Button(action: { showShareSheet = true }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ControlButtonStyle(color: .blue))
                        
                        Button(action: {
                            Task {
                                await runAnalysis()
                            }
                        }) {
                            if isAnalyzing {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Analyzing...")
                                }
                            } else {
                                Label("Analyze", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(isAnalyzing)
                        .buttonStyle(ControlButtonStyle(color: .purple))
                    }
                }
                .padding(.bottom, 20)
            }
            .task {
                if analysisResults.isEmpty && !isAnalyzing {
                    await runAnalysis()
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ImageShareSheet(crops: goalImages.enumerated().map { (idx, image) in
                    // Map color to string (Red, Green, Blue, Orange)
                    let colorNames = ["Red", "Green", "Blue", "Orange"]
                    let colorName = idx < colorNames.count ? colorNames[idx] : "Unknown"
                    let angle = idx < goalAngles.count ? goalAngles[idx] : 0.0
                    return ExportableCrop(image: image, colorName: colorName, angleRadians: angle)
                })
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveAll() {
        Logger.debug("Saving all goal images to photo library", category: .export)
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                Logger.error("Photo library access not authorised", category: .export)
                return
            }
            for image in goalImages {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }
    
    private func runAnalysis() async {
        guard !goalImages.isEmpty else {
            Logger.error("Cannot analyze - no goal images available", category: .imageProcessing)
            return
        }
        
        Logger.debug("Starting analysis of \(goalImages.count) goal images", category: .imageProcessing)
        await MainActor.run { isAnalyzing = true }

        // Move the analysis work off the main thread
        let crops = self.goalImages
        let redThreshold = self.redThreshold
        let blueThreshold = self.blueThreshold
        let whiteThreshold = self.whiteThreshold
        let goalDetectionConfigs = defaultGoalDetectionConfigs

        let results: [CropAnalysisResult] = await Task.detached(priority: .userInitiated) {
            var results: [CropAnalysisResult] = []

            for (idx, image) in crops.enumerated() {
                Logger.debug("Analyzing goal image \(idx) (\(labels[idx]))", category: .imageProcessing)

                // Lower white threshold for red goal (idx 0), else use default
                let customWhiteThreshold: CGFloat = (idx == 0) ? 0.18 : whiteThreshold
                
                // Quantize the image
                guard let quantizedImage = ColorQuantizer.quantize(
                    image: image,
                    redThreshold: redThreshold,
                    blueThreshold: blueThreshold,
                    whiteThreshold: customWhiteThreshold
                ) else {
                    Logger.error("Failed to quantize goal image \(idx)", category: .imageProcessing)
                    results.append(CropAnalysisResult(
                        quantizedImage: nil,
                        detectionResult: (zoneCounts: ZoneCounts(), annotatedImage: nil),
                        ballCounts: ZoneCounts()
                    ))
                    continue
                }
                
                // Use default goal detection configs for analysis
                let config = goalDetectionConfigs[idx]
                let angle = idx < goalAngles.count ? goalAngles[idx] : 0.0
                let params = BallCounter.Parameters(
                    minWhiteLineSize: config.minWhiteLineSize,
                    ballRadiusRatio: config.ballRadiusRatio,
                    exclusionRadiusMultiplier: config.exclusionRadiusMultiplier,
                    whiteMergeThreshold: config.whiteMergeThreshold,
                    imageScale: config.imageScale,
                    ballAreaPercentage: config.ballAreaPercentage,
                    maxBallsInCluster: config.maxBallsInCluster,
                    clusterSplitThreshold: config.clusterSplitThreshold,
                    minClusterSeparation: config.minClusterSeparation,
                    whitePixelConversionDistance: config.whitePixelConversionDistance,
                    maxClustersToExpand: config.maxClustersToExpand,
                    minClusterSizeToExpand: config.minClusterSizeToExpand,
                    pipeType: config.pipeType
                )
                
                Logger.debug("Params for goal \(idx): \(params)", category: .imageProcessing)
                let detector = BallCounter(parameters: params)
                let detectionResult = detector.detectBalls(in: quantizedImage, pipeType: params.pipeType, principalAngle: angle)
                
                results.append(CropAnalysisResult(
                    quantizedImage: quantizedImage,
                    detectionResult: detectionResult,
                    ballCounts: detectionResult.zoneCounts
                ))
            }
            return results
        }.value

        await MainActor.run {
            analysisResults = results
            isAnalyzing = false
            Logger.debug("Analysis complete", category: .imageProcessing)
        }
    }
} 

// Struct for detected goal scores payload
struct DetectedGoalScores: Codable {
    let topLongRed: Int
    let topLongBlue: Int
    let topLongControlDiff: Int
    let bottomLongRed: Int
    let bottomLongBlue: Int
    let bottomLongControlDiff: Int
    let orangeShortRed: Int
    let orangeShortBlue: Int
    let blueShortRed: Int
    let blueShortBlue: Int
} 
