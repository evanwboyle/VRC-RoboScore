import cv2
import numpy as np
import os
from pathlib import Path

# Convert hex colors to HSV for reference
# 91511F -> HSV: (21, 79, 57)  Dark orange-brown
# E3913E -> HSV: (28, 73, 89)  Bright orange
# 60411E -> HSV: (26, 68, 38)  Dark brown

def bgr_to_hsv(bgr_color):
    """Convert a single BGR color to HSV."""
    # Reshape color to what OpenCV expects
    pixel = np.uint8([[bgr_color]])
    # Convert to HSV
    hsv = cv2.cvtColor(pixel, cv2.COLOR_BGR2HSV)
    return hsv[0][0]

def hex_to_bgr(hex_color):
    """Convert hex color string to BGR."""
    # Remove '#' if present
    hex_color = hex_color.lstrip('#')
    # Convert to RGB then reverse for BGR
    rgb = tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))
    return (rgb[2], rgb[1], rgb[0])  # Reverse to BGR

def analyze_colors():
    """Analyze reference hex colors and print HSV values."""
    hex_colors = ['91511F', 'E3913E', '60411E']
    print("\nReference Color Analysis:")
    print("-" * 50)
    
    for hex_color in hex_colors:
        bgr = hex_to_bgr(hex_color)
        hsv = bgr_to_hsv(bgr)
        print(f"Hex: {hex_color}")
        print(f"BGR: {bgr}")
        print(f"HSV: {hsv}")
        print("-" * 50)
    
def sample_image_colors(image, points=None):
    """Sample colors at specific points in the image or on click."""
    if points is None:
        # If no points provided, set up mouse callback for clicking
        def mouse_callback(event, x, y, flags, param):
            if event == cv2.EVENT_LBUTTONDOWN:
                bgr_color = image[y, x]
                hsv_color = cv2.cvtColor(np.uint8([[bgr_color]]), cv2.COLOR_BGR2HSV)[0][0]
                print(f"\nClicked Position: ({x}, {y})")
                print(f"BGR: {bgr_color}")
                print(f"HSV: {hsv_color}")
        
        # Create window and set callback
        cv2.namedWindow('Click to sample colors')
        cv2.setMouseCallback('Click to sample colors', mouse_callback)
        
        # Show image and wait for clicks
        cv2.imshow('Click to sample colors', image)
        print("\nClick on the image to sample colors. Press 'q' to quit.")
        while True:
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        
        cv2.destroyAllWindows()
    else:
        # Sample at provided points
        print("\nSampling at provided points:")
        print("-" * 50)
        for x, y in points:
            if 0 <= y < image.shape[0] and 0 <= x < image.shape[1]:
                bgr_color = image[y, x]
                hsv_color = cv2.cvtColor(np.uint8([[bgr_color]]), cv2.COLOR_BGR2HSV)[0][0]
                print(f"Position: ({x}, {y})")
                print(f"BGR: {bgr_color}")
                print(f"HSV: {hsv_color}")
                print("-" * 50)

# Configuration parameters
PARAMS = {
    # HSV color range for orange detection - Based on sampled values
    'HSV_ORANGE_LOWER': np.array([10, 85, 110]),     # Slightly wider than observed to account for variation
    'HSV_ORANGE_UPPER': np.array([18, 210, 180]),    # Covers the full range we observed
    
    # Morphological operations
    'MORPH_KERNEL_SIZE': 7,
    'MORPH_ITERATIONS': 2,
    
    # Edge detection
    'CANNY_LOW_THRESHOLD': 30,
    'CANNY_HIGH_THRESHOLD': 90,
    
    # Hough Line Transform
    'HOUGH_RHO': 1,
    'HOUGH_THETA': np.pi/180,
    'HOUGH_THRESHOLD': 40,
    'HOUGH_MIN_LINE_LENGTH': 80,
    'HOUGH_MAX_LINE_GAP': 70,
    
    # Line filtering
    'MAX_ANGLE_DEVIATION': 10,
    'MIN_LINE_LENGTH': 80,
    
    # Visualization
    'LINE_COLORS': [
        (0, 0, 255),   # Red (BGR)
        (255, 0, 0),   # Blue (BGR)
        (0, 255, 0),   # Green (BGR)
    ],
    'LINE_THICKNESS': 3,
    'OVERLAY_ALPHA': 0.7,
    'LINE_EXTENSION': 50
}

