import UIKit
import SwiftUI
import Foundation

struct BallCount {
    var red: Int = 0
    var blue: Int = 0
}

struct ZoneCounts {
    var middle: BallCount = BallCount()
    var outside: BallCount = BallCount()
    
    var total: BallCount {
        BallCount(
            red: middle.red + outside.red,
            blue: middle.blue + outside.blue
        )
    }
}

private struct Ball {
    var center: CGPoint
    var color: BallColor
    var radius: CGFloat
    
    var isInMiddleZone: Bool = false
}

private struct WhiteLine {
    var yPosition: Int
    var xPosition: CGFloat  // Average x position of the line
    var pixels: Set<CGPoint>
}

private struct WhitePixelConversion {
    var point: CGPoint
    var convertedColor: BallColor
}

class BallCounter {
    static let maxTotalBalls = 15
    
    // Detection parameters
    struct Parameters {
        var minWhiteLineSize: Int = 50  // Minimum pixels to consider as potential white line
        var ballRadiusRatio: CGFloat = 0.024  // Ball radius as fraction of image width
        var exclusionRadiusMultiplier: CGFloat = 1.2  // Multiplier for exclusion zone
        var whiteMergeThreshold: Int = 20  // Number of adjacent colored pixels to merge white region
        var imageScale: CGFloat = 0.33     // Scale factor to downsample image for faster processing
        var ballAreaPercentage: Double = 30.0  // Percentage of theoretical ball area needed to count as a ball
        var maxBallsInCluster: Int = 3     // Maximum number of balls to detect in a single cluster
        var clusterSplitThreshold: CGFloat = 1.8  // Width/height ratio threshold for splitting clusters
        var minClusterSeparation: CGFloat = 0.8   // Minimum separation between ball centers as a fraction of ball diameter
        var whitePixelConversionDistance: Int = 5  // Distance to expand from cluster borders
        var maxClustersToExpand: Int = 15          // Maximum number of largest clusters to expand from
        var minClusterSizeToExpand: Int = 10       // Minimum cluster size to consider for expansion
        var pipeType: PipeType? = nil // Add this line
    }
    
    private var params: Parameters
    private var imageWidth: Int = 0
    private var imageHeight: Int = 0
    private var visited: [Bool] = []   // Flattened visited array (row-major)
    private var excludedPoints: Set<CGPoint> = []
    private var detectedBalls: [Ball] = []
    private var middleZoneStart: Int = 0
    private var middleZoneEnd: Int = 0
    
    private var whitePixelConversions: [WhitePixelConversion] = []
    private var efficientWhitePixelConversions: [WhitePixelConversion] = []
    
    init(parameters: Parameters = Parameters()) {
        self.params = parameters
    }
    
    // Helper to compute 1-D index in visited array
    private func vIndex(x: Int, y: Int) -> Int { y * imageWidth + x }
    
    static func countBalls(in image: UIImage, sensitivity: Double = 1.0) -> ZoneCounts {
        let counter = BallCounter(parameters: .init(
            minWhiteLineSize: Int(50.0 * sensitivity),
            ballRadiusRatio: 0.024,
            exclusionRadiusMultiplier: 1.2,
            whiteMergeThreshold: 20,
            imageScale: 0.33,
            ballAreaPercentage: 30.0
        ))
        return counter.detectBalls(in: image).zoneCounts
    }
    
