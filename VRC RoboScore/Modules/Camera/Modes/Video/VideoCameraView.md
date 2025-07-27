# VideoCameraView.swift Documentation

## Overview
`VideoCameraView.swift` implements the video-based object detection and tracking system for the VRC RoboScore app. It uses Roboflow for object detection and the SORT algorithm (via TrackSS) for persistent tracking of important objects, specifically "Goal Leg" objects. The UI is built with SwiftUI and UIKit integration.

---

## Main Components

### 1. FieldCameraView (SwiftUI)
- The main SwiftUI view embedding the camera functionality.
- Uses `CameraViewControllerRepresentable` to bridge UIKit and SwiftUI.

### 2. CameraViewControllerRepresentable
- A SwiftUI wrapper for the `CameraViewController` (UIKit).
- Handles creation and updating of the camera controller.

### 3. CameraViewController (UIKit)
- Handles camera setup, frame capture, object detection, and overlay drawing.
- Uses `AVCaptureSession` for video input and `AVCaptureVideoDataOutputSampleBufferDelegate` for frame processing.
- Integrates Roboflow for object detection.
- Integrates TrackSS (SORT) for tracking "Goal Leg" objects.
- Draws overlays for detected and tracked objects.

#### Key Properties:
- `captureSession`: Manages camera input/output.
- `previewLayer`: Displays the camera feed.
- `overlayView`: Draws bounding boxes and overlays.
- `boundingBoxLayers`: Stores overlay layers for easy removal.
- `goalLegTracker`: Manages tracking of "Goal Leg" objects.

#### Key Methods:
- `setupCamera()`: Configures camera and preview.
- `loadRoboflowModel()`: Loads the detection model.
- `captureOutput(...)`: Processes each frame, runs detection, updates tracker, and draws overlays.
- `drawTrackedGoalLegs(...)`: Draws tracked "Goal Leg" boxes with persistent IDs.
- `drawBoundingBoxes(...)`: Draws other detected objects (balls, etc).
- `removeBoundingBoxes()`: Clears overlays each frame.

### 4. GoalLegTrackerManager
- Encapsulates the SORT tracker logic for "Goal Leg" objects.
- Converts detections to the format required by TrackSS.
- Updates and stores tracked objects for overlay drawing.

---

## Object Detection & Tracking Flow
1. **Camera Setup:**
   - Camera is initialized and preview is displayed.
2. **Frame Capture:**
   - Each frame is captured and converted to a UIImage.
3. **Object Detection:**
   - Roboflow model detects objects in the frame.
4. **Tracking Update:**
   - "Goal Leg" detections are passed to the SORT tracker.
   - Tracker returns persistent bounding boxes with IDs.
5. **Overlay Drawing:**
   - Tracked "Goal Leg" boxes are drawn in orange with their IDs.
   - Other detected objects (balls) are drawn in their respective colors.
6. **Overlay Cleanup:**
   - Overlays are cleared before drawing new ones each frame.

---

## Extensibility
- The tracking system is modular and can be extended to track other object classes by adding new tracker managers.
- Overlay drawing logic is separated for tracked and detected objects.

---

## Changelog

### 2025-07-27
- Integrated TrackSS (SORT) for persistent tracking of "Goal Leg" objects.
- Refactored detection and overlay logic for modularity and extensibility.
- Added ID overlays for tracked objects.
- Improved type handling for tracker input/output.
- Added SwiftUI import for compatibility.

