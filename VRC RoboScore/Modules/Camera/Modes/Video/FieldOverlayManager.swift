import SwiftUI
import AVFoundation
import TrackSS


// MARK: - Field Overlay Manager
struct FieldOverlayManager {
    private var cachedReferencePolygon: [CGPoint]?
    private var hasPrintedReferencePolygon = false
    
    mutating func getReferencePolygon() -> [CGPoint]? {
        if cachedReferencePolygon == nil {
            if let refCenters = getReferencePolygonCenters() {
                cachedReferencePolygon = orderVerticesClockwise(refCenters)
                if !hasPrintedReferencePolygon {
                    print("Reference Polygon Centers:")
                    for (i, pt) in cachedReferencePolygon!.enumerated() {
                        print("  [\(i)]: (x: \(pt.x), y: \(pt.y))")
                    }
                    hasPrintedReferencePolygon = true
                }
            }
        }
        return cachedReferencePolygon
    }
    
    func getLivePolygon(from tracker: GoalLegTrackerManager) -> [CGPoint]? {
        var centers: [CGPoint] = []
        let allLegs = tracker.trackedGoalLegs + tracker.ghostLegs
        if allLegs.count == 4 {
            for leg in allLegs {
                if leg.count >= 4 {
                    let cx = (leg[0] + leg[2]) / 2.0
                    let cy = (leg[1] + leg[3]) / 2.0
                    centers.append(CGPoint(x: cx, y: cy))
                }
            }
            return orderVerticesClockwise(centers)
        }
        return nil
    }
    
    private func getReferencePolygonCenters() -> [CGPoint]? {
        guard let annotations = FieldAnnotationLoader.loadAnnotations(from: Bundle.main.path(forResource: "VexFieldAnnotations", ofType: "json") ?? "") else { return nil }
        let legs = annotations.goalLegs
        if legs.count == 4 {
            return legs.map { $0.center }
        }
        return nil
    }
    
    private func orderVerticesClockwise(_ vertices: [CGPoint]) -> [CGPoint] {
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
    
}
