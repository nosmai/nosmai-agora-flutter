import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Native preview widget for displaying processed Nosmai frames
/// 
/// This widget shows the processed video frames directly from the native
/// layer, bypassing the Agora preview system to show filtered/processed content.
class AgoraNosmaiPreview extends StatefulWidget {
  /// Optional callback when the preview is created
  final VoidCallback? onPreviewCreated;
  
  /// Background color when no frames are available
  final Color backgroundColor;
  
  const AgoraNosmaiPreview({
    super.key,
    this.onPreviewCreated,
    this.backgroundColor = Colors.black,
  });

  @override
  State<AgoraNosmaiPreview> createState() => _AgoraNosmaiPreviewState();
}

class _AgoraNosmaiPreviewState extends State<AgoraNosmaiPreview> {
  @override
  Widget build(BuildContext context) {
    // Platform-specific preview
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'SimpleNosmaiPreview',
        layoutDirection: TextDirection.ltr,
        creationParams: <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{},
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'SimpleNosmaiPreview',
        layoutDirection: TextDirection.ltr,
        creationParams: <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{},
      );
    }
    
    // Fallback for unsupported platforms
    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Text(
          'Native preview not supported on this platform',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
  
  void _onPlatformViewCreated(int id) {
    debugPrint('AgoraNosmaiPreview created with ID: $id');
    widget.onPreviewCreated?.call();
  }
}