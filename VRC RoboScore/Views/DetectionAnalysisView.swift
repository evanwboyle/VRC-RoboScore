import SwiftUI

/// Simple view showing the results of a `DetectionSession`.
/// Currently displays the original image followed by basic statistics for each pipe.
struct DetectionAnalysisView: View {
    let session: DetectionSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(uiImage: session.originalImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay(alignment: .bottomTrailing) {
                        Text("Original Image")
                            .font(.caption)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .padding(8)
                    }
                ForEach(Array(session.results.enumerated()), id: \.offset) { idx, result in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pipe \(idx + 1) – \(result.pipeType.rawValue.capitalized)")
                            .font(.headline)
                        Text("Detected balls: \(result.balls.count)")
                            .font(.subheadline)
                        if let note = result.obstructionNotes {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationBarTitle("Detection Results", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
            }
        }
    }
}

#if DEBUG
struct DetectionAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyBall = BallDetection(position: CGPoint(x: 100, y: 100), color: .blue, confidence: 0.85)
        let result = DetectionResult(pipeType: .long, balls: [dummyBall], obstructionNotes: nil)
        let session = DetectionSession(originalImage: UIImage(systemName: "photo")!, results: [result, result, result, result])
        NavigationView {
            DetectionAnalysisView(session: session)
        }
    }
}
#endif 