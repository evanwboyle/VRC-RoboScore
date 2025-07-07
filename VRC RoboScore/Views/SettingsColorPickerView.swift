import SwiftUI

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss
    
    private let predefinedColors: [Color] = [
        .white, .black, .gray, .red, .orange, .yellow, 
        .green, .blue, .purple, .pink, .brown, .mint,
        .indigo, .teal, .cyan
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Current color preview
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedColor)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary, lineWidth: 2)
                    )
                    .padding(.horizontal)
                
                // Predefined colors grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 15) {
                    ForEach(predefinedColors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == color ? Color.blue : Color.clear, lineWidth: 3)
                            )
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
                .padding(.horizontal)
                
                // System color picker
                ColorPicker("Custom Color", selection: $selectedColor)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Choose Background Color")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Done") {
                    dismiss()
                }
            )
        }
    }
}

#Preview {
    ColorPickerView(selectedColor: .constant(.blue))
} 