// MARK: - Field Overlay Manager
struct FieldOverlayManager {
    private var cachedReferencePolygon: [CGPoint]?
    private var hasPrintedReferencePolygon = false
    
    mutating func getReferencePolygon() -> [CGPoint]? {
        if cachedReferencePolygon == nil {
            if let refCenters = getReferencePolygonCenters() {
                cachedReferencePolygon = orderVerticesClockwise(refCenters)
                if !hasPrintedReferencePolygon {
                    print("Reference Polygon Centers:")
                    for (i, pt) in cachedReferencePolygon!.enumerated() {
                        print("  [\(i)]: (x: \(pt.x), y: \(pt.y))")
                    }
                    hasPrintedReferencePolygon = true
                }
            }
        }
        return cachedReferencePolygon
    }
    
    func getLivePolygon(from tracker: GoalLegTrackerManager) -> [CGPoint]? {
        var centers: [CGPoint] = []
        let allLegs = tracker.trackedGoalLegs + tracker.ghostLegs
        if allLegs.count == 4 {
            for leg in allLegs {
                if leg.count >= 4 {
                    let cx = (leg[0] + leg[2]) / 2.0
                    let cy = (leg[1] + leg[3]) / 2.0
                    centers.append(CGPoint(x: cx, y: cy))
                }
            }
            return orderVerticesClockwise(centers)
        }
        return nil
    }
    
    private func getReferencePolygonCenters() -> [CGPoint]? {
        guard let annotations = FieldAnnotationLoader.loadAnnotations(from: Bundle.main.path(forResource: "VexFieldAnnotations", ofType: "json") ?? "") else { return nil }
        let legs = annotations.goalLegs
        if legs.count == 4 {
            return legs.map { $0.center }
        }
        return nil
    }
    
    private func orderVerticesClockwise(_ vertices: [CGPoint]) -> [CGPoint] {
        guard vertices.count == 4 else { return vertices }
        let centroid = CGPoint(
            x: vertices.map { $0.x }.reduce(0, +) / 4.0,
            y: vertices.map { $0.y }.reduce(0, +) / 4.0
        )
        return vertices.sorted { a, b in
            let angleA = atan2(a.y - centroid.y, a.x - centroid.x)
            let angleB = atan2(b.y - centroid.y, b.x - centroid.x)
            return angleA < angleB
        }
    }
}

// MARK: - Model Load Flag
/// Tracks if the Roboflow model has loaded in this app session (prevents loading overlay on subsequent opens)
fileprivate var hasLoadedModel: Bool = false
/// Persists the loaded Roboflow model instance across camera opens
fileprivate var sharedRFModel: RFModel? = nil
// MARK: - Camera Constants
/// CameraConstants: All configuration values for camera overlays and tracking logic.
struct CameraConstants {
    static let pauseButtonHeight: CGFloat = 28
    static let pauseButtonWidth: CGFloat = 72
    static let pauseButtonCornerRadius: CGFloat = 7
    static let pauseButtonFontSize: CGFloat = 13
    static let pauseButtonBackgroundOpacity: Double = 0.18
    static let pauseButtonTextOpacity: Double = 0.92
    // --- Camera Button UI ---
    static let cameraButtonBackgroundOpacity: Double = 0.18
    static let cameraButtonIconOpacity: Double = 0.92
    static let cameraButtonSize: CGFloat = 32
    static let cameraButtonIconSize: CGFloat = 16
    static let cameraButtonPadding: CGFloat = 16
    static let cameraButtonSpacing: CGFloat = 8
    static let fpsCounterFontSize: CGFloat = 14
    static let fpsCounterBackgroundOpacity: Double = 0.18
    static let fpsCounterTextOpacity: Double = 0.92
    // --- Tracking Logic ---
    /// Maximum distance (pixels) to match ghost legs to newborn goal legs
    static let goalLegThreshold: Double = 60.0
    /// Maximum number of goal legs (tracked + ghosts) to display
    static let maxGoalLegs: Int = 4

    // --- Tracked Goal Leg Overlay ---
    /// Border color for tracked goal leg overlays
    static let trackedBorderColor: UIColor = .orange
    /// Border width for tracked goal leg overlays
    static let trackedBorderWidth: CGFloat = 4
    /// Label color for tracked goal leg overlays
    static let trackedLabelColor: UIColor = .orange
    /// Label width for tracked goal leg overlays
    static let trackedLabelWidth: CGFloat = 60
    /// Label height for tracked goal leg overlays
    static let trackedLabelHeight: CGFloat = 20
    /// Font size for tracked goal leg labels
    static let trackedLabelFontSize: CGFloat = 14

