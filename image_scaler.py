from PIL import Image
import os

# Debug Configuration
PRINT_DEBUG_OUTPUT = False

class ImageScaler:
    def __init__(self, scale_factor=0.25):
        """Initialize scaler with a scale factor."""
        self.scale_factor = scale_factor
        self.min_width = 1000

    def calculate_scale_factor(self, original_width):
        """Calculate the best integer divisor to achieve desired width."""
        # Start with scale factor of 1 (no scaling)
        scale_divisor = 1
        
        # Keep increasing divisor until width would be too small
        while (original_width / (scale_divisor + 1)) >= self.min_width:
            scale_divisor += 1
            
        return 1.0 / scale_divisor

    def scale_image(self, input_path, output_path):
        """Scale an image by the configured factor."""
        with Image.open(input_path) as img:
            # Get original size
            width, height = img.size
            if PRINT_DEBUG_OUTPUT:
                print(f"Processing {os.path.basename(input_path)}")
                print(f"Original size: {width}x{height}")
            
            # Calculate appropriate scale factor
            actual_scale = self.calculate_scale_factor(width)
            if PRINT_DEBUG_OUTPUT:
                print(f"Using scale factor: 1/{int(1/actual_scale)} (keeping width >= {self.min_width})")
            
            # Calculate new size
            new_width = int(width * actual_scale)
            new_height = int(height * actual_scale)
            
            # Resize image using nearest neighbor interpolation
            resized_img = img.resize((new_width, new_height), Image.Resampling.NEAREST)
            if PRINT_DEBUG_OUTPUT:
                print(f"New size: {new_width}x{new_height}")
            
            # Save resized image
            resized_img.save(output_path)
            if PRINT_DEBUG_OUTPUT:
                print(f"Saved scaled image to: {output_path}\n")

def main():
    # Example usage
    input_dir = "/Users/evanboyle/Downloads/colormaps"
    input_path = os.path.join(input_dir, "test_image.jpg")
    output_path = os.path.join(input_dir, "test_image_shrunk.jpg")
    
    # Scale down by 1/4
    scaler = ImageScaler(0.25)
    scaler.scale_image(input_path, output_path)

if __name__ == "__main__":
    main() 