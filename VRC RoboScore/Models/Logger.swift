import Foundation
import OSLog

struct Logger {
    private static let logger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.vrc.roboscore", category: "ShareDebug")
    
    static func debug(_ message: String) {
        #if DEBUG
        os_log(.debug, log: logger, "%{public}@", message)
        print("🔍 Debug: \(message)")
        #endif
    }
    
    static func error(_ message: String) {
        #if DEBUG
        os_log(.error, log: logger, "❌ Error: %{public}@", message)
        print("❌ Error: \(message)")
        #endif
    }
} 