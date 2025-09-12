import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'nosmai_integration.dart';
import 'nosmai_types.dart';

/// Flutter widget for Nosmai's native camera preview
/// This widget wraps the platform-specific camera preview implementation
/// and provides camera control functionality
class NosmaiCameraPreview extends StatefulWidget {
  final bool autoStart;
  final VoidCallback? onCameraStarted;
  final VoidCallback? onCameraStopped;
  final Function(String)? onCameraStateChanged;
  final Function(String)? onError;

  const NosmaiCameraPreview({
    super.key,
    this.autoStart = true,
    this.onCameraStarted,
    this.onCameraStopped,
    this.onCameraStateChanged,
    this.onError,
  });

  @override
  State<NosmaiCameraPreview> createState() => _NosmaiCameraPreviewState();
}

class _NosmaiCameraPreviewState extends State<NosmaiCameraPreview> {
  bool _isStarted = false;
  String _cameraState = 'stopped';
  String _cameraPosition = 'front';

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    if (_isStarted) {
      _stopCamera().catchError((error) {
        // Ignore errors during disposal to prevent widget tree lookup issues
        if (kDebugMode) {
          print('[NosmaiCameraPreview] Disposal error (ignored): $error');
        }
      });
    }
    super.dispose();
  }

  Future<void> _startCamera() async {
    try {
      final success = await Nosmai.startCameraPreview();
      if (success) {
        setState(() {
          _isStarted = true;
          _cameraState = 'running';
        });
        widget.onCameraStarted?.call();
        widget.onCameraStateChanged?.call(_cameraState);
        _updateCameraPosition();
      } else {
        widget.onError?.call('Failed to start camera preview');
      }
    } catch (e) {
      widget.onError?.call('Error starting camera: $e');
    }
  }

  Future<void> _stopCamera() async {
    try {
      final success = await Nosmai.stopCameraPreview();
      if (success) {
        setState(() {
          _isStarted = false;
          _cameraState = 'stopped';
        });
        widget.onCameraStopped?.call();
        widget.onCameraStateChanged?.call(_cameraState);
      } else {
        widget.onError?.call('Failed to stop camera preview');
      }
    } catch (e) {
      widget.onError?.call('Error stopping camera: $e');
    }
  }

  Future<void> _updateCameraPosition() async {
    try {
      // Position tracking removed - keeping method for compatibility
      setState(() {
        _cameraPosition = _isStarted ? 'front' : 'unknown';
      });
    } catch (e) {
      // Ignore error for camera position
    }
  }

  /// Start camera preview programmatically
  Future<void> startPreview() => _startCamera();

  /// Stop camera preview programmatically  
  Future<void> stopPreview() => _stopCamera();

  /// Switch between front and back camera
  Future<bool> switchCamera() async {
    try {
      final success = await Nosmai.switchCamera();
      if (success) {
        await _updateCameraPosition();
      }
      return success;
    } catch (e) {
      widget.onError?.call('Error switching camera: $e');
      return false;
    }
  }


  /// Set flash mode with typed enum
  Future<bool> setFlashMode(NosmaiFlashMode mode) async {
    try {
      return await Nosmai.setFlashMode(mode);
    } catch (e) {
      widget.onError?.call('Error setting flash mode: $e');
      return false;
    }
  }

  /// Set flash mode with string (for backward compatibility)
  Future<bool> setFlashModeString(String mode) async {
    try {
      NosmaiFlashMode flashMode = NosmaiFlashModeExtension.fromString(mode);
      return await setFlashMode(flashMode);
    } catch (e) {
      widget.onError?.call('Error setting flash mode: $e');
      return false;
    }
  }

  /// Set torch mode with typed enum
  Future<bool> setTorchMode(NosmaiTorchMode mode) async {
    try {
      return await Nosmai.setTorchMode(mode);
    } catch (e) {
      widget.onError?.call('Error setting torch mode: $e');
      return false;
    }
  }

  /// Set torch mode with string (for backward compatibility)
  Future<bool> setTorchModeString(String mode) async {
    try {
      NosmaiTorchMode torchMode = NosmaiTorchModeExtension.fromString(mode);
      return await setTorchMode(torchMode);
    } catch (e) {
      widget.onError?.call('Error setting torch mode: $e');
      return false;
    }
  }

  /// Get current camera state
  String get cameraState => _cameraState;

  /// Get current camera position ('front' or 'back')
  String get cameraPosition => _cameraPosition;

  /// Check if camera is currently running
  bool get isRunning => _isStarted && _cameraState == 'running';

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidView(
        viewType: 'nosmai_native_camera',
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(
        viewType: 'nosmai/camera_preview',
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      );
    } else {
      return const Center(
        child: Text('Platform not supported'),
      );
    }
  }
}