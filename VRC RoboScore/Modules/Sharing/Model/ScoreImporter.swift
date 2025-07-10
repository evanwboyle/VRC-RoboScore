import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Handles importing a RoboScore string from the system clipboard and applying it to an in-memory `GameState`.
/// All heavy lifting – parsing, validation, mapping back to `GameState` – is encapsulated here so the UI only has
/// to deal with a simple `Result`.
struct ScoreImporter {
    // MARK: - Public API
    static func importFromClipboard(into gameState: GameState) -> Result<Void, ImportError> {
        // 1. Fetch clipboard text
        let rawText: String?
        #if os(iOS)
        rawText = UIPasteboard.general.string
        #elseif os(macOS)
        rawText = NSPasteboard.general.string(forType: .string)
        #else
        rawText = nil
        #endif
        guard var text = rawText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.error("Clipboard is empty or contains non-text data")
            return .failure(.clipboardEmpty)
        }

        Logger.debug("Raw clipboard text:\n\(text)")

        // 2. Normalise – remove all spaces but keep newlines
        text = text.replacingOccurrences(of: " ", with: "")
        Logger.debug("Normalised clipboard text:\n\(text)")

        // 3. Basic signature check
        guard text.hasPrefix("RoboScore\n🔴") else {
            Logger.debug("Clipboard does not start with RoboScore signature")
            return .failure(.notRoboScore)
        }

        // 4. Break into lines
        let lines = text.components(separatedBy: "\n")
        guard lines.count == 8 else {
            Logger.error("Expected 8 lines but found \(lines.count)")
            return .failure(.invalidFormat)
        }

        do {
            try mapLines(lines, to: gameState)
        } catch let error as ImportError {
            return .failure(error)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }

