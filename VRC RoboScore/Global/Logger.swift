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

    enum LogCategory: String {
        case imageProcessing = "ImageProcessing"
        case navigation = "Navigation"
        case export = "Export"
        case ui = "UI"
    }

    private static func logger(for category: LogCategory) -> OSLog {
        return OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.vrc.roboscore", category: category.rawValue)
    }

    static func debug(_ message: String, category: LogCategory) {
        #if DEBUG
        let log = logger(for: category)
        os_log(.debug, log: log, "%{public}@", message)
        print("🔍 [\(category.rawValue)] \(message)")
        #endif
    }

    static func error(_ message: String, category: LogCategory) {
        #if DEBUG
        let log = logger(for: category)
        os_log(.error, log: log, "❌ Error: %{public}@", message)
        print("❌ [\(category.rawValue)] \(message)")
        #endif
    }
} 