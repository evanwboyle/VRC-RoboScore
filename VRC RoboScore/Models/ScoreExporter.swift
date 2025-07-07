import Foundation
import SwiftUI

struct ScoreSharer {
    static func generateScoreText(gameState: GameState) -> String {
        // Calculate scores for each alliance
        let redScore = calculateTotalScore(for: .red, gameState: gameState)
        let blueScore = calculateTotalScore(for: .blue, gameState: gameState)
        
        // Generate goal control indicators
        let longGoal1Control = getControlIndicator(redGoal: gameState.topGoals[0].redGoal, blueGoal: gameState.topGoals[0].blueGoal)
        let longGoal2Control = getControlIndicator(redGoal: gameState.topGoals[1].redGoal, blueGoal: gameState.topGoals[1].blueGoal)
        let shortGoal1Control = getControlIndicator(redGoal: gameState.bottomGoals[0].redGoal, blueGoal: gameState.bottomGoals[0].blueGoal)
        let shortGoal2Control = getControlIndicator(redGoal: gameState.bottomGoals[1].redGoal, blueGoal: gameState.bottomGoals[1].blueGoal)
        
        // Get autonomous indicator
        let autoIndicator = getAutonomousIndicator(winner: gameState.autoWinner)
        
        // Format each line with exact spacing
        let lines = [
            // Title: 1 space before
            " RoboScore",
            
            // Score: no spaces
            "🔴\(String(format: "%d", redScore))-\(String(format: "%d", blueScore))🔵",
            
            // Long goals: 1 space before, 1 space between numbers and squares
            " \(String(format: "%d", getGoalScore(gameState.topGoals[0]))) \(longGoal1Control) \(String(format: "%d", getGoalScore(gameState.topGoals[0], isBlue: true)))",
            " \(String(format: "%d", getGoalScore(gameState.topGoals[1]))) \(longGoal2Control) \(String(format: "%d", getGoalScore(gameState.topGoals[1], isBlue: true)))",
            
            // Short goals: 3 spaces before, 1 space between numbers and squares
            "   \(String(format: "%d", getGoalScore(gameState.bottomGoals[0]))) \(shortGoal1Control) \(String(format: "%d", getGoalScore(gameState.bottomGoals[0], isBlue: true)))",
            "   \(String(format: "%d", getGoalScore(gameState.bottomGoals[1]))) \(shortGoal2Control) \(String(format: "%d", getGoalScore(gameState.bottomGoals[1], isBlue: true)))",
            
            // Park zone: no spaces
            "\(gameState.parkedRobots[.red] ?? 0)🔺P🔹\(gameState.parkedRobots[.blue] ?? 0)",
            
            // Auton: 6 spaces before
            "      \(autoIndicator)"
        ]
        
        return lines.joined(separator: "\n")
    }
    
    private static func calculateTotalScore(for alliance: Alliance, gameState: GameState) -> Int {
        var score = 0
        
        // Add scores from top goals
        for pair in gameState.topGoals {
            let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
            score += (goal.blocks[alliance] ?? 0) * 3
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
    
    private static func getControlIndicator(redGoal: Goal, blueGoal: Goal) -> String {
        let isLongGoal = redGoal.type == .longGoal
        let controlSymbol = isLongGoal ? "⬜️⬜️" : "⬜️"
        let redControlSymbol = isLongGoal ? "🟥🟥" : "🟥"
        let blueControlSymbol = isLongGoal ? "🟦🟦" : "🟦"
        
        if isLongGoal {
            // For long goals, check centerControl
            if redGoal.centerControl == .red || blueGoal.centerControl == .red {
                return redControlSymbol
            } else if redGoal.centerControl == .blue || blueGoal.centerControl == .blue {
                return blueControlSymbol
            }
        } else {
            // For middle goals, check controlPoint
            if redGoal.controlPoint.controlledBy == .red || blueGoal.controlPoint.controlledBy == .red {
                return redControlSymbol
            } else if redGoal.controlPoint.controlledBy == .blue || blueGoal.controlPoint.controlledBy == .blue {
                return blueControlSymbol
            }
        }
        return controlSymbol
    }
    
    private static func getGoalScore(_ goalPair: GoalPair, isBlue: Bool = false) -> Int {
        let goal = isBlue ? goalPair.blueGoal : goalPair.redGoal
        let alliance: Alliance = isBlue ? .blue : .red
        return goal.blocks[alliance] ?? 0
    }
    
    private static func getAutonomousIndicator(winner: Alliance?) -> String {
        switch winner {
        case .red:
            return "A🔴"
        case .blue:
            return "A🔵"
        case .tie:
            return "A🟡"
        case .none:
            return "A⚪️"
        }
    }
} 