        Logger.debug("Import completed successfully")
        return .success(())
    }

    // MARK: - Internal helpers
    private static func mapLines(_ lines: [String], to gameState: GameState) throws {
        // Reset current state so that we start from a known baseline
        gameState.reset()

        // 1. Total score line – store for later comparison
        let scoreRegex = try NSRegularExpression(pattern: "^🔴([0-9]+)-([0-9]+)🔵$")
        guard let scoreMatch = scoreRegex.firstMatch(in: lines[1], range: NSRange(location: 0, length: lines[1].utf16.count)),
              let redScoreRange = Range(scoreMatch.range(at: 1), in: lines[1]),
              let blueScoreRange = Range(scoreMatch.range(at: 2), in: lines[1]) else {
            Logger.error("Failed to parse total score line: \(lines[1])")
            throw ImportError.invalidFormat
        }
        let claimedRedScore = Int(String(lines[1][redScoreRange])) ?? -1
        let claimedBlueScore = Int(String(lines[1][blueScoreRange])) ?? -1
        Logger.debug("Claimed total scores – Red: \(claimedRedScore) Blue: \(claimedBlueScore)")

        // 2 & 3. Goal lines
        // Top long goals – indices 2 & 3
        let longGoal1 = try parseGoalLine(lines[2], type: .longGoal, pairIndex: 0)
        let longGoal2 = try parseGoalLine(lines[3], type: .longGoal, pairIndex: 1)
        let middleGoal1 = try parseGoalLine(lines[4], type: .middleGoal, pairIndex: 0)
        let middleGoal2 = try parseGoalLine(lines[5], type: .middleGoal, pairIndex: 1)

        // Apply parsed goal data
        applyGoal(longGoal1, to: gameState.topGoals[0])
        applyGoal(longGoal2, to: gameState.topGoals[1])
        applyGoal(middleGoal1, to: gameState.bottomGoals[0])
        applyGoal(middleGoal2, to: gameState.bottomGoals[1])

        // 4. Park line
        try parseParkLine(lines[6], into: gameState)

        // 5. Auton line
        try parseAutonLine(lines[7], into: gameState)

        // 6. Validate capacity rules & total score
        try validateGameStateConsistency(gameState: gameState,
                                          claimedRedScore: claimedRedScore,
                                          claimedBlueScore: claimedBlueScore)
    }

    // MARK: - Goal Parsing Helpers
    private struct ParsedGoal {
        let redBlocks: Int
        let blueBlocks: Int
        let control: Alliance?
        let type: GoalType
    }

    private static func parseGoalLine(_ line: String, type: GoalType, pairIndex: Int) throws -> ParsedGoal {
        Logger.debug("Parsing goal line \(pairIndex + 1) (type: \(type)): \(line)")

        // Extract leading red digits
        guard let redPrefixRange = line.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) else {
            throw ImportError.invalidFormat
        }
        let redString = String(line[..<redPrefixRange.lowerBound])
        guard let redBlocks = Int(redString) else {
            throw ImportError.invalidFormat
        }

        // Remaining string starts at first non-digit
        var remainder = String(line[redPrefixRange.lowerBound...])

        // Identify control indicator
        let controlIndicator: String
        let controlAlliance: Alliance?
        if type == .longGoal {
            if remainder.hasPrefix("🟥🟥") { controlIndicator = "🟥🟥"; controlAlliance = .red }
            else if remainder.hasPrefix("🟦🟦") { controlIndicator = "🟦🟦"; controlAlliance = .blue }
            else if remainder.hasPrefix("⬜️⬜️") { controlIndicator = "⬜️⬜️"; controlAlliance = nil }
            else { throw ImportError.invalidFormat }
        } else {
            if remainder.hasPrefix("🟥") { controlIndicator = "🟥"; controlAlliance = .red }
            else if remainder.hasPrefix("🟦") { controlIndicator = "🟦"; controlAlliance = .blue }
            else if remainder.hasPrefix("⬜️") { controlIndicator = "⬜️"; controlAlliance = nil }
            else { throw ImportError.invalidFormat }
        }
        remainder.removeFirst(controlIndicator.count)

        // Now remainder should be blue digits
        guard let blueBlocks = Int(remainder) else {
            throw ImportError.invalidFormat
        }

        Logger.debug("Parsed – redBlocks: \(redBlocks) blueBlocks: \(blueBlocks) control: \(String(describing: controlAlliance))")

        // Validate capacity rule early
        let capacity = type.totalCapacity
        guard redBlocks + blueBlocks <= capacity else {
            throw ImportError.invalidData("Combined blocks (\(redBlocks+blueBlocks)) exceed capacity (\(capacity)) for goal type \(type)")
        }
        guard redBlocks >= 0 && blueBlocks >= 0 else {
            throw ImportError.invalidData("Negative block count detected")
        }

        return ParsedGoal(redBlocks: redBlocks, blueBlocks: blueBlocks, control: controlAlliance, type: type)
    }

    private static func applyGoal(_ parsed: ParsedGoal, to pair: GoalPair) {
        // Update blocks through shared state, but ensure each goal maintains its own count
        pair.redGoal.blocks = [.red: parsed.redBlocks]
        pair.blueGoal.blocks = [.blue: parsed.blueBlocks]
        
        // Force a shared state update through the red goal to sync both
        pair.redGoal.blocks = [
            .red: parsed.redBlocks,
            .blue: parsed.blueBlocks
        ]
        
        // Control mapping
        switch parsed.type {
        case .longGoal:
            pair.redGoal.centerControl = parsed.control
            pair.blueGoal.centerControl = parsed.control
        case .middleGoal:
            pair.redGoal.controlPoint.controlledBy = parsed.control
            pair.blueGoal.controlPoint.controlledBy = parsed.control
        }
    }

    // MARK: - Park line
    private static func parseParkLine(_ line: String, into gameState: GameState) throws {
        Logger.debug("Parsing park line: \(line)")
        // Expected format: "<red>🔺P🔹<blue>"
        guard let redEndRange = line.range(of: "🔺P🔹") else {
            throw ImportError.invalidFormat
        }
        let redString = String(line[..<redEndRange.lowerBound])
        let blueString = String(line[redEndRange.upperBound...])
        guard let redPark = Int(redString), let bluePark = Int(blueString) else {
            throw ImportError.invalidFormat
        }
        guard (0...2).contains(redPark), (0...2).contains(bluePark) else {
            throw ImportError.invalidData("Park counts outside 0–2 range")
        }
        gameState.parkedRobots[.red] = redPark
        gameState.parkedRobots[.blue] = bluePark
    }

    // MARK: - Auton line
    private static func parseAutonLine(_ line: String, into gameState: GameState) throws {
        Logger.debug("Parsing auton line: \(line)")
        guard line.hasPrefix("A") else { throw ImportError.invalidFormat }
        let indicator = String(line.dropFirst())
        switch indicator {
        case "🔴":
            gameState.autoWinner = .red
        case "🔵":
            gameState.autoWinner = .blue
        case "🟡":
            gameState.autoWinner = .tie
        case "⚪️":
            gameState.autoWinner = nil
        default:
            throw ImportError.invalidFormat
        }
    }

    // MARK: - Consistency validation
    private static func validateGameStateConsistency(gameState: GameState,
                                                     claimedRedScore: Int,
                                                     claimedBlueScore: Int) throws {
        let calculatedRed = calculateScore(for: .red, in: gameState)
        let calculatedBlue = calculateScore(for: .blue, in: gameState)
        Logger.debug("Calculated totals – Red: \(calculatedRed) Blue: \(calculatedBlue)")
        guard calculatedRed == claimedRedScore, calculatedBlue == claimedBlueScore else {
            throw ImportError.invalidData("Copied score was 🔴\(claimedRedScore)-\(claimedBlueScore)🔵 but calculated score was 🔴\(calculatedRed)-\(calculatedBlue)🔵. Importing match with correct score.")
        }
    }

    private static func calculateScore(for alliance: Alliance, in gameState: GameState) -> Int {
        var score = 0
        // Top goals
        for pair in gameState.topGoals {
            let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
            score += (goal.blocks[alliance] ?? 0) * 3
            if pair.redGoal.centerControl == alliance || pair.blueGoal.centerControl == alliance {
                score += 10
            }
        }
        // Bottom goals
        for pair in gameState.bottomGoals {
            let goal = (alliance == .red) ? pair.redGoal : pair.blueGoal
            score += (goal.blocks[alliance] ?? 0) * 3
            if goal.controlPoint.controlledBy == alliance {
                score += 8
            }
        }
        // Parked robots
        let parked = gameState.parkedRobots[alliance] ?? 0
        switch parked {
        case 1: score += 8
        case 2: score += 30
        default: break
        }
        // Auton bonus
        if gameState.autoWinner == alliance {
            score += 10
        } else if gameState.autoWinner == .tie {
            score += 5
        }
        return score
    }

    // MARK: - Error type
    enum ImportError: LocalizedError {
        case clipboardEmpty
        case notRoboScore
        case invalidFormat
        case invalidData(String)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .clipboardEmpty:
                return "Clipboard is empty or does not contain text."
            case .notRoboScore:
                return "Clipboard text is not a RoboScore."
            case .invalidFormat:
                return "Error: invalid formatting of score."
            case .invalidData(let msg):
                return "Error: invalid score – \(msg)"
            case .unknown(let msg):
                return msg
            }
        }
    }
} 