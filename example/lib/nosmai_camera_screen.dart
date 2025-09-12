import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_rtc_engine/src/nosmai_integration.dart';
import 'package:agora_rtc_engine/src/nosmai_types.dart';
import 'package:agora_rtc_engine/src/nosmai_camera_preview.dart';

/// Modern Nosmai Camera Screen - Full screen camera with beauty filters
class NosmaiCameraScreen extends StatefulWidget {
  const NosmaiCameraScreen({super.key});

  @override
  State<NosmaiCameraScreen> createState() => _NosmaiCameraScreenState();
}

class _NosmaiCameraScreenState extends State<NosmaiCameraScreen>
    with TickerProviderStateMixin {
  // Camera state
  bool _cameraPreviewActive = false;
  NosmaiFlashMode _flashMode = NosmaiFlashMode.off;
  bool _hasFlash = false;
  bool _isRecording = false;
  bool _beautyFilterEnabled = false;
  bool _showFilters = false;

  // Animation controllers
  late AnimationController _recordingAnimationController;
  late AnimationController _controlsAnimationController;
  late Animation<double> _recordingAnimation;
  late Animation<double> _controlsAnimation;

  // Filter values - Beauty Filters
  double _brightness = 0.0;
  double _skinSmoothing = 0.0;
  double _skinWhitening = 0.0;
  double _faceSlimming = 0.0;
  double _eyeEnlargement = 0.0;
  double _noseSize = 0.0;
  double _contrast = 1.0;
  double _lipstick = 0.0;
  double _blusher = 0.0;
  double _hue = 0.0;
  double _redMultiplier = 1.0;
  double _greenMultiplier = 1.0;
  double _blueMultiplier = 1.0;
  double _saturation = 1.0;

  // HSB adjustment values
  double _hsbHue = 0.0;
  double _hsbSaturation = 1.0;
  double _hsbBrightness = 0.0;

  // Filter states
  bool _nosmaiInitialized = false;
  Map<String, double> _currentFilterStates = {};
  List<NosmaiFilter> _localFilters = [];
  List<NosmaiFilter> _cloudFilters = [];
  int _selectedFilterTab = 0; // 0: Beauty, 1: HSB, 2: Local, 3: Cloud

  @override
  void initState() {
    super.initState();
    _initializeNosmai();

    _setupAnimations();
    _initializeCamera();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _recordingAnimationController.dispose();
    _controlsAnimationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _setupAnimations() {
    _recordingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _recordingAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _recordingAnimationController,
      curve: Curves.easeInOut,
    ));

    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _controlsAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeOut,
    ));

    _controlsAnimationController.forward();
  }

  Future<void> _initializeCamera() async {
    await _applyFilters();
    await _startCameraPreview();
    await _updateCameraInfo(); // Check capabilities after camera is started
    await _loadFilters();

    // Initialize Nosmai and filters after camera is ready
  }

  Future<void> _initializeNosmai() async {
    try {
      // Nosmai should already be initialized in main.dart
      // Just check if it's working and load filters
      bool nosmaiResult = false;
      try {
        // Test Nosmai by checking if beauty filter methods work
        nosmaiResult = await Nosmai.isBeautyFilterEnabled();
        if (kDebugMode) {
          log('[NosmaiCamera] Nosmai is working: $nosmaiResult');
        }
      } catch (e) {
        if (kDebugMode) {
          log('[NosmaiCamera] Nosmai test failed: $e');
        }
        // Assume it's working for demo purposes
        nosmaiResult = true;
      }

      setState(() {
        _nosmaiInitialized = nosmaiResult;
      });

      // Always load filters (including dummy data) for UI demo
      await _loadFilters();
    } catch (e) {
      if (kDebugMode) {
        log('[NosmaiCamera] General initialization error: $e');
      }
      if (kDebugMode) {
        log('[NosmaiCamera] Filters not loaded due to initialization failure');
      }
    }
  }

  Future<void> _loadFilters() async {
    try {
      // Load local filters
      List<NosmaiFilter> localFilters = [];
      try {
        localFilters = await Nosmai.getLocalFilters();
        if (kDebugMode) {
          log('[NosmaiCamera] Loaded ${localFilters.length} local filters');
        }
      } catch (e) {
        if (kDebugMode) {
          log('[NosmaiCamera] Failed to load local filters: $e');
        }
      }

      // Try to load cloud filters
      List<NosmaiFilter> cloudFilters = [];
      try {
        bool cloudEnabled = await Nosmai.isCloudFilterEnabled();
        if (cloudEnabled) {
          cloudFilters = await Nosmai.getCloudFilters();
          if (kDebugMode) {
            log('[NosmaiCamera] Loaded ${cloudFilters.length} cloud filters');
          }
        } else {
          if (kDebugMode) {
            log('[NosmaiCamera] Cloud filters not enabled');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          log('[NosmaiCamera] Failed to load cloud filters: $e');
        }
      }

      setState(() {
        _localFilters = localFilters;
        _cloudFilters = cloudFilters;
      });

      if (kDebugMode) {
        log('[NosmaiCamera] Total loaded: ${localFilters.length} local, ${cloudFilters.length} cloud filters');
      }
    } catch (e) {
      if (kDebugMode) {
        log('[NosmaiCamera] Failed to load filters: $e');
      }
    }
  }

  Future<void> _applyFilter(NosmaiFilter filter) async {
    try {
      String effectPath = filter.path;
      bool success = false;

      if (kDebugMode) {
        log('[NosmaiCamera] Applying filter: ${filter.displayName}, type: ${filter.type.name}, original path: "$effectPath"');
      }

      // For cloud filters, always download to ensure we have the actual file
      if (filter.type == NosmaiFilterType.cloud) {
        if (kDebugMode) {
          log('[NosmaiCamera] Cloud filter detected, downloading to ensure file exists...');
        }

        _showSnackBar('Downloading ${filter.displayName}...', Colors.blue);

        try {
          final downloadResult = await Nosmai.downloadCloudFilter(filter.id);

          if (kDebugMode) {
            log('[NosmaiCamera] Download result: $downloadResult');
          }

          if (downloadResult['success'] == true &&
              downloadResult['path'] != null) {
            effectPath = downloadResult['path'] as String;
            _showSnackBar('Downloaded ${filter.displayName}', Colors.green);

            if (kDebugMode) {
              log('[NosmaiCamera] Downloaded cloud filter: ${filter.displayName}, new path: "$effectPath"');
            }
          } else {
            String errorMsg =
                downloadResult['error'] ?? 'Unknown download error';
            _showSnackBar('Failed to download ${filter.displayName}: $errorMsg',
                Colors.red);
            if (kDebugMode) {
              log('[NosmaiCamera] Download failed: $errorMsg');
            }
            return;
          }
        } catch (e) {
          _showSnackBar('Download error: $e', Colors.red);
          if (kDebugMode) {
            log('[NosmaiCamera] Download exception for ${filter.displayName}: $e');
          }
          return;
        }
      }

      // Apply the filter effect using the path (either original or downloaded)
      if (effectPath.isNotEmpty) {
        if (kDebugMode) {
          log('[NosmaiCamera] Attempting to apply effect with path: "$effectPath"');
        }
        success = await Nosmai.applyFilter(effectPath);

        if (success) {
          _showSnackBar('Applied ${filter.displayName}', Colors.green);
          setState(() {
            _currentFilterStates[filter.id] = 1.0;
          });
        } else {
          _showSnackBar('Failed to apply ${filter.displayName}', Colors.orange);
        }
      } else {
        if (kDebugMode) {
          log('[NosmaiCamera] Empty effect path after processing');
        }
        _showSnackBar('Filter path not available', Colors.orange);
      }

      if (kDebugMode) {
        log('[NosmaiCamera] Apply result - Filter: ${filter.displayName}, final path: "$effectPath", success: $success');
      }
    } catch (e) {
      _showSnackBar('Error applying filter: $e', Colors.red);
      if (kDebugMode) {
        log('[NosmaiCamera] Error applying filter: $e');
      }
    }
  }

  Future<void> _removeFilter(String filterId) async {
    try {
      // Remove all effects
      bool success = await Nosmai.removeAllFilters();

      if (success) {
        _showSnackBar('Filter removed', Colors.green);
        setState(() {
          _currentFilterStates.remove(filterId);
        });
      } else {
        _showSnackBar('Failed to remove filter', Colors.orange);
      }

      if (kDebugMode) {
        log('[NosmaiCamera] Removed filter: $filterId, success: $success');
      }
    } catch (e) {
      _showSnackBar('Error removing filter: $e', Colors.red);
      if (kDebugMode) {
        log('[NosmaiCamera] Error removing filter: $e');
      }
    }
  }

  Future<void> _updateCameraInfo() async {
    try {
      if (kDebugMode) {
        log('[NosmaiCamera] Updating camera info...');
      }

      final flashMode = await Nosmai.getFlashMode();
      final hasFlash = await Nosmai.hasFlash();
      final beautyEnabled = await Nosmai.isBeautyFilterEnabled();

      if (kDebugMode) {
        log('[NosmaiCamera] Camera info - Flash mode: $flashMode, Has flash: $hasFlash, Beauty enabled: $beautyEnabled');
      }

      setState(() {
        _flashMode = flashMode;
        _hasFlash = hasFlash;
        _beautyFilterEnabled = beautyEnabled;
      });

      if (kDebugMode) {
        log('[NosmaiCamera] Camera info updated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        log('[NosmaiCamera] Error updating camera info: $e');
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      final success = await Nosmai.switchCamera();
      if (success) {
        await _updateCameraInfo();
        _showSnackBar('Camera switched', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Failed to switch camera', Colors.red);
    }
  }

  Future<void> _startCameraPreview() async {
    try {
      final success = await Nosmai.startProcessing();
      if (success) {
        setState(() {
          _cameraPreviewActive = true;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        log('[NosmaiCamera] Error starting camera preview: $e');
      }
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final result = await Nosmai.stopRecording();
        setState(() {
          _isRecording = false;
        });
        _recordingAnimationController.stop();
        _recordingAnimationController.reset();

        if (result.success) {
          _showSnackBar('Recording stopped successfully', Colors.green);

          // Show dialog to save to gallery if video path is available
          if (result.videoPath != null &&
              result.videoPath!.isNotEmpty &&
              mounted) {
            _showSaveToGalleryDialog(
              title: 'Save Video to Gallery?',
              onSave: () async {
                try {
                  final galleryResult = await Nosmai.saveVideoToGallery(
                    result.videoPath!,
                    name:
                        'nosmai_video_${DateTime.now().millisecondsSinceEpoch}',
                  );

                  if (galleryResult.success) {
                    _showSnackBar('Video saved to gallery', Colors.green);
                  } else {
                    _showSnackBar(
                        'Failed to save video: ${galleryResult.error}',
                        Colors.red);
                  }
                } catch (e) {
                  _showSnackBar('Error saving video: $e', Colors.red);
                }
              },
            );
          }
        } else {
          _showSnackBar('Recording stopped with errors', Colors.red);
        }
      } else {
        final success = await Nosmai.startRecording();
        setState(() {
          _isRecording = success;
        });
        if (success) {
          _recordingAnimationController.repeat();
          _showSnackBar('Recording started', Colors.green);
        } else {
          _showSnackBar('Failed to start recording', Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar('Recording error: $e', Colors.red);
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final result = await Nosmai.capturePhoto();
      if (result.success && result.imageData != null) {
        _showSnackBar('Photo captured successfully', Colors.green);

        // Show dialog to save to gallery
        if (mounted) {
          _showSaveToGalleryDialog(
            title: 'Save Photo to Gallery?',
            onSave: () async {
              try {
                final galleryResult = await Nosmai.saveImageToGallery(
                  result.imageData!,
                  name: 'nosmai_photo_${DateTime.now().millisecondsSinceEpoch}',
                );

                if (galleryResult.success) {
                  _showSnackBar('Photo saved to gallery', Colors.green);
                } else {
                  _showSnackBar('Failed to save photo: ${galleryResult.error}',
                      Colors.red);
                }
              } catch (e) {
                _showSnackBar('Error saving photo: $e', Colors.red);
              }
            },
          );
        }
      } else {
        _showSnackBar('Photo capture failed', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Photo capture error: $e', Colors.red);
    }
  }

  Future<void> _captureAndSavePhoto() async {
    try {
      final result = await Nosmai.capturePhoto();
      if (result.success && result.imageData != null) {
        _showSnackBar('Photo captured, saving to gallery...', Colors.blue);

        try {
          final galleryResult = await Nosmai.saveImageToGallery(
            result.imageData!,
            name: 'nosmai_photo_${DateTime.now().millisecondsSinceEpoch}',
          );

          if (galleryResult.success) {
            _showSnackBar('Photo captured and saved to gallery', Colors.green);
          } else {
            _showSnackBar(
                'Photo captured but failed to save: ${galleryResult.error}',
                Colors.orange);
          }
        } catch (e) {
          _showSnackBar('Photo captured but error saving: $e', Colors.orange);
        }
      } else {
        _showSnackBar('Photo capture failed', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Photo capture error: $e', Colors.red);
    }
  }

  Future<void> _toggleFlash() async {
    try {
      final newMode = _flashMode == NosmaiFlashMode.off
          ? NosmaiFlashMode.auto
          : NosmaiFlashMode.off;
      final success = await Nosmai.setFlashMode(newMode);
      if (success) {
        setState(() {
          _flashMode = newMode;
        });
      }
    } catch (e) {
      _showSnackBar('Flash toggle error', Colors.red);
    }
  }

  Future<void> _applyFilters() async {
    try {
      await Nosmai.applyBrightness(_brightness);
      await Nosmai.applySkinSmoothing(_skinSmoothing);
      await Nosmai.applySkinWhitening(_skinWhitening);
      await Nosmai.applyFaceSlimming(_faceSlimming);
      await Nosmai.applyEyeEnlargement(_eyeEnlargement);
      await Nosmai.applyNoseSize(_noseSize);
      await Nosmai.applyContrast(_contrast);
      await Nosmai.applyLipstick(_lipstick);
      await Nosmai.applyBlusher(_blusher);
      await Nosmai.applyHue(_hue);
      await Nosmai.applyRGB(_redMultiplier, _greenMultiplier, _blueMultiplier);
      await Nosmai.applySaturation(_saturation);
    } catch (e) {
      if (kDebugMode) {
        log('[NosmaiCamera] Error applying filters: $e');
      }
    }
  }

  Future<void> _applyHSBFilter() async {
    try {
      await Nosmai.adjustHSB(
        hue: _hsbHue,
        saturation: _hsbSaturation,
        brightness: _hsbBrightness,
      );
    } catch (e) {
      if (kDebugMode) {
        log('[NosmaiCamera] Error applying HSB filter: $e');
      }
    }
  }

  Future<void> _resetFilters() async {
    try {
      setState(() {
        _brightness = 0.0;
        _skinSmoothing = 0.0;
        _skinWhitening = 0.0;
        _faceSlimming = 0.0;
        _eyeEnlargement = 0.0;
        _noseSize = 0.0;
        _contrast = 1.0;
        _lipstick = 0.0;
        _blusher = 0.0;
        _hue = 0.0;
        _redMultiplier = 1.0;
        _greenMultiplier = 1.0;
        _blueMultiplier = 1.0;
        _saturation = 1.0;
        _hsbHue = 0.0;
        _hsbSaturation = 1.0;
        _hsbBrightness = 0.0;
      });
      await Nosmai.removeAllFilters();
      await _applyFilters();
      _showSnackBar('Filters reset', Colors.green);
    } catch (e) {
      _showSnackBar('Filter reset error', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSaveToGalleryDialog({
    required String title,
    required VoidCallback onSave,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Would you like to save this to your device gallery?',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onSave();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showGalleryOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Gallery Options',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Manual save options
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.photo_camera, color: Colors.blue),
                ),
                title: const Text(
                  'Take Photo & Save',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                subtitle: const Text(
                  'Capture a photo and automatically save to gallery',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _captureAndSavePhoto();
                },
              ),

              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.videocam, color: Colors.red),
                ),
                title: Text(
                  _isRecording ? 'Stop Recording & Save' : 'Start Recording',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                subtitle: Text(
                  _isRecording
                      ? 'Stop current recording and save to gallery'
                      : 'Start video recording (will prompt to save when stopped)',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (_isRecording) {
                    await _toggleRecording();
                  } else {
                    await _toggleRecording();
                  }
                },
              ),

              const Divider(color: Colors.grey),

              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.grey),
                title: const Text(
                  'About Gallery Save',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                subtitle: const Text(
                  'Photos and videos will be saved to your device gallery with proper permissions.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Full screen camera preview
          Positioned.fill(
            child: NosmaiCameraPreview(
              autoStart: true,
              onCameraStarted: () {
                setState(() {
                  _cameraPreviewActive = true;
                });
              },
              onCameraStopped: () {
                setState(() {
                  _cameraPreviewActive = false;
                });
              },
              onCameraStateChanged: (String state) {
                setState(() {
                  _cameraPreviewActive = state == 'running';
                });
              },
              onError: (String error) {
                _showSnackBar('Camera error: $error', Colors.red);
              },
            ),
          ),

          // Top controls overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _controlsAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -50 * (1 - _controlsAnimation.value)),
                  child: Opacity(
                    opacity: _controlsAnimation.value,
                    child: _buildTopControls(),
                  ),
                );
              },
            ),
          ),

          // Recording indicator
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 20,
              child: AnimatedBuilder(
                animation: _recordingAnimation,
                builder: (context, child) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 10 * _recordingAnimation.value,
                          spreadRadius: 2 * _recordingAnimation.value,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withOpacity(_recordingAnimation.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'REC',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Bottom controls overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _controlsAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, 100 * (1 - _controlsAnimation.value)),
                  child: Opacity(
                    opacity: _controlsAnimation.value,
                    child: _buildBottomControls(),
                  ),
                );
              },
            ),
          ),

          // Filter controls overlay
          if (_showFilters)
            Positioned.fill(
              child: _buildFilterOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 20,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Close button
          _buildIconButton(
            icon: Icons.close,
            onPressed: () => Navigator.of(context).pop(),
          ),

          const Spacer(),

          // Flash button
          if (_hasFlash)
            _buildIconButton(
              icon: _flashMode == NosmaiFlashMode.off
                  ? Icons.flash_off
                  : Icons.flash_on,
              isActive: _flashMode != NosmaiFlashMode.off,
              onPressed: _toggleFlash,
            ),

          const SizedBox(width: 16),

          // Switch camera button
          _buildIconButton(
            icon: Icons.switch_camera,
            onPressed: _cameraPreviewActive ? _switchCamera : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Filter toggle button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIconButton(
                icon: Icons.tune,
                label: 'Filters',
                isActive: _showFilters || _beautyFilterEnabled,
                onPressed: () {
                  setState(() {
                    _showFilters = !_showFilters;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Main camera controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gallery/Media button
              GestureDetector(
                onTap: _showGalleryOptions,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.photo_library,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // Capture button
              GestureDetector(
                onTap: _cameraPreviewActive ? _capturePhoto : null,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // Record button
              GestureDetector(
                onTap: _cameraPreviewActive ? _toggleRecording : null,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? Colors.red
                        : Colors.white.withOpacity(0.2),
                    border: Border.all(
                      color: _isRecording ? Colors.white : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.videocam,
                    color: _isRecording ? Colors.white : Colors.red,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    String? label,
    bool isActive = false,
    VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withOpacity(0.3)
              : Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.yellow : Colors.white,
              size: 24,
            ),
            if (label != null) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.yellow : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(
        children: [
          // Filter controls header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              left: 20,
              right: 20,
              bottom: 10,
            ),
            child: Row(
              children: [
                const Text(
                  'Filters & Effects',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _resetFilters,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'Reset',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showFilters = false;
                    });
                  },
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          // Filter tabs
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                _buildFilterTab('Beauty', 0, Icons.face),
                _buildFilterTab('HSB', 1, Icons.color_lens),
                _buildFilterTab('Local', 2, Icons.filter),
                _buildFilterTab('Cloud', 3, Icons.cloud),
              ],
            ),
          ),

          // Filter content
          Expanded(
            child: _buildFilterContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSlider(
    String label,
    double value,
    double min,
    double max,
    IconData icon,
    ValueChanged<double> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.3),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, int index, IconData icon) {
    final isSelected = _selectedFilterTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilterTab = index;
          });
        },
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color:
                isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(isSelected ? 0.5 : 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterContent() {
    switch (_selectedFilterTab) {
      case 0:
        return _buildBeautyFiltersContent();
      case 1:
        return _buildHSBContent();
      case 2:
        return _buildLocalFiltersContent();
      case 3:
        return _buildCloudFiltersContent();
      default:
        return _buildBeautyFiltersContent();
    }
  }

  Widget _buildBeautyFiltersContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildFilterSlider(
            'Brightness',
            _brightness,
            -0.5,
            0.5,
            Icons.brightness_6,
            (value) async {
              setState(() => _brightness = value);
              await Nosmai.applyBrightness(value);
            },
          ),
          _buildFilterSlider(
            'Skin Smoothing',
            _skinSmoothing,
            0.0,
            10.0,
            Icons.face,
            (value) async {
              setState(() => _skinSmoothing = value);
              await Nosmai.applySkinSmoothing(value);
            },
          ),
          _buildFilterSlider(
            'Skin Whitening',
            _skinWhitening,
            0.0,
            10.0,
            Icons.face_2,
            (value) async {
              setState(() => _skinWhitening = value);
              await Nosmai.applySkinWhitening(value);
            },
          ),
          _buildFilterSlider(
            'Face Slimming',
            _faceSlimming,
            0.0,
            10.0,
            Icons.face_3,
            (value) async {
              setState(() => _faceSlimming = value);
              await Nosmai.applyFaceSlimming(value);
            },
          ),
          _buildFilterSlider(
            'Eye Enlargement',
            _eyeEnlargement,
            0.0,
            10.0,
            Icons.remove_red_eye,
            (value) async {
              setState(() => _eyeEnlargement = value);
              await Nosmai.applyEyeEnlargement(value);
            },
          ),
          _buildFilterSlider(
            'Nose Size',
            _noseSize,
            0.0,
            100.0,
            Icons.face_retouching_natural,
            (value) async {
              setState(() => _noseSize = value);
              await Nosmai.applyNoseSize(value);
            },
          ),
          _buildFilterSlider(
            'Contrast',
            _contrast,
            1.0,
            4.0,
            Icons.contrast,
            (value) async {
              setState(() => _contrast = value);
              await Nosmai.applyContrast(value);
            },
          ),
          _buildFilterSlider(
            'Lipstick',
            _lipstick,
            0.0,
            10.0,
            Icons.favorite,
            (value) async {
              setState(() => _lipstick = value);
              await Nosmai.applyLipstick(value);
            },
          ),
          _buildFilterSlider(
            'Blusher',
            _blusher,
            0.0,
            50.0,
            Icons.face,
            (value) async {
              setState(() => _blusher = value);
              await Nosmai.applyBlusher(value);
            },
          ),
          _buildFilterSlider(
            'Saturation',
            _saturation,
            0.0,
            2.0,
            Icons.water_drop,
            (value) async {
              setState(() => _saturation = value);
              await Nosmai.applySaturation(value);
            },
          ),
          _buildFilterSlider(
            'Hue',
            _hue,
            0.0,
            360.0,
            Icons.palette,
            (value) async {
              setState(() => _hue = value);
              await Nosmai.applyHue(value);
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'RGB Adjustment',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _buildFilterSlider(
            'Red',
            _redMultiplier,
            0.0,
            2.0,
            Icons.circle,
            (value) async {
              setState(() => _redMultiplier = value);
              await Nosmai.applyRGB(
                  _redMultiplier, _greenMultiplier, _blueMultiplier);
            },
          ),
          _buildFilterSlider(
            'Green',
            _greenMultiplier,
            0.0,
            2.0,
            Icons.circle,
            (value) async {
              setState(() => _greenMultiplier = value);
              await Nosmai.applyRGB(
                  _redMultiplier, _greenMultiplier, _blueMultiplier);
            },
          ),
          _buildFilterSlider(
            'Blue',
            _blueMultiplier,
            0.0,
            2.0,
            Icons.circle,
            (value) async {
              setState(() => _blueMultiplier = value);
              await Nosmai.applyRGB(
                  _redMultiplier, _greenMultiplier, _blueMultiplier);
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildHSBContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Text(
            'Color Adjustment',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildFilterSlider(
            'Hue',
            _hsbHue,
            -180.0,
            180.0,
            Icons.palette,
            (value) async {
              setState(() => _hsbHue = value);
              await _applyHSBFilter();
            },
          ),
          _buildFilterSlider(
            'Saturation',
            _hsbSaturation,
            0.0,
            2.0,
            Icons.water_drop,
            (value) async {
              setState(() => _hsbSaturation = value);
              await _applyHSBFilter();
            },
          ),
          _buildFilterSlider(
            'HSB Brightness',
            _hsbBrightness,
            -1.0,
            1.0,
            Icons.brightness_high,
            (value) async {
              setState(() => _hsbBrightness = value);
              await _applyHSBFilter();
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildLocalFiltersContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Local Filters',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Text(
                  '${_localFilters.length} filters',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_localFilters.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: const Column(
                children: [
                  Icon(
                    Icons.filter_alt_off,
                    color: Colors.grey,
                    size: 48,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No local filters available',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          else
            ...(_localFilters.map((filter) => _buildFilterCard(filter, true))),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildCloudFiltersContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Cloud Filters',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Text(
                  '${_cloudFilters.length} filters',
                  style: const TextStyle(
                    color: Colors.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_cloudFilters.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: const Column(
                children: [
                  Icon(
                    Icons.cloud_off,
                    color: Colors.grey,
                    size: 48,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No cloud filters available',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Cloud filters may require network connection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            ...(_cloudFilters.map((filter) => _buildFilterCard(filter, false))),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildFilterCard(NosmaiFilter filter, bool isLocal) {
    final isActive = _currentFilterStates.containsKey(filter.id) &&
        _currentFilterStates[filter.id]! > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? (isLocal ? Colors.blue : Colors.purple)
              : Colors.white.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (isLocal ? Colors.blue : Colors.purple).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isLocal ? Icons.filter : Icons.cloud,
            color: isLocal ? Colors.blue : Colors.purple,
            size: 20,
          ),
        ),
        title: Text(
          filter.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          'Type: ${filter.type.name}${isActive ? ' • Active' : ''}',
          style: TextStyle(
            color: isActive
                ? (isLocal ? Colors.blue : Colors.purple)
                : Colors.grey,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              GestureDetector(
                onTap: () => _removeFilter(filter.id),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 16,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => _applyFilter(filter),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isLocal ? Colors.blue : Colors.purple)
                        .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.add,
                    color: isLocal ? Colors.blue : Colors.purple,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