    // --- Ghost Leg Overlay ---
    /// Border color for ghost leg overlays
    static let ghostBorderColor: UIColor = .systemGray
    /// Border width for ghost leg overlays
    static let ghostBorderWidth: CGFloat = 2
    /// Label color for ghost leg overlays
    static let ghostLabelColor: UIColor = .systemGray
    /// Label width for ghost leg overlays
    static let ghostLabelWidth: CGFloat = 80
    /// Label height for ghost leg overlays
    static let ghostLabelHeight: CGFloat = 20
    /// Font size for ghost leg labels
    static let ghostLabelFontSize: CGFloat = 14

    // --- Ball Overlay ---
    /// Border width for ball overlays
    static let ballBorderWidth: CGFloat = 3
    /// Label width for ball overlays
    static let ballLabelWidth: CGFloat = 80
    /// Label height for ball overlays
    static let ballLabelHeight: CGFloat = 20
    /// Font size for ball labels
    static let ballLabelFontSize: CGFloat = 14
    /// Border color for red ball overlays
    static let redBallColor: UIColor = .red
    /// Border color for blue ball overlays
    static let blueBallColor: UIColor = .blue
    /// Default border color for ball overlays
    static let defaultBallColor: UIColor = .red
}

// MARK: - CameraManager
class CameraManager {
    let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?

    func setupCamera(on view: UIView, position: AVCaptureDevice.Position = .back) {
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else { return }
        captureSession.addInput(videoInput)
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    func addVideoOutput(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
    }

    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
}
// MARK: - BoundingBoxDrawer
class BoundingBoxDrawer {
    static func drawBox(on overlayView: UIView, previewLayer: AVCaptureVideoPreviewLayer, rect: [Double], imageSize: CGSize, color: UIColor, borderWidth: CGFloat, label: String, labelColor: UIColor, labelWidth: CGFloat = 60, labelHeight: CGFloat = 20, labelFontSize: CGFloat = 14) -> CAShapeLayer? {
        guard rect.count >= 4 else { return nil }
        let x1 = CGFloat(rect[0])
        let y1 = CGFloat(rect[1])
        let x2 = CGFloat(rect[2])
        let y2 = CGFloat(rect[3])
        let width = x2 - x1
        let height = y2 - y1
        let normX = x1 / imageSize.width
        let normY = y1 / imageSize.height
        let normWidth = width / imageSize.width
        let normHeight = height / imageSize.height
        let normalizedRect = CGRect(x: normX, y: normY, width: normWidth, height: normHeight)
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
        let boxLayer = CAShapeLayer()
        boxLayer.frame = convertedRect
        boxLayer.borderColor = color.cgColor
        boxLayer.borderWidth = borderWidth
        boxLayer.cornerRadius = 6
        boxLayer.masksToBounds = true
        let idLabel = CATextLayer()
        idLabel.string = label
        idLabel.fontSize = labelFontSize
        idLabel.foregroundColor = labelColor.cgColor
        idLabel.frame = CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight)
        boxLayer.addSublayer(idLabel)
        overlayView.layer.addSublayer(boxLayer)
        return boxLayer
    }
}
import SwiftUI
import AVFoundation
import Roboflow
import TrackSS

// MARK: - GoalLegTrackerManager

class GhostLegManager {
    private(set) var ghostLegs: [[Double]] = []
    private let threshold: Double = CameraConstants.goalLegThreshold // pixels, adjust as needed

    func clear() {
        ghostLegs.removeAll()
    }

    func addGhostLeg(for lostID: Double, from trackedGoalLegs: [[Double]]) {
        if let lastLeg = trackedGoalLegs.first(where: { $0.count == 5 && $0[4] == lostID }) {
            if !ghostLegs.contains(where: { $0.count == 5 && $0[4] == lostID }) {
                ghostLegs.append(lastLeg)
            }
        }
    }

    func removeGhostLegIfClose(to newborn: [Double]) {
        guard newborn.count == 5 else { return }
        let newbornCenter = CGPoint(x: (newborn[0] + newborn[2]) / 2, y: (newborn[1] + newborn[3]) / 2)
        var closestIndex: Int? = nil
        var minDist = Double.greatestFiniteMagnitude
        for (i, ghost) in ghostLegs.enumerated() where ghost.count == 5 {
            let ghostCenter = CGPoint(x: (ghost[0] + ghost[2]) / 2, y: (ghost[1] + ghost[3]) / 2)
            let dist = hypot(newbornCenter.x - ghostCenter.x, newbornCenter.y - ghostCenter.y)
            if dist < minDist {
                minDist = dist
                closestIndex = i
            }
        }
        if let idx = closestIndex, minDist < threshold {
            ghostLegs.remove(at: idx)
        }
    }

