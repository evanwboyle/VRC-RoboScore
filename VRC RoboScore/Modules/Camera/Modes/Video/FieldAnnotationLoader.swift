import Foundation
import CoreGraphics

struct FieldGoalLeg {
    let id: Int
    let center: CGPoint
}

struct FieldShortGoal {
    let id: Int
    let endpoints: [CGPoint]
}

struct FieldLongGoal {
    let id: Int
    let endpoints: [CGPoint]
    let controlZonePercentage: (start: Double, end: Double)?
}

struct FieldAnnotations {
    let goalLegs: [FieldGoalLeg]
    let shortGoals: [FieldShortGoal]
    let longGoals: [FieldLongGoal]
}

class FieldAnnotationLoader {
    static func loadAnnotations(from path: String) -> FieldAnnotations? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("[FieldAnnotationLoader] Failed to read file at path: \(path)")
            return nil
        }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let objects = json["objects"] as? [[String: Any]] {
                var goalLegs: [FieldGoalLeg] = []
                var shortGoals: [FieldShortGoal] = []
                var longGoals: [FieldLongGoal] = []
                for obj in objects {
                    if let type = obj["type"] as? String, let id = obj["id"] as? Int {
                        if type == "Goal Leg", let centerDict = obj["center"] as? [String: Any],
                           let x = centerDict["x"] as? Double, let y = centerDict["y"] as? Double {
                            goalLegs.append(FieldGoalLeg(id: id, center: CGPoint(x: x, y: y)))
                        } else if type == "Short Goal", let endpointsArr = obj["endpoints"] as? [[String: Any]] {
                            let endpoints = endpointsArr.compactMap { ep in
                                if let x = ep["x"] as? Double, let y = ep["y"] as? Double {
                                    return CGPoint(x: x, y: y)
                                }
                                return nil
                            }
                            shortGoals.append(FieldShortGoal(id: id, endpoints: endpoints))
                        } else if type == "Long Goal", let endpointsArr = obj["endpoints"] as? [[String: Any]] {
                            let endpoints = endpointsArr.compactMap { ep in
                                if let x = ep["x"] as? Double, let y = ep["y"] as? Double {
                                    return CGPoint(x: x, y: y)
                                }
                                return nil
                            }
                            var controlZone: (start: Double, end: Double)? = nil
                            if let cz = obj["controlZonePercentage"] as? [String: Any],
                               let start = cz["start"] as? Double, let end = cz["end"] as? Double {
                                controlZone = (start: start, end: end)
                            }
                            longGoals.append(FieldLongGoal(id: id, endpoints: endpoints, controlZonePercentage: controlZone))
                        }
                    }
                }
                print("[FieldAnnotationLoader] Parsed \(goalLegs.count) goal legs, \(shortGoals.count) short goals, \(longGoals.count) long goals.")
                return FieldAnnotations(goalLegs: goalLegs, shortGoals: shortGoals, longGoals: longGoals)
            } else {
                print("[FieldAnnotationLoader] JSON structure invalid.")
                return nil
            }
        } catch {
            print("[FieldAnnotationLoader] Error parsing JSON: \(error)")
            return nil
        }
    }
}


// Example usage (for testing):

extension FieldAnnotationLoader {
    static func testLoadAnnotations() {
        guard let url = Bundle.main.url(forResource: "VexFieldAnnotations", withExtension: "json") else {
            print("[FieldAnnotationLoader] Could not find VexFieldAnnotations.json in bundle.")
            return
        }
        let annotationPath = url.path
        if let annotations = FieldAnnotationLoader.loadAnnotations(from: annotationPath) {
            //print("[FieldAnnotationLoader] Loaded annotations: \(annotations)")
        } else {
            print("[FieldAnnotationLoader] Failed to load annotations.")
        }
    }
}

