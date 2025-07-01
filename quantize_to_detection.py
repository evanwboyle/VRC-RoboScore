import os
import numpy as np
from PIL import Image
import colorsys
import cv2
import argparse
from image_scaler import ImageScaler
from color_mapper import (process_tape_regions, analyze_white_tape, 
                        create_white_map_with_tape_analysis, is_color_close,
                        RED_THRESHOLD, BLUE_THRESHOLD, WHITE_THRESHOLD, COLORS, main as color_mapper_main,
                        PRINT_DEBUG_OUTPUT as COLOR_MAPPER_DEBUG)
from new_detection import BallDetector
import re

SCALE_FACTOR = 0.25

# Set debug flags
PRINT_DEBUG_OUTPUT = False

class ImageProcessor:
    def __init__(self, scale_factor=None, enable_scaling=True):
        """
        Initialize the image processor with a scale factor.
        
        Args:
            scale_factor (float): Scale factor for image resizing (e.g., 0.25 for 1/4 size)
            enable_scaling (bool): Whether to enable image scaling
        """
        self.scale_factor = scale_factor
        self.enable_scaling = enable_scaling
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        self.input_dir = os.path.join(self.base_dir, "images", "input")
        self.scaled_dir = os.path.join(self.base_dir, "images", "output", "scaled")
        self.output_base_dir = os.path.join(self.base_dir, "images", "output")
        
        if enable_scaling and scale_factor is not None:
            self.scaler = ImageScaler(scale_factor)
            # Create output directories if they don't exist
            os.makedirs(self.scaled_dir, exist_ok=True)
        
        self.ball_detector = BallDetector()
    
    def process_directory(self):
        """Process all images in the input directory."""
        if not os.path.exists(self.input_dir):
            print(f"Error: Input directory {self.input_dir} does not exist!")
            return
        
        # Process each image in the input directory
        image_count = 0
        print("\nStarting image processing...")
        
        for filename in os.listdir(self.input_dir):
            if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                print(f"\n{'='*50}")
                print(f"Processing image: {filename}")
                print(f"{'='*50}")
                
                input_path = os.path.join(self.input_dir, filename)
                
                try:
                    if self.enable_scaling:
                        # Step 1: Scale the image
                        print("\nStep 1: Scaling image...")
                        scaled_path = os.path.join(self.scaled_dir, filename)
                        self.scaler.scale_image(input_path, scaled_path)
                        process_path = scaled_path
                    else:
                        # Skip scaling, use original image
                        print("\nStep 1: Skipping scaling (using original image)...")
                        process_path = input_path
                    
                    # Step 2: Process the image with color mapping
                    print("\nStep 2: Processing color maps...")
                    self.process_color_maps(process_path, filename)
                    
                    # Step 3: Detect balls in the color maps
                    print("\nStep 3: Detecting balls...")
                    self.detect_balls(filename)
                    
                    image_count += 1
                    print(f"\nSuccessfully processed {filename}")
                    
                except Exception as e:
                    print(f"Error processing {filename}: {str(e)}")
        
        print(f"\n{'='*50}")
        print(f"Processing complete! Successfully processed {image_count} images.")
        if self.enable_scaling:
            print(f"Scaled images are saved in: {self.scaled_dir}")
        print(f"Color maps and ball detection results are saved in individual directories under: {self.output_base_dir}")
        print(f"{'='*50}\n")
    
    def process_color_maps(self, image_path, filename):
        """
        Process color maps for a single image and store the arrays.
        
        Args:
            image_path: Path to the scaled image
            filename: Original filename for output organization
        """
        # Create output directory for this image
        base_name = os.path.splitext(filename)[0]
        image_output_dir = os.path.join(self.output_base_dir, base_name)
        os.makedirs(image_output_dir, exist_ok=True)
        
        # Open and process image
        img = Image.open(image_path).convert('RGB')
        width = img.width
        height = img.height
        pixels = np.array(img)
        
        print(f"\nProcessing color maps for {filename}")
        print(f"Image size: {width}x{height}")
        
        # Initialize count arrays for each color
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
            
            # Show progress every 100 columns (only if debug is enabled)
            if PRINT_DEBUG_OUTPUT and x % 100 == 0:
                print(f"Column {x}/{width}: Red={red_count}, Blue={blue_count}, White={white_count}")
        
        # Find maximum height needed
        max_height = max(max(red_counts), max(blue_counts), max(white_counts))
        if max_height == 0:
            print("No color pixels found in the image!")
            return
        
        print(f"\nMaximum counts - Red: {max(red_counts)}, Blue: {max(blue_counts)}, White: {max(white_counts)}")
        
        # Get tape positions
        tape_edges = analyze_white_tape(white_counts, width, max_height)
        print(f"Detected tape edges: Left={tape_edges[0]}, Right={tape_edges[1]}")
        
        # Create and save white map
        white_map = create_white_map_with_tape_analysis(white_counts, width, max_height)
        white_map.save(os.path.join(image_output_dir, "white_map.png"))
        print("Saved white map")
        
        # Process red and blue maps
        # Store arrays for later use
        self.red_array = process_tape_regions(red_counts, width, max_height, COLORS['RED'], tape_edges, for_export=True)
        self.blue_array = process_tape_regions(blue_counts, width, max_height, COLORS['BLUE'], tape_edges, for_export=True)
        
        # Save visualization maps
        red_map_viz = process_tape_regions(red_counts, width, max_height, COLORS['RED'], tape_edges)
        blue_map_viz = process_tape_regions(blue_counts, width, max_height, COLORS['BLUE'], tape_edges)
        
        red_map_viz.save(os.path.join(image_output_dir, "red_map.png"))
        blue_map_viz.save(os.path.join(image_output_dir, "blue_map.png"))
        print("Saved color maps")
        
        # Save arrays for later use
        np.save(os.path.join(image_output_dir, "red_array.npy"), self.red_array)
        np.save(os.path.join(image_output_dir, "blue_array.npy"), self.blue_array)
        print("Saved array data")
        
        print(f"Color maps and arrays saved to: {image_output_dir}")

    def detect_balls(self, filename):
        """
        Detect balls in the red and blue arrays.
        
        Args:
            filename: Original filename for output organization
        """
        base_name = os.path.splitext(filename)[0]
        image_output_dir = os.path.join(self.output_base_dir, base_name)
        
        # Debug info about raw arrays
        print(f"\nRaw array statistics:")
        print(f"Red array shape: {self.red_array.shape}")
        print(f"Red array - Min: {self.red_array.min()}, Max: {self.red_array.max()}, Unique values: {np.unique(self.red_array)}")
        print(f"Blue array shape: {self.blue_array.shape}")
        print(f"Blue array - Min: {self.blue_array.min()}, Max: {self.blue_array.max()}, Unique values: {np.unique(self.blue_array)}")
        
        # Convert arrays to uint8 format (0-255) and ensure proper orientation
        red_map = self.red_array.astype(np.uint8) * 255
        blue_map = self.blue_array.astype(np.uint8) * 255
        
        # Debug info about processed arrays
        print(f"\nProcessed array statistics:")
        print(f"Red map - Min: {red_map.min()}, Max: {red_map.max()}, Unique values: {np.unique(red_map)}")
        print(f"Blue map - Min: {blue_map.min()}, Max: {blue_map.max()}, Unique values: {np.unique(blue_map)}")
        
        try:
            # Detect balls in red map
            print("\nDetecting red balls...")
            if red_map.max() > 0:
                red_centers, red_viz = self.ball_detector.detect_balls(red_map)
                print(f"Found {len(red_centers)} red balls")
                cv2.imwrite(os.path.join(image_output_dir, "red_balls_detected.png"), red_viz)
            else:
                print("No red balls to detect")
                red_centers = []
                red_viz = np.zeros((red_map.shape[0], red_map.shape[1], 3), dtype=np.uint8)
            
            # Detect balls in blue map
            print("\nDetecting blue balls...")
            if blue_map.max() > 0:
                blue_centers, blue_viz = self.ball_detector.detect_balls(blue_map)
                print(f"Found {len(blue_centers)} blue balls")
                cv2.imwrite(os.path.join(image_output_dir, "blue_balls_detected.png"), blue_viz)
            else:
                print("No blue balls to detect")
                blue_centers = []
                blue_viz = np.zeros((blue_map.shape[0], blue_map.shape[1], 3), dtype=np.uint8)
            
            # Create combined visualization
            combined_viz = np.zeros_like(red_viz)
            
            # Add red balls
            if red_map.max() > 0:
                red_mask = cv2.threshold(red_map, 1, 255, cv2.THRESH_BINARY)[1]
                combined_viz[red_mask > 0] = [0, 0, 255]  # BGR format: Red
            
            # Add blue balls
            if blue_map.max() > 0:
                blue_mask = cv2.threshold(blue_map, 1, 255, cv2.THRESH_BINARY)[1]
                combined_viz[blue_mask > 0] = [255, 0, 0]  # BGR format: Blue
            
            # Draw all detected balls on combined visualization
            for cx, cy in red_centers:
                cv2.circle(combined_viz, (cx, cy), 15, (0, 255, 255), -1)  # Yellow circle for red balls
            for cx, cy in blue_centers:
                cv2.circle(combined_viz, (cx, cy), 15, (0, 255, 0), -1)  # Green circle for blue balls
            
            # Add total count to combined visualization
            cv2.putText(combined_viz, f"Red: {len(red_centers)}, Blue: {len(blue_centers)}", 
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            
            cv2.imwrite(os.path.join(image_output_dir, "all_balls_detected.png"), combined_viz)
            print(f"\nBall detection visualizations saved to: {image_output_dir}")
            
            # Store the centers for later use
            self.red_centers = red_centers
            self.blue_centers = blue_centers
            
        except Exception as e:
            print(f"Error during ball detection: {str(e)}")
            print("Debug info:")
            print(f"Red map shape: {red_map.shape}")
            print(f"Blue map shape: {blue_map.shape}")
            raise

def parse_expected_counts(filename):
    """Parse expected ball counts from filename format XB_YR."""
    pattern = r'(\d+)B_(\d+)R'
    match = re.match(pattern, filename)
    if match:
        blue_expected = int(match.group(1))
        red_expected = int(match.group(2))
        return blue_expected, red_expected
    return None, None

def process_image(input_path, output_dir, enable_scaling=True, scale_factor=SCALE_FACTOR):
    """Process a single image through the entire pipeline."""
    filename = os.path.basename(input_path)
    blue_expected, red_expected = parse_expected_counts(os.path.splitext(filename)[0])
    
    print(f"\n{'='*50}")
    print(f"Processing image: {filename}")
    if blue_expected is not None:
        print(f"Expected counts - Blue: {blue_expected}, Red: {red_expected}")
    print(f"{'='*50}")
    
    # Step 1: Scale the image (if enabled)
    if enable_scaling:
        print("\nStep 1: Scaling Image")
        print("-"*20)
        scaled_dir = os.path.join(output_dir, "scaled")
        os.makedirs(scaled_dir, exist_ok=True)
        scaled_path = os.path.join(scaled_dir, filename)
        
        scaler = ImageScaler(scale_factor)
        scaler.scale_image(input_path, scaled_path)
        process_path = scaled_path
    else:
        print("\nStep 1: Skipping scaling (using original image)")
        print("-"*20)
        process_path = input_path
    
    # Step 2: Generate color maps
    print("\nStep 2: Generating Color Maps")
    print("-"*20)
    base_name = os.path.splitext(filename)[0]
    image_output_dir = os.path.join(output_dir, base_name)
    os.makedirs(image_output_dir, exist_ok=True)
    
    # Process the image
    img = Image.open(process_path).convert('RGB')
    width = img.width
    height = img.height
    pixels = np.array(img)
    
    # Initialize count arrays
    red_counts = []
    blue_counts = []
    white_counts = []
    
    # Process each column
    RED = COLORS['RED']
    BLUE = COLORS['BLUE']
    WHITE = COLORS['WHITE']
    
    for x in range(width):
        column = pixels[:, x]
        red_count = sum(1 for pixel in column if is_color_close(pixel, RED))
        blue_count = sum(1 for pixel in column if is_color_close(pixel, BLUE))
        white_count = sum(1 for pixel in column if is_color_close(pixel, WHITE))
        
        red_counts.append(red_count)
        blue_counts.append(blue_count)
        white_counts.append(white_count)
    
    # Find maximum height needed
    max_height = max(max(red_counts), max(blue_counts), max(white_counts))
    if max_height == 0:
        print("No color pixels found in the image!")
        return
    
    # Get tape positions
    tape_edges = analyze_white_tape(white_counts, width, max_height)
    
    # Generate arrays directly
    red_array = process_tape_regions(red_counts, width, max_height, RED, tape_edges, for_export=True)
    blue_array = process_tape_regions(blue_counts, width, max_height, BLUE, tape_edges, for_export=True)
    
    # Create and save white map for visualization
    white_map = create_white_map_with_tape_analysis(white_counts, width, max_height)
    white_map.save(os.path.join(image_output_dir, "white_map.png"))
    
    if PRINT_DEBUG_OUTPUT:
        print(f"Red array shape: {red_array.shape}")
        print(f"Blue array shape: {blue_array.shape}")
        print(f"Red array range: min={red_array.min()}, max={red_array.max()}")
        print(f"Blue array range: min={blue_array.min()}, max={blue_array.max()}")
    
    # Step 3: Detect balls
    print("\nStep 3: Detecting Balls")
    print("-"*20)
    detector = BallDetector()
    
    # Process red balls
    print("\nProcessing red balls:")
    # Convert array to uint8 format (0-255) for ball detection
    red_array_uint8 = red_array.astype(np.uint8) * 255
    red_centers, red_viz = detector.detect_balls(red_array_uint8)
    cv2.imwrite(os.path.join(image_output_dir, "red_balls_detected.png"), red_viz)
    print(f"Found {len(red_centers)} red balls")
    if red_expected is not None:
        diff = len(red_centers) - red_expected
        print(f"Expected: {red_expected}, Difference: {diff:+d}")
        if diff != 0:
            print("WARNING: Red ball count mismatch!")
    
    # Process blue balls
    print("\nProcessing blue balls:")
    # Convert array to uint8 format (0-255) for ball detection
    blue_array_uint8 = blue_array.astype(np.uint8) * 255
    blue_centers, blue_viz = detector.detect_balls(blue_array_uint8)
    cv2.imwrite(os.path.join(image_output_dir, "blue_balls_detected.png"), blue_viz)
    print(f"Found {len(blue_centers)} blue balls")
    if blue_expected is not None:
        diff = len(blue_centers) - blue_expected
        print(f"Expected: {blue_expected}, Difference: {diff:+d}")
        if diff != 0:
            print("WARNING: Blue ball count mismatch!")
    
    # Create combined visualization
    combined_viz = cv2.imread(os.path.join(image_output_dir, "white_map.png"))
    if combined_viz is None:
        combined_viz = np.zeros((red_array.shape[0], red_array.shape[1], 3), dtype=np.uint8)
    
    # Draw all balls on combined visualization
    for cx, cy in red_centers:
        cv2.circle(combined_viz, (cx, cy), 15, (0, 0, 255), -1)  # Red
    for cx, cy in blue_centers:
        cv2.circle(combined_viz, (cx, cy), 15, (255, 0, 0), -1)  # Blue
        
    # Add total count and accuracy info
    total_balls = len(red_centers) + len(blue_centers)
    y_offset = 30
    cv2.putText(combined_viz, f"Total Balls: {total_balls}", (10, y_offset),
                cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    
    y_offset += 30
    cv2.putText(combined_viz, f"Red: {len(red_centers)}/{red_expected if red_expected is not None else '?'}", 
                (10, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
    
    y_offset += 30
    cv2.putText(combined_viz, f"Blue: {len(blue_centers)}/{blue_expected if blue_expected is not None else '?'}", 
                (10, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 0, 0), 2)
    
    if red_expected is not None and blue_expected is not None:
        total_expected = red_expected + blue_expected
        total_diff = total_balls - total_expected
        y_offset += 30
        color = (0, 255, 0) if total_diff == 0 else (0, 0, 255)  # Green if correct, red if mismatch
        cv2.putText(combined_viz, f"Accuracy: {total_diff:+d}", 
                    (10, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 1, color, 2)
    
    cv2.imwrite(os.path.join(image_output_dir, "all_balls_detected.png"), combined_viz)
    
    # Print summary
    print(f"\nDetection Summary for {filename}:")
    print(f"{'='*30}")
    print(f"Red Balls  - Found: {len(red_centers)}, Expected: {red_expected if red_expected is not None else 'unknown'}")
    print(f"Blue Balls - Found: {len(blue_centers)}, Expected: {blue_expected if blue_expected is not None else 'unknown'}")
    if red_expected is not None and blue_expected is not None:
        total_expected = red_expected + blue_expected
        accuracy = (total_balls - abs(total_diff)) / total_expected * 100 if total_expected > 0 else 0
        print(f"Total     - Found: {total_balls}, Expected: {total_expected}")
        print(f"Accuracy  - {accuracy:.1f}%")

def main():
    parser = argparse.ArgumentParser(description="Process images and detect balls.")
    parser.add_argument("-i", "--input", type=str, help="Input directory containing images")
    parser.add_argument("-o", "--output", type=str, help="Output directory for results")
    parser.add_argument("-s", "--scale", type=float, default=SCALE_FACTOR, help="Scale factor for image resizing")
    parser.add_argument("--no-scaling", action="store_true", help="Disable image scaling (use original image size)")
    args = parser.parse_args()

    input_dir = args.input or "images/input"
    output_dir = args.output or "images/output"
    enable_scaling = not args.no_scaling
    scale_factor = args.scale
    
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"Processing configuration:")
    print(f"  Input directory: {input_dir}")
    print(f"  Output directory: {output_dir}")
    print(f"  Scaling enabled: {enable_scaling}")
    if enable_scaling:
        print(f"  Scale factor: {scale_factor}")
    
    # Process each image in input directory
    for filename in os.listdir(input_dir):
        if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            input_path = os.path.join(input_dir, filename)
            try:
                process_image(input_path, output_dir, enable_scaling, scale_factor)
            except Exception as e:
                print(f"Error processing {filename}: {str(e)}")
    
    print(f"\nProcessing complete!")
    print(f"Usage examples:")
    print(f"  python quantize_to_detection.py                    # Use default settings (scaling enabled)")
    print(f"  python quantize_to_detection.py --no-scaling       # Disable scaling")
    print(f"  python quantize_to_detection.py -s 0.5            # Use 0.5 scale factor")
    print(f"  python quantize_to_detection.py -i custom_input -o custom_output  # Custom directories")

if __name__ == "__main__":
    main()
