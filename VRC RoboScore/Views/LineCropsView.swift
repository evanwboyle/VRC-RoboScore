import SwiftUI
import UIKit
import Photos
import OSLog

struct LineCrop {
    let image: UIImage
    let color: Color
    let label: String
}

struct LineCropsView: View {
    @Environment(\.presentationMode) private var presentationMode
    let originalImage: UIImage
    let lineEndpoints: [[CGPoint]] // relative 0-1 positions matching originalImage orientation (landscape)

    // MARK: - State
    @State private var processedCrops: [LineCrop] = []
    @State private var isProcessing: Bool = true
    @State private var showShareSheet: Bool = false
    @State private var paddingEnabled: Bool = true
    @State private var showDetectionAnalysisView: Bool = false
    @State private var detectionSession: DetectionSession? = nil
    @State private var isAnalyzing: Bool = false
    @State private var analysisError: String? = nil

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
                            ForEach(0..<processedCrops.count, id: \.self) { idx in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(processedCrops[idx].label)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.leading, 8)
                                    Image(uiImage: processedCrops[idx].image)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(processedCrops[idx].color, lineWidth: 4)
                                        )
                                        .cornerRadius(8)
                                }
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
                                    guard !processedCrops.isEmpty else {
                                        Logger.error("Cannot analyze - no processed crops available", category: .imageProcessing)
                                        return
                                    }
                                    
                                    Logger.debug("Analyze pressed – starting detection", category: .imageProcessing)
                                    
                                    // Reset state
                                    analysisError = nil
                                    isAnalyzing = true
                                    
                                    do {
                                        // Add artificial delay to ensure UI updates
                                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                        
                                        let coordinator = BallDetectionCoordinator()
                                        let session = await coordinator.analyze(croppedImages: processedCrops)
                                        
                                        await MainActor.run {
                                            detectionSession = session
                                            isAnalyzing = false
                                            showDetectionAnalysisView = true
                                        }
                                        
                                        Logger.debug("Detection complete - showing analysis view", category: .imageProcessing)
                                    } catch {
                                        Logger.error("Detection failed: \(error.localizedDescription)", category: .imageProcessing)
                                        await MainActor.run {
                                            analysisError = error.localizedDescription
                                            isAnalyzing = false
                                        }
                                    }
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
                        
                        if let error = analysisError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
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
                .sheet(isPresented: $showDetectionAnalysisView) {
                    if let session = detectionSession {
                        NavigationView {
                            DetectionAnalysisView(session: session)
                        }
                    }
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

    // MARK: - Image Processing

    private func processImages() async {
        Logger.debug("Starting image processing for cropped lines", category: .imageProcessing)
        let uiImage = originalImage
        let imageSize = uiImage.size
        var tempCrops: [LineCrop] = []

        // Calculate scaling factors based on how the image is displayed in MultiGoalCameraView
        let screenAspect: CGFloat = 2256.0 / 1179.0 // Your screen dimensions
        let imageAspect = imageSize.width / imageSize.height
        
        // Calculate the scaling factors
        let (scaleX, scaleY): (CGFloat, CGFloat)
        let (offsetX, offsetY): (CGFloat, CGFloat)
        
        if imageAspect > screenAspect {
            scaleY = imageSize.height
            scaleX = scaleY * screenAspect
            offsetX = (imageSize.width - scaleX) / 2
            offsetY = 0
        } else {
            scaleX = imageSize.width
            scaleY = scaleX / screenAspect
            offsetX = 0
            offsetY = (imageSize.height - scaleY) / 2
        }
        
        Logger.debug("Image scaling - aspect ratios: screen=\(screenAspect), image=\(imageAspect)", category: .imageProcessing)
        Logger.debug("Scaling factors: x=\(scaleX), y=\(scaleY), offsets: x=\(offsetX), y=\(offsetY)", category: .imageProcessing)

        for i in 0..<min(4, lineEndpoints.count) {
            let rel = lineEndpoints[i]
            guard rel.count == 2 else { continue }

            // Convert relative coordinates to image coordinates
            let p0 = CGPoint(
                x: rel[0].x * scaleX + offsetX,
                y: rel[0].y * scaleY + offsetY
            )
            let p1 = CGPoint(
                x: rel[1].x * scaleX + offsetX,
                y: rel[1].y * scaleY + offsetY
            )

            // Calculate line properties
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let lineLength = sqrt(dx * dx + dy * dy)
            let padding = paddingEnabled ? max(minPadding, lineLength * paddingRatio) : 5 // Minimum 5 pixels when disabled
            let angle = atan2(dy, dx)
            
            Logger.debug("Line \(i) - length: \(lineLength), padding: \(padding), angle: \(angle * 180 / .pi)°", category: .imageProcessing)

            // Calculate corners of the rotated rectangle
            let sin = CGFloat(sinf(Float(angle)))
            let cos = CGFloat(cosf(Float(angle)))
            
            // Calculate the four corners of our padded rectangle
            let halfHeight = padding
            let halfWidth = (lineLength + 2 * padding) / 2
            
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
            
            // Find the bounding box of our rotated rectangle
            let minX = max(0, corners.map { $0.x }.min() ?? 0)
            let maxX = min(imageSize.width, corners.map { $0.x }.max() ?? imageSize.width)
            let minY = max(0, corners.map { $0.y }.min() ?? 0)
            let maxY = min(imageSize.height, corners.map { $0.y }.max() ?? imageSize.height)
            
            // Create a context sized to the bounding box
            let contextWidth = ceil(maxX - minX)
            let contextHeight = ceil(maxY - minY)
            
            guard contextWidth > 0 && contextHeight > 0 else {
                Logger.error("Invalid context dimensions: \(contextWidth) x \(contextHeight)", category: .imageProcessing)
                continue
            }
            
            Logger.debug("Line \(i) crop bounds: (\(minX), \(minY)) to (\(maxX), \(maxY))", category: .imageProcessing)
            
            UIGraphicsBeginImageContextWithOptions(CGSize(width: contextWidth, height: contextHeight), false, uiImage.scale)
            guard let context = UIGraphicsGetCurrentContext() else { continue }
            
            // Draw the image offset by the bounding box
            context.translateBy(x: -minX, y: -minY)
            uiImage.draw(at: .zero)
            
            // Create a path for the rotated rectangle and clip
            let path = UIBezierPath()
            path.move(to: corners[0])
            for i in 1...3 {
                path.addLine(to: corners[i])
            }
            path.close()
            path.addClip()
            
            // Draw the image again after clipping
            uiImage.draw(at: .zero)
            
            guard let croppedImage = UIGraphicsGetImageFromCurrentImageContext() else { continue }
            UIGraphicsEndImageContext()
            
            // Now create a second context to rotate the image to horizontal
            let finalWidth = lineLength + 2 * padding
            let finalHeight = 2 * padding
            
            Logger.debug("Line \(i) final dimensions: \(finalWidth) x \(finalHeight)", category: .imageProcessing)
            
            UIGraphicsBeginImageContextWithOptions(CGSize(width: finalWidth, height: finalHeight), false, uiImage.scale)
            guard let finalContext = UIGraphicsGetCurrentContext() else { continue }
            
            // Set up the transform to position and rotate the image
            let transform = CGAffineTransform.identity
                .translatedBy(x: finalWidth / 2, y: finalHeight / 2)
                .rotated(by: -angle)
                .translatedBy(x: -center.x + minX, y: -center.y + minY)
            
            finalContext.concatenate(transform)
            croppedImage.draw(at: .zero)
            
            guard let finalImage = UIGraphicsGetImageFromCurrentImageContext() else { continue }
            UIGraphicsEndImageContext()
            
            tempCrops.append(LineCrop(image: finalImage, color: colors[i], label: labels[i]))
        }

        await MainActor.run {
            self.processedCrops = tempCrops
            self.isProcessing = false
            Logger.debug("Finished image processing", category: .imageProcessing)
        }
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
