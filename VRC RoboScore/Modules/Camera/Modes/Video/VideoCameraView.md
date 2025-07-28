## Live Ball Detection Wiring to GameState (2025-07-28)

### Overview
The camera overlay now directly updates the calculator `GameState` with live ball detection results. This enables real-time scoring and control zone logic based on detected ball positions and colors.

### Mapping Logic
- **Long Goals (LG1, LG2):**
    - LG1 = `topGoals[0]`, LG2 = `topGoals[1]` in `GameState`.
    - For each, the total blue/red balls is the sum of balls in LR (left/right) and CZ (control zone) segments.
    - These are set via `blocks[.red]` and `blocks[.blue]` on both the red and blue goals in each `GoalPair`.
- **Short Goals (SG1, SG2):**
    - SG1 = `bottomGoals[0]`, SG2 = `bottomGoals[1]` in `GameState`.
    - Blue/red ball counts are set via `blocks[.red]` and `blocks[.blue]` on both goals in each pair.
- **Control Zone State:**
    - For each long goal, the control zone state is determined by comparing the number of red and blue balls in the CZ segment.
    - If blue > red, control is set to `.blue`; if red > blue, control is `.red`; if equal, control is `nil` (tie).
    - This is set via `controlPoint.controlledBy` on both goals in the pair.

### Implementation Details
- The ball counts are calculated and averaged over a sliding window for stability.
- The overlay logic in `CameraViewController` calls `drawBallCountOverlay`, which updates the `GameState` as described above.
- The calculator UI and scoring logic now reflect live camera detections automatically.

### Example Code (Swift)
```swift
// LG1
let lg1B = (ballCounts["LG1LR"]?.blue ?? 0) + (ballCounts["LG1CZ"]?.blue ?? 0)
let lg1R = (ballCounts["LG1LR"]?.red ?? 0) + (ballCounts["LG1CZ"]?.red ?? 0)
// Update blocks for both goals in LG1 pair
gameState.topGoals[0].redGoal.blocks[.red] = lg1R
gameState.topGoals[0].redGoal.blocks[.blue] = lg1B
gameState.topGoals[0].blueGoal.blocks[.red] = lg1R
gameState.topGoals[0].blueGoal.blocks[.blue] = lg1B
// Control zone
let lg1Control: Alliance? = lg1CZB > lg1CZR ? .blue : (lg1CZR > lg1CZB ? .red : nil)
gameState.topGoals[0].redGoal.controlPoint.controlledBy = lg1Control
gameState.topGoals[0].blueGoal.controlPoint.controlledBy = lg1Control
```

### Developer Notes
- The mapping is robust to changes in the underlying model or UI, as long as the goal ordering and segment naming conventions are maintained.
- If the game format changes, update the mapping logic in `drawBallCountOverlay`.
- The control zone logic uses the `Alliance` enum from the calculator model for consistency.

### Changelog
- **2025-07-28:** Added direct wiring from camera ball detection to calculator `GameState`, including correct mapping to topGoals/bottomGoals and control zone logic.
# Model Persistence (NEW)
- `hasLoadedModel` (file scope): Tracks if the Roboflow model has loaded in this app session. Prevents loading overlay on subsequent opens.
- `sharedRFModel` (file scope): Persists the loaded Roboflow model instance across camera opens. Ensures detection works after reopening the camera.
- **How to use:** Always access the model via `sharedRFModel` in `CameraViewController`. The model is loaded once and reused for all camera sessions.
- **Warning:** If you reload the model, update `sharedRFModel` so all camera sessions use the new instance.
# VideoCameraView.swift Documentation

## Overview
`VideoCameraView.swift` implements the video-based object detection and tracking system for the VRC RoboScore app. It uses Roboflow for object detection and the SORT algorithm (via TrackSS) for persistent tracking of important objects, specifically "Goal Leg" objects. The UI is built with SwiftUI and UIKit integration.

---

## Main Components
### 9. Pause/Unpause Button (NEW)
- Rectangular button with bezels, located next to the X button.
- Toggles between "Pause" and "Unpause" text. When paused, object detection is halted but the camera feed continues updating.
- Overlay persists while paused, showing the last detected objects.
- **How to use:** Use the `isPaused` state in `FieldCameraView` and pass it to `CameraViewControllerRepresentable`. The button toggles this state.
- **Warning:** Pausing does not reset ghost legs when changing orientation while paused.

### 10. X Button (NEW)
- Circular button with a mostly transparent background and opaque black "X" icon.
- Located at the top left of the camera overlay, allows users to exit the camera view.
- **How to use:** Use the `isPresented` binding in `FieldCameraView`. The button sets this to `false` to dismiss the camera.

### 11. FPS Counter (NEW)
- Compact, rectangular overlay at the top right, styled similarly to other buttons.
- Displays the current frames per second with 1 decimal place accuracy.
- **How to use:** The `fps` state in `FieldCameraView` is updated each frame and shown in the overlay.


