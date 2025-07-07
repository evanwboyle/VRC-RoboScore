import SwiftUI
import UIKit
import Photos
import OSLog
import CoreGraphics

struct LineCrop {
    let image: UIImage
    let color: Color
    let label: String
}

// Add these helper functions before the main struct or as extensions

struct LineCropsView: View {
    @Environment(\.presentationMode) private var presentationMode
    let originalImage: UIImage
    let lineEndpoints: [[CGPoint]] // screen coordinates matching originalImage orientation (landscape)
    let screenSize: CGSize

    // MARK: - State
    @State private var processedCrops: [LineCrop] = []
    @State private var isProcessing: Bool = true
    @State private var showShareSheet: Bool = false
    @State private var paddingEnabled: Bool = true
    @State private var isAnalyzing: Bool = false
    
    // Detection parameters (shared across all crops)
    @State private var redThreshold: CGFloat = 0.25
    @State private var blueThreshold: CGFloat = 0.37
    @State private var whiteThreshold: CGFloat = 0.26
    @State private var regionSensitivity: CGFloat = 1.0
    @State private var ballRadiusRatio: Double = AppSettingsManager.shared.ballRadiusRatio
    @State private var exclusionRadiusMultiplier: Double = AppSettingsManager.shared.exclusionRadiusMultiplier
    @State private var ballAreaPercentage: Double = AppSettingsManager.shared.ballAreaPercentage
    @State private var whitePixelConversionDistance: Double = 5.0
    @State private var coloredPixelThreshold: Double = 10.0
    
    // Analysis results for each crop
    @State private var analysisResults: [CropAnalysisResult] = []
    
    // MARK: - Constants
    private let minPadding: CGFloat = 20.0 // Minimum padding in pixels
    private let paddingRatio: CGFloat = 0.05 // 5% of line length
    private let colors: [Color] = [.red, .green, .blue, .orange]
    private let labels: [String] = ["Red Line", "Green Line", "Blue Line", "Orange Line"]

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
                                    whiteThreshold: $whiteThreshold,
                                    regionSensitivity: $regionSensitivity,
                                    ballRadiusRatio: $ballRadiusRatio,
                                    exclusionRadiusMultiplier: $exclusionRadiusMultiplier,
                                    ballAreaPercentage: $ballAreaPercentage,
                                    whitePixelConversionDistance: $whitePixelConversionDistance,
                                    coloredPixelThreshold: $coloredPixelThreshold
                                )
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)

                    // Control buttons
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            Button(action: { presentationMode.wrappedValue.dismiss() }) {
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
                        }
                        
                        Button(action: {
                            paddingEnabled.toggle()
                            Task {
                                await processImages()
                            }
                        }) {
                            Label(paddingEnabled ? "Disable Padding" : "Enable Padding", 
                                  systemImage: paddingEnabled ? "square.slash" : "square")
                        }
                        .buttonStyle(ControlButtonStyle(color: .orange))
                    }
                    .padding(.bottom, 20)
                }
                .sheet(isPresented: $showShareSheet) {
                    ImageShareSheet(images: processedCrops.map { $0.image })
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
        isAnalyzing = true
        
        var results: [CropAnalysisResult] = []
        
        for (idx, crop) in processedCrops.enumerated() {
            Logger.debug("Analyzing crop \(idx) (\(crop.label))", category: .imageProcessing)
            
            // Quantize the image
            guard let quantizedImage = ColorQuantizer.quantize(
                image: crop.image,
                redThreshold: redThreshold,
                blueThreshold: blueThreshold,
                whiteThreshold: whiteThreshold
            ) else {
                Logger.error("Failed to quantize crop \(idx)", category: .imageProcessing)
                results.append(CropAnalysisResult(
                    quantizedImage: nil,
                    detectionResult: nil,
                    ballCounts: ZoneCounts()
                ))
                continue
            }
            
            // Run detection
            let detectionResult = await runDetection(on: quantizedImage)
            
            results.append(CropAnalysisResult(
                quantizedImage: quantizedImage,
                detectionResult: detectionResult,
                ballCounts: detectionResult?.zoneCounts ?? ZoneCounts()
            ))
        }
        
        await MainActor.run {
            analysisResults = results
            isAnalyzing = false
            Logger.debug("Analysis complete", category: .imageProcessing)
        }
    }
    
    private func runDetection(on image: UIImage) async -> (zoneCounts: ZoneCounts, annotatedImage: UIImage?)? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var params = BallCounter.Parameters(
                    minWhiteLineSize: Int(50.0 * regionSensitivity),
                    ballRadiusRatio: CGFloat(ballRadiusRatio),
                    exclusionRadiusMultiplier: CGFloat(exclusionRadiusMultiplier),
                    whiteMergeThreshold: 20,
                    imageScale: 1.0,
                    ballAreaPercentage: ballAreaPercentage
                )
                params.whitePixelConversionDistance = Int(whitePixelConversionDistance)
                params.coloredPixelThreshold = Int(coloredPixelThreshold)
                let detector = BallCounter(parameters: params)
                let result = detector.detectBalls(in: image)
                
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Image Processing

    private func processImages() async {
        Logger.debug("Starting image processing for cropped lines", category: .imageProcessing)
        let uiImage = originalImage
        let imageSize = uiImage.size
        Logger.debug("LineCropsView: originalImage size = \(imageSize.width) x \(imageSize.height)", category: .imageProcessing)

        // All cropping logic removed. No crops will be produced.
        await MainActor.run {
            self.processedCrops = []
            self.isProcessing = false
            Logger.debug("Finished image processing (no crops produced)", category: .imageProcessing)
        }
    }
}

// MARK: - Data Structures

struct CropAnalysisResult {
    let quantizedImage: UIImage?
    let detectionResult: (zoneCounts: ZoneCounts, annotatedImage: UIImage?)?
    let ballCounts: ZoneCounts
}

// MARK: - Crop Analysis Section

struct CropAnalysisSection: View {
    let crop: LineCrop
    let analysisResult: CropAnalysisResult?
    @Binding var redThreshold: CGFloat
    @Binding var blueThreshold: CGFloat
    @Binding var whiteThreshold: CGFloat
    @Binding var regionSensitivity: CGFloat
    @Binding var ballRadiusRatio: Double
    @Binding var exclusionRadiusMultiplier: Double
    @Binding var ballAreaPercentage: Double
    @Binding var whitePixelConversionDistance: Double
    @Binding var coloredPixelThreshold: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Crop label
            Text(crop.label)
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
            
            // Quantized image
            if let analysisResult = analysisResult,
               let quantizedImage = analysisResult.quantizedImage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quantized")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                    
                    Image(uiImage: quantizedImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .background(Color.black)
                        .cornerRadius(8)
                }
                
                // Detection overlay
                if let detectionResult = analysisResult.detectionResult,
                   let annotatedImage = detectionResult.annotatedImage {
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
struct ImageShareSheet: UIViewControllerRepresentable {
    let images: [UIImage]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        Logger.debug("Presenting ImageShareSheet with \(images.count) images", category: .export)
        return UIActivityViewController(activityItems: images, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 
