import UIKit

/// Represents the color of a VEX ball.
enum BallColor: String, Codable {
    case red
    case blue
    case unknown
    
    var uiColor: UIColor {
        switch self {
        case .red: return VRCColors.red
        case .blue: return VRCColors.blue
        case .unknown: return .gray
        }
    }
} 