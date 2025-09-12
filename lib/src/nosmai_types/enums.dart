/// Nosmai Agora Integration Enums
///
/// This file contains all the enumeration types used by the Nosmai Agora integration.

/// Camera position enumeration
enum NosmaiCameraPosition {
  front,
  back,
}

/// Filter types supported by Nosmai SDK
enum NosmaiFilterType {
  local, // Custom .nosmai effect packages
  cloud, // Cloud-based filters
}

/// Filter category types for metadata-based categorization
enum NosmaiFilterCategory {
  beauty, // Beauty enhancement filters (lipstick, face slimming, etc.)
  effect, // Creative/artistic effects (glitch, holographic, etc.)
  filter, // Standard filters (color adjustments, basic effects, etc.)
  unknown, // Unknown or uncategorized filters
}

/// Filter source type enumeration
enum NosmaiFilterSourceType {
  filter,
  effect,
}

/// Error types that can occur in the Nosmai SDK
enum NosmaiErrorType {
  // General errors
  unknown,
  stateError,
  operationTimeout,
  platformError,
  networkError,
  invalidParameter,

  // SDK initialization errors
  sdkNotInitialized,
  invalidLicense,
  licenseExpired,

  // Camera errors
  cameraPermissionDenied,
  cameraUnavailable,
  cameraConfigurationFailed,
  cameraSwitchFailed,

  // Filter errors
  filterNotFound,
  filterInvalidFormat,
  filterLoadFailed,
  filterDownloadFailed,

  // Recording errors
  recordingPermissionDenied,
  recordingStorageFull,
  recordingWriteFailed,
  recordingInProgress,
}

/// SDK state enumeration
enum NosmaiSdkState {
  uninitialized,
  initializing,
  ready,
  error,
}

/// Flash mode enumeration
enum NosmaiFlashMode {
  off,
  on,
  auto,
}

/// Torch mode enumeration
enum NosmaiTorchMode {
  off,
  on,
  auto,
}

/// Session preset enumeration for camera configuration
enum NosmaiSessionPreset {
  low,
  medium,
  high,
  photo,
  video1080p,
  video4K,
}

/// Beauty filter types
enum NosmaiBeautyFilterType {
  skinSmoothing,
  skinWhitening,
  faceSlimming,
  eyeEnlargement,
  noseSize,
  lipstick,
  blusher,
}

/// Color adjustment types
enum NosmaiColorAdjustmentType {
  brightness,
  contrast,
  saturation,
  hue,
  exposure,
  sharpen,
  whiteBalance,
  grayscale,
}

/// Extension methods for string conversion
extension NosmaiCameraPositionExtension on NosmaiCameraPosition {
  String get value {
    switch (this) {
      case NosmaiCameraPosition.front:
        return 'front';
      case NosmaiCameraPosition.back:
        return 'back';
    }
  }

  static NosmaiCameraPosition fromString(String value) {
    switch (value.toLowerCase()) {
      case 'front':
        return NosmaiCameraPosition.front;
      case 'back':
        return NosmaiCameraPosition.back;
      default:
        return NosmaiCameraPosition.front;
    }
  }
}

extension NosmaiFlashModeExtension on NosmaiFlashMode {
  String get value {
    switch (this) {
      case NosmaiFlashMode.off:
        return 'off';
      case NosmaiFlashMode.on:
        return 'on';
      case NosmaiFlashMode.auto:
        return 'auto';
    }
  }

  static NosmaiFlashMode fromString(String value) {
    switch (value.toLowerCase()) {
      case 'on':
        return NosmaiFlashMode.on;
      case 'auto':
        return NosmaiFlashMode.auto;
      case 'off':
      default:
        return NosmaiFlashMode.off;
    }
  }
}

extension NosmaiTorchModeExtension on NosmaiTorchMode {
  String get value {
    switch (this) {
      case NosmaiTorchMode.off:
        return 'off';
      case NosmaiTorchMode.on:
        return 'on';
      case NosmaiTorchMode.auto:
        return 'auto';
    }
  }

  static NosmaiTorchMode fromString(String value) {
    switch (value.toLowerCase()) {
      case 'on':
        return NosmaiTorchMode.on;
      case 'auto':
        return NosmaiTorchMode.auto;
      case 'off':
      default:
        return NosmaiTorchMode.off;
    }
  }
}

extension NosmaiSessionPresetExtension on NosmaiSessionPreset {
  String get value {
    switch (this) {
      case NosmaiSessionPreset.low:
        return 'low';
      case NosmaiSessionPreset.medium:
        return 'medium';
      case NosmaiSessionPreset.high:
        return 'high';
      case NosmaiSessionPreset.photo:
        return 'photo';
      case NosmaiSessionPreset.video1080p:
        return '1080p';
      case NosmaiSessionPreset.video4K:
        return '4k';
    }
  }

  static NosmaiSessionPreset fromString(String value) {
    switch (value.toLowerCase()) {
      case 'low':
        return NosmaiSessionPreset.low;
      case 'medium':
        return NosmaiSessionPreset.medium;
      case 'photo':
        return NosmaiSessionPreset.photo;
      case '1080p':
        return NosmaiSessionPreset.video1080p;
      case '4k':
        return NosmaiSessionPreset.video4K;
      case 'high':
      default:
        return NosmaiSessionPreset.high;
    }
  }
}