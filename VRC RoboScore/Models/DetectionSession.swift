import UIKit

/// Represents a full analysis session over the four defined pipe regions.
struct DetectionSession {
    let id: UUID = UUID()
    let timestamp: Date = Date()
    /// The original captured image (landscape orientation).
    let originalImage: UIImage
    /// Results for the four pipe regions (red, green, blue, orange order).
    let results: [DetectionResult]
} 