import 'package:flutter/services.dart';
import 'nosmai_types.dart';

class Nosmai {
  static const platform = MethodChannel('nosmai_agora');

  static Future<bool> initialize(String licenseKey) async {
    try {
      final bool result = await platform.invokeMethod('initialize', {
        'licenseKey': licenseKey,
      });
      return result;
    } catch (e) {
      print('Error initializing Nosmai: $e');
      throw NosmaiError.license(
        type: NosmaiErrorType.invalidLicense,
        message: 'Failed to initialize Nosmai SDK',
        details: e.toString(),
      );
    }
  }

  static Future<bool> initAgora(String appId) async {
    try {
      final bool result = await platform.invokeMethod('initAgora', {
        'appId': appId,
      });
      return result;
    } catch (e) {
      print('Error initializing Agora: $e');
      throw NosmaiError.general(
        type: NosmaiErrorType.platformError,
        message: 'Failed to initialize Agora SDK',
        details: e.toString(),
      );
    }
  }

  static Future<bool> releaseAgora() async {
    try {
      final bool result = await platform.invokeMethod('releaseAgora');
      return result;
    } catch (e) {
      print('Error releasing Agora: $e');
      return false;
    }
  }

  static Future<String> getFlutterEngineInfo() async {
    try {
      final String result = await platform.invokeMethod('getFlutterEngineInfo');
      return result;
    } catch (e) {
      print('Error getting Flutter engine info: $e');
      return 'Error: $e';
    }
  }

  static Future<bool> startStreaming(
    String appId,
    String token,
    String channelId,
    int userId, {
    bool startCameraImmediately = true,
  }) async {
    try {
      final bool result = await platform.invokeMethod('startCustomCamera', {
        'appId': appId,
        'token': token,
        'channelId': channelId,
        'userId': userId,
        'startCameraImmediately': startCameraImmediately,
      });
      return result;
    } catch (e) {
      print('Error starting streaming: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraUnavailable,
        message: 'Failed to start streaming',
        details: e.toString(),
      );
    }
  }

  static Future<bool> stopStreaming() async {
    try {
      final bool result = await platform.invokeMethod('stopCustomCamera');
      return result;
    } catch (e) {
      print('Error stopping streaming: $e');
      return false;
    }
  }

  // Native Agora control methods
  static Future<bool> enableVideo() async {
    try {
      final bool result = await platform.invokeMethod('enableVideo');
      return result;
    } catch (e) {
      print('Error enabling video: $e');
      return false;
    }
  }

  static Future<bool> enableLocalVideo(bool enabled) async {
    try {
      final bool result = await platform.invokeMethod('enableLocalVideo', {
        'enabled': enabled,
      });
      return result;
    } catch (e) {
      print('Error enabling local video: $e');
      return false;
    }
  }

  // static Future<bool> startStreaming() async {
  //   try {
  //     final bool result = await platform.invokeMethod('startProcessing');
  //     return result;
  //   } catch (e) {
  //     print('Error starting streaming: $e');
  //     return false;
  //   }
  // }

  // static Future<bool> stopStreaming() async {
  //   try {
  //     final bool result = await platform.invokeMethod('stopProcessing');
  //     return result;
  //   } catch (e) {
  //     print('Error stopping streaming: $e');
  //     return false;
  //   }
  // }

  static Future<bool> setClientRole(int role) async {
    try {
      final bool result = await platform.invokeMethod('setClientRole', {
        'role': role,
      });
      return result;
    } catch (e) {
      print('Error setting client role: $e');
      return false;
    }
  }

  static Future<bool> joinChannel(
    String token,
    String channelId,
    int userId,
  ) async {
    try {
      final bool result = await platform.invokeMethod('joinChannel', {
        'token': token,
        'channelId': channelId,
        'userId': userId,
      });
      return result;
    } catch (e) {
      print('Error joining channel: $e');
      return false;
    }
  }

  static Future<bool> leaveChannel() async {
    try {
      final bool result = await platform.invokeMethod('leaveChannel');
      return result;
    } catch (e) {
      print('Error leaving channel: $e');
      return false;
    }
  }

  static Future<bool> teardownStreaming() async {
    try {
      final ok = await platform.invokeMethod<bool>('teardownStreaming');
      return ok == true;
    } catch (e) {
      return false;
    }
  }

