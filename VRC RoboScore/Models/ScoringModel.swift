import Foundation
import SwiftUI
import Combine

// MARK: - Alliance
enum Alliance: String {
    case red
    case blue
    case tie
    
    var color: Color {
        switch self {
        case .red: return ThemeColors.red
        case .blue: return ThemeColors.blue
        case .tie: return Color.yellow
        }
    }
}

// MARK: - Goal Type
enum GoalType {
    case longGoal
    case middleGoal
    
    var totalCapacity: Int {
        switch self {
        case .longGoal: return 15
        case .middleGoal: return 7
        }
    }
}

// MARK: - Control Point
struct ControlPoint {
    var controlledBy: Alliance?
    var blocks: [Alliance: Int]
    
    init(controlledBy: Alliance? = nil, blocks: [Alliance: Int] = [:]) {
        self.controlledBy = controlledBy
        self.blocks = blocks
    }
}

// MARK: - Shared Goal State
class SharedGoalState: ObservableObject {
    @Published var blocks: [Alliance: Int] = [:] {
        didSet {
            updateControl()
        }
    }
    @Published var controlPoint: ControlPoint
    
    init() {
        self.controlPoint = ControlPoint(controlledBy: nil, blocks: [:])
    }
    
    func updateControl() {
        let redBlocks = blocks[.red] ?? 0
        let blueBlocks = blocks[.blue] ?? 0
        
        if redBlocks > blueBlocks {
            controlPoint.controlledBy = .red
        } else if blueBlocks > redBlocks {
            controlPoint.controlledBy = .blue
        } else {
            controlPoint.controlledBy = nil
        }
        
        // Update the control point's blocks to match
        controlPoint.blocks = blocks
    }
}

// MARK: - Goal
class Goal: ObservableObject {
    let type: GoalType
    @Published var controlPoint: ControlPoint {
        willSet {
            // Notify parent GameState of upcoming change
            parent?.objectWillChange.send()
        }
        didSet {
            // Only update shared control point for middle goals
            if type == .middleGoal {
                sharedState?.controlPoint = controlPoint
            }
        }
    }
    @Published var blocks: [Alliance: Int] {
        willSet {
            // Notify parent GameState of upcoming change
            parent?.objectWillChange.send()
        }
        didSet {
            // Always update shared state for both goal types
            sharedState?.blocks = blocks
            
            // Only update control point automatically for middle goals
            if type == .middleGoal {
                updateControl()
            }
        }
    }
    @Published var centerControl: Alliance? {
        willSet {
            // Notify parent GameState of upcoming change
            parent?.objectWillChange.send()
        }
    }
    
    // Weak reference to parent GameState to avoid retain cycle
    private weak var parent: GameState?
    private let sharedState: SharedGoalState?
    private var sharedStateCancellable: AnyCancellable?
    
    var remainingCapacity: Int {
        let totalUsed = (sharedState?.blocks[.red] ?? 0) + (sharedState?.blocks[.blue] ?? 0)
        return type.totalCapacity - totalUsed
    }
    
    var isAtMaxCapacity: Bool {
        remainingCapacity <= 0
    }
    
