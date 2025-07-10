import Foundation
import SwiftUI

// MARK: - App Settings Manager
class AppSettingsManager: ObservableObject {
    @AppStorage("debugMode") var debugMode: Bool = false
    
    static let shared = AppSettingsManager()
    
    private init() {
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
    }
} 