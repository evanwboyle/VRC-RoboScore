import UIKit

struct VRCColors {
    static let red = UIColor(red: 0xD6/255.0, green: 0x41/255.0, blue: 0x4F/255.0, alpha: 1.0)
    static let blue = UIColor(red: 0x4A/255.0, green: 0xAA/255.0, blue: 0xEE/255.0, alpha: 1.0)
    static let white = UIColor.white
    static let background = UIColor.black
    
    static let allColors = [red, blue, white, background]
}

extension UIColor {
    convenience init?(hex: String) {
        let r, g, b: CGFloat
        
        if hex.hasPrefix("#") {
            let start = hex.index(hex.startIndex, offsetBy: 1)
            let hexColor = String(hex[start...])
            
            if hexColor.count == 6 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0
                
                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
                    g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
                    b = CGFloat(hexNumber & 0x0000ff) / 255
                    
                    self.init(red: r, green: g, blue: b, alpha: 1)
                    return
                }
            }
        }
        
        return nil
    }
    
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
    
    func distance(to color: UIColor) -> CGFloat {
        let c1 = self.components
        let c2 = color.components
        
        let rDiff = c1.red - c2.red
        let gDiff = c1.green - c2.green
        let bDiff = c1.blue - c2.blue
        
        return sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff)
    }
}

class ColorQuantizer {
    static var redThreshold: CGFloat = 0.25
    static var blueThreshold: CGFloat = 0.25
    static var whiteThreshold: CGFloat = 0.26 // Updated threshold for white
    
    static func quantize(image: UIImage, redThreshold: CGFloat? = nil, blueThreshold: CGFloat? = nil, whiteThreshold: CGFloat? = nil) -> UIImage? {
        // Use provided thresholds or default values
        let redDist = redThreshold ?? self.redThreshold
        let blueDist = blueThreshold ?? self.blueThreshold
        let whiteDist = whiteThreshold ?? self.whiteThreshold
        
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixelData,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: width * 4,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Create output buffer
        var outputData = [UInt8](repeating: 0, count: width * height * 4)
        
        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0
                let a = CGFloat(pixelData[pixelIndex + 3]) / 255.0
                
                let pixelColor = UIColor(red: r, green: g, blue: b, alpha: a)
                
                // Find nearest color with threshold
                var nearestColor = VRCColors.background
                let redDistance = pixelColor.distance(to: VRCColors.red)
                let blueDistance = pixelColor.distance(to: VRCColors.blue)
                let whiteDistance = pixelColor.distance(to: VRCColors.white)
                
                if redDistance <= redDist && redDistance <= blueDistance && redDistance <= whiteDistance {
                    nearestColor = VRCColors.red
                } else if blueDistance <= blueDist && blueDistance <= redDistance && blueDistance <= whiteDistance {
                    nearestColor = VRCColors.blue
                } else if whiteDistance <= whiteDist {
                    nearestColor = VRCColors.white
                }
                
                let components = nearestColor.components
                outputData[pixelIndex] = UInt8(components.red * 255)
                outputData[pixelIndex + 1] = UInt8(components.green * 255)
                outputData[pixelIndex + 2] = UInt8(components.blue * 255)
                outputData[pixelIndex + 3] = UInt8(a * 255)
            }
        }
        
        // Create output image
        guard let outputContext = CGContext(data: &outputData,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outputCGImage = outputContext.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: outputCGImage)
    }
} 