  // Camera Support - No streaming required
  static Future<bool> startCameraPreview() async {
    try {
      final bool result = await platform.invokeMethod('startCameraPreview');
      return result;
    } catch (e) {
      print('Error starting camera preview: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraUnavailable,
        message: 'Failed to start camera preview',
        details: e.toString(),
      );
    }
  }

  static Future<bool> stopCameraPreview() async {
    try {
      final bool result = await platform.invokeMethod('stopCameraPreview');
      return result;
    } catch (e) {
      print('Error stopping camera preview: $e');
      return false;
    }
  }

  static Future<bool> startProcessing() async {
    try {
      final bool result = await platform.invokeMethod('startCameraPreview');
      return result;
    } catch (e) {
      print('Error starting processing: $e');
      return false;
    }
  }

  static Future<bool> stopProcessing() async {
    try {
      final bool result = await platform.invokeMethod('stopCameraPreview');
      return result;
    } catch (e) {
      print('Error stopping processing: $e');
      return false;
    }
  }

  static Future<bool> switchCamera() async {
    try {
      final bool result = await platform.invokeMethod('switchCamera');
      return result;
    } catch (e) {
      print('Error switching camera: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraSwitchFailed,
        message: 'Failed to switch camera',
        details: e.toString(),
      );
    }
  }

  // Streaming specific camera controls
  static Future<bool> flipCamera() async {
    try {
      final bool result = await platform.invokeMethod('flipCamera');
      return result;
    } catch (e) {
      print('Error flipping camera: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraSwitchFailed,
        message: 'Failed to flip camera',
        details: e.toString(),
      );
    }
  }

  static Future<bool> muteMicrophone(bool muted) async {
    try {
      final bool result = await platform.invokeMethod('muteMicrophone', {
        'muted': muted,
      });
      return result;
    } catch (e) {
      print('Error muting microphone: $e');
      throw NosmaiError.general(
        type: NosmaiErrorType.platformError,
        message: 'Failed to mute microphone',
        details: e.toString(),
      );
    }
  }

  static Future<bool> toggleMirror(bool enabled) async {
    try {
      final bool result = await platform.invokeMethod('toggleMirror', {
        'enabled': enabled,
      });
      return result;
    } catch (e) {
      print('Error toggling mirror: $e');
      throw NosmaiError.general(
        type: NosmaiErrorType.platformError,
        message: 'Failed to toggle mirror',
        details: e.toString(),
      );
    }
  }

  static Future<bool> setFlashMode(NosmaiFlashMode flashMode) async {
    try {
      final bool result = await platform.invokeMethod('setFlashMode', {
        'flashMode': flashMode.value,
      });
      return result;
    } catch (e) {
      print('Error setting flash mode: $e');
      return false;
    }
  }

  static Future<bool> setTorchMode(NosmaiTorchMode torchMode) async {
    try {
      final bool result = await platform.invokeMethod('setTorchMode', {
        'torchMode': torchMode.value,
      });
      return result;
    } catch (e) {
      print('Error setting torch mode: $e');
      return false;
    }
  }

