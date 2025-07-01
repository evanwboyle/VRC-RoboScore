import numpy as np
from PIL import Image
import os
import colorsys
import cv2

# Debug Configuration
PRINT_DEBUG_OUTPUT = False

# Configuration Constants
# Original reference dimensions
REFERENCE_WIDTH = 5947  # Original width used for ratio calculations
REFERENCE_HEIGHT = 899  # Original height used for ratio calculations

# Debug and Output Configuration
SHOW_COLUMN_PROGRESS = False    # Whether to show progress every 100 columns
SAVE_OUTPUT_IMAGES = True    # Whether to save the output images

# Color Detection Thresholds
RED_THRESHOLD = {
    'min_red': 150,
    'max_green': 100,
    'max_blue': 100
}

BLUE_THRESHOLD = {
    'min_blue': 130,
    'max_red': 130,
    'max_green': 130,
    'hsv_hue_min': 0.55,
    'hsv_hue_max': 0.7,
    'hsv_saturation_min': 0.4
}

WHITE_THRESHOLD = {
    'min_rgb': 200  # Minimum value for R, G, and B channels
}

# Tape Detection Parameters
TAPE_SEARCH_REGIONS = {
    'left_start': 0.25,   # Percentage of width
    'left_end': 0.45,
    'right_start': 0.55,
    'right_end': 0.75,
    'height_threshold': 0.20  # Percentage of max height
}

# Visualization Colors (BGR for OpenCV, RGB for PIL)
COLORS = {
    'RED': (255, 0, 0),
    'BLUE': (0, 0, 255),
    'WHITE': (255, 255, 255),
    'NEON_YELLOW': (255, 255, 0),
    'PURPLE': (255, 0, 255),
    'GREEN': (0, 255, 0),
    'ORANGE': (255, 165, 0)
}

def rgb_to_hsv(r, g, b):
    """Convert RGB (0-255) to HSV (0-1)"""
    return colorsys.rgb_to_hsv(r/255.0, g/255.0, b/255.0)

def is_color_close(pixel, target_color, threshold=50):
    """Check if a pixel color is close to target color within threshold."""
    r, g, b = pixel
    
    # Convert to HSV
    h, s, v = rgb_to_hsv(r, g, b)
    
    if target_color == COLORS['RED']:  # Red
        return (r > RED_THRESHOLD['min_red'] and 
                g < RED_THRESHOLD['max_green'] and 
                b < RED_THRESHOLD['max_blue'])
    elif target_color == COLORS['BLUE']:  # Blue
        return ((b > BLUE_THRESHOLD['min_blue'] and 
                r < BLUE_THRESHOLD['max_red'] and 
                g < BLUE_THRESHOLD['max_green']) or 
                (BLUE_THRESHOLD['hsv_hue_min'] <= h <= BLUE_THRESHOLD['hsv_hue_max'] and 
                 s > BLUE_THRESHOLD['hsv_saturation_min']))
    elif target_color == COLORS['WHITE']:  # White
        return (r > WHITE_THRESHOLD['min_rgb'] and 
                g > WHITE_THRESHOLD['min_rgb'] and 
                b > WHITE_THRESHOLD['min_rgb'])
    
    return False

def analyze_white_tape(counts, width, max_height):
    """Analyze white tape positions and split them into left/right sections."""
    # Define search regions using configuration
    left_search_start = int(width * TAPE_SEARCH_REGIONS['left_start'])
    left_search_end = int(width * TAPE_SEARCH_REGIONS['left_end'])
    right_search_start = int(width * TAPE_SEARCH_REGIONS['right_start'])
    right_search_end = int(width * TAPE_SEARCH_REGIONS['right_end'])
    height_threshold = int(max_height * TAPE_SEARCH_REGIONS['height_threshold'])
    
    # Find peaks in left and right regions
    left_peak = max(range(left_search_start, left_search_end), 
                   key=lambda x: counts[x] if counts[x] > height_threshold else 0)
    right_peak = max(range(right_search_start, right_search_end), 
                    key=lambda x: counts[x] if counts[x] > height_threshold else 0)
    
    # Find tape edges
    def find_tape_edges(peak_pos):
        # Go left until height drops below threshold
        left_edge = peak_pos
        while left_edge > 0 and counts[left_edge] > height_threshold:
            left_edge -= 1
            
        # Go right until height drops below threshold
        right_edge = peak_pos
        while right_edge < width - 1 and counts[right_edge] > height_threshold:
            right_edge += 1
            
        return left_edge, right_edge
    
    left_tape_edges = find_tape_edges(left_peak)
    right_tape_edges = find_tape_edges(right_peak)
    
    return left_tape_edges, right_tape_edges

