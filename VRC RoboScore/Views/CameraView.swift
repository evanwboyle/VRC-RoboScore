import SwiftUI
import UIKit
import AVFoundation
import Combine
import CoreImage
import Foundation

struct CameraView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var showCamera = true
    @State private var capturedImage: UIImage?
    @State private var croppedImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    @State private var dragThreshold: CGFloat = 10.0
    @State private var isDragging: Bool = false
    @State private var rotationThreshold: Angle = Angle(degrees: 5.0)
    @State private var isRotating: Bool = false
    @StateObject private var appSettings = AppSettingsManager.shared
    
    // Color threshold states
    @State private var redThreshold: CGFloat = 0.25
    @State private var blueThreshold: CGFloat = 0.37
    @State private var whiteThreshold: CGFloat = 0.26
    @State private var showThresholdControls: Bool = false
    @State private var regionSensitivity: CGFloat = 1.0
    
    // Detection parameter states
    @State private var showDetectionControls: Bool = false
    @State private var ballRadiusRatio: Double = AppSettingsManager.shared.ballRadiusRatio
    @State private var exclusionRadiusMultiplier: Double = AppSettingsManager.shared.exclusionRadiusMultiplier
    @State private var ballAreaPercentage: Double = AppSettingsManager.shared.ballAreaPercentage
    
    @State private var ballCounts = ZoneCounts()
    @State private var currentDetectionResult: (zoneCounts: ZoneCounts, annotatedImage: UIImage?)? = nil
    
    @State private var lastCapturedImage: UIImage? = nil
    @State private var isProcessing: Bool = false
    @State private var whitePixelConversionDistance: Double = 5.0
    @State private var coloredPixelThreshold: Double = 10.0
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 0.2), 3.0)
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: dragThreshold)
            .onChanged { value in
                if !isDragging && abs(value.translation.width) > dragThreshold || abs(value.translation.height) > dragThreshold {
                    isDragging = true
                }
                
                if isDragging {
                    // Calculate rotation-adjusted translation
                    let angle = rotation.radians
                    let translationX = value.translation.width
                    let translationY = value.translation.height
                    
                    // Apply rotation transformation to the translation
                    let rotatedX = translationX * Foundation.cos(angle) + translationY * Foundation.sin(angle)
                    let rotatedY = -translationX * Foundation.sin(angle) + translationY * Foundation.cos(angle)
                    
                    let newOffset = CGSize(
                        width: lastOffset.width + rotatedX,
                        height: lastOffset.height + rotatedY
                    )
                    offset = newOffset
                }
            }
            .onEnded { _ in
                lastOffset = offset
                isDragging = false
            }
    }
    
    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                if !isRotating && abs(value.degrees) > rotationThreshold.degrees {
                    isRotating = true
                }
                
                if isRotating {
                    rotation = lastRotation + value
                }
            }
            .onEnded { _ in
                lastRotation = rotation
                isRotating = false
            }
    }
    
    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(magnificationGesture, dragGesture),
            rotationGesture
        )
    }
    
    private func imageView(screenGeometry: GeometryProxy, image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height)
            .rotationEffect(rotation)
            .gesture(combinedGesture)
    }
    
    private func debugOverlays(screenGeometry: GeometryProxy) -> some View {
        Group {
            if appSettings.debugMode {
                // Visual feedback for drag threshold
                if isDragging {
                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .position(x: screenGeometry.size.width * 0.9, y: screenGeometry.size.height * 0.15)
                        .overlay(
                            Image(systemName: "hand.draw")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                        )
                }
                
                // Visual feedback for rotation threshold
                if isRotating {
                    Circle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .position(x: screenGeometry.size.width * 0.9, y: screenGeometry.size.height * 0.2)
                        .overlay(
                            Image(systemName: "rotate.3d")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                        )
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            if let croppedImage = croppedImage {
                // Cropped page
                VStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Spacer()
                                .frame(height: 20)
                            
                            // Original cropped image
                            OriginalImageSection(croppedImage: croppedImage)
                            
                            // Quantized and Detection sections
                            QuantizedImageSection(
                                croppedImage: croppedImage,
                                redThreshold: $redThreshold,
                                blueThreshold: $blueThreshold,
                                whiteThreshold: $whiteThreshold,
                                showThresholdControls: $showThresholdControls,
                                regionSensitivity: $regionSensitivity,
                                showDetectionControls: $showDetectionControls,
                                ballRadiusRatio: $ballRadiusRatio,
                                exclusionRadiusMultiplier: $exclusionRadiusMultiplier,
                                ballAreaPercentage: $ballAreaPercentage,
                                ballCounts: $ballCounts,
                                currentDetectionResult: $currentDetectionResult,
                                whitePixelConversionDistance: $whitePixelConversionDistance,
                                coloredPixelThreshold: $coloredPixelThreshold
                            )
                        }
                    }
                    
                    HStack(spacing: 20) {
                        Button("Back") {
                            self.croppedImage = nil
                            self.currentDetectionResult = nil
                            self.ballCounts = ZoneCounts()
                            self.scale = 1.0
                            self.offset = .zero
                            self.lastOffset = .zero
                            self.rotation = .zero
                            self.lastRotation = .zero
                            self.isDragging = false
                            self.isRotating = false
                        }
                        .buttonStyle(AppleButtonStyle(color: .blue))
                        
                        Button("Done") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(AppleButtonStyle(color: .green))
                    }
                    .padding(.bottom, 50)
                }
                .background(Color.black)
                .edgesIgnoringSafeArea(.all)
            } else if let image = capturedImage {
                GeometryReader { screenGeometry in
                    ZStack(alignment: .center) {
                        Color.black.edgesIgnoringSafeArea(.all)
                        
                        imageView(screenGeometry: screenGeometry, image: image)
                        
                        // Neon line overlay using actual screen dimensions
                        Rectangle()
                            .fill(Color(red: 0.0, green: 1.0, blue: 0.3))
                            .frame(width: screenGeometry.size.width * 0.85, height: 6)
                            .position(x: screenGeometry.size.width / 2, y: screenGeometry.size.height * 0.5)
                        
                        debugOverlays(screenGeometry: screenGeometry)
                    }
                    .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
                }
                .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button("Retake") {
                            capturedImage = nil
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                            rotation = .zero
                            lastRotation = .zero
                            isDragging = false
                            isRotating = false
                        }
                        .buttonStyle(AppleButtonStyle(color: .red))
                        
                        Button("Continue") {
                            if let cropped = createCroppedImage(from: image, screenWidth: UIScreen.main.bounds.width, screenHeight: UIScreen.main.bounds.height, scale: scale, offset: offset, rotation: rotation) {
                                croppedImage = cropped
                            }
                        }
                        .buttonStyle(AppleButtonStyle(color: .green))
                    }
                    .padding(.bottom, 50)
                }
            } else {
                CustomCameraView(capturedImage: $capturedImage)
                    .edgesIgnoringSafeArea(.all)
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
    }
    
    // Helper to normalize UIImage orientation
    private func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalized
    }

    private func createCroppedImage(from image: UIImage, screenWidth: CGFloat, screenHeight: CGFloat, scale: CGFloat, offset: CGSize, rotation: Angle) -> UIImage? {
        // Normalize image orientation
        let image = normalizedImage(image)
        
        // Calculate rotated size components
        let cosRotation = cos(rotation.radians)
        let sinRotation = sin(rotation.radians)
        let rotatedWidth = abs(image.size.width * cosRotation) + abs(image.size.height * sinRotation)
        let rotatedHeight = abs(image.size.width * sinRotation) + abs(image.size.height * cosRotation)
        let rotatedSize = CGSize(width: rotatedWidth, height: rotatedHeight)
        
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // Move to center of new context
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        
        // Rotate context
        context.rotate(by: rotation.radians)
        
        // Calculate draw rect
        let drawX = -image.size.width / 2
        let drawY = -image.size.height / 2
        let drawRect = CGRect(x: drawX, y: drawY, width: image.size.width, height: image.size.height)
        
        // Draw image centered in context
        image.draw(in: drawRect)
        
        // Get the rotated image
        guard let rotatedImage = UIGraphicsGetCurrentContext()?.makeImage() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        
        // Calculate display dimensions
        let imageAspectRatio = CGFloat(rotatedImage.width) / CGFloat(rotatedImage.height)
        let screenAspectRatio = screenWidth / screenHeight
        var imageDisplayRect: CGRect
        
        if imageAspectRatio > screenAspectRatio {
            // Image is wider than screen - height fills screen, width extends beyond
            let displayHeight = screenHeight
            let displayWidth = displayHeight * imageAspectRatio
            let displayX = (screenWidth - displayWidth) / 2
            imageDisplayRect = CGRect(x: displayX, y: 0, width: displayWidth, height: displayHeight)
        } else {
            // Image is taller than screen - width fills screen, height extends beyond
            let displayWidth = screenWidth
            let displayHeight = displayWidth / imageAspectRatio
            let displayY = (screenHeight - displayHeight) / 2
            imageDisplayRect = CGRect(x: 0, y: displayY, width: displayWidth, height: displayHeight)
        }
        
        // Calculate neon line dimensions, accounting for scale
        let neonLineWidth = (screenWidth * 0.85) / scale
        let neonLineHeight: CGFloat = 50.0 / scale
        
        // Calculate screen center
        let screenCenterX = screenWidth / 2
        let screenCenterY = screenHeight / 2
        
        // Calculate crop rect components, accounting for scale and offset
        let scaledOffsetX = offset.width / scale
        let scaledOffsetY = offset.height / scale
        
        // Determine if we need to invert offsets based on rotation
        let normalizedRotation = (rotation.degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let shouldInvertX = normalizedRotation > 90 && normalizedRotation < 270
        let shouldInvertY = shouldInvertX
        
        let cropX = screenCenterX - (neonLineWidth / 2) + (shouldInvertX ? scaledOffsetX : -scaledOffsetX)
        let cropY = screenCenterY - (neonLineHeight / 2) + (shouldInvertY ? scaledOffsetY : -scaledOffsetY)
        
        // Create crop rect in screen coordinates
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: neonLineWidth,
            height: neonLineHeight
        )
        
        // Calculate scale factors between rotated image and display rect
        let scaleX = CGFloat(rotatedImage.width) / imageDisplayRect.width
        let scaleY = CGFloat(rotatedImage.height) / imageDisplayRect.height
        
        // Calculate image crop rect components
        let imageCropX = (cropRect.minX - imageDisplayRect.minX) * scaleX
        let imageCropY = (cropRect.minY - imageDisplayRect.minY) * scaleY
        let imageCropWidth = cropRect.width * scaleX
        let imageCropHeight = cropRect.height * scaleY
        
        // Create the final crop rect in image coordinates
        let imageCropRect = CGRect(
            x: imageCropX,
            y: imageCropY,
            width: imageCropWidth,
            height: imageCropHeight
        ).integral
        
        // Debug output
        if appSettings.debugMode {
            print("=== CROP DEBUG ===")
            print("Scale: \(scale)")
            print("Original image: \(image.size.width) x \(image.size.height)")
            print("Rotated image: \(rotatedImage.width) x \(rotatedImage.height)")
            print("Screen: \(screenWidth) x \(screenHeight)")
            print("Image display rect: \(imageDisplayRect)")
            print("Neon line dimensions: \(neonLineWidth) x \(neonLineHeight)")
            print("Crop rect (screen): \(cropRect)")
            print("Crop rect (image): \(imageCropRect)")
            print("Offset: \(offset)")
            print("Scaled offset: (\(scaledOffsetX), \(scaledOffsetY))")
        }
        
        // Ensure we have a valid crop rect
        guard imageCropRect.width > 0 && imageCropRect.height > 0 else {
            print("Invalid crop rect dimensions")
            return nil
        }
        
        // Create a new image from the rotated image
        guard let cgImage = rotatedImage.cropping(to: imageCropRect) else {
            print("Failed to crop image")
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private var settingsSection: some View {
        Section(header: Text("Detection Settings")) {
            VStack(alignment: .leading) {
                Text("White Pixel Conversion Distance: \(Int(whitePixelConversionDistance))")
                if #available(iOS 17.0, *) {
                    Slider(value: $whitePixelConversionDistance, in: 1...20, step: 1)
                        .onChange(of: whitePixelConversionDistance) { _, _ in
                            if let lastImage = lastCapturedImage {
                                runDetection(on: lastImage, isManualUpdate: true)
                            }
                        }
                } else {
                    Slider(value: $whitePixelConversionDistance, in: 1...20, step: 1)
                        .onChange(of: whitePixelConversionDistance) { _ in
                            if let lastImage = lastCapturedImage {
                                runDetection(on: lastImage, isManualUpdate: true)
                            }
                        }
                }
            }
            VStack(alignment: .leading) {
                Text("Colored Pixel Threshold: \(Int(coloredPixelThreshold))")
                if #available(iOS 17.0, *) {
                    Slider(value: $coloredPixelThreshold, in: 1...50, step: 1)
                        .onChange(of: coloredPixelThreshold) { _, _ in
                            if let lastImage = lastCapturedImage {
                                runDetection(on: lastImage, isManualUpdate: true)
                            }
                        }
                } else {
                    Slider(value: $coloredPixelThreshold, in: 1...50, step: 1)
                        .onChange(of: coloredPixelThreshold) { _ in
                            if let lastImage = lastCapturedImage {
                                runDetection(on: lastImage, isManualUpdate: true)
                            }
                        }
                }
            }
        }
    }
    
    private func runDetection(on image: UIImage, isManualUpdate: Bool = false) {
        lastCapturedImage = image
        guard !isProcessing else { return }
        isProcessing = true
        
        if appSettings.debugMode {
            print("DEBUG: \(isManualUpdate ? "Manual" : "Auto") detection requested")
        }
        
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
            
            DispatchQueue.main.async {
                withAnimation {
                    currentDetectionResult = result
                    ballCounts = result.zoneCounts
                    
                    if appSettings.debugMode {
                        print("DEBUG: Ball counts updated - Middle: Red=\(ballCounts.middle.red), Blue=\(ballCounts.middle.blue)")
                        print("DEBUG: Ball counts updated - Outside: Red=\(ballCounts.outside.red), Blue=\(ballCounts.outside.blue)")
                    }
                }
                isProcessing = false
            }
        }
    }
}

