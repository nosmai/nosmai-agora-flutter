import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'nosmai_integration.dart';

/// Flutter widget for Nosmai's streaming video view
/// This widget wraps the platform-specific streaming preview implementation
/// Optimized for live streaming with Agora integration
class NosmaiVideoView extends StatefulWidget {
  final bool autoStart;
  final VoidCallback? onStreamingStarted;
  final VoidCallback? onStreamingStopped;
  final Function(String)? onStreamingStateChanged;
  final Function(String)? onError;

  const NosmaiVideoView({
    super.key,
    this.autoStart = false,
    this.onStreamingStarted,
    this.onStreamingStopped,
    this.onStreamingStateChanged,
    this.onError,
  });

  @override
  State<NosmaiVideoView> createState() => _NosmaiVideoViewState();
}

class _NosmaiVideoViewState extends State<NosmaiVideoView> {
  bool _isStreaming = false;
  String _streamingState = 'stopped';

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      _startStreaming();
    }
  }

  @override
  void dispose() {
    if (_isStreaming) {
      _stopStreaming().catchError((error) {
        // Ignore errors during disposal
        if (kDebugMode) {
          print('[NosmaiVideoView] Disposal error (ignored): $error');
        }
      });
    }
    super.dispose();
  }

  Future<void> _startStreaming() async {
    try {
      // Note: This starts the video processing but doesn't join Agora channel
      // Use Nosmai.startStreaming() separately to join channel with credentials
      final success = await Nosmai.enableVideo();
      if (success) {
        setState(() {
          _isStreaming = true;
          _streamingState = 'processing';
        });
        widget.onStreamingStarted?.call();
        widget.onStreamingStateChanged?.call(_streamingState);
      } else {
        widget.onError?.call('Failed to start video processing');
      }
    } catch (e) {
      widget.onError?.call('Error starting streaming: $e');
    }
  }

  Future<void> _stopStreaming() async {
    try {
      final success = await Nosmai.stopStreaming();
      if (success) {
        setState(() {
          _isStreaming = false;
          _streamingState = 'stopped';
        });
        widget.onStreamingStopped?.call();
        widget.onStreamingStateChanged?.call(_streamingState);
      } else {
        widget.onError?.call('Failed to stop streaming');
      }
    } catch (e) {
      widget.onError?.call('Error stopping streaming: $e');
    }
  }

  /// Start streaming programmatically
  Future<void> startStreaming() => _startStreaming();

  /// Stop streaming programmatically  
  Future<void> stopStreaming() => _stopStreaming();

  /// Switch between front and back camera during streaming
  Future<bool> switchCamera() async {
    try {
      return await Nosmai.switchCamera();
    } catch (e) {
      widget.onError?.call('Error switching camera: $e');
      return false;
    }
  }

  /// Get current streaming state
  String get streamingState => _streamingState;

  /// Check if streaming is currently active
  bool get isStreaming => _isStreaming && _streamingState == 'processing';

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidView(
        viewType: 'nosmai_camera_preview',
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(
        viewType: 'nosmai_camera_preview',
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      );
    } else {
      return const Center(
        child: Text('Streaming not supported on this platform'),
      );
    }
  }
}