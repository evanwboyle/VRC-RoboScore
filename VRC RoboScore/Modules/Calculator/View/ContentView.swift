//
//  ContentView.swift
//  VRC RoboScore
//
//  Created by Evan Boyle on 5/15/25.
//

import SwiftUI

// MARK: - Theme Colors
struct ThemeColors {
    static let red = Color("AllianceRed", bundle: nil)
    static let blue = Color("AllianceBlue", bundle: nil)
    static let background = Color("Background", bundle: nil)
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var gameState = GameState()
    
    var body: some View {
        CalculatorView(gameState: gameState)
    }
}

// MARK: - Calculator View
struct CalculatorView: View {
    @ObservedObject var gameState: GameState
    @State private var showingCamera = false
    @State private var showingMultiGoalCamera = false
    @State private var showingFieldCamera = false
    @State private var showingShareSheet = false
    @State private var scoreToShare = ""
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var importSuccessful = false
    @State private var notificationObserver: NSObjectProtocol?
    
    // Alert state management
    enum AlertType: Identifiable {
        case resetConfirmation
        case importError(String)
        
        var id: Int {
            switch self {
            case .resetConfirmation:
                return 0
            case .importError:
                return 1
            }
        }
    }
    @State private var activeAlert: AlertType?
    
    var body: some View {
        NavigationView {
            ZStack {
                ThemeColors.background
                    .ignoresSafeArea()
                
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            if geometry.size.width > geometry.size.height {
                                LandscapeCalculatorContent(gameState: gameState)
                            } else {
                                PortraitCalculatorContent(gameState: gameState)
                            }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("VRC RoboScore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: HStack {
                    Button(action: {
                        activeAlert = .resetConfirmation
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    Button(action: {
                        handleImport()
                    }) {
                        if importSuccessful {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    Button(action: {
                        let generatedScore = ScoreSharer.generateScoreText(gameState: gameState)
                        Logger.debug("Generated score text: \(generatedScore)")
                        scoreToShare = generatedScore
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                },
                trailing: HStack {
                    Button(action: {
                        showingFieldCamera = true
                    }) {
                        Image(systemName: "viewfinder.circle")
                            .accessibilityLabel("Field Camera")
                    }
                    Button(action: {
                        showingMultiGoalCamera = true
                    }) {
                        ZStack {
                            Image(systemName: "camera.circle")
                            Text("4")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .offset(x: 10, y: 10)
                        }
                        .accessibilityLabel("Multi-Goal Camera")
                    }
                    Button(action: {
                        showingCamera = true
                    }) {
                        Image(systemName: "camera")
                    }
                }
            )
            .alert(item: $activeAlert) { alertType in
                switch alertType {
                case .resetConfirmation:
                    return Alert(
                        title: Text("Reset Score?"),
                        message: Text("This will reset all scores to 0. This cannot be undone."),
                        primaryButton: .destructive(Text("Reset")) {
                            gameState.reset()
                        },
                        secondaryButton: .cancel()
                    )
                case .importError(let message):
                    return Alert(
                        title: Text("Import Failed"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .fullScreenCover(isPresented: $showingFieldCamera) {
                FieldCameraView()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView()
            }
            .fullScreenCover(isPresented: $showingMultiGoalCamera) {
                MultiGoalCameraView()
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: {
                Logger.debug("Share sheet dismissed")
                scoreToShare = ""
            }) {
                ShareSheet(shareText: $scoreToShare)
            }
        }
        .onAppear {
            notificationObserver = NotificationCenter.default.addObserver(forName: Notification.Name("NavigateToCalculatorHome"), object: nil, queue: .main) { _ in
                showingCamera = false
                showingMultiGoalCamera = false
                showingFieldCamera = false
                showingShareSheet = false
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("DetectedGoalScores"), object: nil, queue: .main) { notification in
                guard let userInfo = notification.userInfo,
                      let detected = userInfo["scores"] as? DetectedGoalScores else { return }
                // Top Long Goal (Red goal)
                let topLong = gameState.topGoals[0]
                let bottomLong = gameState.topGoals[1]
                let topShort = gameState.bottomGoals[0]
                let bottomShort = gameState.bottomGoals[1]

                // Update blocks (max 15 for long, 7 for short)
                let clamp15 = { (v: Int) in max(0, min(15, v)) }
                let clamp7 = { (v: Int) in max(0, min(7, v)) }

                topLong.redGoal.blocks = [.red: clamp15(detected.topLongRed), .blue: clamp15(detected.topLongBlue)]
                topLong.blueGoal.blocks = [.red: clamp15(detected.topLongRed), .blue: clamp15(detected.topLongBlue)]
                // Control for long goal
                if detected.topLongControlDiff > 0 {
                    topLong.redGoal.centerControl = .blue
                    topLong.blueGoal.centerControl = .blue
                } else if detected.topLongControlDiff < 0 {
                    topLong.redGoal.centerControl = .red
                    topLong.blueGoal.centerControl = .red
                } else {
                    topLong.redGoal.centerControl = nil
                    topLong.blueGoal.centerControl = nil
                }

                bottomLong.redGoal.blocks = [.red: clamp15(detected.bottomLongRed), .blue: clamp15(detected.bottomLongBlue)]
                bottomLong.blueGoal.blocks = [.red: clamp15(detected.bottomLongRed), .blue: clamp15(detected.bottomLongBlue)]
                if detected.bottomLongControlDiff > 0 {
                    bottomLong.redGoal.centerControl = .blue
                    bottomLong.blueGoal.centerControl = .blue
                } else if detected.bottomLongControlDiff < 0 {
                    bottomLong.redGoal.centerControl = .red
                    bottomLong.blueGoal.centerControl = .red
                } else {
                    bottomLong.redGoal.centerControl = nil
                    bottomLong.blueGoal.centerControl = nil
                }

                // Short goals (orange -> top short, blue -> bottom short)
                topShort.redGoal.blocks = [.red: clamp7(detected.orangeShortRed), .blue: clamp7(detected.orangeShortBlue)]
                topShort.blueGoal.blocks = [.red: clamp7(detected.orangeShortRed), .blue: clamp7(detected.orangeShortBlue)]
                bottomShort.redGoal.blocks = [.red: clamp7(detected.blueShortRed), .blue: clamp7(detected.blueShortBlue)]
                bottomShort.blueGoal.blocks = [.red: clamp7(detected.blueShortRed), .blue: clamp7(detected.blueShortBlue)]
            }
        }
        .onDisappear {
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    
    private func handleImport() {
        let result = ScoreImporter.importFromClipboard(into: gameState)
        switch result {
        case .success:
            Logger.debug("Import succeeded")
            importSuccessful = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                importSuccessful = false
            }
        case .failure(let error):
            Logger.error("Import failed: \(error.localizedDescription)")
            activeAlert = .importError(error.localizedDescription)
        }
    }
}

// MARK: - Landscape Calculator Content
struct LandscapeCalculatorContent: View {
    @ObservedObject var gameState: GameState
    
    var body: some View {
        VStack(spacing: 0) {
            // Top row with scores and park zones
            HStack(alignment: .top, spacing: 20) {
                // Scores on the left
                HStack(spacing: 30) {
                    Text("\(calculateScore(for: .red, gameState: gameState))")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(ThemeColors.red)
                        .frame(minWidth: 120, alignment: .trailing)
                    
                    AutonButton(gameState: gameState)
                    
                    Text("\(calculateScore(for: .blue, gameState: gameState))")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(ThemeColors.blue)
                        .frame(minWidth: 120, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                
                // Park zones on the right
                HStack(spacing: 20) {
                    VStack {
                        ParkZoneView(alliance: .red, count: Binding(
                            get: { gameState.parkedRobots[.red] ?? 0 },
                            set: { gameState.parkedRobots[.red] = $0 }
                        ))
                    }
                    VStack {
                        ParkZoneView(alliance: .blue, count: Binding(
                            get: { gameState.parkedRobots[.blue] ?? 0 },
                            set: { gameState.parkedRobots[.blue] = $0 }
                        ))
                    }
                }
                .padding(.trailing)
                .padding(.bottom, 10)
                .padding(.trailing, 45)
            }
            
            // Goals layout
            HStack(alignment: .top, spacing: 20) {
                // Left column - Long goals
                VStack(spacing: 8) {
                    ForEach(0..<2) { index in
                        CombinedGoalPipeView(redGoal: gameState.topGoals[index].redGoal, blueGoal: gameState.topGoals[index].blueGoal)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right column - Middle goals
                VStack(spacing: 8) {
                    ForEach(0..<2) { index in
                        CombinedGoalPipeView(redGoal: gameState.bottomGoals[index].redGoal, blueGoal: gameState.bottomGoals[index].blueGoal)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Portrait Calculator Content
struct PortraitCalculatorContent: View {
    @ObservedObject var gameState: GameState
    
    var body: some View {
        VStack(spacing: 12) {
            // Score Header
            HStack(spacing: 30) {
                Text("\(calculateScore(for: .red, gameState: gameState))")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(ThemeColors.red)
                    .frame(minWidth: 120, alignment: .trailing)
                
                AutonButton(gameState: gameState)
                
                Text("\(calculateScore(for: .blue, gameState: gameState))")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(ThemeColors.blue)
                    .frame(minWidth: 120, alignment: .leading)
            }
            .padding(.top)
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Top Goals
            VStack(spacing: 8) {
                ForEach(0..<2) { index in
                    CombinedGoalPipeView(redGoal: gameState.topGoals[index].redGoal, blueGoal: gameState.topGoals[index].blueGoal)
                }
            }
            .padding(.horizontal)
            
            // Bottom Goals
            VStack(spacing: 8) {
                ForEach(0..<2) { index in
                    CombinedGoalPipeView(redGoal: gameState.bottomGoals[index].redGoal, blueGoal: gameState.bottomGoals[index].blueGoal)
                }
            }
            .padding(.horizontal)
            
            // Park Zones
            HStack(spacing: 20) {
                VStack {
                    ParkZoneView(alliance: .red, count: Binding(
                        get: { gameState.parkedRobots[.red] ?? 0 },
                        set: { gameState.parkedRobots[.red] = $0 }
                    ))
                }
                VStack {
                    ParkZoneView(alliance: .blue, count: Binding(
                        get: { gameState.parkedRobots[.blue] ?? 0 },
                        set: { gameState.parkedRobots[.blue] = $0 }
                    ))
                }
            }
            .padding(.horizontal, 20)
        }
    }
}



// MARK: - Score Calculation Functions
func calculateScore(for alliance: Alliance, gameState: GameState) -> Int {
    var score = 0
    
    // Add scores from top goals
    for pair in gameState.topGoals {
        let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
        score += (goal.blocks[alliance] ?? 0) * 3
        // Check both goals' center control for this alliance
        if pair.redGoal.centerControl == alliance || pair.blueGoal.centerControl == alliance {
            score += 10
        }
    }
    
    // Add scores from bottom goals
    for pair in gameState.bottomGoals {
        let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
        score += (goal.blocks[alliance] ?? 0) * 3
        if goal.controlPoint.controlledBy == alliance {
            score += 8
        }
    }
    
    // Add parked robot scores
    let parkedCount = gameState.parkedRobots[alliance] ?? 0
    if parkedCount == 1 {
        score += 8
    } else if parkedCount == 2 {
        score += 30
    }
    
    // Add autonomous winner bonus
    if gameState.autoWinner == alliance {
        score += 10
    } else if gameState.autoWinner == .tie {
        score += 5
    }
    
    return score
}

func calculateTopGoalScore(for alliance: Alliance, gameState: GameState) -> Int {
    var score = 0
    
    // Add scores from top goals
    for pair in gameState.topGoals {
        let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
        score += (goal.blocks[alliance] ?? 0) * 3
        // Check both goals' center control for this alliance
        if pair.redGoal.centerControl == alliance || pair.blueGoal.centerControl == alliance {
            score += 10
        }
    }
    
    return score
}

func calculateBottomGoalScore(for alliance: Alliance, gameState: GameState) -> Int {
    var score = 0
    
    // Add scores from bottom goals
    for pair in gameState.bottomGoals {
        let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
        score += (goal.blocks[alliance] ?? 0) * 3
        if goal.controlPoint.controlledBy == alliance {
            score += 8
        }
    }
    
    return score
}

// MARK: - Auton Button
struct AutonButton: View {
    @ObservedObject var gameState: GameState
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var showingIndicators = false
    @State private var wasLastActionDrag = false
    @State private var currentSelection: Alliance? = nil
    
    // For haptic feedback
    let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    let selectionGenerator = UISelectionFeedbackGenerator()
    
    private let vexOrange = Color(red: 0xE0/255.0, green: 0x84/255.0, blue: 0x2C/255.0)
    
    private func calculateAngle(from offset: CGSize) -> Double {
        let angle = atan2(offset.height, offset.width) * (180 / .pi)
        // Convert to 0-360 range where 0 is up
        return (450 - angle).truncatingRemainder(dividingBy: 360)
    }
    
    private func calculateSelection(from offset: CGSize) -> Alliance? {
        // Ignore very small movements
        let magnitude = sqrt(pow(offset.width, 2) + pow(offset.height, 2))
        if magnitude < 10 { return nil }
        
        let angle = calculateAngle(from: offset)
        
        // Define zones based on angles (0 is up)
        switch angle {
        case 337.5...360, 0..<22.5:  // Up: None
            return nil
        case 22.5..<157.5:           // Right: Blue
            return .blue
        case 157.5..<202.5:          // Down: Tie
            return .tie
        case 202.5..<337.5:          // Left: Red
            return .red
        default:
            return nil
        }
    }
    
    private func cycleAutoWinner() {
        if wasLastActionDrag {
            gameState.autoWinner = nil
            wasLastActionDrag = false
        } else {
            switch gameState.autoWinner {
            case nil: gameState.autoWinner = .red
            case .red: gameState.autoWinner = .blue
            case .blue: gameState.autoWinner = .tie
            case .tie: gameState.autoWinner = nil
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Directional indicators
                if showingIndicators || isDragging {
                    // Red indicator (left)
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [ThemeColors.red.opacity(0.7), .clear]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 40, height: 4)
                        .offset(x: -55, y: 0)
                        .opacity(currentSelection == .red ? 1.0 : 0.3)
                    
                    // Blue indicator (right)
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.clear, ThemeColors.blue.opacity(0.7)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 40, height: 4)
                        .offset(x: 55, y: 0)
                        .opacity(currentSelection == .blue ? 1.0 : 0.3)
                    
                    // Tie indicator (up)
                    VStack(spacing: 4) {
                        Text("TIE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(vexOrange.opacity(0.8))
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.clear, vexOrange.opacity(0.7)]),
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .frame(width: 4, height: 30)
                    }
                    .offset(y: -50)
                    .opacity(currentSelection == .tie ? 1.0 : 0.3)
                    
                    // None indicator (down)
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.clear, Color.primary.opacity(0.7)]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 4, height: 30)
                        Text("NONE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.primary.opacity(0.8))
                    }
                    .offset(y: 50)
                    .opacity(currentSelection == nil && isDragging ? 1.0 : 0.3)
                }
                
                // Main button
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(gameState.autoWinner?.color ?? Color.primary, lineWidth: isDragging ? 3 : 2)
                        .frame(width: 70, height: 70)
                    Text("A")
                        .foregroundColor(gameState.autoWinner?.color ?? Color.primary)
                        .font(.system(size: 36, weight: .bold))
                }
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .onTapGesture {
                    cycleAutoWinner()
                    // Show indicators briefly
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingIndicators = true
                    }
                    // Hide indicators after shorter delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingIndicators = false
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                impactGenerator.prepare()
                                selectionGenerator.prepare()
                            }
                            
                            dragOffset = gesture.translation
                            let newSelection = calculateSelection(from: dragOffset)
                            
                            if newSelection != currentSelection {
                                currentSelection = newSelection
                                selectionGenerator.selectionChanged()
                                impactGenerator.impactOccurred()
                            }
                        }
                        .onEnded { _ in
                            gameState.autoWinner = currentSelection
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isDragging = false
                                dragOffset = .zero
                                wasLastActionDrag = true
                                currentSelection = nil
                            }
                        }
                )
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: gameState.autoWinner)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(width: 70, height: 70)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