// MARK: - Apple Style Button
struct AppleButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 120, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(color)
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Neon Green Line Overlay for Preview
struct NeonGreenLineOverlay: View {
    @StateObject private var appSettings = AppSettingsManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Debug elements (only when debug mode is enabled)
                Group {
                    if appSettings.debugMode {
                        // Debug: Show frame boundaries
                        Rectangle()
                            .stroke(Color.red, lineWidth: 2)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        
                        // Debug: Show center point
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 10, height: 10)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        
                        // Debug: Show 85% width boundaries
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 1)
                            .frame(width: geometry.size.width * 0.85, height: 2)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.3)
                        
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 1)
                            .frame(width: geometry.size.width * 0.85, height: 2)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.7)
                        
                        // Debug: Show actual frame dimensions
                        VStack {
                            Text("Frame: \(String(format: "%.0f", geometry.size.width))x\(String(format: "%.0f", geometry.size.height))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(4)
                                .position(x: geometry.size.width / 2, y: 20)
                        }
                    }
                }
                
                // Actual neon line - always visible
                Rectangle()
                    .fill(Color(red: 0.0, green: 1.0, blue: 0.3)) // Same neon green as camera
                    .frame(width: geometry.size.width * 0.85, height: 6) // 85% width
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.5) // Back to center
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Custom Camera View using AVFoundation
struct CustomCameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    var useWideCamera: Bool = false
    var rotateCapturedImage90Degrees: Bool = false
    var hideNeonLine: Bool = false
    var shutterVerticalFraction: CGFloat = 1.0
    
    func makeUIViewController(context: Context) -> CustomCameraViewController {
        let controller = CustomCameraViewController()
        controller.delegate = context.coordinator
        controller.useWideCamera = useWideCamera
        controller.rotateCapturedImage90Degrees = rotateCapturedImage90Degrees
        controller.hideNeonLine = hideNeonLine
        controller.shutterVerticalFraction = shutterVerticalFraction
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CustomCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CustomCameraViewControllerDelegate {
        let parent: CustomCameraView
        
        init(_ parent: CustomCameraView) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            parent.capturedImage = image
        }
    }
}