def detect_orange_bars(image):
    """
    Detect orange bars in the image and return the top 3 candidates.
    
    Args:
        image: numpy array in BGR format
        
    Returns:
        tuple: (lines, orange_mask, edges) where:
            - lines is list of (x1, y1, x2, y2) coordinates
            - orange_mask is the binary mask of orange pixels
            - edges is the edge detection result
    """
    # Convert to HSV color space
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    
    # Create mask for orange color
    orange_mask = cv2.inRange(hsv, PARAMS['HSV_ORANGE_LOWER'], PARAMS['HSV_ORANGE_UPPER'])
    
    # Apply morphological operations to clean up the mask
    kernel = np.ones((PARAMS['MORPH_KERNEL_SIZE'], PARAMS['MORPH_KERNEL_SIZE']), np.uint8)
    
    # First do an opening to remove small noise
    orange_mask = cv2.morphologyEx(orange_mask, cv2.MORPH_OPEN, kernel, iterations=1)
    
    # Then do a closing to connect nearby regions
    orange_mask = cv2.morphologyEx(orange_mask, cv2.MORPH_CLOSE, kernel, 
                                 iterations=PARAMS['MORPH_ITERATIONS'])
    
    # Edge detection
    edges = cv2.Canny(orange_mask, PARAMS['CANNY_LOW_THRESHOLD'], PARAMS['CANNY_HIGH_THRESHOLD'])
    
    # Hough Line Transform
    lines = cv2.HoughLinesP(edges, PARAMS['HOUGH_RHO'], PARAMS['HOUGH_THETA'],
                           threshold=PARAMS['HOUGH_THRESHOLD'],
                           minLineLength=PARAMS['HOUGH_MIN_LINE_LENGTH'],
                           maxLineGap=PARAMS['HOUGH_MAX_LINE_GAP'])
    
    if lines is None:
        return [], orange_mask, edges
    
    # Process and filter lines
    filtered_lines = []
    for line in lines:
        x1, y1, x2, y2 = line[0]
        
        # Calculate line angle
        angle = abs(np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi)
        
        # Filter for nearly horizontal lines
        if angle < PARAMS['MAX_ANGLE_DEVIATION'] or angle > (180 - PARAMS['MAX_ANGLE_DEVIATION']):
            length = np.sqrt((x2 - x1)**2 + (y2 - y1)**2)
            if length >= PARAMS['MIN_LINE_LENGTH']:
                # Extend the line on both ends
                dx = x2 - x1
                dy = y2 - y1
                magnitude = np.sqrt(dx*dx + dy*dy)
                dx = dx / magnitude * PARAMS['LINE_EXTENSION']
                dy = dy / magnitude * PARAMS['LINE_EXTENSION']
                
                new_x1 = int(x1 - dx)
                new_y1 = int(y1 - dy)
                new_x2 = int(x2 + dx)
                new_y2 = int(y2 + dy)
                
                filtered_lines.append((length, (new_x1, new_y1, new_x2, new_y2)))
    
    # Sort by length and get top 3
    filtered_lines.sort(reverse=True, key=lambda x: x[0])
    return [line[1] for line in filtered_lines[:3]], orange_mask, edges

def create_visualization(image, lines):
    """Create an overlay showing detected lines."""
    # Create a separate overlay for the lines
    line_overlay = np.zeros_like(image)
    
    # Draw each line with different colors
    for i, line in enumerate(lines):
        if i >= len(PARAMS['LINE_COLORS']):
            break
            
        x1, y1, x2, y2 = line
        color = PARAMS['LINE_COLORS'][i]
        
        # Draw the main line
        cv2.line(line_overlay, (x1, y1), (x2, y2), color, PARAMS['LINE_THICKNESS'])
        
        # Draw circles at endpoints for better visibility
        cv2.circle(line_overlay, (x1, y1), PARAMS['LINE_THICKNESS'] * 2, color, -1)
        cv2.circle(line_overlay, (x2, y2), PARAMS['LINE_THICKNESS'] * 2, color, -1)
    
    # Blend the line overlay with the original image
    result = cv2.addWeighted(image, 1.0, line_overlay, PARAMS['OVERLAY_ALPHA'], 0)
    return result

def main():
    # First analyze reference colors
    analyze_colors()
    
    # Get input image path
    input_dir = Path('images/orange_bar')
    if not input_dir.exists():
        print(f"Error: Input directory {input_dir} does not exist")
        return
        
    # Process first image found in the directory
    image_files = list(input_dir.glob('*'))
    if not image_files:
        print(f"Error: No images found in {input_dir}")
        return
        
    input_path = image_files[0]
    print(f"\nProcessing image: {input_path}")
    
    # Read image
    image = cv2.imread(str(input_path))
    if image is None:
        print(f"Error: Could not read image {input_path}")
        return
    
    # Let user sample colors from the image
    print("\nLet's sample colors from the image to calibrate detection...")
    sample_image_colors(image)
    
    # After sampling, proceed with detection
    lines, orange_mask, edges = detect_orange_bars(image)
    
    if not lines:
        print("No orange bars detected!")
        return
    
    # Create visualization
    result = create_visualization(image, lines)
    
    # Save results
    output_base = input_path.parent / input_path.stem
    cv2.imwrite(str(output_base) + "_detected.jpg", result)
    cv2.imwrite(str(output_base) + "_orange_mask.jpg", orange_mask)
    cv2.imwrite(str(output_base) + "_edges.jpg", edges)
    
    print(f"\nOutput saved to:")
    print(f"  Main result: {output_base}_detected.jpg")
    print(f"  Orange mask: {output_base}_orange_mask.jpg")
    print(f"  Edge detection: {output_base}_edges.jpg")
    
    # Print detected lines info
    print("\nDetected Lines:")
    for i, line in enumerate(lines):
        x1, y1, x2, y2 = line
        length = np.sqrt((x2 - x1)**2 + (y2 - y1)**2)
        angle = np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi
        print(f"Line {i+1}:")
        print(f"  Start: ({x1}, {y1})")
        print(f"  End: ({x2}, {y2})")
        print(f"  Length: {length:.1f} pixels")
        print(f"  Angle: {angle:.1f} degrees")

if __name__ == "__main__":
    main() 