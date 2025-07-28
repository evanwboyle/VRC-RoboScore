import UIKit

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
