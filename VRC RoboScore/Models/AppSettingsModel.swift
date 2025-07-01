import Foundation
import SwiftUI

// MARK: - Visual Mode
enum VisualMode: String, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
    case custom = "Custom"
    
    var displayName: String {
        return self.rawValue
    }
}

// MARK: - App Settings Manager
class AppSettingsManager: ObservableObject {
    @AppStorage("debugMode") var debugMode: Bool = false
    @AppStorage("visualModeRaw") private var visualModeRaw: String = VisualMode.auto.rawValue
    @AppStorage("customBackgroundColorHex") private var customBackgroundColorHex: String = "#FFFFFF"
    
    @Published var ballRadiusRatio: Double = 0.024 {
        didSet {
            UserDefaults.standard.set(ballRadiusRatio, forKey: "ballRadiusRatio")
        }
    }
    
    @Published var exclusionRadiusMultiplier: Double = 1.2 {
        didSet {
            UserDefaults.standard.set(exclusionRadiusMultiplier, forKey: "exclusionRadiusMultiplier")
        }
    }
    
    @Published var ballAreaPercentage: Double = 30.0 {
        didSet {
            UserDefaults.standard.set(ballAreaPercentage, forKey: "ballAreaPercentage")
        }
    }
    
    var visualMode: VisualMode {
        get {
            return VisualMode(rawValue: visualModeRaw) ?? .auto
        }
        set {
            visualModeRaw = newValue.rawValue
        }
    }
    
    var customBackgroundColor: Color {
        get {
            return Color(hex: customBackgroundColorHex) ?? Color("Background", bundle: nil)
        }
        set {
            customBackgroundColorHex = newValue.toHex() ?? "#FFFFFF"
        }
    }
    
    static let shared = AppSettingsManager()
    
    private init() {
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        ballRadiusRatio = UserDefaults.standard.double(forKey: "ballRadiusRatio")
        exclusionRadiusMultiplier = UserDefaults.standard.double(forKey: "exclusionRadiusMultiplier")
        ballAreaPercentage = UserDefaults.standard.double(forKey: "ballAreaPercentage")
        
        // Set default values if not already set
        if ballRadiusRatio == 0 { ballRadiusRatio = 0.024 }
        if exclusionRadiusMultiplier == 0 { exclusionRadiusMultiplier = 1.2 }
        if ballAreaPercentage == 0 { ballAreaPercentage = 30.0 }
    }
    
    func getCurrentBackgroundColor() -> Color {
        switch visualMode {
        case .auto:
            return Color("Background", bundle: nil)
        case .light:
            return Color(.systemBackground)
        case .dark:
            return Color(.systemBackground)
        case .custom:
            return customBackgroundColor
        }
    }
    
    func getCurrentColorScheme() -> ColorScheme? {
        switch visualMode {
        case .auto:
            return nil // Use system setting
        case .light:
            return .light
        case .dark:
            return .dark
        case .custom:
            return nil // Use system setting for custom mode
        }
    }
}

// MARK: - Color Extensions
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        
        return String(format: "#%02lX%02lX%02lX",
                     lroundf(r * 255),
                     lroundf(g * 255),
                     lroundf(b * 255))
    }
} 