def create_white_map_with_tape_analysis(counts, width, max_height):
    """Create white map with analyzed tape sections."""
    # Create base image
    img = np.zeros((max_height, width, 3), dtype=np.uint8)
    
    # Draw original white pixels
    for x, count in enumerate(counts):
        if count > 0:
            start_y = max_height - count
            img[start_y:max_height, x] = (255, 255, 255)  # White
    
    # Analyze tape positions
    (left_tape_left, left_tape_right), (right_tape_left, right_tape_right) = analyze_white_tape(counts, width, max_height)
    
    # Color for tape sections
    ORANGE = (255, 165, 0)
    
    # Color entire left tape piece orange
    for x in range(left_tape_left, left_tape_right):
        if counts[x] > 0:
            start_y = max_height - counts[x]
            img[start_y:max_height, x] = ORANGE
            
    # Color entire right tape piece orange
    for x in range(right_tape_left, right_tape_right):
        if counts[x] > 0:
            start_y = max_height - counts[x]
            img[start_y:max_height, x] = ORANGE
    
    return Image.fromarray(img)

def create_color_map(column_counts, width, max_height, color):
    """Create a color map image for the given color counts."""
    # Create a black background image
    img = np.zeros((max_height, width, 3), dtype=np.uint8)
    
    # Fill in the color columns from bottom up
    for x, count in enumerate(column_counts):
        if count > 0:  # Only process if there are pixels of this color
            start_y = max_height - count
            img[start_y:max_height, x] = color
            
    return Image.fromarray(img)