    init(type: GoalType, parent: GameState? = nil, sharedState: SharedGoalState? = nil) {
        self.type = type
        self.sharedState = sharedState
        // Only use shared control point for middle goals
        self.controlPoint = type == .middleGoal ? (sharedState?.controlPoint ?? ControlPoint()) : ControlPoint()
        self.blocks = sharedState?.blocks ?? [:]
        self.centerControl = nil
        self.parent = parent
        
        if let sharedState = sharedState {
            // Observe shared state changes
            sharedStateCancellable = sharedState.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    // Only update if values are different to prevent loops
                    if self.blocks != sharedState.blocks {
                        self.blocks = sharedState.blocks
                    }
                    // Only update control point from shared state for middle goals
                    if self.type == .middleGoal && self.controlPoint.controlledBy != sharedState.controlPoint.controlledBy {
                        self.controlPoint = sharedState.controlPoint
                    }
                    self.objectWillChange.send()
                }
        }
    }
    
    deinit {
        sharedStateCancellable?.cancel()
    }
    
    private func updateControl() {
        // Only update control for middle goals
        guard type == .middleGoal else { return }
        
        let redBlocks = sharedState?.blocks[.red] ?? 0
        let blueBlocks = sharedState?.blocks[.blue] ?? 0
        
        if redBlocks > blueBlocks {
            sharedState?.controlPoint.controlledBy = .red
        } else if blueBlocks > redBlocks {
            sharedState?.controlPoint.controlledBy = .blue
        } else {
            sharedState?.controlPoint.controlledBy = nil
        }
    }
    
    func canAddBlock(for alliance: Alliance) -> Bool {
        let totalBlocks = (sharedState?.blocks[.red] ?? 0) + (sharedState?.blocks[.blue] ?? 0)
        return !isAtMaxCapacity && totalBlocks < type.totalCapacity
    }
    
    func canRemoveBlock(for alliance: Alliance) -> Bool {
        return (sharedState?.blocks[alliance] ?? 0) > 0
    }
    
    func addBlock(for alliance: Alliance) {
        if canAddBlock(for: alliance) {
            let current = sharedState?.blocks[alliance] ?? 0
            sharedState?.blocks[alliance] = current + 1
            
            // Explicitly notify parent of change
            parent?.objectWillChange.send()
        }
    }
    
    func removeBlock(for alliance: Alliance) {
        if canRemoveBlock(for: alliance) {
            let current = sharedState?.blocks[alliance] ?? 0
            sharedState?.blocks[alliance] = current - 1
            
            // Explicitly notify parent of change
            parent?.objectWillChange.send()
        }
    }
}

// MARK: - Goal Pair
struct GoalPair {
    @ObservedObject var redGoal: Goal
    @ObservedObject var blueGoal: Goal
    private let sharedState: SharedGoalState?
    
    init(type: GoalType, parent: GameState?) {
        // Create shared state for both middle and top goals
        sharedState = SharedGoalState()
        redGoal = Goal(type: type, parent: parent, sharedState: sharedState)
        blueGoal = Goal(type: type, parent: parent, sharedState: sharedState)
    }
}

// MARK: - Game State
class GameState: ObservableObject {
    @Published var topGoals: [GoalPair]
    @Published var bottomGoals: [GoalPair]
    @Published var parkedRobots: [Alliance: Int]
    @Published var autoWinner: Alliance?
    
    init() {
        // Initialize with self reference for state updates
        topGoals = []
        bottomGoals = []
        parkedRobots = [.red: 0, .blue: 0]
        autoWinner = nil
        // Create goal pairs with parent reference
        topGoals = [GoalPair(type: .longGoal, parent: self), GoalPair(type: .longGoal, parent: self)]
        bottomGoals = [GoalPair(type: .middleGoal, parent: self), GoalPair(type: .middleGoal, parent: self)]
    }
    
    func reset() {
        // Create new goal pairs with parent reference
        topGoals = [GoalPair(type: .longGoal, parent: self), GoalPair(type: .longGoal, parent: self)]
        bottomGoals = [GoalPair(type: .middleGoal, parent: self), GoalPair(type: .middleGoal, parent: self)]
        parkedRobots = [.red: 0, .blue: 0]
        autoWinner = nil
        objectWillChange.send()
    }
    
    func parkRobot(alliance: Alliance) {
        let current = parkedRobots[alliance] ?? 0
        if current < 2 {
            parkedRobots[alliance] = current + 1
            objectWillChange.send()
        }
    }
    
    func unparkRobot(alliance: Alliance) {
        let current = parkedRobots[alliance] ?? 0
        if current > 0 {
            parkedRobots[alliance] = current - 1
            objectWillChange.send()
        }
    }
} 