  // Filter Methods with typed models
  static Future<List<NosmaiFilter>> getLocalFilters() async {
    try {
      final list = await platform.invokeMethod<List>('getLocalFilters');
      return (list ?? [])
          .map((e) => NosmaiFilter.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      print('Error getting local filters: $e');
      return [];
    }
  }

  static Future<bool> applyFilter(String path) async {
    try {
      final ok = await platform.invokeMethod<bool>('applyFilter', {
        'path': path,
      });
      return ok == true;
    } catch (e) {
      print('Error applying filter: $e');
      throw NosmaiError.filter(
        type: NosmaiErrorType.filterLoadFailed,
        message: 'Failed to apply filter',
        details: e.toString(),
      );
    }
  }

  static Future<bool> removeAllFilters() async {
    try {
      final ok = await platform.invokeMethod<bool>('removeAllFilters');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  // Cloud filters methods
  static Future<bool> isCloudFilterEnabled() async {
    try {
      final ok = await platform.invokeMethod<bool>('isCloudFilterEnabled');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<NosmaiFilter>> getCloudFilters() async {
    try {
      final list = await platform.invokeMethod<List>('getCloudFilters');
      return (list ?? [])
          .map((e) => NosmaiFilter.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      print('Error getting cloud filters: $e');
      throw NosmaiError.filter(
        type: NosmaiErrorType.networkError,
        message: 'Failed to get cloud filters',
        details: e.toString(),
      );
    }
  }

  static Future<Map<String, dynamic>> downloadCloudFilter(
    String filterId,
  ) async {
    try {
      final result = await platform.invokeMethod<Map>('downloadCloudFilter', {
        'filterId': filterId,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      print('Error downloading cloud filter: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<NosmaiFilter>> getFilters() async {
    try {
      final list = await platform.invokeMethod<List>('getFilters');
      return (list ?? [])
          .map((e) => NosmaiFilter.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      print('Error getting filters: $e');
      return [];
    }
  }

  // Beauty filter methods
  static Future<bool> applyBrightness(double brightness) async {
    try {
      // brightness range: -1.0 to +1.0
      final clamped = brightness.clamp(-1.0, 1.0);
      final bool result = await platform.invokeMethod('applyBrightness', {
        'brightness': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying brightness: $e');
      return false;
    }
  }

  // Skin smoothing filter
  static Future<bool> applySkinSmoothing(double level) async {
    try {
      final clamped = level.clamp(0.0, 10.0);
      final bool result = await platform.invokeMethod('applySkinSmoothing', {
        'level': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying skin smoothing: $e');
      return false;
    }
  }

  // Skin whitening filter
  static Future<bool> applySkinWhitening(double level) async {
    try {
      final clamped = level.clamp(0.0, 10.0);
      final bool result = await platform.invokeMethod('applySkinWhitening', {
        'level': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying skin whitening: $e');
      return false;
    }
  }

  // Face slimming filter
  static Future<bool> applyFaceSlimming(double level) async {
    try {
      final clamped = level.clamp(0.0, 10.0);
      final bool result = await platform.invokeMethod('applyFaceSlimming', {
        'level': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying face slimming: $e');
      return false;
    }
  }

  // Eye enlargement filter
  static Future<bool> applyEyeEnlargement(double level) async {
    try {
      final clamped = level.clamp(0.0, 10.0);
      final bool result = await platform.invokeMethod('applyEyeEnlargement', {
        'level': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying eye enlargement: $e');
      return false;
    }
  }

  // Nose size filter
  static Future<bool> applyNoseSize(double level) async {
    try {
      final clamped = level.clamp(0.0, 100.0);
      final bool result = await platform.invokeMethod('applyNoseSize', {
        'level': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying nose size: $e');
      return false;
    }
  }

  // Contrast filter
  static Future<bool> applyContrast(double contrast) async {
    try {
      final clamped = contrast.clamp(0.0, 2.0);
      final bool result = await platform.invokeMethod('applyContrast', {
        'contrast': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying contrast: $e');
      return false;
    }
  }

  // Hue filter
  static Future<bool> applyHue(double hue) async {
    try {
      final bool result = await platform.invokeMethod('applyHue', {'hue': hue});
      return result;
    } catch (e) {
      print('Error applying hue: $e');
      return false;
    }
  }

  // RGB filter
  static Future<bool> applyRGB(double red, double green, double blue) async {
    try {
      final bool result = await platform.invokeMethod('applyRGB', {
        'red': red,
        'green': green,
        'blue': blue,
      });
      return result;
    } catch (e) {
      print('Error applying RGB filter: $e');
      return false;
    }
  }

  // Lipstick makeup
  static Future<bool> applyLipstick(double intensity) async {
    try {
      final clamped = intensity.clamp(0.0, 10.0);
      final bool result = await platform.invokeMethod('applyLipstick', {
        'intensity': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying lipstick: $e');
      return false;
    }
  }

  // Blusher makeup
  static Future<bool> applyBlusher(double intensity) async {
    try {
      final clamped = intensity.clamp(0.0, 50.0);
      final bool result = await platform.invokeMethod('applyBlusher', {
        'intensity': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying blusher: $e');
      return false;
    }
  }

  // Get current filter states
  static Future<Map<String, double>> getCurrentFilterStates() async {
    try {
      final Map<dynamic, dynamic> result = await platform.invokeMethod(
        'getCurrentFilterStates',
      );
      return Map<String, double>.from(
        result.map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        ),
      );
    } catch (e) {
      print('Error getting current filter states: $e');
      return {};
    }
  }

  // Check if any filter is active
  static Future<bool> hasActiveFilters() async {
    try {
      final bool result = await platform.invokeMethod('hasActiveFilters');
      return result;
    } catch (e) {
      print('Error checking active filters: $e');
      return false;
    }
  }

  // Typed Camera Configuration
  static Future<bool> configureCamera({
    NosmaiCameraPosition? position,
    NosmaiSessionPreset? sessionPreset,
  }) async {
    try {
      final bool result = await platform.invokeMethod('configureCamera', {
        'position': (position ?? NosmaiCameraPosition.front).value,
        'sessionPreset': (sessionPreset ?? NosmaiSessionPreset.high).value,
      });
      return result;
    } catch (e) {
      print('Error configuring camera: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraConfigurationFailed,
        message: 'Failed to configure camera',
        details: e.toString(),
      );
    }
  }

  // Cleanup resources
  static Future<bool> cleanup() async {
    try {
      final bool result = await platform.invokeMethod('cleanup');
      return result;
    } catch (e) {
      print('Error during cleanup: $e');
      return false;
    }
  }

  // Apply makeup blend level
  static Future<bool> applyMakeupBlendLevel(
    String filterName,
    double level,
  ) async {
    try {
      final bool result = await platform.invokeMethod('applyMakeupBlendLevel', {
        'filterName': filterName,
        'level': level,
      });
      return result;
    } catch (e) {
      print('Error applying makeup blend level: $e');
      return false;
    }
  }

  // Exposure filter
  static Future<bool> applyExposure(double exposure) async {
    try {
      final clamped = exposure.clamp(-10.0, 10.0);
      final bool result = await platform.invokeMethod('applyExposure', {
        'exposure': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying exposure: $e');
      return false;
    }
  }

  // Saturation filter
  static Future<bool> applySaturation(double saturation) async {
    try {
      final clamped = saturation.clamp(0.0, 2.0);
      final bool result = await platform.invokeMethod('applySaturation', {
        'saturation': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying saturation: $e');
      return false;
    }
  }

  // Sharpening filter
  static Future<bool> applySharpening(double sharpening) async {
    try {
      final clamped = sharpening.clamp(0.0, 1.5);
      final bool result = await platform.invokeMethod('applySharpening', {
        'sharpening': clamped,
      });
      return result;
    } catch (e) {
      print('Error applying sharpening: $e');
      return false;
    }
  }

  // White balance filter
  static Future<bool> applyWhiteBalance(
    double temperatureK,
    double tint,
  ) async {
    try {
      final tempClamped = temperatureK.clamp(1000.0, 12000.0);
      final tintClamped = tint.clamp(-200.0, 200.0);
      final bool result = await platform.invokeMethod('applyWhiteBalance', {
        'temperatureK': tempClamped,
        'tint': tintClamped,
      });
      return result;
    } catch (e) {
      print('Error applying white balance: $e');
      return false;
    }
  }

  // Grayscale filter
  static Future<bool> setGrayscaleEnabled(bool enabled) async {
    try {
      final bool result = await platform.invokeMethod('setGrayscaleEnabled', {
        'enabled': enabled,
      });
      return result;
    } catch (e) {
      print('Error setting grayscale: $e');
      return false;
    }
  }

  // Typed Recording Methods
  static Future<bool> startRecording() async {
    try {
      final bool result = await platform.invokeMethod('startRecording');
      return result;
    } catch (e) {
      print('Error starting recording: $e');
      throw NosmaiError.recording(
        type: NosmaiErrorType.recordingWriteFailed,
        message: 'Failed to start recording',
        details: e.toString(),
      );
    }
  }

  static Future<NosmaiRecordingResult> stopRecording() async {
    try {
      final Map<dynamic, dynamic> result = await platform.invokeMethod(
        'stopRecording',
      );
      return NosmaiRecordingResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      print('Error stopping recording: $e');
      throw NosmaiError.recording(
        type: NosmaiErrorType.recordingWriteFailed,
        message: 'Failed to stop recording',
        details: e.toString(),
      );
    }
  }

  // Typed Photo Capture
  static Future<NosmaiPhotoResult> capturePhoto() async {
    try {
      final Map<dynamic, dynamic> result = await platform.invokeMethod(
        'capturePhoto',
      );
      return NosmaiPhotoResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      print('Error capturing photo: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraUnavailable,
        message: 'Failed to capture photo',
        details: e.toString(),
      );
    }
  }

  // Camera View Management
  static Future<bool> detachCameraView() async {
    try {
      final bool result = await platform.invokeMethod('detachCameraView');
      return result;
    } catch (e) {
      print('Error detaching camera view: $e');
      return false;
    }
  }

  static Future<bool> reinitializePreview() async {
    try {
      final bool result = await platform.invokeMethod('reinitializePreview');
      return result;
    } catch (e) {
      print('Error reinitializing preview: $e');
      throw NosmaiError.camera(
        type: NosmaiErrorType.cameraConfigurationFailed,
        message: 'Failed to reinitialize preview',
        details: e.toString(),
      );
    }
  }

  // Typed Gallery Save Methods
  static Future<NosmaiGalleryResult> saveImageToGallery(
    List<int> imageData, {
    String? name,
  }) async {
    try {
      final Map<dynamic, dynamic> result = await platform
          .invokeMethod('saveImageToGallery', {
            'imageData': imageData,
            'name':
                name ?? 'nosmai_photo_${DateTime.now().millisecondsSinceEpoch}',
          });
      return NosmaiGalleryResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      print('Error saving image to gallery: $e');
      throw NosmaiError.general(
        type: NosmaiErrorType.recordingWriteFailed,
        message: 'Failed to save image to gallery',
        details: e.toString(),
      );
    }
  }

  static Future<NosmaiGalleryResult> saveVideoToGallery(
    String videoPath, {
    String? name,
  }) async {
    try {
      final Map<dynamic, dynamic> result = await platform
          .invokeMethod('saveVideoToGallery', {
            'videoPath': videoPath,
            'name':
                name ?? 'nosmai_video_${DateTime.now().millisecondsSinceEpoch}',
          });
      return NosmaiGalleryResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      print('Error saving video to gallery: $e');
      throw NosmaiError.general(
        type: NosmaiErrorType.recordingWriteFailed,
        message: 'Failed to save video to gallery',
        details: e.toString(),
      );
    }
  }

  // HSB Adjustment Methods
  static Future<bool> adjustHSB({
    required double hue,
    required double saturation,
    required double brightness,
  }) async {
    try {
      final bool result = await platform.invokeMethod('adjustHSB', {
        'hue': hue,
        'saturation': saturation,
        'brightness': brightness,
      });
      return result;
    } catch (e) {
      print('Error adjusting HSB: $e');
      return false;
    }
  }

  static Future<bool> resetHSBFilter() async {
    try {
      final bool result = await platform.invokeMethod('resetHSBFilter');
      return result;
    } catch (e) {
      print('Error resetting HSB filter: $e');
      return false;
    }
  }

  // Beauty Filter Status
  static Future<bool> isBeautyFilterEnabled() async {
    try {
      final bool result = await platform.invokeMethod('isBeautyFilterEnabled');
      return result;
    } catch (e) {
      print('Error checking beauty filter status: $e');
      return false;
    }
  }

  // Flash/Torch Capability and Mode Methods
  static Future<bool> hasFlash() async {
    try {
      final bool result = await platform.invokeMethod('hasFlash');
      return result;
    } catch (e) {
      print('Error checking flash capability: $e');
      return false;
    }
  }

  static Future<bool> hasTorch() async {
    try {
      final bool result = await platform.invokeMethod('hasTorch');
      return result;
    } catch (e) {
      print('Error checking torch capability: $e');
      return false;
    }
  }

  static Future<NosmaiFlashMode> getFlashMode() async {
    try {
      final String result = await platform.invokeMethod('getFlashMode');
      return NosmaiFlashModeExtension.fromString(result);
    } catch (e) {
      print('Error getting flash mode: $e');
      return NosmaiFlashMode.off;
    }
  }

  static Future<NosmaiTorchMode> getTorchMode() async {
    try {
      final String result = await platform.invokeMethod('getTorchMode');
      return NosmaiTorchModeExtension.fromString(result);
    } catch (e) {
      print('Error getting torch mode: $e');
      return NosmaiTorchMode.off;
    }
  }
}
