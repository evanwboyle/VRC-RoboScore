import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    @Binding var shareText: String
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        Logger.debug("Creating ShareSheet with text length: \(shareText.count)")
        
        // Only create controller if we have valid text
        guard !shareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.error("No valid text to share")
            DispatchQueue.main.async {
                self.presentationMode.wrappedValue.dismiss()
            }
            return UIActivityViewController(activityItems: [], applicationActivities: nil)
        }
        
        let controller = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        // Handle iPad presentation
        if let popoverController = controller.popoverPresentationController {
            Logger.debug("Configuring for iPad presentation")
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popoverController.sourceView = window
                popoverController.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
        }
        
        // Add completion handler
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            if let error = error {
                Logger.error("Share sheet error: \(error.localizedDescription)")
            }
            if completed {
                Logger.debug("Share completed with activity type: \(activityType?.rawValue ?? "none")")
            } else {
                Logger.debug("Share cancelled")
            }
            DispatchQueue.main.async {
                self.presentationMode.wrappedValue.dismiss()
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 