### 1. CameraConstants (NEW)
- Centralizes all configuration values for overlays and tracking logic.
- Groups constants by purpose: tracking logic, tracked goal leg overlays, ghost leg overlays, ball overlays.
- **How to use:** Reference `CameraConstants` for any configurable value (colors, sizes, thresholds) in overlays or tracking logic. This makes future tuning and maintenance much easier.
- **Warning:** Always update constants here rather than hardcoding values elsewhere.

### 2. CameraManager (NEW)
- Handles camera session setup, preview layer management, and video output configuration.
- **How to use:** Instantiate and call `setupCamera(on:)`, `addVideoOutput(delegate:)`, and `startSession()` from your view controller.
- **Warning:** Only one `AVCaptureSession` should be active at a time. Do not duplicate camera setup logic elsewhere.

### 3. BoundingBoxDrawer (NEW)
- Helper class for drawing bounding box overlays and labels on the camera preview.
- **How to use:** Call `BoundingBoxDrawer.drawBox(...)` with the appropriate parameters for tracked legs, ghost legs, or balls. Returns the created `CAShapeLayer` for management.
- **Warning:** Always append returned layers to your `boundingBoxLayers` array so overlays can be properly cleared.

### 4. FieldCameraView (SwiftUI)
- The main SwiftUI view embedding the camera functionality.
- Uses `CameraViewControllerRepresentable` to bridge UIKit and SwiftUI.

### 5. CameraViewControllerRepresentable
- A SwiftUI wrapper for the `CameraViewController` (UIKit).
- Handles creation and updating of the camera controller.

### 6. CameraViewController (UIKit)
- Handles frame capture, object detection, overlay drawing, and delegates camera setup to `CameraManager`.
- Integrates Roboflow for object detection and TrackSS (SORT) for tracking "Goal Leg" objects.
- Draws overlays for detected and tracked objects using `BoundingBoxDrawer` and configuration from `CameraConstants`.
- Uses the shared model instance (`sharedRFModel`) for detection, ensuring persistence across camera opens.
- **How to use:** Extend or modify this class for additional overlay types or detection logic. Use the provided helpers and constants for consistency. Always use the shared model reference for detection.
- **Warning:** Always clear overlays each frame using `removeBoundingBoxes()` to prevent UI artifacts. Do not instantiate a new model unless you intend to reload it for all camera sessions.

### 7. GoalLegTrackerManager
- Encapsulates the SORT tracker logic for "Goal Leg" objects.
- Converts detections to the format required by TrackSS.
- Updates and stores tracked objects for overlay drawing.
- Delegates ghost leg management to `GhostLegManager`.
- Tracks how many frames each goal leg ID has persisted, using the `idPersistence` dictionary.
- Each frame, computes the average movement (delta x, delta y) of tracked goal legs that have persisted for 3+ frames, and calls `moveGhostLegs(by:)` to shift all ghost legs accordingly.
- **How to use:** No extra calls needed; persistence and movement are handled automatically in `update(with:)`.
- **Warning:** If no tracked goal legs persist for 3+ frames, ghost legs will not move that frame.

### 8. GhostLegManager
- Handles ghost leg persistence, proximity-based removal, lifecycle management, and now ghost leg movement.
- **How to use:**
    - Use `addGhostLeg`, `removeGhostLegIfClose`, and `limitGhostLegs` to manage ghost leg overlays.
    - Ghost legs are automatically shifted each frame by the average movement (delta x, delta y) of tracked goal legs that have persisted for 3 or more frames. This is done via `moveGhostLegs(by:)`, which is called from the tracker manager.
- **Warning:**
    - If no tracked goal legs have persisted for 3+ frames, ghost legs will not move that frame.
    - If tracked goal legs move erratically, ghost leg movement may be less accurate. Consider tuning persistence threshold or movement logic if needed.
    - Ghost legs are only removed if a new goal leg appears close enough (see `goalLegThreshold`). Tune this value in `CameraConstants` if needed.

---

## Object Detection & Tracking Flow
1. **Camera Setup:**
   - Camera is initialized via `CameraManager` and preview is displayed.
2. **Frame Capture:**
   - Each frame is captured and converted to a UIImage.
3. **Object Detection:**
   - Roboflow model detects objects in the frame.
4. **Tracking Update:**
   - "Goal Leg" detections are passed to the SORT tracker.
   - Tracker returns persistent bounding boxes with IDs.
   - Each goal leg's persistence (number of frames tracked) is updated.
   - The average movement (delta x, delta y) of tracked goal legs that have persisted for 3+ frames is computed and applied to all ghost legs, so ghost legs shift with the field/camera.
5. **Overlay Drawing:**
   - Tracked "Goal Leg" boxes are drawn in orange with their IDs.
   - Ghost legs (last known positions of lost goal legs) are drawn in gray with their IDs, as placeholders until the real goal leg returns, and now move with the field/camera.
   - Other detected objects (balls) are drawn in their respective colors.
