import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/src/nosmai_integration.dart';
import 'package:agora_rtc_engine/src/nosmai_types.dart';
import 'package:agora_rtc_engine/src/nosmai_video_view.dart';
import 'config/agora_config.dart';

/// Streaming Screen
/// Shows streaming preview with Nosmai processing
class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key});

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen>
    with TickerProviderStateMixin {
  bool _isStreaming = false;
  bool _nosmaiInitialized = false;
  String _statusMessage = 'Ready to stream';

  // Filter management
  List<NosmaiFilter> _localFilters = [];
  List<NosmaiFilter> _cloudFilters = [];
  NosmaiFilter? _selectedFilter;
  bool _isLoadingFilters = false;

  // Beauty filter values
  double _skinSmoothingLevel = 0.0;
  double _skinWhiteningLevel = 0.0;
  double _faceSlimmingLevel = 0.0;
  double _eyeEnlargementLevel = 0.0;
  double _brightnessLevel = 0.0;
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
  double _hsbBrightness = 1.0;

  // UI state
  bool _showFilters = false;
  bool _showBeautyPanel = false;
  bool _isMicrophoneMuted = false;
  bool _isMirrorEnabled = false;
  late AnimationController _filtersPanelController;
  late AnimationController _beautyPanelController;
  late Animation<Offset> _filtersPanelAnimation;
  late Animation<Offset> _beautyPanelAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeNosmai();
    _loadFilters();
  }

  void _initializeAnimations() {
    _filtersPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _beautyPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _filtersPanelAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _filtersPanelController,
      curve: Curves.easeInOut,
    ));

    _beautyPanelAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _beautyPanelController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _initializeNosmai() async {
    try {
      // Initialize Agora with Nosmai integration
      bool agoraResult = await Nosmai.initAgora(AgoraConfig.appId);
      if (!agoraResult) {
        throw Exception('Agora initialization failed');
      }

      setState(() {
        _nosmaiInitialized = true;
        _statusMessage = 'Ready to stream';
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to initialize Nosmai: $e');
      }
      setState(() {
        _statusMessage = 'Failed to initialize: $e';
      });
    }
  }

  @override
  void dispose() {
    _filtersPanelController.dispose();
    _beautyPanelController.dispose();
    super.dispose();
    _dispose();
  }

  Future<void> _dispose() async {
    if (_isStreaming) {
      await Nosmai.stopStreaming();
    }
    await Nosmai.teardownStreaming();
    await Nosmai.releaseAgora();
  }

  Widget _buildNosmaiPreview() {
    return NosmaiVideoView(
      autoStart: false,
      onStreamingStarted: () {
        if (kDebugMode) {
          debugPrint('NosmaiVideoView: Streaming started');
        }
      },
      onStreamingStopped: () {
        if (kDebugMode) {
          debugPrint('NosmaiVideoView: Streaming stopped');
        }
        setState(() {
          _isStreaming = false;
          _statusMessage = 'Streaming stopped';
        });
      },
      onStreamingStateChanged: (state) {
        if (kDebugMode) {
          debugPrint('NosmaiVideoView: State changed to $state');
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('NosmaiVideoView: Error - $error');
        }
        setState(() {
          _statusMessage = 'Video error: $error';
        });
      },
    );
  }

  void _toggleStreaming() async {
    if (!_nosmaiInitialized) {
      setState(() {
        _statusMessage = 'Please wait for initialization to complete';
      });
      return;
    }

    if (_isStreaming) {
      // Stop streaming
      try {
        bool stopResult = await Nosmai.stopStreaming();
        setState(() {
          _isStreaming = false;
          _statusMessage =
              stopResult ? 'Streaming stopped' : 'Failed to stop streaming';
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error stopping stream: $e');
        }
        setState(() {
          _statusMessage = 'Error stopping: $e';
        });
      }
    } else {
      // Start streaming with Nosmai processing
      try {
        setState(() {
          _statusMessage = 'Starting camera and streaming...';
        });

        // Stop any camera preview first to prevent conflicts
        try {
          await Nosmai.stopCameraPreview();
          if (kDebugMode) {
            debugPrint('Stopped camera before starting streaming');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Warning: Failed to stop camera: $e');
          }
        }

        // Start custom camera with Nosmai processing
        bool startResult = await Nosmai.startStreaming(
          AgoraConfig.appId,
          AgoraConfig.token,
          AgoraConfig.channelId,
          AgoraConfig.uid,
        );

        if (startResult) {
          // Enable video and start preview
          await Nosmai.enableVideo();
          // await Nosmai.startStreaming();

          setState(() {
            _isStreaming = true;
            _statusMessage = 'Streaming live';
          });
        } else {
          setState(() {
            _statusMessage = 'Failed to start streaming - Check Nosmai license';
          });
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error starting stream: $e');
        }
        setState(() {
          _statusMessage = 'Error starting: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Fullscreen camera preview
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0A0A0A),
              child: _isStreaming
                  ? _buildNosmaiPreview()
                  : _buildPlaceholderPreview(),
            ),
          ),

          // Top gradient overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0A0A).withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _buildTopButton(
                  Icons.close,
                  () => Navigator.pop(context),
                ),
                const Spacer(),
                // Status indicator
                if (_isStreaming) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: const Color(0xFF8B5CF6), width: 1),
                    ),
                    child: const Text(
                      'READY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                _buildTopButton(
                  Icons.flip_camera_ios,
                  _flipCamera,
                ),
                const SizedBox(width: 12),
                _buildTopButton(
                  _isMirrorEnabled ? Icons.flip : Icons.flip_outlined,
                  _toggleMirror,
                  isActive: _isMirrorEnabled,
                ),
              ],
            ),
          ),

          // Side controls (Snapchat style)
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.35,
            child: Column(
              children: [
                _buildSideButton(
                  Icons.auto_awesome,
                  _toggleFiltersPanel,
                  'Filters',
                  isActive: _showFilters,
                ),
                const SizedBox(height: 20),
                _buildSideButton(
                  Icons.face_retouching_natural,
                  _toggleBeautyPanel,
                  'Beauty',
                  isActive: _showBeautyPanel,
                ),
                const SizedBox(height: 20),
                _buildSideButton(
                  Icons.refresh,
                  _resetAllFilters,
                  'Reset',
                ),
              ],
            ),
          ),

          // Bottom gradient overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0A0A0A).withOpacity(0.6),
                    const Color(0xFF0A0A0A),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Secondary controls (only when streaming)
                if (_isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBottomButton(
                          _isMicrophoneMuted ? Icons.mic_off : Icons.mic,
                          _toggleMicrophone,
                          isActive: !_isMicrophoneMuted,
                        ),
                        // const SizedBox(width: 40),
                        // _buildBottomButton(
                        //   Icons.camera_alt,
                        //   () {}, // TODO: Capture photo during streaming
                        // ),
                      ],
                    ),
                  ),
                // Main record button
                GestureDetector(
                  onTap: _toggleStreaming,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color:
                            _isStreaming ? Colors.red : const Color(0xFF8B5CF6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isStreaming
                            ? Icons.stop_rounded
                            : Icons.radio_button_checked,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Panels
          if (_showFilters) _buildFiltersPanel(),
          if (_showBeautyPanel) _buildBeautyPanel(),
        ],
      ),
    );
  }

  // Load filters from Nosmai integration
  Future<void> _loadFilters() async {
    if (!mounted) return;

    setState(() {
      _isLoadingFilters = true;
    });

    try {
      // Load local filters
      final localFilters = await Nosmai.getLocalFilters();

      // Load cloud filters
      final cloudFilters = await Nosmai.getCloudFilters();

      if (mounted) {
        setState(() {
          _localFilters = localFilters;
          _cloudFilters = cloudFilters;
          _isLoadingFilters = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load filters: $e');
      }
      if (mounted) {
        setState(() {
          _isLoadingFilters = false;
        });
      }
    }
  }

  Widget _buildPlaceholderPreview() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Tap to start streaming',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const Spacer(),
            // Live indicator
            if (_isStreaming) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'READY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          top: 16,
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
            // Filter and beauty controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: Icons.tune,
                  label: 'Beauty',
                  isActive: _showBeautyPanel,
                  onTap: _toggleBeautyPanel,
                ),
                _buildControlButton(
                  icon: Icons.filter,
                  label: 'Filters',
                  isActive: _showFilters,
                  onTap: _toggleFiltersPanel,
                ),
                _buildControlButton(
                  icon: Icons.flip_camera_ios,
                  label: 'Flip',
                  onTap: _flipCamera,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Streaming controls (only show when streaming)
            if (_isStreaming)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: _isMicrophoneMuted ? Icons.mic_off : Icons.mic,
                    label: 'Mic',
                    isActive: !_isMicrophoneMuted,
                    onTap: _toggleMicrophone,
                  ),
                  _buildControlButton(
                    icon: Icons.flip,
                    label: 'Mirror',
                    isActive: _isMirrorEnabled,
                    onTap: _toggleMirror,
                  ),
                ],
              ),
            const SizedBox(height: 24),
            // Main streaming control
            GestureDetector(
              onTap: _toggleStreaming,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isStreaming ? Colors.red : Colors.white,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 4,
                  ),
                ),
                child: Icon(
                  _isStreaming ? Icons.stop : Icons.play_arrow,
                  color: _isStreaming ? Colors.white : Colors.black,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              border:
                  isActive ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _filtersPanelAnimation,
        child: Container(
          height:
              MediaQuery.of(context).size.height * 0.65, // Larger for better UX
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1A1A1A),
                const Color(0xFF0A0A0A),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedFilter != null)
                      TextButton(
                        onPressed: _clearFilter,
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    IconButton(
                      onPressed: _toggleFiltersPanel,
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              // Filter tabs and content
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        indicatorColor: const Color(0xFF8B5CF6),
                        indicatorWeight: 3,
                        labelColor: const Color(0xFF8B5CF6),
                        unselectedLabelColor: Colors.white.withOpacity(0.6),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        tabs: const [
                          Tab(text: 'Local'),
                          Tab(text: 'Cloud'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildFiltersList(_localFilters, isLocal: true),
                            _buildFiltersList(_cloudFilters, isLocal: false),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersList(List<NosmaiFilter> filters,
      {required bool isLocal}) {
    if (_isLoadingFilters) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (filters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLocal ? Icons.folder_outlined : Icons.cloud_outlined,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isLocal
                  ? 'No local filters available\nAdd .nosmai files to assets/filters/'
                  : 'No cloud filters available\nCheck internet connection',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: filters.length,
      itemBuilder: (context, index) {
        final filter = filters[index];
        final isSelected = _selectedFilter?.id == filter.id;

        return GestureDetector(
          onTap: () => _applyFilter(filter),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  isSelected ? Border.all(color: Colors.white, width: 2) : null,
              color: Colors.white.withOpacity(0.1),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      color: Colors.white.withOpacity(0.05),
                    ),
                    child: Center(
                      child: Icon(
                        isLocal ? Icons.photo_filter : Icons.cloud,
                        color: Colors.white70,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    filter.displayName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBeautyPanel() {
    return SlideTransition(
      position: _beautyPanelAnimation,
      child: Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        height: MediaQuery.of(context).size.height * 0.45, // Bottom sheet style
        child: GestureDetector(
          onTap: () {}, // Prevent tap from propagating
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.95),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Beauty Filters',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _resetBeautyFilters,
                        child: const Text(
                          'Reset',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleBeautyPanel,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                // Beauty controls in tabs
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        TabBar(
                          indicatorColor: const Color(0xFF8B5CF6),
                          indicatorWeight: 3,
                          labelColor: const Color(0xFF8B5CF6),
                          unselectedLabelColor: Colors.white.withOpacity(0.6),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          isScrollable: true,
                          tabs: const [
                            Tab(text: 'Basic'),
                            Tab(text: 'Color'),
                            Tab(text: 'HSB'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildBasicBeautyFilters(),
                              _buildColorFilters(),
                              _buildHSBFilters(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBeautySlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              Text(
                max > 2 ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
              trackHeight: 2,
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              min: min,
              max: max,
            ),
          ),
        ],
      ),
    );
  }

  // Control methods
  void _toggleFiltersPanel() {
    setState(() {
      _showFilters = !_showFilters;
      if (_showFilters) {
        _showBeautyPanel = false;
        _beautyPanelController.reverse();
        _filtersPanelController.forward();
      } else {
        _filtersPanelController.reverse();
      }
    });
  }

  void _toggleBeautyPanel() {
    setState(() {
      _showBeautyPanel = !_showBeautyPanel;
      if (_showBeautyPanel) {
        _showFilters = false;
        _filtersPanelController.reverse();
        _beautyPanelController.forward();
      } else {
        _beautyPanelController.reverse();
      }
    });
  }

  void _flipCamera() async {
    if (kDebugMode) {
      debugPrint('🔄 Flutter: _flipCamera() called');
    }
    try {
      final result = await Nosmai.flipCamera();
      if (kDebugMode) {
        debugPrint('🔄 Flutter: flipCamera result: $result');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Flutter: Failed to flip camera: $e');
      }
    }
  }

  void _toggleMicrophone() async {
    if (kDebugMode) {
      debugPrint(
          '🎤 Flutter: _toggleMicrophone() called, current muted: $_isMicrophoneMuted');
    }
    try {
      final result = await Nosmai.muteMicrophone(!_isMicrophoneMuted);
      if (kDebugMode) {
        debugPrint('🎤 Flutter: muteMicrophone result: $result');
      }
      if (result) {
        setState(() {
          _isMicrophoneMuted = !_isMicrophoneMuted;
        });
        if (kDebugMode) {
          debugPrint('🎤 Flutter: Updated muted state to: $_isMicrophoneMuted');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Flutter: Failed to toggle microphone: $e');
      }
    }
  }

  void _toggleMirror() async {
    if (kDebugMode) {
      debugPrint(
          '🪞 Flutter: _toggleMirror() called, current enabled: $_isMirrorEnabled');
    }
    try {
      final result = await Nosmai.toggleMirror(!_isMirrorEnabled);
      if (kDebugMode) {
        debugPrint('🪞 Flutter: toggleMirror result: $result');
      }
      if (result) {
        setState(() {
          _isMirrorEnabled = !_isMirrorEnabled;
        });
        if (kDebugMode) {
          debugPrint('🪞 Flutter: Updated mirror state to: $_isMirrorEnabled');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Flutter: Failed to toggle mirror: $e');
      }
    }
  }

  void _applyFilter(NosmaiFilter filter) async {
    try {
      String effectPath = filter.path;
      bool success = false;

      if (kDebugMode) {
        debugPrint(
            '[StreamingScreen] Applying filter: ${filter.displayName}, type: ${filter.type.name}, original path: "$effectPath"');
      }

      // For cloud filters, always download to ensure we have the actual file
      if (filter.type == NosmaiFilterType.cloud) {
        if (kDebugMode) {
          debugPrint(
              '[StreamingScreen] Cloud filter detected, downloading to ensure file exists...');
        }

        _showSnackBar('Downloading ${filter.displayName}...', Colors.blue);

        try {
          final downloadResult = await Nosmai.downloadCloudFilter(filter.id);

          if (kDebugMode) {
            debugPrint('[StreamingScreen] Download result: $downloadResult');
          }

          if (downloadResult['success'] == true &&
              downloadResult['path'] != null) {
            effectPath = downloadResult['path'] as String;
            _showSnackBar('Downloaded ${filter.displayName}', Colors.green);

            if (kDebugMode) {
              debugPrint(
                  '[StreamingScreen] Downloaded cloud filter: ${filter.displayName}, new path: "$effectPath"');
            }
          } else {
            String errorMsg =
                downloadResult['error'] ?? 'Unknown download error';
            _showSnackBar('Failed to download ${filter.displayName}: $errorMsg',
                Colors.red);
            if (kDebugMode) {
              debugPrint('[StreamingScreen] Download failed: $errorMsg');
            }
            return;
          }
        } catch (e) {
          _showSnackBar('Download error: $e', Colors.red);
          if (kDebugMode) {
            debugPrint(
                '[StreamingScreen] Download exception for ${filter.displayName}: $e');
          }
          return;
        }
      }

      // Apply the filter effect using the path (either original or downloaded)
      if (effectPath.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[StreamingScreen] Attempting to apply effect with path: "$effectPath"');
        }
        success = await Nosmai.applyFilter(effectPath);

        if (success) {
          _showSnackBar('Applied ${filter.displayName}', Colors.green);
          setState(() {
            _selectedFilter = filter;
          });
        } else {
          _showSnackBar('Failed to apply ${filter.displayName}', Colors.orange);
        }
      } else {
        if (kDebugMode) {
          debugPrint('[StreamingScreen] Empty effect path after processing');
        }
        _showSnackBar('Filter path not available', Colors.orange);
      }

      if (kDebugMode) {
        debugPrint(
            '[StreamingScreen] Apply result - Filter: ${filter.displayName}, final path: "$effectPath", success: $success');
      }
    } catch (e) {
      _showSnackBar('Error applying filter: $e', Colors.red);
      if (kDebugMode) {
        debugPrint('[StreamingScreen] Error applying filter: $e');
      }
    }
  }

  void _clearFilter() async {
    try {
      await Nosmai.removeAllFilters();
      setState(() {
        _selectedFilter = null;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to clear filter: $e');
      }
    }
  }

  // Beauty filter methods
  void _updateSkinSmoothing(double value) async {
    setState(() {
      _skinSmoothingLevel = value;
    });
    try {
      await Nosmai.applySkinSmoothing(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply skin smoothing: $e');
      }
    }
  }

  void _updateSkinWhitening(double value) async {
    setState(() {
      _skinWhiteningLevel = value;
    });
    try {
      await Nosmai.applySkinWhitening(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply skin whitening: $e');
      }
    }
  }

  void _updateFaceSlimming(double value) async {
    setState(() {
      _faceSlimmingLevel = value;
    });
    try {
      await Nosmai.applyFaceSlimming(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply face slimming: $e');
      }
    }
  }

  void _updateEyeEnlargement(double value) async {
    setState(() {
      _eyeEnlargementLevel = value;
    });
    try {
      await Nosmai.applyEyeEnlargement(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply eye enlargement: $e');
      }
    }
  }

  void _updateBrightness(double value) async {
    setState(() {
      _brightnessLevel = value;
    });
    try {
      await Nosmai.applyBrightness(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply brightness: $e');
      }
    }
  }

  void _updateNoseSize(double value) async {
    setState(() {
      _noseSize = value;
    });
    try {
      await Nosmai.applyNoseSize(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply nose size: $e');
      }
    }
  }

  void _updateContrast(double value) async {
    setState(() {
      _contrast = value;
    });
    try {
      await Nosmai.applyContrast(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply contrast: $e');
      }
    }
  }

  void _updateLipstick(double value) async {
    setState(() {
      _lipstick = value;
    });
    try {
      await Nosmai.applyMakeupBlendLevel("LipstickFilter", _lipstick);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply lipstick: $e');
      }
    }
  }

  void _updateBlusher(double value) async {
    setState(() {
      _blusher = value;
    });
    try {
      await Nosmai.applyMakeupBlendLevel("BlusherFilter", _blusher);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply blusher: $e');
      }
    }
  }

  void _updateHue(double value) async {
    setState(() {
      _hue = value;
    });
    try {
      await Nosmai.applyHue(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply hue: $e');
      }
    }
  }

  void _updateSaturation(double value) async {
    setState(() {
      _saturation = value;
    });
    try {
      await Nosmai.applySaturation(value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply saturation: $e');
      }
    }
  }

  void _updateRedMultiplier(double value) async {
    setState(() {
      _redMultiplier = value;
    });
    try {
      await Nosmai.applyRGB(_redMultiplier, _greenMultiplier, _blueMultiplier);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply RGB: $e');
      }
    }
  }

  void _updateGreenMultiplier(double value) async {
    setState(() {
      _greenMultiplier = value;
    });
    try {
      await Nosmai.applyRGB(_redMultiplier, _greenMultiplier, _blueMultiplier);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply RGB: $e');
      }
    }
  }

  void _updateBlueMultiplier(double value) async {
    setState(() {
      _blueMultiplier = value;
    });
    try {
      await Nosmai.applyRGB(_redMultiplier, _greenMultiplier, _blueMultiplier);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply RGB: $e');
      }
    }
  }

  void _updateHsbHue(double value) async {
    setState(() {
      _hsbHue = value;
    });
    try {
      await Nosmai.adjustHSB(
        hue: _hsbHue,
        saturation: _hsbSaturation,
        brightness: _hsbBrightness,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply HSB: $e');
      }
    }
  }

  void _updateHsbSaturation(double value) async {
    setState(() {
      _hsbSaturation = value;
    });
    try {
      await Nosmai.adjustHSB(
        hue: _hsbHue,
        saturation: _hsbSaturation,
        brightness: _hsbBrightness,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply HSB: $e');
      }
    }
  }

  void _updateHsbBrightness(double value) async {
    setState(() {
      _hsbBrightness = value;
    });
    try {
      await Nosmai.adjustHSB(
        hue: _hsbHue,
        saturation: _hsbSaturation,
        brightness: _hsbBrightness,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to apply HSB: $e');
      }
    }
  }

  Widget _buildBasicBeautyFilters() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildBeautySlider(
            'Skin Smoothing',
            _skinSmoothingLevel,
            0.0,
            10.0,
            (value) => _updateSkinSmoothing(value),
          ),
          _buildBeautySlider(
            'Skin Whitening',
            _skinWhiteningLevel,
            0.0,
            10.0,
            (value) => _updateSkinWhitening(value),
          ),
          _buildBeautySlider(
            'Face Slimming',
            _faceSlimmingLevel,
            0.0,
            10.0,
            (value) => _updateFaceSlimming(value),
          ),
          _buildBeautySlider(
            'Eye Enlargement',
            _eyeEnlargementLevel,
            0.0,
            10.0,
            (value) => _updateEyeEnlargement(value),
          ),
          _buildBeautySlider(
            'Nose Size',
            _noseSize,
            0.0,
            100.0,
            (value) => _updateNoseSize(value),
          ),
          _buildBeautySlider(
            'Brightness',
            _brightnessLevel,
            -0.5,
            0.5,
            (value) => _updateBrightness(value),
          ),
          _buildBeautySlider(
            'Contrast',
            _contrast,
            1.0,
            4.0,
            (value) => _updateContrast(value),
          ),
        ],
      ),
    );
  }

  Widget _buildColorFilters() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildBeautySlider(
            'Lipstick',
            _lipstick,
            0.0,
            10.0,
            (value) => _updateLipstick(value),
          ),
          _buildBeautySlider(
            'Blusher',
            _blusher,
            0.0,
            50.0,
            (value) => _updateBlusher(value),
          ),
          _buildBeautySlider(
            'Hue',
            _hue,
            0.0,
            360.0,
            (value) => _updateHue(value),
          ),
          _buildBeautySlider(
            'Saturation',
            _saturation,
            0.0,
            2.0,
            (value) => _updateSaturation(value),
          ),
          _buildBeautySlider(
            'Red',
            _redMultiplier,
            0.0,
            2.0,
            (value) => _updateRedMultiplier(value),
          ),
          _buildBeautySlider(
            'Green',
            _greenMultiplier,
            0.0,
            2.0,
            (value) => _updateGreenMultiplier(value),
          ),
          _buildBeautySlider(
            'Blue',
            _blueMultiplier,
            0.0,
            2.0,
            (value) => _updateBlueMultiplier(value),
          ),
        ],
      ),
    );
  }

  Widget _buildHSBFilters() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildBeautySlider(
            'HSB Hue',
            _hsbHue,
            -180.0,
            180.0,
            (value) => _updateHsbHue(value),
          ),
          _buildBeautySlider(
            'HSB Saturation',
            _hsbSaturation,
            0.0,
            2.0,
            (value) => _updateHsbSaturation(value),
          ),
          _buildBeautySlider(
            'HSB Brightness',
            _hsbBrightness,
            0.0,
            2.0,
            (value) => _updateHsbBrightness(value),
          ),
        ],
      ),
    );
  }

  void _resetBeautyFilters() async {
    setState(() {
      _skinSmoothingLevel = 0.0;
      _skinWhiteningLevel = 0.0;
      _faceSlimmingLevel = 0.0;
      _eyeEnlargementLevel = 0.0;
      _brightnessLevel = 0.0;
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
      _hsbBrightness = 1.0;
    });
    try {
      await Nosmai.removeAllFilters();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to reset beauty filters: $e');
      }
    }
  }

  void _resetAllFilters() async {
    _resetBeautyFilters();
    _clearFilter();
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

  Widget _buildTopButton(IconData icon, VoidCallback onTap,
      {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF8B5CF6).withOpacity(0.3)
              : Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(22),
          border: isActive
              ? Border.all(color: const Color(0xFF8B5CF6), width: 1.5)
              : null,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildSideButton(IconData icon, VoidCallback onTap, String label,
      {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF8B5CF6).withOpacity(0.3)
                  : Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(28),
              border: isActive
                  ? Border.all(color: const Color(0xFF8B5CF6), width: 2)
                  : Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton(IconData icon, VoidCallback onTap,
      {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF8B5CF6).withOpacity(0.3)
              : Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(25),
          border: isActive
              ? Border.all(color: const Color(0xFF8B5CF6), width: 2)
              : Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
