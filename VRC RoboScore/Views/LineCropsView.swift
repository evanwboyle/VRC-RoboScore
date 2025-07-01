import SwiftUI
import UIKit
import Photos
import OSLog

struct LineCrop {
    let image: UIImage
    let color: Color
    let label: String
}

struct LineCropsView: View {
    @Environment(\.presentationMode) private var presentationMode
    let originalImage: UIImage
    let lineEndpoints: [[CGPoint]] // relative 0-1 positions matching originalImage orientation (landscape)

    // MARK: - State
    @State private var processedCrops: [LineCrop] = []
    @State private var isProcessing: Bool = true
    @State private var showShareSheet: Bool = false

    // MARK: - Constants
    private let padding: CGFloat = 50.0
    private let colors: [Color] = [.red, .green, .blue, .orange]
    private let labels: [String] = ["Red Line", "Green Line", "Blue Line", "Orange Line"]

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if isProcessing {
                ProgressView("Processing…")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            } else {
                VStack {
                    ScrollView {
                        VStack(spacing: 24) {
                            ForEach(0..<processedCrops.count, id: \.self) { idx in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(processedCrops[idx].label)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.leading, 8)
                                    Image(uiImage: processedCrops[idx].image)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(processedCrops[idx].color, lineWidth: 4)
                                        )
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)

                    // Control buttons
                    HStack(spacing: 24) {
                        Button(action: undo) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(ControlButtonStyle(color: .orange))

                        Button(action: saveAll) {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(ControlButtonStyle(color: .green))

                        Button(action: { showShareSheet = true }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ControlButtonStyle(color: .blue))
                    }
                    .padding(.bottom, 20)
                }
                .sheet(isPresented: $showShareSheet) {
                    ImageShareSheet(images: processedCrops.map { $0.image })
                }
            }
        }
        .onAppear {
            Task {
                await processImages()
            }
        }
    }

    // MARK: - Actions

    private func undo() {
        Logger.debug("Undo pressed – dismissing LineCropsView", category: .navigation)
        presentationMode.wrappedValue.dismiss()
    }

    private func saveAll() {
        Logger.debug("Saving all cropped images to photo library", category: .export)
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                Logger.error("Photo library access not authorised", category: .export)
                return
            }
            for crop in processedCrops {
                UIImageWriteToSavedPhotosAlbum(crop.image, nil, nil, nil)
            }
        }
    }

    // MARK: - Image Processing

    private func processImages() async {
        Logger.debug("Starting image processing for cropped lines", category: .imageProcessing)
        let uiImage = originalImage
        let imageSize = uiImage.size
        var tempCrops: [LineCrop] = []

        for i in 0..<min(4, lineEndpoints.count) {
            let rel = lineEndpoints[i]
            guard rel.count == 2 else { continue }
            let p0 = CGPoint(x: rel[0].x * imageSize.width, y: rel[0].y * imageSize.height)
            let p1 = CGPoint(x: rel[1].x * imageSize.width, y: rel[1].y * imageSize.height)

            // Crop rectangle
            let minX = max(min(p0.x, p1.x) - padding, 0)
            let maxX = min(max(p0.x, p1.x) + padding, imageSize.width)
            let minY = max(min(p0.y, p1.y) - padding, 0)
            let maxY = min(max(p0.y, p1.y) + padding, imageSize.height)
            let cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            Logger.debug("Crop rect for line \(i): \(cropRect)", category: .imageProcessing)

            guard let cgImage = uiImage.cgImage?.cropping(to: cropRect) else {
                Logger.error("Failed to crop CGImage for line \(i)", category: .imageProcessing)
                continue
            }
            var croppedImage = UIImage(cgImage: cgImage, scale: uiImage.scale, orientation: uiImage.imageOrientation)

            // Deskew (rotate to horizontal)
            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let degrees = angle * 180 / .pi
            if let rotated = croppedImage.rotated(by: -degrees) {
                croppedImage = rotated
            }
            tempCrops.append(LineCrop(image: croppedImage, color: colors[i], label: labels[i]))
        }

        await MainActor.run {
            self.processedCrops = tempCrops
            self.isProcessing = false
            Logger.debug("Finished image processing", category: .imageProcessing)
        }
    }
}

// MARK: - Control Button Style
struct ControlButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(color.opacity(configuration.isPressed ? 0.6 : 0.9))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

// MARK: - Image Share Sheet
struct ImageShareSheet: UIViewControllerRepresentable {
    let images: [UIImage]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        Logger.debug("Presenting ImageShareSheet with \(images.count) images", category: .export)
        return UIActivityViewController(activityItems: images, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 