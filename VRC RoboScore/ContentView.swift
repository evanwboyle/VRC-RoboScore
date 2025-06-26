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

// MARK: - Tab Selection
enum Tab {
    case calculator
    case settings
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var gameState = GameState()
    @StateObject private var appSettings = AppSettingsManager.shared
    @State private var selectedTab: Tab = .calculator
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CalculatorView(gameState: gameState)
                .tabItem {
                    Label("Calculator", systemImage: "plus.forwardslash.minus")
                }
                .tag(Tab.calculator)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        .accentColor(ThemeColors.red)
        .animation(.none, value: selectedTab)
        .preferredColorScheme(appSettings.getCurrentColorScheme())
        .background(appSettings.getCurrentBackgroundColor())
        .ignoresSafeArea(.all, edges: .all)
    }
}

// MARK: - Calculator View
struct CalculatorView: View {
    @ObservedObject var gameState: GameState
    @StateObject private var appSettings = AppSettingsManager.shared
    @State private var showingCamera = false
    @State private var showingShareSheet = false
    @State private var scoreToShare = ""
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var importSuccessful = false
    
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
                appSettings.getCurrentBackgroundColor()
                    .ignoresSafeArea()
                
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            if geometry.size.width > geometry.size.height {
                                LandscapeCalculatorContent(gameState: gameState)
                            } else {
                                PortraitCalculatorContent(gameState: gameState)
                            }
                            
                            // Debug information
                            if appSettings.debugMode {
                                DebugView(gameState: gameState)
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
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView()
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: {
                Logger.debug("Share sheet dismissed")
                scoreToShare = ""
            }) {
                ShareSheet(shareText: $scoreToShare)
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

// MARK: - Debug View
struct DebugView: View {
    @ObservedObject var gameState: GameState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG MODE")
                .font(.headline)
                .foregroundColor(.orange)
            
            Text("Red Score Breakdown:")
                .font(.subheadline)
                .foregroundColor(.red)
            Text("  Top Goals: \(calculateTopGoalScore(for: .red, gameState: gameState))")
            Text("  Bottom Goals: \(calculateBottomGoalScore(for: .red, gameState: gameState))")
            let redParkedCount = gameState.parkedRobots[.red] ?? 0
            let redParkedScore = redParkedCount == 1 ? 8 : (redParkedCount == 2 ? 30 : 0)
            Text("  Parked Robots: \(redParkedScore)")
            let redAutoScore = gameState.autoWinner == .red ? 10 : (gameState.autoWinner == .tie ? 5 : 0)
            Text("  Auto Winner: \(redAutoScore)")
            
            Text("Blue Score Breakdown:")
                .font(.subheadline)
                .foregroundColor(.blue)
            Text("  Top Goals: \(calculateTopGoalScore(for: .blue, gameState: gameState))")
            Text("  Bottom Goals: \(calculateBottomGoalScore(for: .blue, gameState: gameState))")
            let blueParkedCount = gameState.parkedRobots[.blue] ?? 0
            let blueParkedScore = blueParkedCount == 1 ? 8 : (blueParkedCount == 2 ? 30 : 0)
            Text("  Parked Robots: \(blueParkedScore)")
            let blueAutoScore = gameState.autoWinner == .blue ? 10 : (gameState.autoWinner == .tie ? 5 : 0)
            Text("  Auto Winner: \(blueAutoScore)")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
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

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("gameMode") private var gameMode = "Simple"
    @AppStorage("matchType") private var matchType = "Non-Worlds"
    @AppStorage("phaseType") private var phaseType = "Full Match"
    @StateObject private var appSettings = AppSettingsManager.shared
    @State private var showingColorPicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Game Settings")) {
                    Picker("Game Mode", selection: $gameMode) {
                        Text("Simple").tag("Simple")
                        Text("Advanced").tag("Advanced")
                    }
                    
                    Picker("Match Type", selection: $matchType) {
                        Text("Worlds").tag("Worlds")
                        Text("Non-Worlds").tag("Non-Worlds")
                    }
                    
                    Picker("Phase Type", selection: $phaseType) {
                        Text("Autonomous").tag("Autonomous")
                        Text("Full Match").tag("Full Match")
                    }
                }
                
                Section(header: Text("App Settings")) {
                    Toggle("Debug Mode", isOn: $appSettings.debugMode)
                    
                    Picker("Visual Mode", selection: $appSettings.visualMode) {
                        ForEach(VisualMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    
                    if appSettings.visualMode == .custom {
                        HStack {
                            Text("Custom Background")
                            Spacer()
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appSettings.customBackgroundColor)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary, lineWidth: 1)
                                )
                                .onTapGesture {
                                    showingColorPicker = true
                                }
                        }
                    }
                }
            }
            .background(appSettings.getCurrentBackgroundColor())
            .navigationTitle("Settings")
            .sheet(isPresented: $showingColorPicker) {
                ColorPickerView(selectedColor: $appSettings.customBackgroundColor)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
