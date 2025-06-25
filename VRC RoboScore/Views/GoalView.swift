import SwiftUI

struct GoalView: View {
    @ObservedObject var goal: Goal
    let alliance: Alliance
    @State private var showingControlPointPicker = false
    var showPipe: Bool = true // New parameter to optionally hide the pipe
    
    private var pipeIsFull: Bool {
        let total = (goal.blocks[.red] ?? 0) + (goal.blocks[.blue] ?? 0)
        return total >= 15
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if alliance == .red {
                // Count to the left, controls to the right
                Text(String(format: "%2d", goal.blocks[alliance] ?? 0))
                    .font(.custom("SF Mono", size: 24))
                    .fontWeight(.bold)
                    .foregroundColor(alliance.color)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 4)
                VStack(spacing: 2) {
                    Button(action: {
                        withAnimation {
                            goal.addBlock(for: .red)
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor((goal.canAddBlock(for: .red) && !pipeIsFull) ? ThemeColors.red : ThemeColors.red.opacity(0.3))
                            .font(.system(size: 36))
                    }
                    .disabled(!goal.canAddBlock(for: .red) || pipeIsFull)
                    Button(action: {
                        withAnimation {
                            goal.removeBlock(for: .red)
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(goal.canRemoveBlock(for: .red) ? ThemeColors.red : ThemeColors.red.opacity(0.3))
                            .font(.system(size: 36))
                    }
                    .disabled(!goal.canRemoveBlock(for: .red))
                }
            }
            
            if showPipe {
                ZStack {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 4)
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 4)
                    }
                    .frame(height: 40)
                    .cornerRadius(8)
                    if goal.type == .longGoal {
                        Rectangle()
                            .fill(goal.controlPoint.controlledBy?.color ?? Color.gray.opacity(0.3))
                            .frame(width: 20, height: 40)
                            .onTapGesture {
                                showingControlPointPicker = true
                            }
                    } else {
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 4)
                        Rectangle()
                            .fill(goal.type == .middleGoal ? (goal.controlPoint.controlledBy?.color ?? Color.gray.opacity(0.2)) : Color.gray.opacity(0.2))
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 4)
                    }
                }
                .frame(width: 160)
            }
            
            if alliance == .blue {
                // Controls to the left, count to the right
                VStack(spacing: 2) {
                    Button(action: {
                        withAnimation {
                            goal.addBlock(for: .blue)
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor((goal.canAddBlock(for: .blue) && !pipeIsFull) ? ThemeColors.blue : ThemeColors.blue.opacity(0.3))
                            .font(.system(size: 36))
                    }
                    .disabled(!goal.canAddBlock(for: .blue) || pipeIsFull)
                    Button(action: {
                        withAnimation {
                            goal.removeBlock(for: .blue)
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(goal.canRemoveBlock(for: .blue) ? ThemeColors.blue : ThemeColors.blue.opacity(0.3))
                            .font(.system(size: 36))
                    }
                    .disabled(!goal.canRemoveBlock(for: .blue))
                }
                Text(String(format: "%2d", goal.blocks[alliance] ?? 0))
                    .font(.custom("SF Mono", size: 24))
                    .fontWeight(.bold)
                    .foregroundColor(alliance.color)
                    .frame(width: 40, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
        .sheet(isPresented: $showingControlPointPicker) {
            if goal.type == .longGoal {
                ControlPointPickerView(goal: goal)
            }
        }
    }
}

struct ControlPointPickerView: View {
    @ObservedObject var goal: Goal
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Button("Red Controls") {
                    goal.controlPoint.controlledBy = .red
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(ThemeColors.red)
                
                Button("Blue Controls") {
                    goal.controlPoint.controlledBy = .blue
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(ThemeColors.blue)
                
                Button("No Control") {
                    goal.controlPoint.controlledBy = nil
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.gray)
            }
            .navigationTitle("Control Point")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - Park Zone Slider
struct ParkZoneSlider: View {
    let alliance: Alliance
    @Binding var value: Int
    let range: ClosedRange<Int> = 0...2
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    
    // For haptic feedback
    let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    let selectionGenerator = UISelectionFeedbackGenerator()
    
    private func normalize(_ value: Int) -> CGFloat {
        return CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 24)
                
                // Filled portion
                RoundedRectangle(cornerRadius: 12)
                    .fill(alliance.color.opacity(0.3))
                    .frame(width: geometry.size.width * normalize(value), height: 24)
                
                // Tick marks
                HStack(spacing: geometry.size.width / 2) {
                    ForEach(range, id: \.self) { tick in
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 2, height: 12)
                    }
                }
                
                // Thumb
                Circle()
                    .fill(alliance.color)
                    .frame(width: 32, height: 32)
                    .shadow(radius: isDragging ? 8 : 4)
                    .offset(x: (geometry.size.width - 32) * normalize(value))
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                    impactGenerator.prepare()
                                    selectionGenerator.prepare()
                                }
                                
                                let totalWidth = geometry.size.width - 32
                                let segmentWidth = totalWidth / CGFloat(range.upperBound - range.lowerBound)
                                let newOffset = gesture.translation.width + dragOffset
                                let normalizedOffset = max(0, min(totalWidth, newOffset))
                                let newValue = Int(round(normalizedOffset / segmentWidth))
                                
                                if newValue != value && newValue >= range.lowerBound && newValue <= range.upperBound {
                                    selectionGenerator.selectionChanged()
                                    impactGenerator.impactOccurred()
                                    value = newValue
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                dragOffset = (geometry.size.width - 32) * normalize(value)
                            }
                    )
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        }
        .frame(height: 32)
    }
}

// MARK: - Park Zone View
struct ParkZoneView: View {
    let alliance: Alliance
    @Binding var count: Int
    let maxCount: Int = 2
    
    // State for interaction
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingGuide = false
    
    // For haptic feedback
    let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    let selectionGenerator = UISelectionFeedbackGenerator()
    
    private func calculateValue(from translation: CGFloat, width: CGFloat) -> Int {
        // Create three zones with the middle zone (1) being larger
        let normalizedTranslation = translation / width
        
        // Adjust these thresholds to make the middle zone larger
        if normalizedTranslation < -0.4 {
            return 0
        } else if normalizedTranslation > 0.4 {
            return 2
        } else {
            return 1
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background zone
                RoundedRectangle(cornerRadius: 8)
                    .stroke(alliance.color, lineWidth: isDragging ? 3 : 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(alliance.color.opacity(Double(count) / Double(maxCount) * 0.3))
                    )
                
                // Count display
                Text("\(count)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(alliance.color)
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                
                // Drag guides
                if showingGuide || isDragging {
                    HStack(spacing: geometry.size.width / 4) {
                        ForEach(0...2, id: \.self) { value in
                            Circle()
                                .fill(alliance.color.opacity(value == count ? 0.4 : 0.2))
                                .frame(width: 12, height: 12)
                                .scaleEffect(value == count ? 1.2 : 1.0)
                        }
                    }
                    .offset(y: geometry.size.height / 2.5)
                }
                
                // Interactive overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                    impactGenerator.prepare()
                                    selectionGenerator.prepare()
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showingGuide = false
                                    }
                                }
                                
                                let newValue = calculateValue(from: gesture.translation.width, width: geometry.size.width)
                                
                                if newValue != count {
                                    selectionGenerator.selectionChanged()
                                    impactGenerator.impactOccurred()
                                    count = newValue
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isDragging = false
                                }
                            }
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingGuide = true
                        }
                        // Hide guide after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingGuide = false
                            }
                        }
                    }
            }
            .frame(width: 100, height: 100)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
        }
        .frame(width: 100, height: 100)
    }
}

