import Foundation
import CoreGraphics
// import VRC_RoboScore if needed for PipeType

enum PipeType {
    case long
    case short
}

struct GoalDetectionConfig {
    let minWhiteLineSize: Int
    let ballRadiusRatio: CGFloat
    let exclusionRadiusMultiplier: CGFloat
    let whiteMergeThreshold: Int
    let imageScale: CGFloat
    let ballAreaPercentage: Double
    let maxBallsInCluster: Int
    let clusterSplitThreshold: CGFloat
    let minClusterSeparation: CGFloat
    let whitePixelConversionDistance: Int
    let maxClustersToExpand: Int
    let minClusterSizeToExpand: Int
    let pipeType: PipeType?
    init(
        minWhiteLineSize: Int,
        ballRadiusRatio: CGFloat,
        exclusionRadiusMultiplier: CGFloat,
        whiteMergeThreshold: Int,
        imageScale: CGFloat,
        ballAreaPercentage: Double,
        maxBallsInCluster: Int,
        clusterSplitThreshold: CGFloat,
        minClusterSeparation: CGFloat,
        whitePixelConversionDistance: Int,
        maxClustersToExpand: Int,
        minClusterSizeToExpand: Int,
        pipeType: PipeType?
    ) {
        self.minWhiteLineSize = minWhiteLineSize
        self.ballRadiusRatio = ballRadiusRatio
        self.exclusionRadiusMultiplier = exclusionRadiusMultiplier
        self.whiteMergeThreshold = whiteMergeThreshold
        self.imageScale = imageScale
        self.ballAreaPercentage = ballAreaPercentage
        self.maxBallsInCluster = maxBallsInCluster
        self.clusterSplitThreshold = clusterSplitThreshold
        self.minClusterSeparation = minClusterSeparation
        self.whitePixelConversionDistance = whitePixelConversionDistance
        self.maxClustersToExpand = maxClustersToExpand
        self.minClusterSizeToExpand = minClusterSizeToExpand
        self.pipeType = pipeType
    }
}

let defaultGoalDetectionConfigs: [GoalDetectionConfig] = [
    // Red
    GoalDetectionConfig(
        minWhiteLineSize: 50,
        ballRadiusRatio: 0.024,
        exclusionRadiusMultiplier: 1.2,
        whiteMergeThreshold: 20,
        imageScale: 1,
        ballAreaPercentage: 30.0,
        maxBallsInCluster: 15,
        clusterSplitThreshold: 1.8,
        minClusterSeparation: 0.8,
        whitePixelConversionDistance: 150,  // Increased from 50 to 150
        maxClustersToExpand: 15,
        minClusterSizeToExpand: 10,
        pipeType: .long
    ),
    // Green
    GoalDetectionConfig(
        minWhiteLineSize: 50,
        ballRadiusRatio: 0.024,
        exclusionRadiusMultiplier: 1.2,
        whiteMergeThreshold: 20,
        imageScale: 0.3,
        ballAreaPercentage: 30.0,
        maxBallsInCluster: 15,
        clusterSplitThreshold: 1.9,
        minClusterSeparation: 0.8,
        whitePixelConversionDistance: 2000,  // Increased from 50 to 150
        maxClustersToExpand: 15,
        minClusterSizeToExpand: 10,
        pipeType: .long
    ),
    // Blue
    GoalDetectionConfig(
        minWhiteLineSize: 0,
        ballRadiusRatio: 4,
        exclusionRadiusMultiplier: 1.2,
        whiteMergeThreshold: 10,
        imageScale: 1,
        ballAreaPercentage: 18.0,
        maxBallsInCluster: 7,
        clusterSplitThreshold: 1.9,
        minClusterSeparation: 0.8,
        whitePixelConversionDistance: 150,  // Increased from 50 to 150
        maxClustersToExpand: 15,
        minClusterSizeToExpand: 10,
        pipeType: .short
    ),
    // Orange
    GoalDetectionConfig(
        minWhiteLineSize: 0,
        ballRadiusRatio: 4,
        exclusionRadiusMultiplier: 1.2,
        whiteMergeThreshold: 40,
        imageScale: 1,
        ballAreaPercentage: 18.0,
        maxBallsInCluster: 7,
        clusterSplitThreshold: 1.9,
        minClusterSeparation: 0.8,
        whitePixelConversionDistance: 150,  // Increased from 50 to 150
        maxClustersToExpand: 15,
        minClusterSizeToExpand: 10,
        pipeType: .short
    )
]

// Helper to get BallCounter.Parameters for a given goal index
func parametersForGoal(at index: Int, configs: [GoalDetectionConfig] = defaultGoalDetectionConfigs) -> BallCounter.Parameters {
    let config = configs[index]
    return BallCounter.Parameters(
        minWhiteLineSize: config.minWhiteLineSize,
        ballRadiusRatio: config.ballRadiusRatio,
        exclusionRadiusMultiplier: config.exclusionRadiusMultiplier,
        whiteMergeThreshold: config.whiteMergeThreshold,
        imageScale: config.imageScale,
        ballAreaPercentage: config.ballAreaPercentage,
        maxBallsInCluster: config.maxBallsInCluster,
        clusterSplitThreshold: config.clusterSplitThreshold,
        minClusterSeparation: config.minClusterSeparation,
        whitePixelConversionDistance: config.whitePixelConversionDistance,
        maxClustersToExpand: config.maxClustersToExpand,
        minClusterSizeToExpand: config.minClusterSizeToExpand,
        pipeType: config.pipeType
    )
} 