    func limitGhostLegs(trackedCount: Int, maxLegs: Int) {
        let excess = (trackedCount + ghostLegs.count) - maxLegs
        if excess > 0 && ghostLegs.count > 0 {
            ghostLegs = Array(ghostLegs.dropFirst(excess))
        }
    }

    // Move all ghost legs by the average delta of tracked goal legs that persist for 3+ frames
    func moveGhostLegs(by delta: (dx: Double, dy: Double)) {
        for i in 0..<ghostLegs.count {
            guard ghostLegs[i].count >= 4 else { continue }
            ghostLegs[i][0] += delta.dx
            ghostLegs[i][1] += delta.dy
            ghostLegs[i][2] += delta.dx
            ghostLegs[i][3] += delta.dy
        }
    }
}

class GoalLegTrackerManager {
    private let tracker = TrackerSS()
    private(set) var trackedGoalLegs: [[Double]] = []
    private var previousIDs: Set<Double> = []
    private let ghostLegManager = GhostLegManager()

    // Track how many frames each goal leg ID has persisted
    private var idPersistence: [Double: Int] = [:]
    private var previousTracked: [[Double]] = []

    var ghostLegs: [[Double]] { ghostLegManager.ghostLegs }

    func update(with detections: [RFObjectDetectionPrediction]) {
        let dets: [[Double]] = detections.compactMap { pred in
            guard pred.className == "Goal Leg" else { return nil }
            let x1 = Double(pred.x - pred.width/2)
            let y1 = Double(pred.y - pred.height/2)
            let x2 = Double(pred.x + pred.width/2)
            let y2 = Double(pred.y + pred.height/2)
            return [x1, y1, x2, y2]
        }
        let newTracked = tracker.update(dets: dets)
        let currentIDs: Set<Double> = Set(newTracked.compactMap { $0.count == 5 ? $0[4] : nil })
        let lostIDs = previousIDs.subtracting(currentIDs)
        for lostID in lostIDs {
            ghostLegManager.addGhostLeg(for: lostID, from: trackedGoalLegs)
        }
        let newbornIDs = currentIDs.subtracting(previousIDs)
        for newbornID in newbornIDs {
            if let newborn = newTracked.first(where: { $0.count == 5 && $0[4] == newbornID }) {
                ghostLegManager.removeGhostLegIfClose(to: newborn)
            }
        }
        ghostLegManager.limitGhostLegs(trackedCount: newTracked.count, maxLegs: CameraConstants.maxGoalLegs)

        // --- Ghost Leg Movement Logic ---
        // Only use goal legs that persist for 3+ frames
        var deltas: [(dx: Double, dy: Double)] = []
        for new in newTracked {
            guard new.count == 5 else { continue }
            let id = new[4]
            // Find previous position for this id
            if let prev = previousTracked.first(where: { $0.count == 5 && $0[4] == id }) {
                // Update persistence count
                idPersistence[id, default: 1] += 1
                if idPersistence[id]! >= 3 {
                    // Compute delta
                    let dx = ((new[0] + new[2]) / 2) - ((prev[0] + prev[2]) / 2)
                    let dy = ((new[1] + new[3]) / 2) - ((prev[1] + prev[3]) / 2)
                    deltas.append((dx: dx, dy: dy))
                }
            } else {
                idPersistence[id] = 1
            }
        }
        // Remove IDs that are no longer tracked
        for id in idPersistence.keys where !currentIDs.contains(id) {
            idPersistence.removeValue(forKey: id)
        }
        // Average delta
        if !deltas.isEmpty {
            let avgDx = deltas.map { $0.dx }.reduce(0, +) / Double(deltas.count)
            let avgDy = deltas.map { $0.dy }.reduce(0, +) / Double(deltas.count)
            ghostLegManager.moveGhostLegs(by: (dx: avgDx, dy: avgDy))
        }

        trackedGoalLegs = newTracked
        previousIDs = currentIDs
        previousTracked = newTracked
    }

    func clearGhostLegs() {
        ghostLegManager.clear()
    }
}

