import numpy as np
import cv2
from pathlib import Path
import time

# Debug Configuration
PRINT_DEBUG_OUTPUT = False

# Tunable Parameters
WATERSHED_PARAMS = {
    'binary_threshold': 1,          # Threshold for creating binary image (0-255)
    'distance_weight': 0,           # Weight for distance transform (higher = more separation)
    'foreground_threshold': 0.55,    # Fraction of max distance to consider as foreground (0-1)
    'min_area': 500,               # Minimum area for a region to be considered a ball
    'visualization': {
        'circle_radius': 10,         # Radius of circles drawn at ball centers
        'circle_color': (139, 0, 0),  # Color of center points (BGR) - Dark Blue
        'circle_thickness': -1,     # Thickness of circles (-1 = filled)
        'text_scale': .5,           # Scale of text annotations
        'text_thickness': 2,        # Thickness of text
        'text_color': (255, 255, 0)  # Color of text (BGR)
    }
}

class BallDetector:
    def __init__(self, params=None):
        self.params = params or WATERSHED_PARAMS
        
    @classmethod
    def with_debug(cls, params=None):
        """Create a BallDetector with debug output enabled."""
        global PRINT_DEBUG_OUTPUT
        PRINT_DEBUG_OUTPUT = True
        return cls(params)
        
    def enable_debug(self):
        """Enable debug output for this detector instance."""
        global PRINT_DEBUG_OUTPUT
        PRINT_DEBUG_OUTPUT = True
        
    def _calculate_resolution_scaled_params(self, image_shape):
        """
        Calculate parameters scaled to the image resolution.
        
        Args:
            image_shape: Tuple of (height, width) or (height, width, channels)
        
        Returns:
            Dictionary of scaled parameters
        """
        # Get image dimensions
        if len(image_shape) == 3:
            height, width = image_shape[:2]
        else:
            height, width = image_shape
            
        # Calculate scale factor relative to the original color map resolution
        # Using 5510x408 as the reference resolution (original color map size)
        standard_width = 5510
        standard_height = 408
        scale_factor = min(width / standard_width, height / standard_height)
        
        # Scale parameters based on resolution
        scaled_params = self.params.copy()
        
        # Scale area-based parameters
        scaled_params['min_area'] = max(10, int(self.params['min_area'] * scale_factor * scale_factor))
        
        # Always use 0 (precise) for distance_weight
        scaled_params['distance_weight'] = 0
        
        # Scale foreground_threshold: increase for small images
        scaled_params['foreground_threshold'] = self.params['foreground_threshold']
        if scale_factor < 0.5:
            scaled_params['foreground_threshold'] = min(0.9, self.params['foreground_threshold'] + 0.1)
        elif scale_factor > 2.0:
            scaled_params['foreground_threshold'] = max(0.1, self.params['foreground_threshold'] - 0.1)
        
        # Scale visualization parameters
        scaled_params['visualization'] = self.params['visualization'].copy()
        scaled_params['visualization']['circle_radius'] = max(3, int(self.params['visualization']['circle_radius'] * scale_factor))
        scaled_params['visualization']['text_scale'] = max(0.3, self.params['visualization']['text_scale'] * scale_factor)
        scaled_params['visualization']['text_thickness'] = max(1, int(self.params['visualization']['text_thickness'] * scale_factor))
        
        # Adjust binary threshold based on resolution
        # Lower resolution images might need a higher threshold
        if scale_factor < 0.5:
            scaled_params['binary_threshold'] = min(10, self.params['binary_threshold'] + 2)
        elif scale_factor > 2.0:
            scaled_params['binary_threshold'] = max(0, self.params['binary_threshold'] - 1)
        
        if PRINT_DEBUG_OUTPUT:
            print(f"Image resolution: {width}x{height}")
            print(f"Scale factor: {scale_factor:.3f}")
            print(f"Scaled min_area: {scaled_params['min_area']}")
            print(f"Scaled circle_radius: {scaled_params['visualization']['circle_radius']}")
            print(f"Scaled binary_threshold: {scaled_params['binary_threshold']}")
            print(f"Scaled distance_weight: {scaled_params['distance_weight']}")
            print(f"Scaled foreground_threshold: {scaled_params['foreground_threshold']}")
        
        return scaled_params
        
    def detect_balls(self, color_map):
        """Watershed-based ball detection with resolution-adaptive parameters"""
        if PRINT_DEBUG_OUTPUT:
            print("\nBall Detection Debug:")
            print(f"Input array shape: {color_map.shape}")
            print(f"Input array dtype: {color_map.dtype}")
            print(f"Input array range: min={color_map.min()}, max={color_map.max()}")
            print(f"Input array unique values: {np.unique(color_map)}")
        
        # Calculate resolution-appropriate parameters
        scaled_params = self._calculate_resolution_scaled_params(color_map.shape)
        
        # Convert to grayscale if needed
        if len(color_map.shape) == 3:
            if PRINT_DEBUG_OUTPUT:
                print("Converting from BGR to grayscale")
            gray = cv2.cvtColor(color_map, cv2.COLOR_BGR2GRAY)
        else:
            if PRINT_DEBUG_OUTPUT:
                print("Input is already grayscale")
            gray = color_map
            
        # Create markers using distance transform
        if PRINT_DEBUG_OUTPUT:
            print("\nThresholding with value:", scaled_params['binary_threshold'])
        _, binary = cv2.threshold(gray, scaled_params['binary_threshold'], 255, cv2.THRESH_BINARY)
        if PRINT_DEBUG_OUTPUT:
            print(f"Binary image unique values: {np.unique(binary)}")
            print(f"Non-zero pixels in binary: {cv2.countNonZero(binary)}")
        
        dist_transform = cv2.distanceTransform(binary, cv2.DIST_L2, scaled_params['distance_weight'])
        if PRINT_DEBUG_OUTPUT:
            print(f"\nDistance transform range: min={dist_transform.min()}, max={dist_transform.max()}")
        
        # Create foreground markers
        fg_threshold = scaled_params['foreground_threshold'] * dist_transform.max()
        if PRINT_DEBUG_OUTPUT:
            print(f"Foreground threshold: {fg_threshold}")
        _, sure_fg = cv2.threshold(dist_transform, fg_threshold, 255, 0)
        sure_fg = np.uint8(sure_fg)
        if PRINT_DEBUG_OUTPUT:
            print(f"Foreground markers unique values: {np.unique(sure_fg)}")
        
        # Find markers for watershed
        if PRINT_DEBUG_OUTPUT:
            print("\nFinding connected components...")
        _, markers = cv2.connectedComponents(sure_fg)
        if PRINT_DEBUG_OUTPUT:
            print(f"Number of components found: {markers.max()}")
        markers = markers + 1
        markers[binary == 0] = 0
        
        # Apply watershed
        if PRINT_DEBUG_OUTPUT:
            print("\nApplying watershed...")
        markers = cv2.watershed(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR), markers)
        if PRINT_DEBUG_OUTPUT:
            print(f"Watershed markers range: min={markers.min()}, max={markers.max()}")
        
        # Find and filter ball centers
        centers = []
        viz = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
        
        if PRINT_DEBUG_OUTPUT:
            print("\nFiltering regions...")
        for label in range(2, markers.max() + 1):
            mask = np.uint8(markers == label)
            area = cv2.countNonZero(mask)
            if PRINT_DEBUG_OUTPUT:
                print(f"Region {label} area: {area}")
            
            if area >= scaled_params['min_area']:
                M = cv2.moments(mask)
                if M["m00"] != 0:
                    cx = int(M["m10"] / M["m00"])
                    cy = int(M["m01"] / M["m00"])
                    centers.append((cx, cy))
                    if PRINT_DEBUG_OUTPUT:
                        print(f"Found ball at ({cx}, {cy})")
                    
                    # Draw visualization
                    cv = scaled_params['visualization']
                    cv2.circle(viz, (cx, cy), cv['circle_radius'], 
                             cv['circle_color'], cv['circle_thickness'])
        
        # Add count to visualization
        cv = scaled_params['visualization']
        cv2.putText(viz, f"Balls: {len(centers)}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, cv['text_scale'], 
                    cv['text_color'], cv['text_thickness'])

        # Add timestamp to visualization
        cv2.putText(viz, f"Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}", (10, 60),
                    cv2.FONT_HERSHEY_SIMPLEX, cv['text_scale'], 
                    cv['text_color'], cv['text_thickness'])
        
        # Add resolution info to visualization
        cv2.putText(viz, f"Res: {color_map.shape[1]}x{color_map.shape[0]}", (10, 90),
                    cv2.FONT_HERSHEY_SIMPLEX, cv['text_scale'], 
                    cv['text_color'], cv['text_thickness'])
        
        if PRINT_DEBUG_OUTPUT:
            print(f"\nTotal balls found: {len(centers)}")
        return centers, viz

def process_images():
    detector = BallDetector()
    input_dir = Path("images/ball_detector/input")
    output_dir = Path("images/ball_detector/output")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Process each image
    for img_path in input_dir.glob("*.png"):
        print(f"Processing {img_path.name}")
        
        # Read image
        color_map = cv2.imread(str(img_path), cv2.IMREAD_GRAYSCALE)
        if color_map is None:
            print(f"Failed to read {img_path}")
            continue
        
        # Detect balls
        start_time = time.time()
        centers, viz = detector.detect_balls(color_map)
        processing_time = time.time() - start_time
        
        # Save results
        output_path = output_dir / f"{img_path.stem}_detected.png"
        cv2.imwrite(str(output_path), viz)
        
        print(f"Found {len(centers)} balls in {processing_time:.3f}s")
        print(f"Results saved to {output_path}")

if __name__ == "__main__":
    process_images() 