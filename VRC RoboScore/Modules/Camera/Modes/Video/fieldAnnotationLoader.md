# FieldAnnotationLoader Documentation

## Purpose
`FieldAnnotationLoader.swift` provides a modular and scalable way to load and parse field annotation data from a JSON file (`VexFieldAnnotations.json`). This data includes the positions and properties of field objects such as goal legs, short goals, and long goals, which are used for overlaying field elements on the camera view in the VRC RoboScore app.

## How It Works
- The loader reads the JSON file from the app bundle (using `Bundle.main` for iOS compatibility).
- It parses the file into Swift structs: `FieldGoalLeg`, `FieldShortGoal`, and `FieldLongGoal`, grouped under the `FieldAnnotations` struct.
- The loader provides a static method `loadAnnotations(from:)` to load and parse the file, returning a `FieldAnnotations` instance.
- For convenience and testing, `testLoadAnnotations()` prints the parsed results to the console.

## Usage
1. Ensure `VexFieldAnnotations.json` is included in your Xcode project and target membership.
2. Call `FieldAnnotationLoader.loadAnnotations(from: path)` with the path to the JSON file (use `Bundle.main.url(forResource:withExtension:)` for iOS).
3. Use the returned `FieldAnnotations` object to access goal leg centers, short goal endpoints, long goal endpoints, and control zone percentages for overlay logic.

Example:
```swift
if let url = Bundle.main.url(forResource: "VexFieldAnnotations", withExtension: "json") {
    let annotationPath = url.path
    if let annotations = FieldAnnotationLoader.loadAnnotations(from: annotationPath) {
        // Use annotations.goalLegs, annotations.shortGoals, annotations.longGoals
    }
}
```

## Next Steps for Overlay Algorithm
1. **Polygon Construction:**
   - When there are exactly four goal legs (real or ghost), construct a quadrilateral from their live centers.
   - Construct a reference quadrilateral from the annotation goal leg centers.
2. **Perspective Transformation:**
   - Use Core Image's `CIPerspectiveTransform` to map annotated goal endpoints (short/long goals) from the reference polygon to the live polygon.
   - This will morph the annotated field lines to match the live camera view.
3. **Coordinate Conversion:**
   - Convert transformed annotation coordinates to screen coordinates, accounting for aspect ratio, cropping, and scaling (raw image is 5712x4284, preview is 1920x1080, may be cropped).
   - Use the same conversion logic as bounding box overlays for consistency.
4. **Overlay Drawing:**
   - Draw short goal lines in orange, long goal lines in green, and control zone segments in pink (based on percentage values in the annotation).
   - Update overlays each frame as goal leg positions change.

## Context for Future Developers
- The annotation loader is designed to be modular and reusable for any field configuration.
- The overlay algorithm will use perspective transforms to ensure field lines match the live camera view, regardless of camera angle or cropping.
- All coordinate conversions should be consistent with existing overlay logic (see `BoundingBoxDrawer` and `convertRect` in `VideoCameraView.swift`).
- Control zones are defined as percentages along long goal lines; use these to draw pink segments for control zones.
- The loader and overlay logic are decoupled, making it easy to update field annotations or overlay logic independently.

---

## For Further Development
- Implement the perspective transform utility using Core Image.
- Integrate the loader and overlay logic into the camera view update cycle.
- Test overlays on different devices and orientations to ensure accuracy.
- Document any new helper functions or changes for maintainability.