// MARK: - Custom Camera View Controller
protocol CustomCameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
}

class CustomCameraViewController: UIViewController {
    weak var delegate: CustomCameraViewControllerDelegate?
    
    private var captureSession: AVCaptureSession!
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput!
    private var cameraPosition: AVCaptureDevice.Position = .back
    
    private let captureButton = UIButton()
    private let photoLibraryButton = UIButton()
    private let cancelButton = UIButton()
    private let flashButton = UIButton()
    private let neonLineView = NeonHorizontalLineView()
    
    private var flashMode: AVCaptureDevice.FlashMode = .off
    var useWideCamera: Bool = false
    var rotateCapturedImage90Degrees: Bool = false
    var hideNeonLine: Bool = false
    var shutterVerticalFraction: CGFloat = 1.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let self = self, !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let self = self, self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer.frame = view.bounds
        if let connection = videoPreviewLayer.connection {
            let orientation = UIDevice.current.orientation
            if #available(iOS 17.0, *) {
                let angle: Double?
                switch orientation {
                case .portrait:
                    angle = 90
                case .portraitUpsideDown:
                    angle = 270
                case .landscapeLeft:
                    angle = 0
                case .landscapeRight:
                    angle = 180
                default:
                    angle = nil
                }
                if let angle, connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            } else {
                let videoOrientation: AVCaptureVideoOrientation?
                switch orientation {
                case .portrait:
                    videoOrientation = .portrait
                case .portraitUpsideDown:
                    videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    videoOrientation = .landscapeRight
                case .landscapeRight:
                    videoOrientation = .landscapeLeft
                default:
                    videoOrientation = nil
                }
                if let videoOrientation, connection.isVideoOrientationSupported {
                    connection.videoOrientation = videoOrientation
                }
            }
        }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        if useWideCamera {
            // Always use 1x wide camera
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
                print("Failed to get wide camera device")
                return
            }
            setupCameraInput(camera)
            return
        }
        // Try to get the ultra-wide camera (0.5x) first
        guard let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: cameraPosition) else {
            // Fall back to wide camera if ultra-wide not available
            guard let fallbackCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
                print("Failed to get camera device")
                return
            }
            setupCameraInput(fallbackCamera)
            return
        }
        setupCameraInput(camera)
    }
    
    private func setupCameraInput(_ camera: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("Failed to create camera input: \(error)")
            return
        }
        
        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = view.bounds
        view.layer.addSublayer(videoPreviewLayer)
        
        // Add neon line overlay unless hidden
        if !hideNeonLine {
            neonLineView.frame = view.bounds
            neonLineView.backgroundColor = .clear
            view.addSubview(neonLineView)
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Capture button
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // Photo library button
        photoLibraryButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        photoLibraryButton.tintColor = .white
        photoLibraryButton.addTarget(self, action: #selector(openPhotoLibrary), for: .touchUpInside)
        view.addSubview(photoLibraryButton)
        
        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        // Flash button
        flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        view.addSubview(flashButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        photoLibraryButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        neonLineView.translatesAutoresizingMaskIntoConstraints = false

        if useWideCamera && rotateCapturedImage90Degrees {
            // Landscape: capture button right, at shutterVerticalFraction height
            NSLayoutConstraint.activate([
                captureButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
                captureButton.centerYAnchor.constraint(equalTo: view.topAnchor, constant: view.bounds.height * shutterVerticalFraction),
                captureButton.widthAnchor.constraint(equalToConstant: 70),
                captureButton.heightAnchor.constraint(equalToConstant: 70),

                photoLibraryButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
                photoLibraryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
                photoLibraryButton.widthAnchor.constraint(equalToConstant: 44),
                photoLibraryButton.heightAnchor.constraint(equalToConstant: 44),

                cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

                flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                flashButton.widthAnchor.constraint(equalToConstant: 44),
                flashButton.heightAnchor.constraint(equalToConstant: 44)
            ])
            if !hideNeonLine {
                NSLayoutConstraint.activate([
                    neonLineView.topAnchor.constraint(equalTo: view.topAnchor),
                    neonLineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    neonLineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    neonLineView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
            }
        } else {
            NSLayoutConstraint.activate([
                // Capture button
                captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
                captureButton.widthAnchor.constraint(equalToConstant: 70),
                captureButton.heightAnchor.constraint(equalToConstant: 70),
                // Photo library button
                photoLibraryButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
                photoLibraryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
                photoLibraryButton.widthAnchor.constraint(equalToConstant: 44),
                photoLibraryButton.heightAnchor.constraint(equalToConstant: 44),
                // Cancel button
                cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                // Flash button
                flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                flashButton.widthAnchor.constraint(equalToConstant: 44),
                flashButton.heightAnchor.constraint(equalToConstant: 44)
            ])
            if !hideNeonLine {
                NSLayoutConstraint.activate([
                    neonLineView.topAnchor.constraint(equalTo: view.topAnchor),
                    neonLineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    neonLineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    neonLineView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
            }
        }
    }
    
    @objc private func toggleFlash() {
        switch flashMode {
        case .off:
            flashMode = .on
            flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
            flashButton.tintColor = .yellow
        case .on:
            flashMode = .auto
            flashButton.setImage(UIImage(systemName: "bolt"), for: .normal)
            flashButton.tintColor = .white
        case .auto:
            flashMode = .off
            flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
            flashButton.tintColor = .white
        @unknown default:
            flashMode = .off
            flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
            flashButton.tintColor = .white
        }
    }
    
    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func openPhotoLibrary() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true)
    }
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CustomCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
           var image = UIImage(data: imageData) {
            if rotateCapturedImage90Degrees {
                image = image.rotated(by: -90) ?? image
            }
            delegate?.didCaptureImage(image)
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension CustomCameraViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            delegate?.didCaptureImage(image)
        }
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - Neon Horizontal Line UIView for Camera Overlay
class NeonHorizontalLineView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Calculate the camera preview area (excluding UI elements)
        let previewHeight = rect.height * 0.7 // Estimate camera preview area
        let previewY = rect.height * 0.15 // Start position for camera preview
        
        context.setStrokeColor(UIColor(red: 0.0, green: 1.0, blue: 0.3, alpha: 1.0).cgColor) // Neon green
        context.setLineWidth(6.0)
        
        // Center the line within the camera preview area
        let y = previewY + (previewHeight / 2.0)
        let margin: CGFloat = rect.width * 0.075 // 7.5% margin on each side = 85% width
        
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: rect.width - margin, y: y))
        context.strokePath()
    }
}

