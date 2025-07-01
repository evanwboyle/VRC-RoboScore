import numpy as np
import cv2
from pathlib import Path
import time

# Tunable Parameters
WATERSHED_PARAMS = {
    'binary_threshold': 1,          # Threshold for creating binary image (0-255)
    'distance_weight': 5,           # Weight for distance transform (higher = more separation)
    'foreground_threshold': 0.5,    # Fraction of max distance to consider as foreground (0-1)
    'min_area': 100,               # Minimum area for a region to be considered a ball
    'visualization': {
        'circle_radius': 5,         # Radius of circles drawn at ball centers
        'circle_color': (0, 255, 255),  # Color of center points (BGR)
        'circle_thickness': -1,     # Thickness of circles (-1 = filled)
        'text_scale': 1,           # Scale of text annotations
        'text_thickness': 2,        # Thickness of text
        'text_color': (255, 255, 255)  # Color of text (BGR)
    }
}

class BallDetector:
    def __init__(self, params=None):
        self.params = params or WATERSHED_PARAMS
        
    def detect_balls(self, color_map):
        """Watershed-based ball detection"""
        # Convert to grayscale if needed
        if len(color_map.shape) == 3:
            gray = cv2.cvtColor(color_map, cv2.COLOR_BGR2GRAY)
        else:
            gray = color_map
            
        # Create markers using distance transform
        _, binary = cv2.threshold(gray, self.params['binary_threshold'], 255, cv2.THRESH_BINARY)
        dist_transform = cv2.distanceTransform(binary, cv2.DIST_L2, self.params['distance_weight'])
        
        # Create foreground markers
        fg_threshold = self.params['foreground_threshold'] * dist_transform.max()
        _, sure_fg = cv2.threshold(dist_transform, fg_threshold, 255, 0)
        sure_fg = np.uint8(sure_fg)
        
        # Find markers for watershed
        _, markers = cv2.connectedComponents(sure_fg)
        markers = markers + 1
        markers[binary == 0] = 0
        
        # Apply watershed
        markers = cv2.watershed(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR), markers)
        
        # Find and filter ball centers
        centers = []
        viz = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
        
        for label in range(2, markers.max() + 1):
            mask = np.uint8(markers == label)
            area = cv2.countNonZero(mask)
            
            if area >= self.params['min_area']:
                M = cv2.moments(mask)
                if M["m00"] != 0:
                    cx = int(M["m10"] / M["m00"])
                    cy = int(M["m01"] / M["m00"])
                    centers.append((cx, cy))
                    
                    # Draw visualization
                    cv = self.params['visualization']
                    cv2.circle(viz, (cx, cy), cv['circle_radius'], 
                             cv['circle_color'], cv['circle_thickness'])
        
        # Add count to visualization
        cv = self.params['visualization']
        cv2.putText(viz, f"Balls: {len(centers)}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, cv['text_scale'], 
                    cv['text_color'], cv['text_thickness'])
        
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