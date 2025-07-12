# VRC RoboScore Ball Detection Algorithm

## Overview

The ball detection algorithm efficiently identifies red and blue balls in VRC (VEX Robotics Competition) images using a cluster-based approach with white pixel conversion. The algorithm is designed for real-time performance and high accuracy in detecting balls within goal zones.

## Core Algorithm Flow

### 1. Image Preprocessing
- **Downscaling**: Images are scaled down by `imageScale` (default: 0.33) for faster processing
- **Pixel Data Extraction**: Raw RGBA pixel data is extracted for analysis

### 2. White Pixel Conversion (Efficient Method)
The algorithm uses a border-expansion approach to convert white pixels near colored clusters:

#### Process:
1. **Cluster Detection**: Find all red and blue clusters in the image
2. **Cluster Filtering**: Select only clusters ≥ `minClusterSizeToExpand` pixels
3. **Top Cluster Selection**: Take the `maxClustersToExpand` largest clusters of each color
4. **Border Expansion**: For each selected cluster:
   - Identify border pixels (pixels with neighbors outside the cluster)
   - Use BFS to expand outward up to `whitePixelConversionDistance` pixels
   - Convert white pixels encountered during expansion to the cluster's color

#### Key Parameters:
- `maxClustersToExpand`: Maximum number of largest clusters to expand from (default: 15)
- `minClusterSizeToExpand`: Minimum cluster size to consider for expansion (default: 10)
- `whitePixelConversionDistance`: Maximum distance to expand from cluster borders (default: 50)

### 3. Ball Detection
After white pixel conversion, the algorithm scans for colored clusters:

#### Cluster Analysis:
- **Minimum Size Check**: Clusters must contain ≥ `minPixelsForBall` pixels
- **Multi-Ball Detection**: Wide clusters are split into multiple balls using aspect ratio analysis
- **Exclusion Zones**: Detected balls create exclusion zones to prevent overlapping detections

#### Key Parameters:
- `ballRadiusRatio`: Ball radius as fraction of image width (default: 0.024)
- `ballAreaPercentage`: Percentage of theoretical ball area needed (default: 30.0)
- `exclusionRadiusMultiplier`: Multiplier for exclusion zone radius (default: 1.2)
- `clusterSplitThreshold`: Width/height ratio for splitting clusters (default: 1.8)
- `maxBallsInCluster`: Maximum balls per cluster (default: 3)
- `minClusterSeparation`: Minimum separation between ball centers (default: 0.8)

### 4. Zone Classification
Balls are classified into middle/outside zones based on white line detection:

#### White Line Detection:
- **Search Area**: Middle half of image horizontally (25%-75% of width)
- **Line Identification**: Find white pixel clusters ≥ `minWhiteLineSize` pixels
- **Zone Definition**: Middle zone is between the two largest white lines
- **Intersection Check**: Balls touching white lines are excluded from middle zone

#### Key Parameters:
- `minWhiteLineSize`: Minimum pixels for white line detection (default: 50)

### 5. Ball Counting
Final counts are generated for each zone:
- **Middle Zone**: Balls between white lines (or all balls for short pipes)
- **Outside Zone**: Balls outside white lines
- **Total**: Sum of middle and outside counts

## Algorithm Efficiency Features

### 1. Border-Based Expansion
Instead of scanning all white pixels, the algorithm:
- Starts from colored cluster borders
- Uses BFS to expand outward
- Marks visited pixels to avoid redundant checks
- Only processes white pixels near large clusters

### 2. Cluster Prioritization
- Only expands from the largest clusters
- Reduces processing time by focusing on significant areas
- Configurable limits prevent excessive expansion

### 3. Early Termination
- Exclusion zones prevent overlapping detections
- Visited pixel tracking avoids redundant processing
- Distance limits prevent infinite expansion

## Parameter Tuning Guide

### For Better Detection:
- **Increase `whitePixelConversionDistance`**: Expands conversion range
- **Decrease `minClusterSizeToExpand`**: Includes smaller clusters
- **Increase `maxClustersToExpand`**: Processes more clusters

### For Faster Processing:
- **Decrease `imageScale`**: Smaller working image
- **Increase `minClusterSizeToExpand`**: Fewer clusters to process
- **Decrease `whitePixelConversionDistance`**: Smaller expansion area

### For Accuracy:
- **Adjust `ballAreaPercentage`**: Fine-tune minimum ball size
- **Modify `exclusionRadiusMultiplier`**: Control ball separation
- **Tune `clusterSplitThreshold`**: Control multi-ball detection

## Debug Features

The algorithm includes comprehensive debug output:
- Cluster sizes and counts
- White pixel conversion statistics
- Ball detection details
- Zone classification results
- Processing time measurements

## File Structure

- **`BallCounter.swift`**: Main algorithm implementation
- **`GoalConfigs.swift`**: Predefined parameter configurations
- **Preview UI**: Interactive testing and parameter tuning interface

## Future Development

### Potential Improvements:
1. **Machine Learning Integration**: Train models for better color detection
2. **Dynamic Parameter Adjustment**: Auto-tune based on image characteristics
3. **Multi-Threading**: Parallel processing for large images
4. **Edge Detection**: Use edge detection for more precise ball boundaries

### Extension Points:
- **Color Detection**: Add support for additional ball colors
- **Shape Analysis**: Implement more sophisticated cluster analysis
- **Temporal Tracking**: Track balls across video frames
- **Calibration**: Automatic camera calibration for different setups

## Performance Characteristics

- **Time Complexity**: O(n × d) where n = number of pixels, d = expansion distance
- **Space Complexity**: O(n) for visited arrays and pixel data
- **Typical Performance**: <100ms for 1080p images on modern devices
- **Memory Usage**: ~4MB for 1080p image processing

## Troubleshooting

### Common Issues:
1. **No balls detected**: Check `minClusterSizeToExpand` and `ballAreaPercentage`
2. **Too many false positives**: Increase `exclusionRadiusMultiplier`
3. **Missing balls**: Decrease `minClusterSizeToExpand` or increase `whitePixelConversionDistance`
4. **Slow performance**: Decrease `imageScale` or `maxClustersToExpand`

### Debug Steps:
1. Enable debug output to see cluster statistics
2. Use inspection mode to examine specific pixels
3. Adjust parameters incrementally
4. Test with known good images 