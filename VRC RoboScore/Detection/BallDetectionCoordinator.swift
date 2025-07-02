import UIKit

/// Central coordinator responsible for analyzing the cropped pipe images and running
/// the various detection pipelines to count balls on each pipe.
///
/// This is currently a *stub* implementation which returns placeholder data so that the
/// UI can be wired up incrementally.
final class BallDetectionCoordinator {
    /// Performs the full analysis asynchronously and returns a DetectionSession.
    /// - Parameters:
    ///   - croppedImages: Array of `LineCrop` containing the pre-cropped pipe images.
    func analyze(croppedImages: [LineCrop]) async -> DetectionSession {
        Logger.debug("Starting detection on \(croppedImages.count) cropped images", category: .imageProcessing)
        
        // TODO: Replace with real detection implementation
        var results: [DetectionResult] = []
        
        // Process each pipe image
        for (idx, crop) in croppedImages.enumerated() {
            Logger.debug("Processing pipe \(idx) (\(crop.label)) - image size: \(crop.image.size.width)x\(crop.image.size.height)", category: .imageProcessing)
            
            let pipeType: PipeType = (idx == 1) ? .long : .short
            Logger.debug("Pipe \(idx) classified as \(pipeType)", category: .imageProcessing)
            
            // Run detection pipeline
            Logger.debug("Running color detection for pipe \(idx)", category: .imageProcessing)
            let (color, confidence) = ColorDetector.detectDominantColor(in: crop.image)
            Logger.debug("Color detection result: \(color) with confidence \(confidence)", category: .imageProcessing)
            
            Logger.debug("Running shape detection for pipe \(idx)", category: .imageProcessing)
            let hasShape = ShapeDetector.containsBallShape(in: crop.image)
            Logger.debug("Shape detection result: \(hasShape)", category: .imageProcessing)
            
            Logger.debug("Running obstruction handling for pipe \(idx)", category: .imageProcessing)
            let processedImage = ObstructionHandler.handleObstructions(in: crop.image)
            Logger.debug("Obstruction handling complete", category: .imageProcessing)
            
            Logger.debug("Running reference line detection for pipe \(idx)", category: .imageProcessing)
            let refLine = ReferenceLineDetector.detectReferenceLine(in: processedImage)
            Logger.debug("Reference line detection result: \(String(describing: refLine))", category: .imageProcessing)
            
            // Generate a single dummy ball roughly in the middle so the UI has something to show
            let dummyBall = BallDetection(
                position: CGPoint(x: crop.image.size.width / 2,
                                y: crop.image.size.height / 2),
                color: color,
                confidence: confidence
            )
            
            let result = DetectionResult(
                pipeType: pipeType,
                balls: [dummyBall],
                obstructionNotes: "Stub – no obstructions analysed"
            )
            results.append(result)
            
            Logger.debug("Completed processing pipe \(idx)", category: .imageProcessing)
        }
        
        Logger.debug("Detection complete - creating session", category: .imageProcessing)
        
        // Use the first crop's image as the original for now
        // TODO: Consider if we want to keep/use the uncropped original
        return DetectionSession(
            originalImage: croppedImages.first?.image ?? UIImage(),
            results: results
        )
    }
} 