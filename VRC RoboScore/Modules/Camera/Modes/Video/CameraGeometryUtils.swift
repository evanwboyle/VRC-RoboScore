import UIKit
import AVFoundation

class BoundingBoxDrawer {
    static func drawBox(on overlayView: UIView, previewLayer: AVCaptureVideoPreviewLayer, rect: [Double], imageSize: CGSize, color: UIColor, borderWidth: CGFloat, label: String, labelColor: UIColor, labelWidth: CGFloat = 60, labelHeight: CGFloat = 20, labelFontSize: CGFloat = 14) -> CAShapeLayer? {
        guard rect.count >= 4 else { return nil }
        let x1 = CGFloat(rect[0])
        let y1 = CGFloat(rect[1])
        let x2 = CGFloat(rect[2])
        let y2 = CGFloat(rect[3])
        let width = x2 - x1
        let height = y2 - y1
        let normX = x1 / imageSize.width
        let normY = y1 / imageSize.height
        let normWidth = width / imageSize.width
        let normHeight = height / imageSize.height
        let normalizedRect = CGRect(x: normX, y: normY, width: normWidth, height: normHeight)
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
        let boxLayer = CAShapeLayer()
        boxLayer.frame = convertedRect
        boxLayer.borderColor = color.cgColor
        boxLayer.borderWidth = borderWidth
        boxLayer.cornerRadius = 6
        boxLayer.masksToBounds = true
        let idLabel = CATextLayer()
        idLabel.string = label
        idLabel.fontSize = labelFontSize
        idLabel.foregroundColor = labelColor.cgColor
        idLabel.frame = CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight)
        boxLayer.addSublayer(idLabel)
        overlayView.layer.addSublayer(boxLayer)
        return boxLayer
    }
}

struct CameraGeometryUtils {
    static func drawPolygon(vertices: [CGPoint], color: UIColor, lineWidth: CGFloat = 3.0, imageSize: CGSize, overlayView: UIView, previewLayer: AVCaptureVideoPreviewLayer, boundingBoxLayers: inout [CAShapeLayer]) {
        guard vertices.count == 4 else { return }
        let path = UIBezierPath()
        path.move(to: convertPoint(vertices[0], imageSize: imageSize, previewLayer: previewLayer))
        for i in 1..<vertices.count {
            path.addLine(to: convertPoint(vertices[i], imageSize: imageSize, previewLayer: previewLayer))
        }
        path.close()
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = lineWidth
        overlayView.layer.addSublayer(shapeLayer)
        boundingBoxLayers.append(shapeLayer)
    }

    static func orderVerticesClockwise(_ vertices: [CGPoint]) -> [CGPoint] {
        guard vertices.count == 4 else { return vertices }
        let centroid = CGPoint(
            x: vertices.map { $0.x }.reduce(0, +) / 4.0,
            y: vertices.map { $0.y }.reduce(0, +) / 4.0
        )
        return vertices.sorted { a, b in
            let angleA = atan2(a.y - centroid.y, a.x - centroid.x)
            let angleB = atan2(b.y - centroid.y, b.x - centroid.x)
            return angleA < angleB
        }
    }

    static func drawPoint(at point: CGPoint, color: UIColor, radius: CGFloat, imageSize: CGSize, overlayView: UIView, previewLayer: AVCaptureVideoPreviewLayer, boundingBoxLayers: inout [CAShapeLayer]) {
        let convertedPoint = convertPoint(point, imageSize: imageSize, previewLayer: previewLayer)
        let pointLayer = CAShapeLayer()
        let path = UIBezierPath(arcCenter: convertedPoint,
                               radius: radius,
                               startAngle: 0,
                               endAngle: 2 * .pi,
                               clockwise: true)
        pointLayer.path = path.cgPath
        pointLayer.fillColor = color.cgColor
        overlayView.layer.addSublayer(pointLayer)
        boundingBoxLayers.append(pointLayer)
    }

    static func convertPoint(_ point: CGPoint, imageSize: CGSize, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        let normX = point.x / imageSize.width
        let normY = point.y / imageSize.height
        let normalizedRect = CGRect(x: normX, y: normY, width: 0.001, height: 0.001)
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
        return CGPoint(x: convertedRect.origin.x, y: convertedRect.origin.y)
    }

    static func ballIntersectsLine(ballCenter: CGPoint, ballRadius: CGFloat, line: (CGPoint, CGPoint)) -> Bool {
        let (p1, p2) = line
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let length = sqrt(dx*dx + dy*dy)
        if length == 0 { return false }
        let t = max(0, min(1, ((ballCenter.x - p1.x) * dx + (ballCenter.y - p1.y) * dy) / (length * length)))
        let closest = CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
        let dist = hypot(ballCenter.x - closest.x, ballCenter.y - closest.y)
        return dist <= ballRadius
    }

    static func getCurrentImageSize<T>(lastOverlays: ([T], CGSize)?) -> CGSize {
        if let overlays = lastOverlays {
            return overlays.1
        }
        return CGSize(width: 5712, height: 4284)
    }
}