def calculate_median_height(counts, start, end):
    """Calculate median height for a range of columns."""
    valid_heights = [count for count in counts[start:end] if count > 0]
    if not valid_heights:
        return 0
    return sorted(valid_heights)[len(valid_heights) // 2]

def process_tape_regions(counts, width, max_height, base_color, tape_edges, for_export=False):
    """Process tape regions with height approximation and visualization."""
    # Create base image
    img = np.zeros((max_height, width, 3), dtype=np.uint8)
    export_array = np.zeros((max_height, width), dtype=np.uint8)
    
    # First draw the original color map
    for x, count in enumerate(counts):
        if count > 0:  # Only process if there are pixels of this color
            start_y = max_height - count
            img[start_y:max_height, x] = base_color
            export_array[start_y:max_height, x] = 1
    
    GREEN = (0, 255, 0)
    WHITE = (255, 255, 255)
    
    left_tape_left, left_tape_right = tape_edges[0]
    right_tape_left, right_tape_right = tape_edges[1]
    
    # Calculate sample range proportional to image width (reference: 20 for 5510 width)
    sample_range = max(1, int(0.0036 * width))
    
    # Calculate left reference with configured range
    left_ref_start = max(0, left_tape_left - sample_range)
    left_ref_height = calculate_median_height(counts, left_ref_start, left_tape_left)
    
    # Calculate right reference with configured range
    left_right_end = min(width, left_tape_right + sample_range)
    left_right_height = calculate_median_height(counts, left_tape_right, left_right_end)
    
    # Draw green reference lines for left tape
    if left_ref_height > 0:
        ref_y = max_height - int(left_ref_height)
        for x in range(left_ref_start, left_tape_left):
            img[ref_y, x] = GREEN
    
    if left_right_height > 0:
        ref_y = max_height - int(left_right_height)
        for x in range(left_tape_right, left_right_end):
            img[ref_y, x] = GREEN
    
    # Process right tape piece
    # Calculate left reference with configured range
    right_ref_start = max(0, right_tape_left - sample_range)
    right_ref_height = calculate_median_height(counts, right_ref_start, right_tape_left)
    
    # Calculate right reference with configured range
    right_right_end = min(width, right_tape_right + sample_range)
    right_right_height = calculate_median_height(counts, right_tape_right, right_right_end)
    
    # Draw green reference lines for right tape
    if right_ref_height > 0:
        ref_y = max_height - int(right_ref_height)
        for x in range(right_ref_start, right_tape_left):
            img[ref_y, x] = GREEN
    
    if right_right_height > 0:
        ref_y = max_height - int(right_right_height)
        for x in range(right_tape_right, right_right_end):
            img[ref_y, x] = GREEN
    
    # Draw white trapezoid for left tape and store heights
    if left_ref_height > 0 and left_right_height > 0:
        for x in range(left_tape_left, left_tape_right):
            # Linear interpolation between left and right heights
            progress = (x - left_tape_left) / (left_tape_right - left_tape_left)
            height = int(left_ref_height + progress * (left_right_height - left_ref_height))
            start_y = max_height - height
            img[start_y:max_height, x] = WHITE
            export_array[start_y:max_height, x] = 1
    
    # Draw white trapezoid for right tape and store heights
    if right_ref_height > 0 and right_right_height > 0:
        for x in range(right_tape_left, right_tape_right):
            # Linear interpolation between left and right heights
            progress = (x - right_tape_left) / (right_tape_right - right_tape_left)
            height = int(right_ref_height + progress * (right_right_height - right_ref_height))
            start_y = max_height - height
            img[start_y:max_height, x] = WHITE
            export_array[start_y:max_height, x] = 1
    
    if for_export:
        return export_array
    return Image.fromarray(img)

def main():
    # Input and output paths
    input_dir = "images/ball_detector/input"
    output_dir = os.path.join(input_dir, "output")
    os.makedirs(output_dir, exist_ok=True)
    
    # Goal configuration
    goal_type = "long"  # can be "long" or "short"
    goal_position = "bottom"  # can be "bottom" or "top"
    
    # Create output directory if it doesn't exist
    if SAVE_OUTPUT_IMAGES:
        os.makedirs(output_dir, exist_ok=True)
    
    # Target colors (RGB)
    RED = (255, 0, 0)
    BLUE = (0, 0, 255)
    WHITE = (255, 255, 255)
    
    # Process each image in the input directory
    for filename in os.listdir(input_dir):
        if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            input_path = os.path.join(input_dir, filename)
            
            # Open and process image
            img = Image.open(input_path)
            img = img.convert('RGB')
            width = img.width
            height = img.height
            pixels = np.array(img)
            
            if PRINT_DEBUG_OUTPUT:
                print(f"Processing image of size {width}x{height}")
                print(f"Goal type: {goal_type}, Position: {goal_position}")
            
            # Initialize count arrays for each color
            red_counts = []
            blue_counts = []
            white_counts = []
            
            # Process each column
            for x in range(width):
                column = pixels[:, x]
                red_count = sum(1 for pixel in column if is_color_close(pixel, RED))
                blue_count = sum(1 for pixel in column if is_color_close(pixel, BLUE))
                white_count = sum(1 for pixel in column if is_color_close(pixel, WHITE))
                
                red_counts.append(red_count)
                blue_counts.append(blue_count)
                white_counts.append(white_count)
                
                # Print progress every 100 columns if enabled
                if SHOW_COLUMN_PROGRESS and x % 100 == 0 and PRINT_DEBUG_OUTPUT:
                    print(f"Column {x}: Red={red_count}, Blue={blue_count}, White={white_count}")
            
            # Find maximum height needed
            max_height = max(max(red_counts), max(blue_counts), max(white_counts))
            if max_height == 0:
                if PRINT_DEBUG_OUTPUT:
                    print("No color pixels found in the image!")
                continue
            
            if PRINT_DEBUG_OUTPUT:
                print(f"\nMaximum counts - Red: {max(red_counts)}, Blue: {max(blue_counts)}, White: {max(white_counts)}")
            
            # Create color maps
            if goal_type == "long":
                # Get tape positions first
                tape_edges = analyze_white_tape(white_counts, width, max_height)
                
                # Create white map with orange tape markers
                white_map = create_white_map_with_tape_analysis(white_counts, width, max_height)
                
                # Process red and blue maps with tape approximation
                red_map_viz = process_tape_regions(red_counts, width, max_height, RED, tape_edges)
                blue_map_viz = process_tape_regions(blue_counts, width, max_height, BLUE, tape_edges)
                
                # Create export arrays
                red_map_array = process_tape_regions(red_counts, width, max_height, RED, tape_edges, for_export=True)
                blue_map_array = process_tape_regions(blue_counts, width, max_height, BLUE, tape_edges, for_export=True)
                
                # Save the arrays for detection
                np.save(os.path.join(output_dir, f"{os.path.splitext(filename)[0]}_red_array.npy"), red_map_array)
                np.save(os.path.join(output_dir, f"{os.path.splitext(filename)[0]}_blue_array.npy"), blue_map_array)
            else:
                white_map = create_color_map(white_counts, width, max_height, WHITE)
                red_map_viz = create_color_map(red_counts, width, max_height, RED)
                blue_map_viz = create_color_map(blue_counts, width, max_height, BLUE)
            
            # Save the color maps if enabled
            if SAVE_OUTPUT_IMAGES:
                base_filename = os.path.splitext(filename)[0]
                white_map.save(os.path.join(output_dir, f"{base_filename}_white_map.png"))
                red_map_viz.save(os.path.join(output_dir, f"{base_filename}_red_map.png"))
                blue_map_viz.save(os.path.join(output_dir, f"{base_filename}_blue_map.png"))
                if PRINT_DEBUG_OUTPUT:
                    print(f"Color maps have been generated for {filename}")

if __name__ == "__main__":
    main()