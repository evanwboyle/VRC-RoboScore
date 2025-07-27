import SwiftUI
import AVFoundation
import Roboflow
import TrackSS

// MARK: - GoalLegTrackerManager
class GoalLegTrackerManager {
    private let tracker = TrackerSS()
    // Store last tracker results for persistence
    private(set) var trackedGoalLegs: [[Double]] = []

    func update(with detections: [RFObjectDetectionPrediction]) {
        // Convert Goal Leg detections to [x1, y1, x2, y2] Double format
        let dets: [[Double]] = detections.compactMap { pred in
            guard pred.className == "Goal Leg" else { return nil }
            let x1 = Double(pred.x - pred.width/2)
            let y1 = Double(pred.y - pred.height/2)
            let x2 = Double(pred.x + pred.width/2)
            let y2 = Double(pred.y + pred.height/2)
            return [x1, y1, x2, y2]
        }
        // Update tracker
        trackedGoalLegs = tracker.update(dets: dets)
    }
}

struct FieldCameraView: View {
    var body: some View {
        ZStack {
            CameraViewControllerRepresentable()
                .edgesIgnoringSafeArea(.all)
        }
    }
}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var overlayView: UIView! // Overlay for bounding boxes
    private var boundingBoxLayers: [CAShapeLayer] = []
    private let rf: RoboflowMobile = {
        let apiKey = ""//Bundle.main.infoDictionary? ["ROBOFLOW_API_KEY"] as? String ?? ""
        return RoboflowMobile(apiKey: apiKey)
    }()
    private let modelId = "roboscore-dxpcr"
    private let modelVersion = 6
    private var model: RFModel?
    private var isModelLoaded = false
    private var isProcessingFrame = false

    // Goal Leg tracker manager
    private let goalLegTracker = GoalLegTrackerManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)
        setupCamera()
        loadRoboflowModel()
    }

    private func setupCamera() {
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else { return }
        captureSession.addInput(videoInput)
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        // Add overlayView above previewLayer
        view.addSubview(overlayView)

        // Add video output for frame capture
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    private func loadRoboflowModel() {
        rf.load(model: modelId, modelVersion: modelVersion) { [weak self] loadedModel, error, modelName, modelType in
            guard let self = self else { return }
            if let error = error {
                print("Error loading model: \(error)")
            } else {
                loadedModel?.configure(threshold: 0.5, overlap: 0.5, maxObjects: 1)
                self.model = loadedModel
                self.isModelLoaded = true
                print("Model loaded: \(modelName ?? "") type: \(modelType ?? "")")
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isModelLoaded, !isProcessingFrame else { return }
        isProcessingFrame = true
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }
        guard let image = UIImage(pixelBuffer: pixelBuffer) else {
            print("Failed to convert pixelBuffer to UIImage")
            isProcessingFrame = false
            return
        }
        // Pass the raw image directly to the model (no preprocessing)
        model?.detect(image: image) { [weak self] predictions, error in
            DispatchQueue.main.async {
                self?.removeBoundingBoxes()
                if let error = error {
                    print("Detection error: \(error)")
                } else if let predictions = predictions as? [RFObjectDetectionPrediction] {
                    // Update Goal Leg tracker
                    self?.goalLegTracker.update(with: predictions)
                    // Draw tracked Goal Legs
                    self?.drawTrackedGoalLegs(imageSize: image.size)
                    // Draw other bounding boxes (balls, etc)
                    self?.drawBoundingBoxes(predictions: predictions, imageSize: image.size, skipGoalLegs: true)
                } else {
                    print("Predictions: \(String(describing: predictions))")
                }
                self?.isProcessingFrame = false
            }
        }
    }

    // Draw tracked Goal Legs using SORT output
    private func drawTrackedGoalLegs(imageSize: CGSize) {
        guard overlayView != nil, let previewLayer = self.previewLayer else { return }
        for tracked in goalLegTracker.trackedGoalLegs {
            // tracked = [x1, y1, x2, y2, id]
            guard tracked.count == 5 else { continue }
            let x1 = CGFloat(tracked[0])
            let y1 = CGFloat(tracked[1])
            let x2 = CGFloat(tracked[2])
            let y2 = CGFloat(tracked[3])
            let id = tracked[4]
            let width = x2 - x1
            let height = y2 - y1
            // Convert to normalized coordinates
            let normX = x1 / imageSize.width
            let normY = y1 / imageSize.height
            let normWidth = width / imageSize.width
            let normHeight = height / imageSize.height
            let normalizedRect = CGRect(x: normX, y: normY, width: normWidth, height: normHeight)
            let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
            let boxLayer = CAShapeLayer()
            boxLayer.frame = convertedRect
            boxLayer.borderColor = UIColor.orange.cgColor
            boxLayer.borderWidth = 4
            boxLayer.cornerRadius = 6
            boxLayer.masksToBounds = true
            // Add ID label
            let idLabel = CATextLayer()
            idLabel.string = "ID: \(id)"
            idLabel.fontSize = 14
            idLabel.foregroundColor = UIColor.orange.cgColor
            idLabel.frame = CGRect(x: 0, y: 0, width: 60, height: 20)
            boxLayer.addSublayer(idLabel)
            overlayView.layer.addSublayer(boxLayer)
            boundingBoxLayers.append(boxLayer)
        }
    }

    // Draw other bounding boxes (balls, etc), optionally skipping Goal Legs
    private func drawBoundingBoxes(predictions: [RFObjectDetectionPrediction], imageSize: CGSize, skipGoalLegs: Bool = false) {
        guard overlayView != nil, let previewLayer = self.previewLayer else { return }
        for prediction in predictions {
            if skipGoalLegs && prediction.className == "Goal Leg" { continue }
            let x = CGFloat(prediction.x)
            let y = CGFloat(prediction.y)
            let width = CGFloat(prediction.width)
            let height = CGFloat(prediction.height)
            // Convert to normalized coordinates
            let normX = (x - width/2) / imageSize.width
            let normY = (y - height/2) / imageSize.height
            let normWidth = width / imageSize.width
            let normHeight = height / imageSize.height
            let normalizedRect = CGRect(x: normX, y: normY, width: normWidth, height: normHeight)
            let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
            let boxLayer = CAShapeLayer()
            boxLayer.frame = convertedRect
            // Set color based on className
            var outlineColor: UIColor = .red
            switch prediction.className {
            case "Red Ball":
                outlineColor = .red
            case "Blue Ball":
                outlineColor = .blue
            default:
                outlineColor = .red
            }
            boxLayer.borderColor = outlineColor.cgColor
            boxLayer.borderWidth = 3
            boxLayer.cornerRadius = 4
            boxLayer.masksToBounds = true
            overlayView.layer.addSublayer(boxLayer)
            boundingBoxLayers.append(boxLayer)
        }
    }

    private func removeBoundingBoxes() {
        for layer in boundingBoxLayers {
            layer.removeFromSuperlayer()
        }
        boundingBoxLayers.removeAll()
    }

    private func convertRect(_ rect: CGRect, fromImageSize imageSize: CGSize, toView previewLayer: AVCaptureVideoPreviewLayer) -> CGRect {
        // Model coordinates (origin at top-left, size = model input size)
        // Preview layer coordinates (origin at top-left, size = previewLayer.bounds)
        let previewSize = previewLayer.bounds.size

        // Calculate scale factors
        let scaleX = previewSize.width / imageSize.width
        let scaleY = previewSize.height / imageSize.height

        // Use the smaller scale to fit the image entirely in the preview (aspect fit)
        let scale = min(scaleX, scaleY)
        let scaledImageWidth = imageSize.width * scale
        let scaledImageHeight = imageSize.height * scale
        let xOffset = (previewSize.width - scaledImageWidth) / 2
        let yOffset = (previewSize.height - scaledImageHeight) / 2

        let x = rect.origin.x * scale + xOffset
        let y = rect.origin.y * scale + yOffset
        let width = rect.size.width * scale
        let height = rect.size.height * scale

        return CGRect(x: x, y: y, width: width, height: height)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        overlayView?.frame = previewLayer?.frame ?? view.bounds
    }
}

// Helper: Convert CVPixelBuffer to UIImage
import CoreVideo
extension UIImage {
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            self.init(cgImage: cgImage)
        } else {
            return nil
        }
    }
}