struct FieldCameraView: View {
    @Binding var isPresented: Bool
    @State private var isPaused: Bool = false
    @State private var fps: Double = 0.0
    @State private var isModelLoaded: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraViewControllerRepresentable(isPaused: $isPaused, fps: $fps, isModelLoaded: $isModelLoaded)
                .edgesIgnoringSafeArea(.all)
            ZStack {
                if !isModelLoaded && !hasLoadedModel {
                    Color.black.opacity(0.45).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 24) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2.0)
                        Text("Loading Camera Model...")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    // X button on loading screen
                    VStack {
                        HStack {
                            Button(action: {
                                isPresented = false
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(CameraConstants.cameraButtonBackgroundOpacity))
                                        .frame(width: CameraConstants.cameraButtonSize, height: CameraConstants.cameraButtonSize)
                                    Image(systemName: "xmark")
                                        .resizable()
                                        .frame(width: CameraConstants.cameraButtonIconSize, height: CameraConstants.cameraButtonIconSize)
                                        .foregroundColor(Color.black.opacity(CameraConstants.cameraButtonIconOpacity))
                                }
                            }
                            Spacer()
                        }
                        .padding([.top, .leading, .trailing], CameraConstants.cameraButtonPadding)
                        Spacer()
                    }
                }
                if isModelLoaded {
                    VStack {
                        HStack(spacing: CameraConstants.cameraButtonSpacing) {
                            Button(action: {
                                isPresented = false
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(CameraConstants.cameraButtonBackgroundOpacity))
                                        .frame(width: CameraConstants.cameraButtonSize, height: CameraConstants.cameraButtonSize)
                                    Image(systemName: "xmark")
                                        .resizable()
                                        .frame(width: CameraConstants.cameraButtonIconSize, height: CameraConstants.cameraButtonIconSize)
                                        .foregroundColor(Color.black.opacity(CameraConstants.cameraButtonIconOpacity))
                                }
                            }
                            Button(action: {
                                isPaused.toggle()
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: CameraConstants.pauseButtonCornerRadius)
                                        .fill(Color.black.opacity(CameraConstants.pauseButtonBackgroundOpacity))
                                        .frame(width: CameraConstants.pauseButtonWidth, height: CameraConstants.pauseButtonHeight)
                                    Text(isPaused ? "Unpause" : "Pause")
                                        .font(.system(size: CameraConstants.pauseButtonFontSize, weight: .bold))
                                        .foregroundColor(Color.black.opacity(CameraConstants.pauseButtonTextOpacity))
                                }
                            }
                            Spacer()
                            ZStack {
                                RoundedRectangle(cornerRadius: CameraConstants.pauseButtonCornerRadius)
                                    .fill(Color.black.opacity(CameraConstants.pauseButtonBackgroundOpacity))
                                    .frame(width: CameraConstants.pauseButtonWidth, height: CameraConstants.pauseButtonHeight)
                                Text(String(format: "FPS: %.1f", fps))
                                    .font(.system(size: CameraConstants.pauseButtonFontSize, weight: .bold))
                                    .foregroundColor(Color.black.opacity(CameraConstants.pauseButtonTextOpacity))
                            }
                        }
                        .padding([.top, .leading, .trailing], CameraConstants.cameraButtonPadding)
                        Spacer()
                    }
                }
            }
        }
    }
}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var isPaused: Bool
    @Binding var fps: Double
    @Binding var isModelLoaded: Bool

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.isPausedBinding = $isPaused
        vc.fpsBinding = $fps
        vc.isModelLoadedBinding = $isModelLoaded
        return vc
    }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.isPausedBinding = $isPaused
        uiViewController.fpsBinding = $fps
        uiViewController.isModelLoadedBinding = $isModelLoaded
    }
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let cameraManager = CameraManager()
    private var overlayView: UIView! // Overlay for bounding boxes
    private var boundingBoxLayers: [CAShapeLayer] = []
    private let rf: RoboflowMobile = {
        let apiKey = ""//Bundle.main.infoDictionary? ["ROBOFLOW_API_KEY"] as? String ?? ""
        return RoboflowMobile(apiKey: apiKey)
    }()
    private let modelId = "roboscore-dxpcr"
    private let modelVersion = 6
    private var model: RFModel? {
        get { sharedRFModel }
        set { sharedRFModel = newValue }
    }
    private var isModelLoaded = false
    private var isProcessingFrame = false

    // Goal Leg tracker manager
    private let goalLegTracker = GoalLegTrackerManager()
    var isPausedBinding: Binding<Bool>? = nil
    var fpsBinding: Binding<Double>? = nil
    var isModelLoadedBinding: Binding<Bool>? = nil
    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()

    override func viewDidLoad() {
        super.viewDidLoad()
        overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)
        cameraManager.setupCamera(on: view)
        // Set initial video orientation for preview layer
        if let previewLayer = cameraManager.previewLayer, let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = currentVideoOrientation()
        }
        // Add overlayView above previewLayer
        view.addSubview(overlayView)
        cameraManager.addVideoOutput(delegate: self)
        cameraManager.startSession()
        loadRoboflowModel()
        FieldAnnotationLoader.testLoadAnnotations()
    }

    // ...removed setupCamera, now handled by CameraManager...

    private func loadRoboflowModel() {
        // Only show loading overlay if model hasn't loaded in this app session
        if hasLoadedModel, let loadedModel = sharedRFModel {
            // Model is already loaded, just update state bindings on next runloop to avoid modifying state during view update
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.model = loadedModel
                self.isModelLoaded = true
                if let binding = self.isModelLoadedBinding {
                    binding.wrappedValue = true
                }
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.rf.load(model: self?.modelId ?? "", modelVersion: self?.modelVersion ?? 1) { loadedModel, error, modelName, modelType in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error {
                        print("Error loading model: \(error)")
                    } else {
                        loadedModel?.configure(threshold: 0.5, overlap: 0.5, maxObjects: 1)
                        self.model = loadedModel
                        sharedRFModel = loadedModel
                        self.isModelLoaded = true
                        if let binding = self.isModelLoadedBinding {
                            binding.wrappedValue = true
                        }
                        hasLoadedModel = true
                        print("Model loaded: \(modelName ?? "") type: \(modelType ?? "")")
                    }
                }
            }
        }
    }

    private var lastOverlays: ([RFObjectDetectionPrediction], CGSize)? = nil

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isModelLoaded, !isProcessingFrame else { return }
        isProcessingFrame = true
        let now = CACurrentMediaTime()
        let dt = now - lastFrameTimestamp
        lastFrameTimestamp = now
        if let fpsBinding = fpsBinding {
            // Clamp dt to avoid division by zero and allow low FPS display
            let fpsValue: Double
            if dt > 0.0 {
                fpsValue = 1.0 / dt
            } else {
                fpsValue = 0.0
            }
            DispatchQueue.main.async {
                fpsBinding.wrappedValue = fpsValue
            }
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }
        guard let image = UIImage(pixelBuffer: pixelBuffer) else {
            print("Failed to convert pixelBuffer to UIImage")
            isProcessingFrame = false
            return
        }
        let paused = isPausedBinding?.wrappedValue ?? false
        if paused {
            DispatchQueue.main.async {
                self.removeBoundingBoxes()
                if let overlays = self.lastOverlays {
                    let (predictions, imageSize) = overlays
                    // Draw overlays from last frame
                    self.drawPausedOverlays(predictions: predictions, imageSize: imageSize)
                }
                self.drawPolygonsOverlay()
                self.isProcessingFrame = false
            }
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
                    // Draw ghost legs if needed
                    if let tracker = self?.goalLegTracker {
                        let aliveCount = tracker.trackedGoalLegs.count
                        if aliveCount <= 3 && tracker.ghostLegs.count > 0 {
                            self?.drawGhostLegs(imageSize: image.size)
                        }
                    }
                    // Draw other bounding boxes (balls, etc)
                    self?.drawBoundingBoxes(predictions: predictions, imageSize: image.size, skipGoalLegs: true)
                    self?.drawPolygonsOverlay()
                    self?.lastOverlays = (predictions, image.size)
                } else {
                    print("Predictions: \(String(describing: predictions))")
                }
                self?.isProcessingFrame = false
            }
        }
    }

    private func drawPausedOverlays(predictions: [RFObjectDetectionPrediction], imageSize: CGSize) {
        // Draw overlays as if not paused, but do not update tracker
        self.drawTrackedGoalLegs(imageSize: imageSize)
        let aliveCount = goalLegTracker.trackedGoalLegs.count
        if aliveCount <= 3 && goalLegTracker.ghostLegs.count > 0 {
            self.drawGhostLegs(imageSize: imageSize)
        }
        self.drawBoundingBoxes(predictions: predictions, imageSize: imageSize, skipGoalLegs: true)
        self.drawPolygonsOverlay()
    }

    // Draw tracked Goal Legs using SORT output
    private func drawTrackedGoalLegs(imageSize: CGSize) {
        guard overlayView != nil, let previewLayer = cameraManager.previewLayer else { return }
        for tracked in goalLegTracker.trackedGoalLegs {
            guard tracked.count == 5 else { continue }
            let id = tracked[4]
            if let boxLayer = BoundingBoxDrawer.drawBox(
                on: overlayView,
                previewLayer: previewLayer,
                rect: tracked,
                imageSize: imageSize,
                color: CameraConstants.trackedBorderColor,
                borderWidth: CameraConstants.trackedBorderWidth,
                label: "ID: \(id)",
                labelColor: CameraConstants.trackedLabelColor,
                labelWidth: CameraConstants.trackedLabelWidth,
                labelHeight: CameraConstants.trackedLabelHeight,
                labelFontSize: CameraConstants.trackedLabelFontSize
            ) {
                boundingBoxLayers.append(boxLayer)
            }
        }
    }

    // Draw ghost legs (last known position of lost goal legs)
    private func drawGhostLegs(imageSize: CGSize) {
        guard overlayView != nil, let previewLayer = cameraManager.previewLayer else { return }
        for ghost in goalLegTracker.ghostLegs {
            guard ghost.count == 5 else { continue }
            let id = ghost[4]
            if let boxLayer = BoundingBoxDrawer.drawBox(
                on: overlayView,
                previewLayer: previewLayer,
                rect: ghost,
                imageSize: imageSize,
                color: CameraConstants.ghostBorderColor,
                borderWidth: CameraConstants.ghostBorderWidth,
                label: "Ghost: \(id)",
                labelColor: CameraConstants.ghostLabelColor,
                labelWidth: CameraConstants.ghostLabelWidth,
                labelHeight: CameraConstants.ghostLabelHeight,
                labelFontSize: CameraConstants.ghostLabelFontSize
            ) {
                boundingBoxLayers.append(boxLayer)
            }
        }
    }

    // Draw other bounding boxes (balls, etc), optionally skipping Goal Legs
    private func drawBoundingBoxes(predictions: [RFObjectDetectionPrediction], imageSize: CGSize, skipGoalLegs: Bool = false) {
        guard overlayView != nil, let previewLayer = cameraManager.previewLayer else { return }
        for prediction in predictions {
            if skipGoalLegs && prediction.className == "Goal Leg" { continue }
            var outlineColor: UIColor = CameraConstants.defaultBallColor
            var label = prediction.className
            switch prediction.className {
            case "Red Ball":
                outlineColor = CameraConstants.redBallColor
            case "Blue Ball":
                outlineColor = CameraConstants.blueBallColor
            default:
                outlineColor = CameraConstants.defaultBallColor
            }
            let rect: [Double] = [
                Double(prediction.x - prediction.width/2),
                Double(prediction.y - prediction.height/2),
                Double(prediction.x + prediction.width/2),
                Double(prediction.y + prediction.height/2)
            ]
            if let boxLayer = BoundingBoxDrawer.drawBox(
                on: overlayView,
                previewLayer: previewLayer,
                rect: rect,
                imageSize: imageSize,
                color: outlineColor,
                borderWidth: CameraConstants.ballBorderWidth,
                label: label,
                labelColor: outlineColor,
                labelWidth: CameraConstants.ballLabelWidth,
                labelHeight: CameraConstants.ballLabelHeight,
                labelFontSize: CameraConstants.ballLabelFontSize
            ) {
                boundingBoxLayers.append(boxLayer)
            }
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
        let scale = min(scaleX, scaleY)
        let scaledImageWidth = imageSize.width * scale
        let scaledImageHeight = imageSize.height * scale
        let xOffset = (previewSize.width - scaledImageWidth) / 2
        let yOffset = (previewSize.height - scaledImageHeight) / 2

        var x = rect.origin.x * scale + xOffset
        var y = rect.origin.y * scale + yOffset
        var width = rect.size.width * scale
        var height = rect.size.height * scale

        // Fix overlay position shifting on device rotation
        if let connection = previewLayer.connection {
            switch connection.videoOrientation {
            case .landscapeLeft:
                // Rotate 90° CCW
                let temp = x
                x = y
                y = previewSize.width - temp - width
                swap(&width, &height)
            case .landscapeRight:
                // Rotate 90° CW
                let temp = x
                x = previewSize.height - y - height
                y = temp
                swap(&width, &height)
            case .portraitUpsideDown:
                // Rotate 180°
                x = previewSize.width - x - width
                y = previewSize.height - y - height
            default:
                break
            }
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraManager.previewLayer?.frame = view.bounds
        overlayView?.frame = cameraManager.previewLayer?.frame ?? view.bounds
    }

    // Fix camera preview orientation when device orientation changes
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Only clear ghost legs if not paused
        let paused = isPausedBinding?.wrappedValue ?? false
        if !paused {
            goalLegTracker.clearGhostLegs()
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self, let previewLayer = self.cameraManager.previewLayer else { return }
            previewLayer.frame = self.view.bounds
            if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = self.currentVideoOrientation()
            }
            self.overlayView?.frame = previewLayer.frame
        })
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    private var fieldOverlayManager = FieldOverlayManager()
    
    private func drawPolygonsOverlay() {
        guard let previewLayer = cameraManager.previewLayer else { return }
        let imageSize = getCurrentImageSize()
        // Draw live polygon in light green
        if let livePolygon = fieldOverlayManager.getLivePolygon(from: goalLegTracker) {
            drawPolygon(vertices: livePolygon,
                       color: UIColor.systemGreen.withAlphaComponent(0.7),
                       lineWidth: 4.0,
                       imageSize: imageSize,
                       previewLayer: previewLayer)

            // --- Draw overlays for long/short goals ---
            drawRelativeGoalOverlays(on: livePolygon, imageSize: imageSize, previewLayer: previewLayer)
        }
        // Draw reference polygon in dark blue
        if let refPolygon = fieldOverlayManager.getReferencePolygon() {
            drawPolygon(vertices: refPolygon,
                       color: UIColor.systemBlue.withAlphaComponent(0.85),
                       lineWidth: 3.0,
                       imageSize: CGSize(width: 5712, height: 4284),
                       previewLayer: previewLayer)
        }
    }

    /// Draws overlays for long and short goals using live polygon and computed ratios/percentages
    private func drawRelativeGoalOverlays(on polygon: [CGPoint], imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
        guard polygon.count == 4 else { return }
        // Order: [topLeft, topRight, bottomRight, bottomLeft] (clockwise)
        let ordered = orderVerticesClockwise(polygon)
        // --- Long Goals ---
        // Horizontal pairs: (0,1) and (2,3)
        let longGoalPairs = [(0,1), (2,3)]
        let longGoalRatios: [CGFloat] = [0.9051, 0.9558] // From script output
        let longGoalControlZone: (start: CGFloat, end: CGFloat) = (0.35, 0.65)
        let longGoalHeightIncrements: [CGFloat] = [90.0, 190.0] // top long goal: lower by 10, bottom long goal: raise by 90
        for (i, pair) in longGoalPairs.enumerated() {
            let p1 = ordered[pair.0]
            let p2 = ordered[pair.1]
            let centerDist = hypot(p2.x - p1.x, p2.y - p1.y)
            let goalLen = centerDist * longGoalRatios[i]
            // Find direction vector
            let dx = (p2.x - p1.x) / centerDist
            let dy = (p2.y - p1.y) / centerDist
            // Compute endpoints for the long goal line
            let mid = CGPoint(x: (p1.x + p2.x)/2, y: (p1.y + p2.y)/2)
            let halfLen = goalLen / 2
            var ep1 = CGPoint(x: mid.x - dx * halfLen, y: mid.y - dy * halfLen)
            var ep2 = CGPoint(x: mid.x + dx * halfLen, y: mid.y + dy * halfLen)
            // Move endpoints vertically by custom increment
            ep1.y -= longGoalHeightIncrements[i]
            ep2.y -= longGoalHeightIncrements[i]
            // Draw long goal line (yellow)
            drawLine(from: ep1, to: ep2, color: UIColor.systemYellow, lineWidth: 5.0, imageSize: imageSize, previewLayer: previewLayer)
            // Draw control zone points (orange)
            var cz1 = CGPoint(x: ep1.x + (ep2.x - ep1.x) * longGoalControlZone.start, y: ep1.y + (ep2.y - ep1.y) * longGoalControlZone.start)
            var cz2 = CGPoint(x: ep1.x + (ep2.x - ep1.x) * longGoalControlZone.end, y: ep1.y + (ep2.y - ep1.y) * longGoalControlZone.end)
            // Control zones already moved with ep1/ep2
            drawPoint(at: cz1, color: UIColor.orange, radius: 14, imageSize: imageSize, previewLayer: previewLayer)
            drawPoint(at: cz2, color: UIColor.orange, radius: 14, imageSize: imageSize, previewLayer: previewLayer)
        }
        // --- Short Goals ---
        // Percentages from script output
        let shortGoalPercents: [[(y: CGFloat, x: CGFloat)]] = [
            [(48.10, 57.07), (34.76, 44.68)], // Short Goal 1
            [(73.33, 41.99), (58.10, 55.18)]  // Short Goal 2
        ]
        // Polygon bounds
        let minX = ordered.map { $0.x }.min() ?? 0
        let maxX = ordered.map { $0.x }.max() ?? 0
        let minY = ordered.map { $0.y }.min() ?? 0
        let maxY = ordered.map { $0.y }.max() ?? 0
        for (goalIdx, endpoints) in shortGoalPercents.enumerated() {
            var pts: [CGPoint] = []
            for ep in endpoints {
                // Undo Y inversion for short goals
                let x = minX + (maxX - minX) * (ep.x / 100)
                var y = minY + (maxY - minY) * (ep.y / 100)
                // Raise short goals by 200
                y -= 150.0
                pts.append(CGPoint(x: x, y: y))
            }
            if pts.count == 2 {
                drawLine(from: pts[0], to: pts[1], color: UIColor.systemPink, lineWidth: 5.0, imageSize: imageSize, previewLayer: previewLayer)
            }
        }
    }

    /// Draws a line between two points on the overlay
    private func drawLine(from: CGPoint, to: CGPoint, color: UIColor, lineWidth: CGFloat, imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
        let p1 = convertPoint(from, imageSize: imageSize, previewLayer: previewLayer)
        let p2 = convertPoint(to, imageSize: imageSize, previewLayer: previewLayer)
        let path = UIBezierPath()
        path.move(to: p1)
        path.addLine(to: p2)
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = lineWidth
        overlayView.layer.addSublayer(shapeLayer)
        boundingBoxLayers.append(shapeLayer)
    }
    
    /// Helper method to draw a point for debugging transforms
    private func drawPoint(at point: CGPoint, color: UIColor, radius: CGFloat, imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
        let convertedPoint = convertPoint(point, imageSize: imageSize, previewLayer: previewLayer)
        let pointLayer = CAShapeLayer()
        let path = UIBezierPath(arcCenter: convertedPoint,
                               radius: radius,
                               startAngle: 0,
                               endAngle: 2 * .pi,
                               clockwise: true)
        pointLayer.path = path.cgPath
        pointLayer.fillColor = color.cgColor
        overlayView.layer.addSublayer(pointLayer)
        boundingBoxLayers.append(pointLayer)
    }

    /// Returns the centers of the live polygon (tracked + ghost goal legs)
    private func getLivePolygonCenters() -> [CGPoint]? {
        var centers: [CGPoint] = []
        let allLegs = goalLegTracker.trackedGoalLegs + goalLegTracker.ghostLegs
        if allLegs.count == 4 {
            for leg in allLegs {
                if leg.count >= 4 {
                    let cx = (leg[0] + leg[2]) / 2.0
                    let cy = (leg[1] + leg[3]) / 2.0
                    centers.append(CGPoint(x: cx, y: cy))
                }
            }
            return centers
        }
        return nil
    }

    /// Returns the centers of the reference polygon from annotation data
    private func getReferencePolygonCenters() -> [CGPoint]? {
        guard let annotations = FieldAnnotationLoader.loadAnnotations(from: Bundle.main.path(forResource: "VexFieldAnnotations", ofType: "json") ?? "") else { return nil }
        let legs = annotations.goalLegs
        if legs.count == 4 {
            return legs.map { $0.center }
        }
        return nil
    }

    /// Draws a polygon on the overlay view given a list of CGPoint vertices
    private func drawPolygon(vertices: [CGPoint], color: UIColor, lineWidth: CGFloat = 3.0, imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
        guard vertices.count == 4 else { return }
        let path = UIBezierPath()
        path.move(to: convertPoint(vertices[0], imageSize: imageSize, previewLayer: previewLayer))
        for i in 1..<vertices.count {
            path.addLine(to: convertPoint(vertices[i], imageSize: imageSize, previewLayer: previewLayer))
        }
        path.close()
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = lineWidth
        overlayView.layer.addSublayer(shapeLayer)
        boundingBoxLayers.append(shapeLayer)
    }
    /// Orders 4 vertices clockwise around their centroid
    private func orderVerticesClockwise(_ vertices: [CGPoint]) -> [CGPoint] {
        guard vertices.count == 4 else { return vertices }
        let centroid = CGPoint(
            x: vertices.map { $0.x }.reduce(0, +) / 4.0,
            y: vertices.map { $0.y }.reduce(0, +) / 4.0
        )
        return vertices.sorted { a, b in
            let angleA = atan2(a.y - centroid.y, a.x - centroid.x)
            let angleB = atan2(b.y - centroid.y, b.x - centroid.x)
            return angleA < angleB
        }
    }

    /// Gets the current image size from the last frame (fallback to 5712x4284 if unavailable)
    private func getCurrentImageSize() -> CGSize {
        if let overlays = lastOverlays {
            return overlays.1
        }
        return CGSize(width: 5712, height: 4284)
    }

    /// Converts a CGPoint from image coordinates to preview layer coordinates
    private func convertPoint(_ point: CGPoint, imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        let normX = point.x / imageSize.width
        let normY = point.y / imageSize.height
        let normalizedRect = CGRect(x: normX, y: normY, width: 0.001, height: 0.001)
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
        return CGPoint(x: convertedRect.origin.x, y: convertedRect.origin.y)
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