6. **Ghost Leg Lifecycle:**
   - When a goal leg disappears, its last position becomes a ghost leg if there are 3 or fewer alive goal legs.
   - When a new goal leg appears, the system checks for nearby ghost legs and removes the closest one if within a threshold distance, ensuring ghosts are only replaced by their real counterparts.
   - The total number of goal legs (tracked + ghosts) is capped at 4 to prevent overlap and maintain UI clarity.
7. **Overlay Cleanup:**
   - Overlays are cleared before drawing new ones each frame.

---

## Extensibility
- The tracking system is modular and can be extended to track other object classes by adding new tracker managers.
- Overlay drawing logic is separated for tracked and detected objects via `BoundingBoxDrawer`.
- All configuration values are centralized in `CameraConstants` for easy tuning.

---

## Changelog
### 2025-07-27 (Pause/Unpause, X Button, FPS Counter)
- Added Pause/Unpause button: toggles object detection, persists overlay while paused, styled for compact UI.
- Added X button: allows user to exit camera view, styled for transparency and compactness.
- Added FPS counter: shows current frame rate in a compact overlay, styled to match other controls.
### 2025-07-27 (Model Persistence & Loading Overlay)
- Added `hasLoadedModel` and `sharedRFModel` at file scope to persist the loaded Roboflow model instance across camera opens.
- Updated `CameraViewController` to reuse the loaded model and avoid reloading, ensuring detection works after reopening the camera.
- Improved loading overlay logic: only shows on first open, not on subsequent opens.
- Fixed state modification during view update by dispatching state changes asynchronously.
- **Warning:** Always use the shared model reference (`sharedRFModel`) for detection. Do not instantiate a new model unless you intend to reload it for all camera sessions.
### 2025-07-27 (Constants & Modularization)
- Added `CameraConstants` struct to centralize all configuration values for overlays and tracking logic.
- Added `CameraManager` class to handle camera setup and session management.
- Added `BoundingBoxDrawer` helper for overlay drawing.
- Refactored overlay drawing and ghost leg logic to use helpers and constants.
- Updated documentation to explain usage and warnings for new helpers and constants.


### 2025-07-27 (Ghost Leg Movement & Persistence)
- Added ghost leg movement: ghost legs now shift each frame by the average movement of tracked goal legs that have persisted for 3+ frames, improving prediction and realism.
- Added persistence tracking for goal leg IDs, so only stable legs influence ghost movement.
- Implemented proximity-based ghost removal: newborn goal legs replace nearby ghost legs, preventing flicker and overlap issues.
- Capped total goal legs (tracked + ghosts) at 4 for UI clarity.
### 2025-07-28 (Model Loading on App Launch)
- Modified AppDelegate.swift to load the Roboflow model when the app starts, reducing initial loading time in the camera view.
- Updated CameraViewController to check for the shared model instance, using it if available.
- Streamlined loading logic to leverage the pre-loaded model instance.

### 2025-07-27
- Integrated TrackSS (SORT) for persistent tracking of "Goal Leg" objects.
- Refactored detection and overlay logic for modularity and extensibility.
- Added ID overlays for tracked objects.
- Improved type handling for tracker input/output.
- Added SwiftUI import for compatibility.

---

## Developer Notes & Warnings
- **Ghost Leg Movement:** Ghost legs now shift by the average movement of tracked goal legs that have persisted for 3+ frames. If no legs meet this threshold, ghost legs remain stationary for that frame. If tracked legs move erratically, ghost leg movement may be less accurate.

## TODO
- Use last 5-10 scores (chosen with slider by user)
- Add goal control changes to overlay
- Make model load while app opens up so it is instantly ready for use


## Overlay Logic: Long and Short Goal Adjustments (2025-07-27)

### drawRelativeGoalOverlays (UPDATED)
- This function draws overlays for long and short goals using the live polygon and computed ratios/percentages.
- **Recent changes:**
    - The bottom long goal overlay is now raised by 90 points (vertical offset).
    - The top long goal overlay is lowered by 10 points.
    - Both short goal overlays are raised by 200 points.
- **How to use:**
    - The function is called automatically within `drawPolygonsOverlay` in `CameraViewController`.
    - It uses the ordered polygon vertices and applies the above vertical adjustments for visual clarity and alignment with the real field.
- **Warnings:**
    - If the field geometry changes, update the vertical offsets in `drawRelativeGoalOverlays` accordingly.
    - The overlay positions are sensitive to the live polygon ordering and field calibration.

### Changelog
#### 2025-07-27 (Overlay Adjustments)
- Updated `drawRelativeGoalOverlays` to:
    - Raise the bottom long goal by 90 points.
    - Lower the top long goal by 10 points.
    - Raise both short goals by 200 points.
- These changes improve the alignment of overlays with the physical field and enhance visual feedback for users.

### Developer Notes
- The overlay logic for long and short goals is modular and can be tuned by adjusting the vertical offsets in the function.
- All overlay drawing functions (`drawLine`, `drawPoint`, `drawPolygon`) are helpers that convert image coordinates to preview layer coordinates for accurate placement.
- When updating overlay logic, always test on real device to ensure overlays match field geometry.