// Add this new view for the threshold sliders
struct ThresholdSlider: View {
    @Binding var value: CGFloat
    let color: Color
    let label: String
    let range: ClosedRange<CGFloat>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .foregroundColor(.white)
            HStack {
                Slider(value: $value, in: range)
                    .accentColor(color)
                Text(String(format: "%.2f", value))
                    .foregroundColor(.white)
                    .frame(width: 50)
            }
        }
    }
}

// Ball count row view
struct BallCountRow: View {
    let count: BallCount
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle()
                    .fill(ThemeColors.red)
                    .frame(width: 12, height: 12)
                Text("\(count.red)")
                    .foregroundColor(.white)
            }
            HStack {
                Circle()
                    .fill(ThemeColors.blue)
                    .frame(width: 12, height: 12)
                Text("\(count.blue)")
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Original Image Section
struct OriginalImageSection: View {
    let croppedImage: UIImage
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Original Image")
                .font(.headline)
                .padding(.horizontal)
            Image(uiImage: croppedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.black)
        }
    }
}

// MARK: - Quantized Image Section
struct QuantizedImageSection: View {
    let croppedImage: UIImage
    @Binding var redThreshold: CGFloat
    @Binding var blueThreshold: CGFloat
    @Binding var whiteThreshold: CGFloat
    @Binding var showThresholdControls: Bool
    @Binding var regionSensitivity: CGFloat
    @Binding var showDetectionControls: Bool
    @Binding var ballRadiusRatio: Double
    @Binding var exclusionRadiusMultiplier: Double
    @Binding var ballAreaPercentage: Double
    @Binding var ballCounts: ZoneCounts
    @Binding var currentDetectionResult: (zoneCounts: ZoneCounts, annotatedImage: UIImage?)?
    @Binding var whitePixelConversionDistance: Double
    @Binding var coloredPixelThreshold: Double
    @StateObject private var appSettings = AppSettingsManager.shared
    @State private var isProcessing: Bool = false
    