    func detectBalls(in image: UIImage, pipeType: PipeType? = nil, principalAngle: CGFloat? = nil) -> (zoneCounts: ZoneCounts, annotatedImage: UIImage?) {
        let usePipeType = pipeType ?? params.pipeType
        let isShort = usePipeType == .short
        let startTime = CFAbsoluteTimeGetCurrent()
        var lastSectionTime = startTime
        let principalAngle = principalAngle ?? 0.0
        
        print("\nDEBUG: Starting new ball detection")
        
        // Downscale image for faster processing if needed
        let workingImage: UIImage
        if params.imageScale < 1.0 {
            let newSize = CGSize(width: image.size.width * params.imageScale,
                                 height: image.size.height * params.imageScale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            workingImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            workingImage = image
        }
        
        guard let cgImage = workingImage.cgImage else { return (ZoneCounts(), nil) }
        
        imageWidth = cgImage.width
        imageHeight = cgImage.height
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        excludedPoints.removeAll()
        detectedBalls.removeAll()
        
        print("Processing image - Width: \(imageWidth), Height: \(imageHeight)")
        
        // Get pixel data
        let bytesPerPixel = 4
        let bytesPerRow = imageWidth * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: imageWidth * imageHeight * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixelData,
                                    width: imageWidth,
                                    height: imageHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (ZoneCounts(), nil)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        // --- TIMING: Efficient white pixel conversion ---
        let whitePixelStart = CFAbsoluteTimeGetCurrent()
        processWhitePixelsEfficiently(in: pixelData)
        let whitePixelEnd = CFAbsoluteTimeGetCurrent()
        print(String(format: "Efficient white pixel conversion - %.2fs", whitePixelEnd - whitePixelStart))
        lastSectionTime = whitePixelEnd
        
        // Apply white pixel conversions to pixel data for ball detection
        applyWhitePixelConversions(to: &pixelData)
        
        print("DEBUG: Efficient white pixel conversions: \(efficientWhitePixelConversions.count)")
        let redConversions = efficientWhitePixelConversions.filter { $0.convertedColor == .red }.count
        let blueConversions = efficientWhitePixelConversions.filter { $0.convertedColor == .blue }.count
        print("DEBUG: Red conversions: \(redConversions), Blue conversions: \(blueConversions)")
        
        // DISABLED: Old white pixel conversion method
        // processWhitePixels(in: pixelData)
        
        // For short pipes, skip white line detection
        var middleLines: [WhiteLine] = []
        let disableWhiteLineDetection = params.minWhiteLineSize <= 0
        var whiteLineEnd: CFAbsoluteTime = lastSectionTime
        if !isShort && !disableWhiteLineDetection {
            // --- TIMING: White line detection ---
            let whiteLineStart = CFAbsoluteTimeGetCurrent()
            // First, find white lines in middle half horizontally of image
            let middleStartX = imageWidth / 4  // Only search middle half horizontally
            let middleEndX = imageWidth * 3 / 4
            var whiteLines: [WhiteLine] = []
            
            // Reset visited array for white line detection
            visited = Array(repeating: false, count: imageWidth * imageHeight)
            
            for y in 0..<imageHeight {
                for x in middleStartX..<middleEndX {
                    let idx = vIndex(x: x, y: y)
                    if visited[idx] { continue }
                    
                    let pixelIndex = (y * imageWidth + x) * bytesPerPixel
                    if isWhitePixel(data: pixelData, index: pixelIndex) {
                        let cluster = findWhiteCluster(at: CGPoint(x: x, y: y), in: pixelData)
                        if cluster.pixels.count > params.minWhiteLineSize {
                            whiteLines.append(findWhiteLine(from: cluster))
                        }
                    }
                }
            }
            
            // Sort white lines by size and get the two largest
            whiteLines.sort { $0.pixels.count > $1.pixels.count }
            middleLines = Array(whiteLines.prefix(2))
            whiteLineEnd = CFAbsoluteTimeGetCurrent()
            print(String(format: "White line detection - %.2fs", whiteLineEnd - whiteLineStart))
            lastSectionTime = whiteLineEnd
        }
        
        // --- TIMING: Cluster scan ---
        let clusterScanStart = CFAbsoluteTimeGetCurrent()
        
        // Reset visited array for ball detection (white pixel conversion may have marked pixels as visited)
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        
        // Calculate ball dimensions
        let ballRadius: CGFloat = isShort ? CGFloat(imageWidth) * 0.045 : CGFloat(imageWidth) * params.ballRadiusRatio
        let minPixelsForBall = Int(Double.pi * pow(Double(ballRadius), 2) * (params.ballAreaPercentage / 100.0))
        
        // Scan for colored clusters (ONLY red and blue)
        print("DEBUG: Starting main ball detection scan...")
        for x in 0..<imageWidth {
            for y in 0..<imageHeight {
                let idx = vIndex(x: x, y: y)
                if visited[idx] || isExcluded(CGPoint(x: x, y: y)) { continue }
                
                let pixelIndex = (y * imageWidth + x) * bytesPerPixel
                let color = getPixelColor(data: pixelData, index: pixelIndex)
                
                // Only process red and blue clusters
                if let color = color {
                    //print("DEBUG: Processing \(color) cluster at (\(x), \(y))")
                    let cluster = findCluster(at: CGPoint(x: x, y: y), color: color, in: pixelData)
                    
                    if cluster.pixels.count >= minPixelsForBall {
                        let analysis = analyzeCluster(cluster, ballRadius: ballRadius, principalAngle: principalAngle)
                        
                        for centerScaled in analysis.centers {
                            let center = CGPoint(x: centerScaled.x / params.imageScale,
                                               y: centerScaled.y / params.imageScale)
                            
                            // Check if ball is between white lines (use scaled coordinates)
                            let isInMiddle: Bool
                            if disableWhiteLineDetection {
                                isInMiddle = false
                            } else {
                                isInMiddle = middleLines.count == 2 &&
                                    centerScaled.x > min(middleLines[0].xPosition, middleLines[1].xPosition) &&
                                    centerScaled.x < max(middleLines[0].xPosition, middleLines[1].xPosition) &&
                                    !doesBallIntersectLines(center: centerScaled, radius: ballRadius, lines: middleLines)
                            }
                            
                            //print("\nDEBUG: Ball Detection Details:")
                            //print("Ball position (scaled): \(centerScaled)")
                            //print("Color: \(analysis.color)")
                            //print("Middle line check result: \(isInMiddle)")
                            //print("Line positions: \(middleLines.map { $0.xPosition })")
                            
                            let ball = Ball(center: center,
                                           color: analysis.color,
                                           radius: ballRadius / params.imageScale,
                                           isInMiddleZone: isInMiddle)
                            detectedBalls.append(ball)
                            
                            let exclusionRadius = ballRadius * params.exclusionRadiusMultiplier
                            addExclusionZone(center: centerScaled, radius: exclusionRadius)
                        }
                    }
                }
            }
        }
        let clusterScanEnd = CFAbsoluteTimeGetCurrent()
        print(String(format: "Cluster scan - %.2fs", clusterScanEnd - clusterScanStart))
        lastSectionTime = clusterScanEnd
        
        // --- TIMING: Counting balls ---
        let countingStart = CFAbsoluteTimeGetCurrent()
        // Create zone counts
        var counts = ZoneCounts()
        //print("\nDEBUG: Counting detected balls:")
        if isShort {
            // For short pipes, count all balls as 'middle', ignore inside/outside
            for ball in detectedBalls {
                if ball.color == .red {
                    counts.middle.red += 1
                    //print("DEBUG: Counted as middle red")
                } else {
                    counts.middle.blue += 1
                    //print("DEBUG: Counted as middle blue")
                }
            }
        } else if disableWhiteLineDetection {
            // If white line detection is disabled, count all balls as outside
            for ball in detectedBalls {
                if ball.color == .red {
                    counts.outside.red += 1
                    //print("DEBUG: Counted as outside red (white line detection disabled)")
                } else {
                    counts.outside.blue += 1
                    //print("DEBUG: Counted as outside blue (white line detection disabled)")
                }
            }
        } else {
        for ball in detectedBalls {
            //print("DEBUG: Processing ball at \(ball.center) - Color: \(ball.color), IsMiddle: \(ball.isInMiddleZone)")
            if ball.isInMiddleZone {
                if ball.color == .red {
                    counts.middle.red += 1
                    //print("DEBUG: Counted as middle red")
                } else {
                    counts.middle.blue += 1
                    //print("DEBUG: Counted as middle blue")
                }
            } else {
                if ball.color == .red {
                    counts.outside.red += 1
                    //print("DEBUG: Counted as outside red")
                } else {
                    counts.outside.blue += 1
                    //print("DEBUG: Counted as outside blue")
                        }
                    }
                }
            }
        let countingEnd = CFAbsoluteTimeGetCurrent()
        print(String(format: "Counting balls - %.2fs", countingEnd - countingStart))
        lastSectionTime = countingEnd
        
        let endTime = CFAbsoluteTimeGetCurrent()
        print(String(format: "Ball detection completed in %.3f seconds (total)", endTime - startTime))
        
        print("DEBUG: Final counts - Middle: Red=\(counts.middle.red), Blue=\(counts.middle.blue)")
        print("DEBUG: Final counts - Outside: Red=\(counts.outside.red), Blue=\(counts.outside.blue)")
        
        // Create annotated image
        let annotatedImage = createAnnotatedImage(originalImage: image, whiteLines: middleLines)
        
        return (counts, annotatedImage)
    }
    
    private func isWhitePixel(data: [UInt8], index: Int) -> Bool {
        let r = CGFloat(data[index]) / 255.0
        let g = CGFloat(data[index + 1]) / 255.0
        let b = CGFloat(data[index + 2]) / 255.0
        
        // Match with exact VRCColors.white
        return r > 0.99 && g > 0.99 && b > 0.99
    }
    
    private func findWhiteCluster(at start: CGPoint, in pixelData: [UInt8]) -> Cluster {
        var cluster = Cluster(pixels: [], color: .red) // Color doesn't matter for white clusters
        var queue: [CGPoint] = [start]
        
        while !queue.isEmpty {
            let point = queue.removeFirst()
            let x = Int(point.x)
            let y = Int(point.y)
            
            if x < 0 || x >= imageWidth || y < 0 || y >= imageHeight { continue }
            if visited[vIndex(x: x, y: y)] { continue }
            
            visited[vIndex(x: x, y: y)] = true
            
            let pixelIndex = (y * imageWidth + x) * 4
            if isWhitePixel(data: pixelData, index: pixelIndex) {
                cluster.pixels.insert(point)
                
                queue.append(CGPoint(x: x + 1, y: y))
                queue.append(CGPoint(x: x - 1, y: y))
                queue.append(CGPoint(x: x, y: y + 1))
                queue.append(CGPoint(x: x, y: y - 1))
            }
        }
        
        return cluster
    }
    
    private func findWhiteLine(from cluster: Cluster) -> WhiteLine {
        let avgY = Int(cluster.pixels.reduce(0.0) { $0 + $1.y } / CGFloat(cluster.pixels.count))
        let avgX = cluster.pixels.reduce(0.0) { $0 + $1.x } / CGFloat(cluster.pixels.count)
        return WhiteLine(yPosition: avgY, xPosition: avgX, pixels: cluster.pixels)
    }
    
    private func doesBallIntersectLines(center: CGPoint, radius: CGFloat, lines: [WhiteLine]) -> Bool {
        guard lines.count == 2 else {
            print("DEBUG: Not enough lines found (\(lines.count))")
            return true
        }
        
        // Find the leftmost and rightmost x-coordinates of the lines
        var leftLineX = CGFloat.infinity
        var rightLineX = -CGFloat.infinity
        
        // Calculate average x position for each line
        for line in lines {
            let avgX = line.pixels.reduce(0.0) { $0 + $1.x } / CGFloat(line.pixels.count)
            leftLineX = min(leftLineX, avgX)
            rightLineX = max(rightLineX, avgX)
        }
        
        //print("\nDEBUG: Line Positions:")
        //print("Left line: \(leftLineX)")
        //print("Right line: \(rightLineX)")
        //print("Ball center: \(center.x)")
        //print("Ball radius: \(radius)")
        //print("Ball left edge: \(center.x - radius)")
        //print("Ball right edge: \(center.x + radius)")
        
        // Add a small buffer to avoid edge cases
        let buffer: CGFloat = 2.0
        
        // Check if ball's center is between the lines horizontally
        if center.x < leftLineX + buffer || center.x > rightLineX - buffer {
            //print("DEBUG: Ball center not between lines")
            return true
        }
        
        // Check if ball touches either line
        let ballLeft = center.x - radius
        let ballRight = center.x + radius
        
        if ballLeft < leftLineX + buffer || ballRight > rightLineX - buffer {
            //print("DEBUG: Ball touches lines")
            return true
        }
        
        //print("DEBUG: Ball is in middle zone!")
        return false
    }
    
    private func getPixelColor(data: [UInt8], index: Int) -> BallColor? {
        let r = CGFloat(data[index]) / 255.0
        let g = CGFloat(data[index + 1]) / 255.0
        let b = CGFloat(data[index + 2]) / 255.0
        
        // Match with exact VRCColors values
        let redComponents = VRCColors.red.components
        let blueComponents = VRCColors.blue.components
        
        if abs(r - redComponents.red) < 0.01 && 
           abs(g - redComponents.green) < 0.01 && 
           abs(b - redComponents.blue) < 0.01 {
            return .red
        } else if abs(r - blueComponents.red) < 0.01 && 
                  abs(g - blueComponents.green) < 0.01 && 
                  abs(b - blueComponents.blue) < 0.01 {
            return .blue
        }
        return nil
    }
    
    private struct Cluster {
        var pixels: Set<CGPoint>
        var color: BallColor
    }
    
    private func findCluster(at start: CGPoint, color: BallColor, in pixelData: [UInt8]) -> Cluster {
        var cluster = Cluster(pixels: [], color: color)
        var queue: [CGPoint] = [start]
        
        while !queue.isEmpty {
            let point = queue.removeFirst()
            let x = Int(point.x)
            let y = Int(point.y)
            
            if x < 0 || x >= imageWidth || y < 0 || y >= imageHeight { continue }
            if visited[vIndex(x: x, y: y)] || isExcluded(point) { continue }
            
            visited[vIndex(x: x, y: y)] = true
            
            let pixelIndex = (y * imageWidth + x) * 4
            if getPixelColor(data: pixelData, index: pixelIndex) == color {
                cluster.pixels.insert(point)
                
                // Add adjacent pixels to queue
                queue.append(CGPoint(x: x + 1, y: y))
                queue.append(CGPoint(x: x - 1, y: y))
                queue.append(CGPoint(x: x, y: y + 1))
                queue.append(CGPoint(x: x, y: y - 1))
            }
        }
        
        return cluster
    }
    
    private func calculateClusterCenter(_ pixels: Set<CGPoint>) -> CGPoint {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        
        for point in pixels {
            sumX += point.x
            sumY += point.y
        }
        
        let count = CGFloat(pixels.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }
    
    private func isExcluded(_ point: CGPoint) -> Bool {
        excludedPoints.contains(point)
    }
    
    private func addExclusionZone(center: CGPoint, radius: CGFloat) {
        let radiusInt = Int(radius)
        for dx in -radiusInt...radiusInt {
            for dy in -radiusInt...radiusInt {
                let x = Int(center.x) + dx
                let y = Int(center.y) + dy
                if x >= 0 && x < imageWidth && y >= 0 && y < imageHeight {
                    if CGPoint(x: center.x - CGFloat(x), y: center.y - CGFloat(y)).length <= radius {
                        excludedPoints.insert(CGPoint(x: x, y: y))
                    }
                }
            }
        }
    }
    
    private func createAnnotatedImage(originalImage: UIImage, whiteLines: [WhiteLine]) -> UIImage? {
        let scaleInv: CGFloat = 1.0 / params.imageScale
        
        UIGraphicsBeginImageContextWithOptions(originalImage.size, false, originalImage.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw original image
        originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
        
        // Draw the zone between lines if we have exactly 2 lines
        if whiteLines.count == 2 {
            // Find the leftmost and rightmost x-coordinates of the lines (convert to original scale)
            let leftLineX = whiteLines.min(by: { $0.xPosition < $1.xPosition })!.xPosition * scaleInv
            let rightLineX = whiteLines.max(by: { $0.xPosition < $1.xPosition })!.xPosition * scaleInv
            
            context.setFillColor(UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.2).cgColor) // Semi-transparent yellow
            let rect = CGRect(x: leftLineX, y: 0, width: rightLineX - leftLineX, height: originalImage.size.height)
            context.fill(rect)
        }
        
        // Draw white lines with pink overlay (scale coordinates)
        context.setFillColor(UIColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 0.3).cgColor) // Pink color
        for line in whiteLines {
            for pixel in line.pixels {
                let rect = CGRect(x: pixel.x * scaleInv - 1, y: pixel.y * scaleInv - 1, width: 3, height: 3)
                context.fillEllipse(in: rect)
            }
        }
        
        // Fill ball areas
        for ball in detectedBalls {
            let fillColor = ball.color == .red ? 
                UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.5) : // Orange for red balls
                UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 0.5)   // Green for blue balls
            
            context.setFillColor(fillColor.cgColor)
            let rect = CGRect(x: ball.center.x - ball.radius,
                            y: ball.center.y - ball.radius,
                            width: ball.radius * 2,
                            height: ball.radius * 2)
            context.fillEllipse(in: rect)
            
            // Draw crosshair
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: ball.center.x - 5, y: ball.center.y))
            context.addLine(to: CGPoint(x: ball.center.x + 5, y: ball.center.y))
            context.move(to: CGPoint(x: ball.center.x, y: ball.center.y - 5))
            context.addLine(to: CGPoint(x: ball.center.x, y: ball.center.y + 5))
            context.strokePath()
        }
        
        // Draw converted white pixels (using new efficient method)
        for conversion in efficientWhitePixelConversions {
            let fillColor = conversion.convertedColor == .red ?
                UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.3) : // Semi-transparent red
                UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.3)   // Semi-transparent blue
            
            context.setFillColor(fillColor.cgColor)
            let size: CGFloat = 3.0
            let rect = CGRect(x: conversion.point.x * scaleInv - size/2,
                             y: conversion.point.y * scaleInv - size/2,
                             width: size,
                             height: size)
            context.fillEllipse(in: rect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Inspection Methods
    fileprivate struct InspectionResult {
        var clusterSize: Int
        var color: BallColor?
        var isExcluded: Bool
        var nearestBallDistance: CGFloat?
        var isInMiddleZone: Bool
        var reason: String
        var inspectedPoint: CGPoint?
    }
    
    fileprivate func inspectPoint(_ point: CGPoint, in image: UIImage) -> InspectionResult {
        guard let cgImage = image.cgImage else {
            return InspectionResult(
                clusterSize: 0,
                color: nil,
                isExcluded: false,
                nearestBallDistance: nil,
                isInMiddleZone: false,
                reason: "Failed to get image data",
                inspectedPoint: nil
            )
        }
        
        // Scale point to match working image coordinates
        let scaledPoint = CGPoint(
            x: min(max(0, point.x * params.imageScale), CGFloat(cgImage.width - 1)),
            y: min(max(0, point.y * params.imageScale), CGFloat(cgImage.height - 1))
        )
        
        // Check if point is excluded
        if isExcluded(scaledPoint) {
            return InspectionResult(
                clusterSize: 0,
                color: nil,
                isExcluded: true,
                nearestBallDistance: nil,
                isInMiddleZone: false,
                reason: "Point is in exclusion zone of another detected ball",
                inspectedPoint: point
            )
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixelData,
                                    width: cgImage.width,
                                    height: cgImage.height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return InspectionResult(
                clusterSize: 0,
                color: nil,
                isExcluded: false,
                nearestBallDistance: nil,
                isInMiddleZone: false,
                reason: "Failed to create graphics context",
                inspectedPoint: point
            )
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        // Get color at point
        let x = Int(scaledPoint.x)
        let y = Int(scaledPoint.y)
        let pixelIndex = (y * cgImage.width + x) * bytesPerPixel
        let color = getPixelColor(data: pixelData, index: pixelIndex)
        
        if color == nil {
            return InspectionResult(
                clusterSize: 0,
                color: nil,
                isExcluded: false,
                nearestBallDistance: nil,
                isInMiddleZone: false,
                reason: "Point is not a recognized color (red or blue)",
                inspectedPoint: point
            )
        }
        
        // Find cluster
        imageWidth = cgImage.width
        imageHeight = cgImage.height
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        let cluster = findCluster(at: scaledPoint, color: color!, in: pixelData)
        let clusterSize = cluster.pixels.count
        
        // Calculate minimum required cluster size based on current parameters
        let ballRadius = CGFloat(cgImage.width) * params.ballRadiusRatio
        let minPixelsForBall = Int(Double.pi * pow(Double(ballRadius), 2) * (params.ballAreaPercentage / 100.0))
        
        // Find nearest detected ball
        var nearestDistance: CGFloat?
        if !detectedBalls.isEmpty {
            let clusterCenter = calculateClusterCenter(cluster.pixels)
            nearestDistance = detectedBalls.map { ball in
                let dx = ball.center.x - clusterCenter.x / params.imageScale
                let dy = ball.center.y - clusterCenter.y / params.imageScale
                return sqrt(dx * dx + dy * dy)
            }.min()
        }
        
        // Check if point would be in middle zone
        let isInMiddle = detectedBalls.first?.isInMiddleZone ?? false
        
        // Determine reason for detection/non-detection
        var reason: String
        if clusterSize < minPixelsForBall {
            reason = "Cluster size (\(clusterSize)) is smaller than minimum required size (\(minPixelsForBall))"
        } else if let distance = nearestDistance, distance < ballRadius * params.exclusionRadiusMultiplier {
            reason = "Too close to another detected ball (distance: \(Int(distance))px, minimum required: \(Int(ballRadius * params.exclusionRadiusMultiplier))px)"
        } else {
            reason = "Cluster meets detection criteria (size: \(clusterSize)px, minimum: \(minPixelsForBall)px)"
        }
        
        return InspectionResult(
            clusterSize: clusterSize,
            color: color,
            isExcluded: false,
            nearestBallDistance: nearestDistance,
            isInMiddleZone: isInMiddle,
            reason: reason,
            inspectedPoint: point
        )
    }
    
    private struct ClusterAnalysis {
        var centers: [CGPoint]
        var color: BallColor
    }
    
    private func analyzeCluster(_ cluster: Cluster, ballRadius: CGFloat, principalAngle: CGFloat = 0.0) -> ClusterAnalysis {
        let pixels = Array(cluster.pixels)
        var centers: [CGPoint] = []
        // Rotate all pixels by -principalAngle around the cluster centroid
        let centroid = calculateClusterCenter(cluster.pixels)
        let rotatedPixels = pixels.map { rotate(point: $0, around: centroid, by: -principalAngle) }
        // Get bounds in rotated space
        let minX = rotatedPixels.map { $0.x }.min() ?? 0
        let maxX = rotatedPixels.map { $0.x }.max() ?? 0
        let minY = rotatedPixels.map { $0.y }.min() ?? 0
        let maxY = rotatedPixels.map { $0.y }.max() ?? 0
        let width = maxX - minX
        let height = maxY - minY
        let aspectRatio = width / height
        if aspectRatio >= params.clusterSplitThreshold {
            let potentialBallCount = min(Int(aspectRatio), params.maxBallsInCluster)
            let segmentWidth = width / CGFloat(potentialBallCount)
            for i in 0..<potentialBallCount {
                let segmentStart = minX + segmentWidth * CGFloat(i)
                let segmentEnd = segmentStart + segmentWidth
                // Get pixels in this segment (rotated space)
                let segmentPixels = zip(pixels, rotatedPixels).filter { (_, rp) in rp.x >= segmentStart && rp.x < segmentEnd }.map { $0.0 }
                if !segmentPixels.isEmpty {
                    let segmentCenter = calculateClusterCenter(Set(segmentPixels))
                    // Check if this center is far enough from other centers
                    let isFarEnough = centers.allSatisfy { existingCenter in
                        let distance = CGPoint(x: existingCenter.x - segmentCenter.x,
                                             y: existingCenter.y - segmentCenter.y).length
                        return distance >= (2 * ballRadius * params.minClusterSeparation)
                    }
                    if isFarEnough {
                        centers.append(segmentCenter)
                    }
                }
            }
        }
        if centers.isEmpty {
            centers = [calculateClusterCenter(cluster.pixels)]
        }
        return ClusterAnalysis(centers: centers, color: cluster.color)
    }
    // Helper to rotate a point around a center by an angle (radians)
    private func rotate(point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let cosA = cos(angle)
        let sinA = sin(angle)
        let rotated = CGPoint(
            x: translated.x * cosA - translated.y * sinA,
            y: translated.x * sinA + translated.y * cosA
        )
        return CGPoint(x: rotated.x + center.x, y: rotated.y + center.y)
    }
    
    // OLD METHOD - No longer used in simplified algorithm
    private func findColoredPixelsAround(point: CGPoint, color: BallColor, distance: Int, in pixelData: [UInt8]) -> Int {
        var count = 0
        let x = Int(point.x)
        let y = Int(point.y)
        
        for dx in -distance...distance {
            for dy in -distance...distance {
                let newX = x + dx
                let newY = y + dy
                
                if newX >= 0 && newX < imageWidth && newY >= 0 && newY < imageHeight {
                    let pixelIndex = (newY * imageWidth + newX) * 4
                    if getPixelColor(data: pixelData, index: pixelIndex) == color {
                        count += 1
                        // Removed threshold check since this method is no longer used
                    }
                }
            }
        }
        return count
    }
    
    private func applyWhitePixelConversions(to pixelData: inout [UInt8]) {
        for conversion in efficientWhitePixelConversions {
            let x = Int(conversion.point.x)
            let y = Int(conversion.point.y)
            let pixelIndex = (y * imageWidth + x) * 4
            
            // Convert the white pixel to the appropriate color
            if conversion.convertedColor == .red {
                // Set to red color (using VRCColors.red components)
                let redComponents = VRCColors.red.components
                pixelData[pixelIndex] = UInt8(redComponents.red * 255.0)     // R
                pixelData[pixelIndex + 1] = UInt8(redComponents.green * 255.0) // G
                pixelData[pixelIndex + 2] = UInt8(redComponents.blue * 255.0)  // B
                pixelData[pixelIndex + 3] = 255 // A
            } else {
                // Set to blue color (using VRCColors.blue components)
                let blueComponents = VRCColors.blue.components
                pixelData[pixelIndex] = UInt8(blueComponents.red * 255.0)     // R
                pixelData[pixelIndex + 1] = UInt8(blueComponents.green * 255.0) // G
                pixelData[pixelIndex + 2] = UInt8(blueComponents.blue * 255.0)  // B
                pixelData[pixelIndex + 3] = 255 // A
            }
        }
    }
    

    
    // NEW EFFICIENT METHOD - Simplified border-based expansion
    private func processWhitePixelsEfficiently(in pixelData: [UInt8]) {
        efficientWhitePixelConversions.removeAll()
        
        // First, find all colored clusters (ONLY red and blue)
        var redClusters: [Cluster] = []
        var blueClusters: [Cluster] = []
        
        // Reset visited array for cluster detection
        visited = Array(repeating: false, count: imageWidth * imageHeight)
        
        print("DEBUG: Starting cluster detection for white pixel conversion...")
        
        // Scan for colored clusters (ONLY red and blue)
        for x in 0..<imageWidth {
            for y in 0..<imageHeight {
                let idx = vIndex(x: x, y: y)
                if visited[idx] { continue }
                
                let pixelIndex = (y * imageWidth + x) * 4
                let color = getPixelColor(data: pixelData, index: pixelIndex)
                
                // Only process red and blue clusters
                if let color = color {
                    //print("DEBUG: Found \(color) pixel at (\(x), \(y))")
                    let cluster = findCluster(at: CGPoint(x: x, y: y), color: color, in: pixelData)
                    
                    // Only consider clusters that meet the minimum size threshold
                    if cluster.pixels.count >= params.minClusterSizeToExpand {
                        if color == .red {
                            redClusters.append(cluster)
                            //print("DEBUG: Added red cluster with \(cluster.pixels.count) pixels")
                        } else if color == .blue {
                            blueClusters.append(cluster)
                            //print("DEBUG: Added blue cluster with \(cluster.pixels.count) pixels")
                        }
                    } else {
                        //print("DEBUG: Skipped \(color) cluster with \(cluster.pixels.count) pixels (below threshold \(params.minClusterSizeToExpand))")
                    }
                }
            }
        }
        
        // Sort clusters by size (largest first) and take only the top N
        redClusters.sort { $0.pixels.count > $1.pixels.count }
        blueClusters.sort { $0.pixels.count > $1.pixels.count }
        
        let topRedClusters = Array(redClusters.prefix(params.maxClustersToExpand))
        let topBlueClusters = Array(blueClusters.prefix(params.maxClustersToExpand))
        
        print("DEBUG: Found \(redClusters.count) red clusters and \(blueClusters.count) blue clusters")
        print("DEBUG: Using top \(topRedClusters.count) red clusters and \(topBlueClusters.count) blue clusters for expansion")
        for (i, cluster) in topRedClusters.enumerated() {
            //print("DEBUG: Top red cluster \(i): \(cluster.pixels.count) pixels")
        }
        for (i, cluster) in topBlueClusters.enumerated() {
            //print("DEBUG: Top blue cluster \(i): \(cluster.pixels.count) pixels")
        }
        
        // Now expand from each top cluster's border to find nearby white pixels
        for cluster in topRedClusters {
            convertWhitePixelsNearClusterSimplified(cluster: cluster, to: .red, maxDistance: params.whitePixelConversionDistance, in: pixelData)
        }
        
        for cluster in topBlueClusters {
            convertWhitePixelsNearClusterSimplified(cluster: cluster, to: .blue, maxDistance: params.whitePixelConversionDistance, in: pixelData)
        }
    }
    

    
    // NEW SIMPLIFIED METHOD - No threshold checking, just expand from large clusters
    private func convertWhitePixelsNearClusterSimplified(cluster: Cluster, to color: BallColor, maxDistance: Int, in pixelData: [UInt8]) {
        var visited = Set<CGPoint>()
        var queue: [(point: CGPoint, distance: Int)] = []
        
        // Find border pixels of the cluster (pixels that have at least one neighbor outside the cluster)
        for point in cluster.pixels {
            let x = Int(point.x)
            let y = Int(point.y)
            
            // Check all 8 neighbors
            for dx in -1...1 {
                for dy in -1...1 {
                    if dx == 0 && dy == 0 { continue }
                    
                    let neighborX = x + dx
                    let neighborY = y + dy
                    let neighbor = CGPoint(x: CGFloat(neighborX), y: CGFloat(neighborY))
                    
                    // If neighbor is outside the cluster, this is a border pixel
                    if !cluster.pixels.contains(neighbor) {
                        queue.append((neighbor, 1))
                    }
                }
            }
        }
        
        // BFS outward from the border
        while !queue.isEmpty {
            let (point, distance) = queue.removeFirst()
            
            if distance > maxDistance { continue }
            if visited.contains(point) { continue }
            visited.insert(point)
            
            let x = Int(point.x)
            let y = Int(point.y)
            
            if x < 0 || x >= imageWidth || y < 0 || y >= imageHeight { continue }
            
            let pixelIndex = (y * imageWidth + x) * 4
            if isWhitePixel(data: pixelData, index: pixelIndex) {
                // Simplified: Since this white pixel is near a large cluster, convert it automatically
                efficientWhitePixelConversions.append(WhitePixelConversion(point: point, convertedColor: color))
                
                // Continue expanding from this white pixel
                for dx in -1...1 {
                    for dy in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        
                        let neighbor = CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy))
                        queue.append((neighbor, distance + 1))
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct BallCounterPreview: View {
    // You can replace this path with your local image path
    private static let localImagePath = "/Users/evanboyle/Downloads/test_image.jpg" // Example path
    
    @State private var image: UIImage? = nil
    @State private var annotatedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var zoneCounts = ZoneCounts()
    
    // Detection parameters
    @State private var showDetectionControls: Bool = false
    @State private var ballRadiusRatio: Double = defaultGoalDetectionConfigs[1].ballRadiusRatio
    @State private var exclusionRadiusMultiplier: Double = defaultGoalDetectionConfigs[1].exclusionRadiusMultiplier
    @State private var ballAreaPercentage: Double = defaultGoalDetectionConfigs[1].ballAreaPercentage
    @State private var whitePixelConversionDistance: Double = 5.0
    @State private var maxClustersToExpand: Double = 15.0
    @State private var minClusterSizeToExpand: Double = 10.0
    
    // Inspection mode state
    @State private var isInspectionMode = false
    @State private var lastInspectionResult: BallCounter.InspectionResult?
    @State private var inspectedPoint: CGPoint?
    

    
    private var detector: BallCounter {
        BallCounter(parameters: .init(
            minWhiteLineSize: 50,
            ballRadiusRatio: CGFloat(ballRadiusRatio),
            exclusionRadiusMultiplier: CGFloat(exclusionRadiusMultiplier),
            whiteMergeThreshold: 20,
            imageScale: 0.33,
            ballAreaPercentage: ballAreaPercentage,
            whitePixelConversionDistance: Int(whitePixelConversionDistance),
            maxClustersToExpand: Int(maxClustersToExpand),
            minClusterSizeToExpand: Int(minClusterSizeToExpand)
        ))
    }
    
    // MARK: - View Components
    
    private var imageSection: some View {
        Group {
            if let annotatedImage = annotatedImage {
                Image(uiImage: annotatedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(inspectionOverlay)
            } else if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var inspectionOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if isInspectionMode {
                            inspectedPoint = location
                            inspectLocation(location, in: geometry)
                        }
                    }
                
                if isInspectionMode, let point = inspectedPoint {
                    Circle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .position(point)
                }
            }
        }
    }
    
    private var inspectionResultsSection: some View {
        Group {
            if isInspectionMode, let result = lastInspectionResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inspection Results")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Group {
                        if let color = result.color {
                            Text("Color: \(color == .red ? "Red" : "Blue")")
                        } else {
                            Text("Color: None detected")
                        }
                        
                        Text("Cluster Size: \(result.clusterSize) pixels")
                        
                        if let distance = result.nearestBallDistance {
                            Text("Distance to nearest ball: \(Int(distance))px")
                        }
                        
                        Text("In Middle Zone: \(result.isInMiddleZone ? "Yes" : "No")")
                        Text("Is Excluded: \(result.isExcluded ? "Yes" : "No")")
                        Text("Analysis: \(result.reason)")
                    }
                    .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
            }
        }
    }
    
    private var detectionControlsSection: some View {
        VStack(spacing: 10) {
            Toggle("Inspection Mode", isOn: $isInspectionMode)
                .onChange(of: isInspectionMode) { _, newValue in
                    if !newValue {
                        lastInspectionResult = nil
                        inspectedPoint = nil
                    }
                }
                .padding(.horizontal)
            
            Toggle("Show Detection Controls", isOn: $showDetectionControls)
                .padding(.horizontal)
            
            if showDetectionControls {
                VStack(spacing: 10) {
                    ParameterSlider(value: $ballRadiusRatio,
                                  range: 0.02...0.1,
                                  label: "Ball Radius Ratio")
                                .onChange(of: ballRadiusRatio) { _, newValue in
            detectBalls()
        }
                    
                    ParameterSlider(value: $exclusionRadiusMultiplier,
                                  range: 1.0...2.0,
                                  label: "Exclusion Radius")
                        .onChange(of: exclusionRadiusMultiplier) { _, newValue in
                            detectBalls()
                        }
                    
                    ParameterSlider(value: $ballAreaPercentage,
                                  range: 10...90,
                                  label: "Ball Area Percentage")
                        .onChange(of: ballAreaPercentage) { _, newValue in
                            detectBalls()
                        }
                    
                    ParameterSlider(value: $whitePixelConversionDistance,
                                  range: 1...20,
                                  label: "White Pixel Conversion Distance")
                        .onChange(of: whitePixelConversionDistance) { _, newValue in
                            detectBalls()
                        }
                    
                    ParameterSlider(value: $maxClustersToExpand,
                                  range: 1...50,
                                  label: "Max Clusters to Expand")
                        .onChange(of: maxClustersToExpand) { _, newValue in
                            detectBalls()
                        }
                    
                    ParameterSlider(value: $minClusterSizeToExpand,
                                  range: 1...50,
                                  label: "Min Cluster Size to Expand")
                        .onChange(of: minClusterSizeToExpand) { _, newValue in
                            detectBalls()
                        }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
    
    private var ballCountsSection: some View {
        VStack(alignment: .leading) {
            Text("Ball Counts:")
                .font(.headline)
                .foregroundColor(.white)
            
            Group {
                Text("Middle Zone:")
                    .foregroundColor(.white)
                HStack {
                    Text("Red: \(zoneCounts.middle.red)")
                        .foregroundColor(.red)
                    Text("Blue: \(zoneCounts.middle.blue)")
                        .foregroundColor(.blue)
                }
                
                Text("Outside Zone:")
                    .foregroundColor(.white)
                HStack {
                    Text("Red: \(zoneCounts.outside.red)")
                        .foregroundColor(.red)
                    Text("Blue: \(zoneCounts.outside.blue)")
                        .foregroundColor(.blue)
                }
                
                Text("Total:")
                    .foregroundColor(.white)
                HStack {
                    Text("Red: \(zoneCounts.total.red)")
                        .foregroundColor(.red)
                    Text("Blue: \(zoneCounts.total.blue)")
                        .foregroundColor(.blue)
                }
            }
            .padding(.leading)
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            // Image section
            imageSection
            
            // Controls and results section
            ScrollView {
                VStack(spacing: 20) {
                    Button(action: {
                        showImagePicker = true
                    }) {
                        Label("Choose Image", systemImage: "photo.on.rectangle")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    inspectionResultsSection
                    detectionControlsSection
                    ballCountsSection
                    
                    // Detect button
                    Button(action: detectBalls) {
                        Label("Detect Balls", systemImage: "wand.and.stars")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .disabled(image == nil)
                }
                .padding()
            }
            .frame(width: 300)  // Fixed width for controls
        }
        .background(Color.black)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $image)
        }
        .onChange(of: image) { _, _ in
            detectBalls()
        }
        .onAppear {
            // Initialize values from green pipe goal detection config
            ballRadiusRatio = defaultGoalDetectionConfigs[1].ballRadiusRatio
            exclusionRadiusMultiplier = defaultGoalDetectionConfigs[1].exclusionRadiusMultiplier
            ballAreaPercentage = defaultGoalDetectionConfigs[1].ballAreaPercentage
            
            // Load initial image if available
            if let localImage = UIImage(contentsOfFile: Self.localImagePath) {
                image = localImage
            } else {
                image = UIImage(systemName: "photo")
            }
        }
    }
    
    private func detectBalls() {
        guard let image = image else { return }
        let result = detector.detectBalls(in: image)
        zoneCounts = result.zoneCounts
        annotatedImage = result.annotatedImage
    }
    
    private func inspectLocation(_ location: CGPoint, in geometry: GeometryProxy) {
        guard let image = image else { return }
        
        // Convert tap location to image coordinates
        let imageSize = image.size
        let viewSize = geometry.size
        
        // Calculate scaling factors
        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height
        
        // Convert tap location to image coordinates
        let imageX = location.x * scaleX
        let imageY = location.y * scaleY
        
        // Inspect the point
        lastInspectionResult = detector.inspectPoint(CGPoint(x: imageX, y: imageY), in: image)
        
        print("DEBUG: Inspection at (\(Int(imageX)), \(Int(imageY)))")
        print("DEBUG: \(lastInspectionResult?.reason ?? "No result")")
    }
}

struct ParameterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .foregroundColor(.white)
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: "%.3f", value))
                    .foregroundColor(.white)
                    .frame(width: 60)
            }
        }
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    var length: CGFloat {
        sqrt(x * x + y * y)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    BallCounterPreview()
}
#endif 
