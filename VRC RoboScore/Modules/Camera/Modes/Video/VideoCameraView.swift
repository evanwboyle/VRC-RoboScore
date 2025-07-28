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
    @ObservedObject var gameState: GameState
    @State private var isPaused: Bool = false
    @State private var fps: Double = 0.0
    @State private var isModelLoaded: Bool = false
    @State var longGoalPercents: [[(y: CGFloat, x: CGFloat)]] = [
        [(58.0, 0.0), (55.0, 105.0)], // Long Goal 1 (y%, x%) for each endpoint
        [(-14.0, 32.0), (-14.0, 66.0)]  // Long Goal 2
    ]
    @State var controlZonePercent: CGFloat = 30.0
    @State var shortGoalPercents: [[(y: CGFloat, x: CGFloat)]] = [
        [(26.0, 57.07), (39.0, 40.0)], // Short Goal 1
        [(19.0, 60.0), (10.0, 42.0)]  // Short Goal 2
    ]
    @State var ballCountAverageWindow: Int = 10
    @State private var showValueEditor: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraViewControllerRepresentable(
                isPaused: $isPaused,
                fps: $fps,
                isModelLoaded: $isModelLoaded,
                longGoalPercents: $longGoalPercents,
                shortGoalPercents: $shortGoalPercents,
                controlZonePercent: $controlZonePercent,
                ballCountAverageWindow: $ballCountAverageWindow,
                gameState: gameState
            )
            .edgesIgnoringSafeArea(.all)
            VStack(spacing: 0) {
                // Top bar: X button, pause, FPS, and score
                HStack(spacing: CameraConstants.cameraButtonSpacing) {
                    Button(action: { isPresented = false }) {
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
                    Button(action: { isPaused.toggle() }) {
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
                .padding(.top, 8)
                .padding(.bottom, 4)
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
                }
                Spacer()
            }
        }
    }
}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var isPaused: Bool
    @Binding var fps: Double
    @Binding var isModelLoaded: Bool
    @Binding var longGoalPercents: [[(y: CGFloat, x: CGFloat)]]
    @Binding var shortGoalPercents: [[(y: CGFloat, x: CGFloat)]]
    @Binding var controlZonePercent: CGFloat
    @Binding var ballCountAverageWindow: Int

    var gameState: GameState

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.isPausedBinding = $isPaused
        vc.fpsBinding = $fps
        vc.isModelLoadedBinding = $isModelLoaded
        vc.longGoalPercentsBinding = $longGoalPercents
        vc.shortGoalPercentsBinding = $shortGoalPercents
        vc.controlZonePercentBinding = $controlZonePercent
        vc.ballCountAverageWindowBinding = $ballCountAverageWindow
        vc.gameState = gameState
        return vc
    }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.isPausedBinding = $isPaused
        uiViewController.fpsBinding = $fps
        uiViewController.isModelLoadedBinding = $isModelLoaded
        uiViewController.longGoalPercentsBinding = $longGoalPercents
        uiViewController.shortGoalPercentsBinding = $shortGoalPercents
        uiViewController.controlZonePercentBinding = $controlZonePercent
        uiViewController.ballCountAverageWindowBinding = $ballCountAverageWindow
        uiViewController.gameState = gameState
    }
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var gameState: GameState!
    var longGoalPercentsBinding: Binding<[[ (y: CGFloat, x: CGFloat) ]]>? = nil
    var shortGoalPercentsBinding: Binding<[[ (y: CGFloat, x: CGFloat) ]]>? = nil
    var controlZonePercentBinding: Binding<CGFloat>? = nil
    var ballCountAverageWindowBinding: Binding<Int>? = nil
    private var ballCountBuffer: [[String: (blue: Int, red: Int)]] = []
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Invalidate FPS timer when view disappears
        fpsTimer?.invalidate()
        fpsTimer = nil
    }
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
    // FPS timer-based counter
    private var frameCount: Int = 0
    private var fpsTimer: Timer?
    private var frameCountsBuffer: [Int] = []
    private let fpsBufferSize = 5

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
        // Start FPS timer
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Add current frameCount to buffer
            self.frameCountsBuffer.append(self.frameCount)
            if self.frameCountsBuffer.count > self.fpsBufferSize {
                self.frameCountsBuffer.removeFirst()
            }
            // Calculate average FPS over buffer
            let sum = self.frameCountsBuffer.reduce(0, +)
            let avgFps = Double(sum) / Double(self.frameCountsBuffer.count)
            self.frameCount = 0
            DispatchQueue.main.async {
                self.fpsBinding?.wrappedValue = avgFps
            }
        }
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
        // Increment frame count for timer-based FPS
        frameCount += 1
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
        var ballCounts: [String: (blue: Int, red: Int)] = [
            "LG1CZ": (0, 0), "LG1LR": (0, 0),
            "LG2CZ": (0, 0), "LG2LR": (0, 0),
            "SG1": (0, 0), "SG2": (0, 0)
        ]
        var ballAssignments: [Int: String] = [:] // ball idx -> category
        var longGoalSegments: [(name: String, line: (CGPoint, CGPoint))] = []
        var controlZones: [(name: String, line: (CGPoint, CGPoint))] = []
        var shortGoals: [(name: String, line: (CGPoint, CGPoint))] = []
        // Draw live polygon in light green
        if let livePolygon = fieldOverlayManager.getLivePolygon(from: goalLegTracker) {
            drawPolygon(vertices: livePolygon,
                       color: UIColor.systemGreen.withAlphaComponent(0.7),
                       lineWidth: 4.0,
                       imageSize: imageSize,
                       previewLayer: previewLayer)
            // --- Draw overlays for long/short goals ---
            drawRelativeGoalOverlays(on: livePolygon, imageSize: imageSize, previewLayer: previewLayer)
            // --- Prepare goal segments for collision ---
            let ordered = orderVerticesClockwise(livePolygon)
            let longGoalPercents: [[(y: CGFloat, x: CGFloat)]] = longGoalPercentsBinding?.wrappedValue ?? []
            let shortGoalPercents: [[(y: CGFloat, x: CGFloat)]] = shortGoalPercentsBinding?.wrappedValue ?? []
            let controlZonePercent: CGFloat = controlZonePercentBinding?.wrappedValue ?? 30.0
            let minX = ordered.map { $0.x }.min() ?? 0
            let maxX = ordered.map { $0.x }.max() ?? 0
            let minY = ordered.map { $0.y }.min() ?? 0
            let maxY = ordered.map { $0.y }.max() ?? 0
            for (i, endpoints) in longGoalPercents.enumerated() {
                guard endpoints.count == 2 else { continue }
                let x0 = minX + (maxX - minX) * (endpoints[0].x / 100)
                let y0 = minY + (maxY - minY) * (endpoints[0].y / 100)
                let x1 = minX + (maxX - minX) * (endpoints[1].x / 100)
                let y1 = minY + (maxY - minY) * (endpoints[1].y / 100)
                let pt0 = CGPoint(x: x0, y: y0)
                let pt1 = CGPoint(x: x1, y: y1)
                // Split into three segments: left, CZ, right
                let dx = pt1.x - pt0.x
                let dy = pt1.y - pt0.y
                let totalLen = sqrt(dx*dx + dy*dy)
                let controlFrac = max(0.0, min(1.0, controlZonePercent / 100.0))
                let controlLen = totalLen * controlFrac
                let midX = (pt0.x + pt1.x) / 2.0
                let midY = (pt0.y + pt1.y) / 2.0
                let halfControlLen = controlLen / 2.0
                let lineAngle = atan2(dy, dx)
                let controlStartX = midX - halfControlLen * cos(lineAngle)
                let controlStartY = midY - halfControlLen * sin(lineAngle)
                let controlEndX = midX + halfControlLen * cos(lineAngle)
                let controlEndY = midY + halfControlLen * sin(lineAngle)
                let controlStartPt = CGPoint(x: controlStartX, y: controlStartY)
                let controlEndPt = CGPoint(x: controlEndX, y: controlEndY)
                // Left segment
                longGoalSegments.append((name: "LG\(i+1)L", line: (pt0, controlStartPt)))
                // Control zone segment
                controlZones.append((name: "LG\(i+1)CZ", line: (controlStartPt, controlEndPt)))
                // Right segment
                longGoalSegments.append((name: "LG\(i+1)R", line: (controlEndPt, pt1)))
            }
            for (i, endpoints) in shortGoalPercents.enumerated() {
                guard endpoints.count == 2 else { continue }
                let x0 = minX + (maxX - minX) * (endpoints[0].x / 100)
                let y0 = minY + (maxY - minY) * (endpoints[0].y / 100)
                let x1 = minX + (maxX - minX) * (endpoints[1].x / 100)
                let y1 = minY + (maxY - minY) * (endpoints[1].y / 100)
                let pt0 = CGPoint(x: x0, y: y0)
                let pt1 = CGPoint(x: x1, y: y1)
                shortGoals.append((name: "SG\(i+1)", line: (pt0, pt1)))
            }
        }
        // Draw reference polygon in dark blue
        if let refPolygon = fieldOverlayManager.getReferencePolygon() {
            drawPolygon(vertices: refPolygon,
                       color: UIColor.systemBlue.withAlphaComponent(0.85),
                       lineWidth: 3.0,
                       imageSize: CGSize(width: 5712, height: 4284),
                       previewLayer: previewLayer)
        }
        // --- Ball categorization logic ---
        // Get balls from lastOverlays
        if let overlays = lastOverlays {
            let (predictions, _) = overlays
            var balls: [(idx: Int, center: CGPoint, radius: CGFloat, color: String)] = []
            for (i, pred) in predictions.enumerated() {
                if pred.className == "Red Ball" || pred.className == "Blue Ball" {
                    let cx = CGFloat(pred.x)
                    let cy = CGFloat(pred.y)
                    let r = CGFloat(max(pred.width, pred.height)) / 2.0
                    balls.append((idx: i, center: CGPoint(x: cx, y: cy), radius: r, color: pred.className == "Red Ball" ? "R" : "B"))
                }
            }
            // Priority order
            let priorities: [(String, [(CGPoint, CGPoint)])] = [
                ("LG1LR", longGoalSegments.filter { $0.name == "LG1L" || $0.name == "LG1R" }.map { $0.line }),
                ("LG1CZ", controlZones.filter { $0.name == "LG1CZ" }.map { $0.line }),
                ("LG2LR", longGoalSegments.filter { $0.name == "LG2L" || $0.name == "LG2R" }.map { $0.line }),
                ("LG2CZ", controlZones.filter { $0.name == "LG2CZ" }.map { $0.line }),
                ("SG1", shortGoals.filter { $0.name == "SG1" }.map { $0.line }),
                ("SG2", shortGoals.filter { $0.name == "SG2" }.map { $0.line })
            ]
            for ball in balls {
                var assigned: String? = nil
                for (cat, lines) in priorities {
                    for line in lines {
                        if ballIntersectsLine(ballCenter: ball.center, ballRadius: ball.radius, line: line) {
                            assigned = cat
                            break
                        }
                    }
                    if assigned != nil { break }
                }
                if let cat = assigned {
                    ballAssignments[ball.idx] = cat
                    if ball.color == "B" {
                        ballCounts[cat]?.blue += 1
                    } else {
                        ballCounts[cat]?.red += 1
                    }
                }
            }
        }
        // --- Ball count averaging logic ---
        let window = ballCountAverageWindowBinding?.wrappedValue ?? 10
        ballCountBuffer.append(ballCounts)
        if ballCountBuffer.count > window {
            ballCountBuffer.removeFirst(ballCountBuffer.count - window)
        }
        // Compute average for each category
        var averagedCounts: [String: (blue: Int, red: Int)] = [:]
        for key in ballCounts.keys {
            let blueSum = ballCountBuffer.map { $0[key]?.blue ?? 0 }.reduce(0, +)
            let redSum = ballCountBuffer.map { $0[key]?.red ?? 0 }.reduce(0, +)
            let avgBlue = Int(round(Double(blueSum) / Double(ballCountBuffer.count)))
            let avgRed = Int(round(Double(redSum) / Double(ballCountBuffer.count)))
            averagedCounts[key] = (avgBlue, avgRed)
        }
        // --- Draw overlay rectangle with averaged counts ---
        drawBallCountOverlay(ballCounts: averagedCounts)
    }

    /// Returns true if the ball (center, radius) intersects the line segment
    private func ballIntersectsLine(ballCenter: CGPoint, ballRadius: CGFloat, line: (CGPoint, CGPoint)) -> Bool {
        // Closest point on line segment to ball center
        let (p1, p2) = line
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let length = sqrt(dx*dx + dy*dy)
        if length == 0 { return false }
        let t = max(0, min(1, ((ballCenter.x - p1.x) * dx + (ballCenter.y - p1.y) * dy) / (length * length)))
        let closest = CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
        let dist = hypot(ballCenter.x - closest.x, ballCenter.y - closest.y)
        return dist <= ballRadius
    }

    /// Draws the semi-transparent bezeled rectangle overlay with ball counts
    private func drawBallCountOverlay(ballCounts: [String: (blue: Int, red: Int)]) {
        // --- Update gameState from ballCounts using correct model ---
        // LG1 = topGoals[0], LG2 = topGoals[1]
        // SG1 = bottomGoals[0], SG2 = bottomGoals[1]
        // Each goal's blocks: blocks[.red], blocks[.blue]
        // Control zone: controlPoint.controlledBy

        // LG1
        let lg1B = (ballCounts["LG1LR"]?.blue ?? 0) + (ballCounts["LG1CZ"]?.blue ?? 0)
        let lg1R = (ballCounts["LG1LR"]?.red ?? 0) + (ballCounts["LG1CZ"]?.red ?? 0)
        // LG2
        let lg2B = (ballCounts["LG2LR"]?.blue ?? 0) + (ballCounts["LG2CZ"]?.blue ?? 0)
        let lg2R = (ballCounts["LG2LR"]?.red ?? 0) + (ballCounts["LG2CZ"]?.red ?? 0)
        // SG1
        let sg1B = ballCounts["SG1"]?.blue ?? 0
        let sg1R = ballCounts["SG1"]?.red ?? 0
        // SG2
        let sg2B = ballCounts["SG2"]?.blue ?? 0
        let sg2R = ballCounts["SG2"]?.red ?? 0

        // Control zone logic
        let lg1CZB = ballCounts["LG1CZ"]?.blue ?? 0
        let lg1CZR = ballCounts["LG1CZ"]?.red ?? 0
        let lg2CZB = ballCounts["LG2CZ"]?.blue ?? 0
        let lg2CZR = ballCounts["LG2CZ"]?.red ?? 0

        // Update topGoals (long goals)
        if gameState.topGoals.count >= 2 {
            // LG1
            gameState.topGoals[0].redGoal.blocks[.red] = lg1R
            gameState.topGoals[0].redGoal.blocks[.blue] = lg1B
            gameState.topGoals[0].blueGoal.blocks[.red] = lg1R
            gameState.topGoals[0].blueGoal.blocks[.blue] = lg1B
            // LG2
            gameState.topGoals[1].redGoal.blocks[.red] = lg2R
            gameState.topGoals[1].redGoal.blocks[.blue] = lg2B
            gameState.topGoals[1].blueGoal.blocks[.red] = lg2R
            gameState.topGoals[1].blueGoal.blocks[.blue] = lg2B
        }

        // Update bottomGoals (middle/short goals)
        if gameState.bottomGoals.count >= 2 {
            // SG1
            gameState.bottomGoals[0].redGoal.blocks[.red] = sg1R
            gameState.bottomGoals[0].redGoal.blocks[.blue] = sg1B
            gameState.bottomGoals[0].blueGoal.blocks[.red] = sg1R
            gameState.bottomGoals[0].blueGoal.blocks[.blue] = sg1B
            // SG2
            gameState.bottomGoals[1].redGoal.blocks[.red] = sg2R
            gameState.bottomGoals[1].redGoal.blocks[.blue] = sg2B
            gameState.bottomGoals[1].blueGoal.blocks[.red] = sg2R
            gameState.bottomGoals[1].blueGoal.blocks[.blue] = sg2B
        }

        // Control zone state for LG1
        let lg1Control: Alliance? = lg1CZB > lg1CZR ? .blue : (lg1CZR > lg1CZB ? .red : nil)
        let lg2Control: Alliance? = lg2CZB > lg2CZR ? .blue : (lg2CZR > lg2CZB ? .red : nil)
        if gameState.topGoals.count >= 2 {
            gameState.topGoals[0].redGoal.controlPoint.controlledBy = lg1Control
            gameState.topGoals[0].blueGoal.controlPoint.controlledBy = lg1Control
            gameState.topGoals[1].redGoal.controlPoint.controlledBy = lg2Control
            gameState.topGoals[1].blueGoal.controlPoint.controlledBy = lg2Control
        }

        // Remove previous overlay if any
        if let old = view.viewWithTag(9999) { old.removeFromSuperview() }
        let overlay = UIView()
        overlay.tag = 9999
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        overlay.layer.cornerRadius = 16
        overlay.layer.borderWidth = 2
        overlay.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        overlay.layer.masksToBounds = true
        // Layout: score title + 4 rows
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .equalSpacing
        let font = UIFont.systemFont(ofSize: 18, weight: .bold)
        let scoreFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        // Score title row
        let scoreRow = UIStackView()
        scoreRow.axis = .horizontal
        scoreRow.spacing = 16
        scoreRow.alignment = .center
        let redScoreLbl = UILabel()
        redScoreLbl.text = "\(calculateScore(for: .red, gameState: gameState))"
        redScoreLbl.font = scoreFont
        redScoreLbl.textColor = UIColor(named: "AllianceRed") ?? .red
        redScoreLbl.textAlignment = .right
        let vsLbl = UILabel()
        vsLbl.text = "VS"
        vsLbl.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        vsLbl.textColor = .white
        let blueScoreLbl = UILabel()
        blueScoreLbl.text = "\(calculateScore(for: .blue, gameState: gameState))"
        blueScoreLbl.font = scoreFont
        blueScoreLbl.textColor = UIColor(named: "AllianceBlue") ?? .blue
        blueScoreLbl.textAlignment = .left
        scoreRow.addArrangedSubview(redScoreLbl)
        scoreRow.addArrangedSubview(vsLbl)
        scoreRow.addArrangedSubview(blueScoreLbl)
        stack.addArrangedSubview(scoreRow)
        func coloredLabel(_ value: Int, color: UIColor) -> UILabel {
            let lbl = UILabel()
            lbl.text = "\(value)"
            lbl.font = font
            lbl.textColor = color
            return lbl
        }
        // Helper for SG1 and SG2 rows
        func row(_ title: String, blue: Int, red: Int) -> UIStackView {
            let h = UIStackView()
            h.axis = .horizontal
            h.spacing = 12
            h.alignment = .center
            let titleLbl = UILabel()
            titleLbl.text = title
            titleLbl.font = font
            titleLbl.textColor = .white
            h.addArrangedSubview(titleLbl)
            h.addArrangedSubview(coloredLabel(blue, color: .blue))
            h.addArrangedSubview(coloredLabel(red, color: .red))
            return h
        }
        // LG1 row: CZ, LR
        let lg1Row = UIStackView()
        lg1Row.axis = .horizontal
        lg1Row.spacing = 12
        lg1Row.alignment = .center
        let lg1Lbl = UILabel()
        lg1Lbl.text = "LG1"
        lg1Lbl.font = font
        lg1Lbl.textColor = .white
        lg1Row.addArrangedSubview(lg1Lbl)
        let czLbl1 = UILabel()
        czLbl1.text = "CZ"
        czLbl1.font = font
        czLbl1.textColor = .white
        lg1Row.addArrangedSubview(czLbl1)
        lg1Row.addArrangedSubview(coloredLabel(ballCounts["LG1CZ"]?.blue ?? 0, color: .blue))
        lg1Row.addArrangedSubview(coloredLabel(ballCounts["LG1CZ"]?.red ?? 0, color: .red))
        let lrLbl1 = UILabel()
        lrLbl1.text = "LR"
        lrLbl1.font = font
        lrLbl1.textColor = .white
        lg1Row.addArrangedSubview(lrLbl1)
        lg1Row.addArrangedSubview(coloredLabel(ballCounts["LG1LR"]?.blue ?? 0, color: .blue))
        lg1Row.addArrangedSubview(coloredLabel(ballCounts["LG1LR"]?.red ?? 0, color: .red))
        stack.addArrangedSubview(lg1Row)
        // LG2 row: CZ, LR
        let lg2Row = UIStackView()
        lg2Row.axis = .horizontal
        lg2Row.spacing = 12
        lg2Row.alignment = .center
        let lg2Lbl = UILabel()
        lg2Lbl.text = "LG2"
        lg2Lbl.font = font
        lg2Lbl.textColor = .white
        lg2Row.addArrangedSubview(lg2Lbl)
        let czLbl2 = UILabel()
        czLbl2.text = "CZ"
        czLbl2.font = font
        czLbl2.textColor = .white
        lg2Row.addArrangedSubview(czLbl2)
        lg2Row.addArrangedSubview(coloredLabel(ballCounts["LG2CZ"]?.blue ?? 0, color: .blue))
        lg2Row.addArrangedSubview(coloredLabel(ballCounts["LG2CZ"]?.red ?? 0, color: .red))
        let lrLbl2 = UILabel()
        lrLbl2.text = "LR"
        lrLbl2.font = font
        lrLbl2.textColor = .white
        lg2Row.addArrangedSubview(lrLbl2)
        lg2Row.addArrangedSubview(coloredLabel(ballCounts["LG2LR"]?.blue ?? 0, color: .blue))
        lg2Row.addArrangedSubview(coloredLabel(ballCounts["LG2LR"]?.red ?? 0, color: .red))
        stack.addArrangedSubview(lg2Row)
        stack.addArrangedSubview(row("SG1", blue: ballCounts["SG1"]?.blue ?? 0, red: ballCounts["SG1"]?.red ?? 0))
        stack.addArrangedSubview(row("SG2", blue: ballCounts["SG2"]?.blue ?? 0, red: ballCounts["SG2"]?.red ?? 0))
        overlay.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16)
        ])
        view.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            overlay.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            overlay.widthAnchor.constraint(equalToConstant: 320),
            overlay.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    /// Draws overlays for long and short goals using live polygon and computed ratios/percentages
    private func drawRelativeGoalOverlays(on polygon: [CGPoint], imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) {
        guard polygon.count == 4 else { return }
        let ordered = orderVerticesClockwise(polygon)
        // --- Long Goals ---
        let longGoalPercents: [[(y: CGFloat, x: CGFloat)]] = longGoalPercentsBinding?.wrappedValue ?? []
        let shortGoalPercents: [[(y: CGFloat, x: CGFloat)]] = shortGoalPercentsBinding?.wrappedValue ?? []
        let controlZonePercent: CGFloat = controlZonePercentBinding?.wrappedValue ?? 30.0
        let minX = ordered.map { $0.x }.min() ?? 0
        let maxX = ordered.map { $0.x }.max() ?? 0
        let minY = ordered.map { $0.y }.min() ?? 0
        let maxY = ordered.map { $0.y }.max() ?? 0
        for endpoints in longGoalPercents {
            guard endpoints.count == 2 else { continue }
            let x0 = minX + (maxX - minX) * (endpoints[0].x / 100)
            let y0 = minY + (maxY - minY) * (endpoints[0].y / 100)
            let x1 = minX + (maxX - minX) * (endpoints[1].x / 100)
            let y1 = minY + (maxY - minY) * (endpoints[1].y / 100)
            let pt0 = CGPoint(x: x0, y: y0)
            let pt1 = CGPoint(x: x1, y: y1)
            // Draw control zone (centered % pink, rest yellow)
            let dx = pt1.x - pt0.x
            let dy = pt1.y - pt0.y
            let totalLen = sqrt(dx*dx + dy*dy)
            let controlFrac = max(0.0, min(1.0, controlZonePercent / 100.0))
            let controlLen = totalLen * controlFrac
            // Calculate start and end points for centered control zone
            let midX = (pt0.x + pt1.x) / 2.0
            let midY = (pt0.y + pt1.y) / 2.0
            let halfControlLen = controlLen / 2.0
            let lineAngle = atan2(dy, dx)
            let controlStartX = midX - halfControlLen * cos(lineAngle)
            let controlStartY = midY - halfControlLen * sin(lineAngle)
            let controlEndX = midX + halfControlLen * cos(lineAngle)
            let controlEndY = midY + halfControlLen * sin(lineAngle)
            let controlStartPt = CGPoint(x: controlStartX, y: controlStartY)
            let controlEndPt = CGPoint(x: controlEndX, y: controlEndY)
            // Draw outer segments (yellow)
            drawLine(from: pt0, to: controlStartPt, color: UIColor.systemYellow, lineWidth: 5.0, imageSize: imageSize, previewLayer: previewLayer)
            drawLine(from: controlEndPt, to: pt1, color: UIColor.systemYellow, lineWidth: 5.0, imageSize: imageSize, previewLayer: previewLayer)
            // Draw centered control zone (pink)
            drawLine(from: controlStartPt, to: controlEndPt, color: UIColor.systemPink, lineWidth: 5.0, imageSize: imageSize, previewLayer: previewLayer)
        }
        for endpoints in shortGoalPercents {
            guard endpoints.count == 2 else { continue }
            let x0 = minX + (maxX - minX) * (endpoints[0].x / 100)
            let y0 = minY + (maxY - minY) * (endpoints[0].y / 100)
            let x1 = minX + (maxX - minX) * (endpoints[1].x / 100)
            let y1 = minY + (maxY - minY) * (endpoints[1].y / 100)
            let pt0 = CGPoint(x: x0, y: y0)
            let pt1 = CGPoint(x: x1, y: y1)
            drawLine(from: pt0, to: pt1, color: UIColor.systemPink, lineWidth: 5.0, imageSize: imageSize, previewLayer: previewLayer)
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
