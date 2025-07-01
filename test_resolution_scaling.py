#!/usr/bin/env python3
"""
Test script to demonstrate resolution-adaptive ball detection.
This script processes the same image at different scales using the actual
color mapping and detection pipeline.
"""

import os
import numpy as np
from PIL import Image
import cv2
from new_detection import BallDetector
from image_scaler import ImageScaler
from color_mapper import (process_tape_regions, analyze_white_tape, 
                        create_white_map_with_tape_analysis, is_color_close,
                        COLORS)

class CustomImageScaler:
    """Custom scaler without minimum width safeguard for testing."""
    def __init__(self, scale_factor=0.25):
        self.scale_factor = scale_factor
    
    def scale_image(self, input_path, output_path):
        """Scale an image by the exact scale factor."""
        with Image.open(input_path) as img:
            width, height = img.size
            new_width = int(width * self.scale_factor)
            new_height = int(height * self.scale_factor)
            
            print(f"Scaling from {width}x{height} to {new_width}x{new_height}")
            
            # Resize image using nearest neighbor interpolation
            resized_img = img.resize((new_width, new_height), Image.Resampling.NEAREST)
            resized_img.save(output_path)

def test_resolution_scaling():
    """Test ball detection at different resolutions using actual color mapping."""
    
    # Test image
    input_image = "images/input/10B_0R.JPG"
    if not os.path.exists(input_image):
        print(f"Test image not found: {input_image}")
        return
    
    # Create test directory
    test_dir = "images/resolution_test"
    os.makedirs(test_dir, exist_ok=True)
    
    # Different scale factors to test
    scale_factors = [1.0, 0.5, 0.25, 0.1]  # Full size, half, quarter, tenth
    
    print("Testing ball detection at different resolutions...")
    print("=" * 60)
    
    for scale_factor in scale_factors:
        print(f"\nTesting scale factor: {scale_factor}")
        print("-" * 30)
        
        # Scale the image using custom scaler
        scaler = CustomImageScaler(scale_factor)
        scaled_path = os.path.join(test_dir, f"scaled_{scale_factor:.2f}.jpg")
        scaler.scale_image(input_image, scaled_path)
        
        # Get the scaled image dimensions
        with Image.open(scaled_path) as img:
            width, height = img.size
            print(f"Scaled image size: {width}x{height}")
        
        # Process the scaled image with color mapping (same as quantize_to_detection.py)
        img = Image.open(scaled_path).convert('RGB')
        pixels = np.array(img)
        
        # Initialize count arrays
        red_counts = []
        blue_counts = []
        white_counts = []
        
        # Process each column
        for x in range(width):
            column = pixels[:, x]
            red_count = sum(1 for pixel in column if is_color_close(pixel, COLORS['RED']))
            blue_count = sum(1 for pixel in column if is_color_close(pixel, COLORS['BLUE']))
            white_count = sum(1 for pixel in column if is_color_close(pixel, COLORS['WHITE']))
            
            red_counts.append(red_count)
            blue_counts.append(blue_count)
            white_counts.append(white_count)
        
        # Find maximum height needed
        max_height = max(max(red_counts), max(blue_counts), max(white_counts))
        if max_height == 0:
            print("No color pixels found in the image!")
            continue
        
        # Get tape positions
        tape_edges = analyze_white_tape(white_counts, width, max_height)
        
        # Generate arrays for ball detection
        red_array = process_tape_regions(red_counts, width, max_height, COLORS['RED'], tape_edges, for_export=True)
        blue_array = process_tape_regions(blue_counts, width, max_height, COLORS['BLUE'], tape_edges, for_export=True)
        
        print(f"Color map dimensions - Red: {red_array.shape}, Blue: {blue_array.shape}")
        
        # Detect balls with resolution-adaptive parameters
        detector = BallDetector()
        
        # Process red balls
        print("\nProcessing red balls:")
        red_array_uint8 = red_array.astype(np.uint8) * 255
        red_centers, red_viz = detector.detect_balls(red_array_uint8)
        red_output_path = os.path.join(test_dir, f"red_detected_{scale_factor:.2f}.png")
        cv2.imwrite(red_output_path, red_viz)
        print(f"Found {len(red_centers)} red balls")
        
        # Process blue balls
        print("Processing blue balls:")
        blue_array_uint8 = blue_array.astype(np.uint8) * 255
        blue_centers, blue_viz = detector.detect_balls(blue_array_uint8)
        blue_output_path = os.path.join(test_dir, f"blue_detected_{scale_factor:.2f}.png")
        cv2.imwrite(blue_output_path, blue_viz)
        print(f"Found {len(blue_centers)} blue balls")
        
        # Create combined visualization
        combined_viz = np.zeros((red_array.shape[0], red_array.shape[1], 3), dtype=np.uint8)
        
        # Add red balls
        if red_array.max() > 0:
            red_mask = cv2.threshold(red_array_uint8, 1, 255, cv2.THRESH_BINARY)[1]
            combined_viz[red_mask > 0] = [0, 0, 255]  # BGR format: Red
        
        # Add blue balls
        if blue_array.max() > 0:
            blue_mask = cv2.threshold(blue_array_uint8, 1, 255, cv2.THRESH_BINARY)[1]
            combined_viz[blue_mask > 0] = [255, 0, 0]  # BGR format: Blue
        
        # Draw detected centers
        for cx, cy in red_centers:
            cv2.circle(combined_viz, (cx, cy), 15, (0, 255, 255), -1)  # Yellow for red balls
        for cx, cy in blue_centers:
            cv2.circle(combined_viz, (cx, cy), 15, (0, 255, 0), -1)  # Green for blue balls
        
        # Add count info
        cv2.putText(combined_viz, f"Red: {len(red_centers)}, Blue: {len(blue_centers)}", 
                    (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        cv2.putText(combined_viz, f"Scale: {scale_factor:.2f}", 
                    (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
        
        combined_output_path = os.path.join(test_dir, f"combined_{scale_factor:.2f}.png")
        cv2.imwrite(combined_output_path, combined_viz)
        
        print(f"Total balls detected: {len(red_centers) + len(blue_centers)}")
        print(f"Results saved to: {test_dir}")
        
        # Show parameter scaling info (enable debug for last run)
        if scale_factor == scale_factors[-1]:
            print("\nParameter scaling debug info:")
            detector.enable_debug()
            detector.detect_balls(red_array_uint8)
    
    print(f"\nAll test results saved to: {test_dir}")
    print("Check the output images to see how detection improves with resolution scaling!")

if __name__ == "__main__":
    test_resolution_scaling() 