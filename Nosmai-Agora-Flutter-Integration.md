# Nosmai-Agora Flutter Integration - Developer Guide

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  agora_rtc_engine:
    git:
      url: https://github.com/nosmai/nosmai-agora-flutter
```

**Required Imports:**
```dart
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_rtc_engine/src/nosmai_integration.dart';
import 'package:agora_rtc_engine/src/nosmai_types.dart';
import 'package:agora_rtc_engine/src/nosmai_camera_preview.dart';
import 'package:agora_rtc_engine/src/nosmai_video_view.dart';
```

## Initialization

**Initialize once in main.dart:**
```dart
await Nosmai.initialize('YOUR_API_KEY_HERE');
```

---

## Camera Mode (Standalone)

**Features:** Beauty filters, recording, photo capture, flash control

### Basic Setup

**1. Camera Preview Widget:**
```dart
NosmaiCameraPreview(
  autoStart: true,
  onCameraStarted: () => print('Camera started'),
  onCameraStopped: () => print('Camera stopped'),
  onError: (error) => print('Error: $error'),
)
```

**2. Start Camera Processing:**
```dart
await Nosmai.startProcessing(); // Starts camera capture and processing
```

**3. Camera Controls:**
```dart
await Nosmai.switchCamera();
await Nosmai.setFlashMode(NosmaiFlashMode.auto);
await Nosmai.stopProcessing();
```

### Beauty Filters
```dart
// Skin & Face Enhancement
await Nosmai.applySkinSmoothing(0.5);    // 0.0 - 1.0
await Nosmai.applySkinWhitening(0.3);    // 0.0 - 1.0
await Nosmai.applyFaceSlimming(0.4);     // 0.0 - 1.0
await Nosmai.applyEyeEnlargement(0.2);   // 0.0 - 1.0
await Nosmai.applyNoseSize(0.3);         // 0.0 - 1.0

// Color Adjustments
await Nosmai.applyBrightness(0.1);       // -1.0 to 1.0
await Nosmai.applyContrast(1.2);         // 0.0 to 2.0
await Nosmai.applySaturation(1.3);       // 0.0 to 2.0
await Nosmai.applyHue(15.0);             // 0.0 to 360.0
await Nosmai.applyExposure(0.5);         // -10.0 to 10.0
await Nosmai.applySharpening(0.4);       // 0.0 to 1.5

// Makeup Effects
await Nosmai.applyLipstick(0.6);         // 0.0 - 1.0
await Nosmai.applyBlusher(0.4);          // 0.0 - 1.0
await Nosmai.applyMakeupBlendLevel('lipstick', 0.7);

// Advanced Effects
await Nosmai.applyRGB(1.1, 1.0, 0.9);   // RGB multipliers
await Nosmai.applyWhiteBalance(5500.0, 0.0); // Temperature & tint
await Nosmai.setGrayscaleEnabled(false); // Enable/disable grayscale

// HSB Adjustment (combined hue, saturation, brightness)
await Nosmai.adjustHSB(hue: 10.0, saturation: 1.2, brightness: 0.1);

// Reset/Remove Filters
await Nosmai.removeAllFilters();         // Remove all applied filters
await Nosmai.resetHSBFilter();           // Reset HSB adjustments

// Filter Status Check
final bool hasFilters = await Nosmai.hasActiveFilters();
final bool beautyEnabled = await Nosmai.isBeautyFilterEnabled();
final Map<String, double> currentStates = await Nosmai.getCurrentFilterStates();
```

### Recording & Photos
```dart
// Recording
await Nosmai.startRecording();
final result = await Nosmai.stopRecording();
await Nosmai.saveVideoToGallery(result.videoPath!, 'my_video');

// Photo Capture
final photo = await Nosmai.capturePhoto();
await Nosmai.saveImageToGallery(photo.imageData!, 'my_photo');
```

### Filters (Local & Cloud)
```dart
// Get available filters
final localFilters = await Nosmai.getLocalFilters();
final cloudFilters = await Nosmai.getCloudFilters();
final allFilters = await Nosmai.getFilters();

// Check cloud filter availability
final bool cloudEnabled = await Nosmai.isCloudFilterEnabled();

// Download cloud filter before applying
final downloadResult = await Nosmai.downloadCloudFilter('filter_id_123');
if (downloadResult['success'] == true) {
  final String filterPath = downloadResult['path'];
  await Nosmai.applyFilter(filterPath);
}

// Apply local filter directly
await Nosmai.applyFilter(localFilter.path);

// Remove filters
await Nosmai.removeAllFilters();
```

---

## Streaming Mode

**Features:** Live streaming + beauty filters (no recording/photos)

### Basic Setup
```dart
// 1. Initialize Agora with Nosmai
await Nosmai.initAgora('YOUR_APP_ID_HERE');

// 2. Streaming Preview Widget
NosmaiVideoView(
  autoStart: false,
  onStreamingStarted: () => print('Streaming started'),
  onStreamingStopped: () => print('Streaming stopped'),
  onError: (error) => print('Error: $error'),
)

// 3. Start streaming with Nosmai processing
await Nosmai.startStreaming('YOUR_APP_ID_HERE', 'YOUR_TOKEN_HERE', 'YOUR_CHANNEL_ID', 12345);
await Nosmai.enableVideo();
```

### Streaming Controls
```dart
// Microphone control
await Nosmai.muteMicrophone(true);  // Mute microphone
await Nosmai.muteMicrophone(false); // Unmute microphone

// Camera controls
await Nosmai.flipCamera(); // Switch between front/back camera

// Mirror/flip the stream view
await Nosmai.toggleMirror(true);  // Enable mirror mode
await Nosmai.toggleMirror(false); // Disable mirror mode
```

### Apply Filters During Stream
```dart
// Same beauty filter methods work during streaming
await Nosmai.applySkinSmoothing(0.5);
await Nosmai.applyFilter(filterPath);
```

---

## Available Enums

```dart
// Camera Position
NosmaiCameraPosition.front / .back

// Flash Modes
NosmaiFlashMode.off / .on / .auto

// Session Presets  
NosmaiSessionPreset.low / .medium / .high / .photo / .video1080p / .video4K

// Filter Types
NosmaiFilterType.local / .cloud
```

## Error Handling

```dart
try {
  await Nosmai.startRecording();
} on NosmaiError catch (e) {
  print('Error: ${e.userMessage}');
  print('Type: ${e.type}');
  print('Recoverable: ${e.isRecoverable}');
}
```

## Quick Comparison

| Feature | Camera Mode | Streaming Mode |
|---------|-------------|----------------|
| **Widget** | `NosmaiCameraPreview` | `NosmaiVideoView` |
| **Recording** | ✅ | ❌ |
| **Photos** | ✅ | ❌ |
| **Live Stream** | ❌ | ✅ |
| **Beauty Filters** | ✅ | ✅ |

## Important

- **Initialize once**: Call `Nosmai.initialize()` only in main.dart
- **Camera Mode**: Use `startProcessing()` for camera capture
- **Permissions**: Request camera/mic permissions before use
- **Resources**: Always cleanup in `dispose()`
