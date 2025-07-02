import UIKit
import Foundation

/// Enum describing pipe types on the VEX field.
enum PipeType: String, Codable {
    case long
    case short
}

/// Simple representation of a detected ball.
struct BallDetection: Codable {
    /// Position in image coordinates (pixels). In the future convert to relative space.
    let position: CGPoint
    /// Classified dominant colour.
    let color: BallColor
    /// Confidence score 0-1 for the colour classification.
    let confidence: CGFloat
    
    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case position, color, confidence
        case x, y
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(confidence, forKey: .confidence)
        
        // Encode CGPoint as nested container
        var positionContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .position)
        try positionContainer.encode(position.x, forKey: .x)
        try positionContainer.encode(position.y, forKey: .y)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(BallColor.self, forKey: .color)
        confidence = try container.decode(CGFloat.self, forKey: .confidence)
        
        // Decode CGPoint from nested container
        let positionContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .position)
        let x = try positionContainer.decode(CGFloat.self, forKey: .x)
        let y = try positionContainer.decode(CGFloat.self, forKey: .y)
        position = CGPoint(x: x, y: y)
    }
    
    // Regular initializer
    init(position: CGPoint, color: BallColor, confidence: CGFloat) {
        self.position = position
        self.color = color
        self.confidence = confidence
    }
}

/// Encapsulates all detection data for a single pipe.
struct DetectionResult: Codable {
    let pipeType: PipeType
    let balls: [BallDetection]
    /// Optional notes about obstructions encountered during detection.
    let obstructionNotes: String?
} 