    private func updateDetection(_ quantizedImage: UIImage) {
        currentDetectionResult = nil
        runDetection(on: quantizedImage)
    }
    
    private func runDetection(on image: UIImage, isManualUpdate: Bool = false) {
        guard !isProcessing else { return }
        isProcessing = true
        
        if appSettings.debugMode {
            print("DEBUG: \(isManualUpdate ? "Manual" : "Auto") detection requested")
        }
        
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
            
            DispatchQueue.main.async {
                withAnimation {
                    currentDetectionResult = result
                    ballCounts = result.zoneCounts
                    
                    if appSettings.debugMode {
                        print("DEBUG: Ball counts updated - Middle: Red=\(ballCounts.middle.red), Blue=\(ballCounts.middle.blue)")
                        print("DEBUG: Ball counts updated - Outside: Red=\(ballCounts.outside.red), Blue=\(ballCounts.outside.blue)")
                    }
                }
                isProcessing = false
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Quantized Image")
                .font(.headline)
                .padding(.horizontal)
            
            if let quantizedImage = ColorQuantizer.quantize(
                image: croppedImage,
                redThreshold: redThreshold,
                blueThreshold: blueThreshold,
                whiteThreshold: whiteThreshold
            ) {
                let quantizedImageView = Image(uiImage: quantizedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .onAppear {
                        // Only run detection if we don't have a result yet
                        if currentDetectionResult == nil {
                            runDetection(on: quantizedImage)
                        }
                    }
                    #if swift(>=5.9)
                    .onChange(of: redThreshold) { _, _ in updateDetection(quantizedImage) }
                    .onChange(of: blueThreshold) { _, _ in updateDetection(quantizedImage) }
                    .onChange(of: whiteThreshold) { _, _ in updateDetection(quantizedImage) }
                    #else
                    .onChange(of: redThreshold) { _ in updateDetection(quantizedImage) }
                    .onChange(of: blueThreshold) { _ in updateDetection(quantizedImage) }
                    .onChange(of: whiteThreshold) { _ in updateDetection(quantizedImage) }
                    #endif
                    .overlay(
                        Group {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                            }
                        }
                    )
                quantizedImageView
                // Threshold controls
                ThresholdControlsSection(
                    showThresholdControls: $showThresholdControls,
                    redThreshold: $redThreshold,
                    blueThreshold: $blueThreshold,
                    whiteThreshold: $whiteThreshold,
                    regionSensitivity: $regionSensitivity,
                    quantizedImage: quantizedImage
                )
                
                // Detection Overlay
                if let result = currentDetectionResult,
                   let annotatedImage = result.annotatedImage {
                    DetectionOverlaySection(
                        annotatedImage: annotatedImage,
                        showDetectionControls: $showDetectionControls,
                        ballRadiusRatio: $ballRadiusRatio,
                        exclusionRadiusMultiplier: $exclusionRadiusMultiplier,
                        ballAreaPercentage: $ballAreaPercentage,
                        quantizedImage: quantizedImage,
                        ballCounts: $ballCounts,
                        currentDetectionResult: $currentDetectionResult,
                        onManualUpdate: {
                            runDetection(on: quantizedImage, isManualUpdate: true)
                        }
                    )
                }
                
                // Ball counts display
                BallCountsDisplaySection(ballCounts: ballCounts)
            }
        }
    }
}