// MARK: - Combined Goal Pipe View
struct CombinedGoalPipeView: View {
    @ObservedObject var redGoal: Goal
    @ObservedObject var blueGoal: Goal
    var body: some View {
        let isLong = redGoal.type == .longGoal
        HStack(alignment: .center, spacing: 0) {
            GoalView(goal: redGoal, alliance: .red, showPipe: false)
                .frame(width: 84, height: 84)
                .padding(.trailing, 4)
            ZStack {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 8)
                    if isLong {
                        Button(action: {
                            switch redGoal.centerControl {
                            case nil:
                                redGoal.centerControl = .red
                            case .red:
                                redGoal.centerControl = .blue
                            case .blue:
                                redGoal.centerControl = nil
                            case .tie:
                                redGoal.centerControl = nil
                            }
                        }) {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 47, height: 40)
                                Rectangle()
                                    .fill(redGoal.centerControl?.color ?? Color.gray.opacity(0.2))
                                    .frame(width: 90, height: 40)
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 47, height: 40)
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(redGoal.controlPoint.controlledBy?.color ?? Color.gray.opacity(0.2))
                            .frame(width: 124, height: 40)
                    }
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 8)
                }
                .frame(width: isLong ? 200 : 140, height: 40)
                .cornerRadius(12)
                HStack {
                    Spacer()
                    if redGoal.type == .longGoal {
                        Rectangle()
                            .fill(redGoal.controlPoint.controlledBy?.color ?? Color.gray.opacity(0.3))
                            .frame(width: 20, height: 40)
                    }
                    Spacer()
                    if blueGoal.type == .longGoal {
                        Rectangle()
                            .fill(blueGoal.controlPoint.controlledBy?.color ?? Color.gray.opacity(0.3))
                            .frame(width: 20, height: 40)
                    }
                    Spacer()
                }
            }
            .frame(width: isLong ? 200 : 140, height: 84)
            GoalView(goal: blueGoal, alliance: .blue, showPipe: false)
                .frame(width: 84, height: 84)
                .padding(.leading, 4)
        }
        .frame(width: (isLong ? 368 : 228), height: 84)
        .offset(y: -8)
    }
}

#Preview {
    VStack {
        CombinedGoalPipeView(redGoal: Goal(type: .longGoal), blueGoal: Goal(type: .longGoal))
        CombinedGoalPipeView(redGoal: Goal(type: .middleGoal), blueGoal: Goal(type: .middleGoal))
        ParkZoneView(alliance: .red, count: .constant(1))
    }
    .padding()
} 
