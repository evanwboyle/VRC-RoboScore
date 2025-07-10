import SwiftUI
import AVFoundation
import Vision

struct FieldCameraView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var coordinator = FieldCameraCoordinator()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            CameraPreviewView(session: coordinator.session)
                .edgesIgnoringSafeArea(.all)
            
            if let mask = coordinator.segmentationMask {
                SegmentationOverlayView(mask: mask)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Controls overlay
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(12)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .padding()
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            coordinator.startSession()
        }
        .onDisappear {
            coordinator.stopSession()
        }
    }
}

// MARK: - Camera Preview View
class PreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Update orientation if needed
        if let connection = uiView.previewLayer.connection {
            let currentDevice = UIDevice.current
            let orientation = currentDevice.orientation
            let previewLayerConnection = connection
            if #available(iOS 17.0, *) {
                let angle: Double
                switch orientation {
                case .portrait:
                    angle = 90
                case .landscapeRight:
                    angle = 180
                case .landscapeLeft:
                    angle = 0
                case .portraitUpsideDown:
                    angle = 270
                default:
                    angle = 90
                }
                if previewLayerConnection.isVideoRotationAngleSupported(angle) {
                    previewLayerConnection.videoRotationAngle = angle
                }
            } else {
                if previewLayerConnection.isVideoOrientationSupported {
                    switch orientation {
                    case .portrait:
                        previewLayerConnection.videoOrientation = .portrait
                    case .landscapeRight:
                        previewLayerConnection.videoOrientation = .landscapeLeft
                    case .landscapeLeft:
                        previewLayerConnection.videoOrientation = .landscapeRight
                    case .portraitUpsideDown:
                        previewLayerConnection.videoOrientation = .portraitUpsideDown
                    default:
                        previewLayerConnection.videoOrientation = .portrait
                    }
                }
            }
        }
    }
}

// MARK: - Bounding Box View
struct BoundingBoxView: View {
    let detection: DetectedObject
    
    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(
                x: detection.boundingBox.minX * geometry.size.width,
                y: (1 - detection.boundingBox.maxY) * geometry.size.height,
                width: detection.boundingBox.width * geometry.size.width,
                height: detection.boundingBox.height * geometry.size.height
            )
            
            Rectangle()
                .path(in: rect)
                .stroke(detection.color == .red ? Color.red : Color.blue, lineWidth: 2)
        }
    }
}

// MARK: - Field Camera Coordinator
class FieldCameraCoordinator: NSObject, ObservableObject {
    @Published var segmentationMask: CGImage?
    let session = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var model: VNCoreMLModel?
    private let processingQueue = DispatchQueue(label: "com.vrcroboscore.videoProcessing", qos: .userInitiated)
    private var isProcessing = false
    
    override init() {
        super.init()
        setupCamera()
        loadModel()
    }
    
    private func setupCamera() {
        session.beginConfiguration()
        
        // Use high resolution preset
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Failed to create video input")
            return
        }
        
        guard session.canAddInput(videoInput) else {
            print("Cannot add video input")
            return
        }
        session.addInput(videoInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        guard session.canAddOutput(videoOutput) else {
            print("Cannot add video output")
            return
        }
        session.addOutput(videoOutput)
        
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                let angle: Double = 90
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }
        
        session.commitConfiguration()
        self.videoOutput = videoOutput
    }
    
    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "detr_resnet50", withExtension: "mlmodelc") else {
            print("❌ Failed to find DETR model")
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let compiledModel = try MLModel(contentsOf: modelURL, configuration: config)
            print("✅ Loaded MLModel")
            self.model = try VNCoreMLModel(for: compiledModel)
            print("✅ Successfully created VNCoreMLModel")
        } catch {
            print("❌ Failed to load model: \(error)")
        }
    }
    
    func startSession() {
        guard !session.isRunning else { return }
        processingQueue.async {
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        guard session.isRunning else { return }
        processingQueue.async {
            self.session.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension FieldCameraCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessing,
              let model = model,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        isProcessing = true
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            defer { 
                self?.isProcessing = false
                print("✅ Finished processing frame")
            }
            
            if let error = error {
                print("❌ Vision ML request error: \(error)")
                return
            }
            
            if let results = request.results as? [VNCoreMLFeatureValueObservation],
               let observation = results.first {
                let featureValue = observation.featureValue
                
                if let multiArray = featureValue.multiArrayValue {
                    let width = multiArray.shape[0].intValue
                    let height = multiArray.shape[1].intValue
                    
                    // Create a color map for different class labels
                    func colorForClass(_ value: Double) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
                        switch Int(value) {
                        case 0: return (0, 0, 0, 0) // Background/empty - transparent
                        case 1: return (1, 0, 0, 0.7) // Class 1 - Red
                        case 2: return (0, 0, 1, 0.7) // Class 2 - Blue
                        default:
                            // Map other values to a gradient
                            let normalized = CGFloat(value) / 199.0
                            return (normalized, 0, 1 - normalized, 0.5)
                        }
                    }
                    
                    var pixelBuffer: CVPixelBuffer?
                    let attrs = [
                        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
                    ] as CFDictionary
                    
                    CVPixelBufferCreate(kCFAllocatorDefault,
                                      width,
                                      height,
                                      kCVPixelFormatType_32BGRA,
                                      attrs,
                                      &pixelBuffer)
                    
                    if let pixelBuffer = pixelBuffer {
                        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
                        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                        
                        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
                        let context = CGContext(data: pixelData,
                                              width: width,
                                              height: height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                              space: rgbColorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
                        
                        if let context = context {
                            // Clear the context first
                            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                            
                            // Draw the segmentation mask
                            for y in 0..<height {
                                for x in 0..<width {
                                    let index = y * width + x
                                    let value = multiArray[index].doubleValue
                                    let color = colorForClass(value)
                                    
                                    // Only draw non-transparent pixels
                                    if color.alpha > 0 {
                                        context.setFillColor(red: color.red,
                                                           green: color.green,
                                                           blue: color.blue,
                                                           alpha: color.alpha)
                                        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                                    }
                                }
                            }
                            
                            if let cgImage = context.makeImage() {
                                DispatchQueue.main.async {
                                    self?.segmentationMask = cgImage
                                }
                            }
                        }
                        
                        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
                    }
                }
            }
        }
        
        request.imageCropAndScaleOption = .scaleFit
        
        do {
            try handler.perform([request])
        } catch {
            print("❌ Failed to perform Vision request: \(error)")
            isProcessing = false
        }
    }
}

struct SegmentationOverlayView: View {
    let mask: CGImage
    
    var body: some View {
        GeometryReader { geometry in
            Image(mask, scale: 1.0, label: Text("Segmentation"))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .blendMode(.normal)
        }
    }
}

// MARK: - Detected Object Model
struct DetectedObject: Identifiable {
    let id = UUID()
    let color: BallColor
    let boundingBox: CGRect
} 