// MARK: - Threshold Controls Section
struct ThresholdControlsSection: View {
    @Binding var showThresholdControls: Bool
    @Binding var redThreshold: CGFloat
    @Binding var blueThreshold: CGFloat
    @Binding var whiteThreshold: CGFloat
    @Binding var regionSensitivity: CGFloat
    let quantizedImage: UIImage
    
    var body: some View {
        VStack(spacing: 10) {
            Toggle("Show Threshold Controls", isOn: $showThresholdControls)
                .padding(.horizontal)
            
            if showThresholdControls {
                VStack(spacing: 15) {
                    ThresholdSlider(value: $redThreshold, color: ThemeColors.red, label: "Red Threshold", range: 0.1...1.0)
                    ThresholdSlider(value: $blueThreshold, color: ThemeColors.blue, label: "Blue Threshold", range: 0.1...1.0)
                    ThresholdSlider(value: $whiteThreshold, color: Color.white, label: "White Threshold", range: 0.1...1.0)
                    ThresholdSlider(value: $regionSensitivity, color: .white, label: "Region Sensitivity", range: 0.1...5.0)
                        .opacity(0.8)
                    
                    Button(action: {
                        UIImageWriteToSavedPhotosAlbum(quantizedImage, nil, nil, nil)
                    }) {
                        Label("Save to Camera Roll", systemImage: "square.and.arrow.down")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Detection Overlay Section
struct DetectionOverlaySection: View {
    let annotatedImage: UIImage
    @Binding var showDetectionControls: Bool
    @Binding var ballRadiusRatio: Double
    @Binding var exclusionRadiusMultiplier: Double
    @Binding var ballAreaPercentage: Double
    let quantizedImage: UIImage
    @Binding var ballCounts: ZoneCounts
    @Binding var currentDetectionResult: (zoneCounts: ZoneCounts, annotatedImage: UIImage?)?
    let onManualUpdate: () -> Void
    @StateObject private var appSettings = AppSettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Detection Overlay")
                .font(.headline)
                .padding(.horizontal)
            
            Image(uiImage: annotatedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.black)
            
            // Detection Parameter Controls
            VStack(spacing: 10) {
                Toggle("Show Detection Controls", isOn: $showDetectionControls)
                    .padding(.horizontal)
                
                if showDetectionControls {
                    VStack(spacing: 10) {
                        ParameterSlider(value: $ballRadiusRatio,
                                      range: 0.02...0.1,
                                      label: "Ball Radius Ratio")
                            .onChange(of: ballRadiusRatio) { _, newValue in
                                appSettings.ballRadiusRatio = newValue
                                onManualUpdate()
                            }
                        
                        ParameterSlider(value: $exclusionRadiusMultiplier,
                                      range: 1.0...2.0,
                                      label: "Exclusion Radius")
                            .onChange(of: exclusionRadiusMultiplier) { _, newValue in
                                appSettings.exclusionRadiusMultiplier = newValue
                                onManualUpdate()
                            }
                        
                        ParameterSlider(value: $ballAreaPercentage,
                                      range: 10...90,
                                      label: "Ball Area Percentage")
                            .onChange(of: ballAreaPercentage) { _, newValue in
                                appSettings.ballAreaPercentage = newValue
                                onManualUpdate()
                            }
                        
                        Button(action: onManualUpdate) {
                            Label("Update Display", systemImage: "arrow.clockwise")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Ball Counts Display Section
struct BallCountsDisplaySection: View {
    let ballCounts: ZoneCounts
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Ball Counts")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                // Middle zone counts
                VStack(alignment: .leading) {
                    Text("Middle Zone")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    BallCountRow(count: ballCounts.middle)
                }
                
                Divider()
                    .background(Color.gray)
                
                // Outside zone counts
                VStack(alignment: .leading) {
                    Text("Outside Zone")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    BallCountRow(count: ballCounts.outside)
                }
                
                Divider()
                    .background(Color.gray)
                
                // Total counts
                VStack(alignment: .leading) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    BallCountRow(count: ballCounts.total)
                }
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
}

extension UIImage {
    func rotated(by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        var newSize = CGRect(origin: .zero, size: self.size).applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        context.rotate(by: radians)
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage
    }
}


