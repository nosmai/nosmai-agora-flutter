import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// Enum for filter categories
enum NosmaiFilterCategory {
  unknown,
  beauty,
  effect,
  filter,
}

/// Enum for filter source type
enum NosmaiFilterSourceType {
  filter,
  effect,
}

/// Helper function to safely parse integers from various types
int? _parseIntSafely(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
    final doubleValue = double.tryParse(value);
    return doubleValue?.toInt();
  }
  return null;
}

/// Filter information for both local and cloud filters
class NosmaiFilter {
  final String id;
  final String name;
  final String description;
  final String displayName;
  final String path;
  final int fileSize;
  final String type; // "cloud" or "local" - indicates source location
  final NosmaiFilterCategory filterCategory; // beauty, effect, filter, unknown
  final NosmaiFilterSourceType sourceType; // filter, effect

  // Cloud-specific properties (optional for local filters)
  final bool isFree;
  final bool isDownloaded;
  final String? previewUrl;
  final String? category;
  final int downloadCount;
  final int price;

  const NosmaiFilter({
    required this.id,
    required this.name,
    required this.description,
    required this.displayName,
    required this.path,
    required this.fileSize,
    required this.type,
    this.filterCategory = NosmaiFilterCategory.unknown,
    this.sourceType = NosmaiFilterSourceType.effect,
    this.isFree = true,
    this.isDownloaded = true,
    this.previewUrl,
    this.category,
    this.downloadCount = 0,
    this.price = 0,
  });

  /// Check if this is a cloud filter
  bool get isCloudFilter => type == 'cloud';

  /// Check if this is a local filter
  bool get isLocalFilter => type == 'local';

  /// Check if this is a filter (vs effect)
  bool get isFilter => sourceType == NosmaiFilterSourceType.filter;

  /// Check if this is an effect (vs filter)
  bool get isEffect => sourceType == NosmaiFilterSourceType.effect;

  factory NosmaiFilter.fromMap(Map<String, dynamic> map) {
    final String typeString = map['type']?.toString() ?? 'local';
    NosmaiFilterSourceType parsedSourceType;
    final filterTypeString = map['filterType']?.toString().toLowerCase();
    switch (filterTypeString) {
      case 'filter':
        parsedSourceType = NosmaiFilterSourceType.filter;
        break;
      case 'effect':
        parsedSourceType = NosmaiFilterSourceType.effect;
        break;
      default:
        // Default to effect for backward compatibility
        parsedSourceType = NosmaiFilterSourceType.effect;
        break;
    }

    NosmaiFilterCategory parsedFilterCategory = NosmaiFilterCategory.unknown;
    final categoryString =
        (map['category'] ?? map['filterCategory'])?.toString().toLowerCase();
    if (categoryString != null) {
      switch (categoryString) {
        case 'beauty':
          parsedFilterCategory = NosmaiFilterCategory.beauty;
          break;
        case 'effect':
          parsedFilterCategory = NosmaiFilterCategory.effect;
          break;
        case 'filter':
          parsedFilterCategory = NosmaiFilterCategory.filter;
          break;
      }
    }

    String finalPath;
    final pathValue = map['path'];
    if (pathValue != null && pathValue.toString() != 'null') {
      finalPath = pathValue.toString();
    } else {
      finalPath = '';
    }

    return NosmaiFilter(
      id: map['id']?.toString() ??
          map['filterId']?.toString() ??
          map['name']?.toString() ??
          '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      displayName:
          map['displayName']?.toString() ?? map['name']?.toString() ?? '',
      path: finalPath,
      fileSize: _parseIntSafely(map['fileSize']) ?? 0,
      type: typeString,
      filterCategory: parsedFilterCategory,
      sourceType: parsedSourceType,
      isFree: map['isFree'] as bool? ?? true,
      isDownloaded: map['isDownloaded'] as bool? ??
          (typeString == 'local' ? true : false),
      previewUrl: map['previewImageBase64']?.toString() ??
          map['previewUrl']?.toString() ??
          map['thumbnailUrl']?.toString(),
      category: map['category']?.toString(),
      downloadCount: _parseIntSafely(map['downloadCount']) ?? 0,
      price: _parseIntSafely(map['price']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'displayName': displayName,
      'path': path,
      'fileSize': fileSize,
      'type': type,
      'filterCategory': filterCategory.name,
      'sourceType': sourceType.name,
      'isFree': isFree,
      'isDownloaded': isDownloaded,
      'previewUrl': previewUrl,
      'category': category,
      'downloadCount': downloadCount,
      'price': price,
    };
  }

  @override
  String toString() {
    return 'NosmaiFilter(id: $id, name: $name, type: $type, filterCategory: $filterCategory, sourceType: $sourceType)';
  }
}

/// Download progress information
class NosmaiDownloadProgress {
  final String filterId;
  final double progress; // 0.0 to 1.0
  final int? bytesDownloaded;
  final int? totalBytes;

  const NosmaiDownloadProgress({
    required this.filterId,
    required this.progress,
    this.bytesDownloaded,
    this.totalBytes,
  });

  factory NosmaiDownloadProgress.fromMap(Map<String, dynamic> map) {
    return NosmaiDownloadProgress(
      filterId: map['filterId']?.toString() ?? '',
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      bytesDownloaded: _parseIntSafely(map['bytesDownloaded']),
      totalBytes: _parseIntSafely(map['totalBytes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'filterId': filterId,
      'progress': progress,
      'bytesDownloaded': bytesDownloaded,
      'totalBytes': totalBytes,
    };
  }
}

/// Nosmai Effect for external video frame processing
///
/// This class provides integration between Agora RTC Engine and Nosmai SDK
/// for advanced video processing, filtering, and beauty effects.
class NosmaiEffect {
  static const MethodChannel _channel = MethodChannel('agora_rtc_ng');

  bool _isInitialized = false;

  /// Filter cache with TTL management
  static List<NosmaiFilter>? _cachedFilters;
  static DateTime? _lastCacheTime;
  static const Duration _defaultCacheValidityDuration = Duration(minutes: 5);

  /// Check if the processor is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the Nosmai processor with Agora RTC Engine
  ///
  /// [engine] - The Agora RTC Engine instance
  /// [licenseKey] - The Nosmai license key
  /// Returns true if initialization is successful
  Future<bool> initialize(RtcEngine engine,
      {required String licenseKey}) async {
    try {
      // Use the same pattern as other Agora SDK components
      final result = await engine.invokeAgoraMethod<bool>('nosmaiInitialize', {
        'apiEngine': engine.getApiEngineHandle(),
        'licenseKey': licenseKey,
      });
      _isInitialized = result == true;
      return _isInitialized;
    } catch (e) {
      print('Failed to initialize Nosmai processor: $e');
      return false;
    }
  }

  /// Create custom AgoraRtcEngineKit instance for frame pushing
  ///
  /// [appId] - The Agora App ID
  /// Returns true if custom engine creation is successful
  Future<bool> createCustomEngine({required String appId}) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiCreateCustomEngine', {
        'appId': appId,
      });
      return result == true;
    } catch (e) {
      print('Failed to create custom engine: $e');
      return false;
    }
  }

  /// Get the custom engine instance pointer for creating VideoViewController
  ///
  /// Returns the engine pointer as an integer that can be used to create
  /// a VideoViewController that displays the processed frames
  Future<int?> getCustomEngine() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiGetCustomEngine');
      return result is int ? result : null;
    } catch (e) {
      print('Failed to get custom engine: $e');
      return null;
    }
  }

  /// Start the video processing
  ///
  /// This starts the camera capture and prepares the processor for frame processing
  Future<bool> startProcessing() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiStartProcessing');
      return result == true;
    } catch (e) {
      print('Failed to start processing: $e');
      return false;
    }
  }

  /// Stop the video processing
  ///
  /// This stops the camera capture and processing
  Future<bool> stopProcessing() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiStopProcessing');
      return result == true;
    } catch (e) {
      print('Failed to stop processing: $e');
      return false;
    }
  }

  /// Start live streaming with external video processing
  ///
  /// This begins sending processed frames to Agora for transmission
  Future<bool> startStreaming() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiStartStreaming');
      return result == true;
    } catch (e) {
      print('Failed to start streaming: $e');
      return false;
    }
  }

  /// Stop live streaming
  ///
  /// This stops sending processed frames to Agora
  Future<bool> stopStreaming() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiStopStreaming');
      return result == true;
    } catch (e) {
      print('Failed to stop streaming: $e');
      return false;
    }
  }

  /// Apply a filter to the video stream
  ///
  /// [filterPath] - Path to the filter file (.nosmai format) or cloud filter ID
  /// This method intelligently handles both local paths and cloud filter IDs
  Future<bool> applyFilter(String filterPath) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    // If empty path, clear all filters
    if (filterPath.isEmpty) {
      return await clearFilter();
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyFilter', {
        'path': filterPath,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply filter: $e');
      return false;
    }
  }

  /// Apply a filter using a NosmaiFilter object
  ///
  /// [filter] - The filter object to apply
  /// This method handles cloud filter downloading automatically if needed
  Future<bool> applyFilterFromObject(NosmaiFilter filter) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    print('🔍 applyFilterFromObject called for: ${filter.name}');
    print('   - ID: ${filter.id}');
    print('   - Path: "${filter.path}"');
    print('   - Type: ${filter.type}');
    print('   - Is Cloud: ${filter.isCloudFilter}');
    print('   - Is Downloaded: ${filter.isDownloaded}');

    // If it's a cloud filter and not downloaded, download it first
    if (filter.isCloudFilter && !filter.isDownloaded) {
      print('☁️ Cloud filter not downloaded, downloading first: ${filter.id}');

      final downloadResult = await downloadCloudFilter(filter.id);
      print('📥 Download result: $downloadResult');

      if (downloadResult['success'] == true) {
        final downloadedPath = downloadResult['localPath'] as String?;
        print('📁 Downloaded path: "$downloadedPath"');

        if (downloadedPath != null && downloadedPath.isNotEmpty) {
          print(
              '✅ Using downloaded path for filter application: $downloadedPath');
          return await applyFilter(downloadedPath);
        } else {
          print('❌ Downloaded cloud filter has empty path');
          return false;
        }
      } else {
        print('❌ Failed to download cloud filter: ${downloadResult['error']}');
        return false;
      }
    }

    // For local filters or already downloaded cloud filters
    if (filter.path.isNotEmpty) {
      print('📁 Using existing path for filter: ${filter.path}');
      return await applyFilter(filter.path);
    } else if (filter.isCloudFilter && filter.isDownloaded) {
      // For downloaded cloud filters with empty path, this shouldn't happen
      // Try to refresh cloud filters to get updated paths
      print(
          '⚠️ Downloaded cloud filter has empty path, this should not happen');
      print('🔄 Refreshing cloud filters to get updated path information');

      try {
        final refreshedFilters = await getCloudFilters();
        final refreshedFilter = refreshedFilters.firstWhere(
          (f) => f.id == filter.id,
          orElse: () => filter,
        );

        if (refreshedFilter.path.isNotEmpty) {
          print('✅ Found updated path after refresh: ${refreshedFilter.path}');
          return await applyFilter(refreshedFilter.path);
        }
      } catch (e) {
        print('❌ Failed to refresh cloud filters: $e');
      }

      // Last resort: try using the filter ID directly
      print('🆔 Using filter ID as fallback: ${filter.id}');
      return await applyFilter(filter.id);
    } else if (filter.isCloudFilter) {
      // For undownloaded cloud filters, try using the filter ID directly
      print(
          '🆔 Trying to apply undownloaded cloud filter using ID: ${filter.id}');
      return await applyFilter(filter.id);
    } else {
      print(
          '❌ Filter has empty path and is not a cloud filter: ${filter.toString()}');
      return false;
    }
  }

  /// Clear all applied filters
  Future<bool> clearFilter() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiClearFilter');
      return result == true;
    } catch (e) {
      print('Failed to clear filter: $e');
      return false;
    }
  }

  /// Get available filters from the Nosmai SDK
  ///
  /// Returns a map containing filter categories and their available filters
  Future<Map<String, dynamic>?> getAvailableFilters() async {
    if (!_isInitialized) return null;

    try {
      final result = await _channel.invokeMethod('nosmaiGetAvailableFilters');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      print('Failed to get available filters: $e');
      return null;
    }
  }

  /// Get list of local .nosmai filters
  Future<List<NosmaiFilter>> getLocalFilters() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final List<dynamic> filters =
          await _channel.invokeMethod('nosmaiGetLocalFilters');
      return filters
          .map((filter) =>
              NosmaiFilter.fromMap(Map<String, dynamic>.from(filter)))
          .toList();
    } catch (e) {
      print('Failed to get local filters: $e');
      return [];
    }
  }

  /// Get list of available cloud filters
  Future<List<NosmaiFilter>> getCloudFilters() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final List<dynamic> filters =
          await _channel.invokeMethod('nosmaiGetCloudFilters');
      return filters
          .map((filter) =>
              NosmaiFilter.fromMap(Map<String, dynamic>.from(filter)))
          .toList();
    } catch (e) {
      print('Failed to get cloud filters: $e');
      // Return empty list instead of throwing to allow app to continue
      return [];
    }
  }

  /// Download a cloud filter
  Future<Map<String, dynamic>> downloadCloudFilter(String filterId) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    print('📥 Starting download for cloud filter: $filterId');

    try {
      final result = await _channel.invokeMethod('nosmaiDownloadCloudFilter', {
        'filterId': filterId,
      });

      print('📥 Native download method returned: $result');

      // Clear cache after successful download to ensure updated download status
      if (result['success'] == true) {
        print('✅ Download successful, clearing cache');
        _cachedFilters = null;
        _lastCacheTime = null;
      } else {
        print('❌ Download failed with result: $result');
      }

      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      print('❌ Download exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get filters
  ///
  /// Returns cached filters when available, otherwise fetches fresh data.
  ///
  /// [forceRefresh] - Whether to force refresh the cache
  Future<List<NosmaiFilter>> getFilters({
    bool forceRefresh = false,
  }) async {
    const cacheValidityDuration = _defaultCacheValidityDuration;
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    // Check if cache is valid and not forcing refresh
    if (!forceRefresh && _isCacheValid(cacheValidityDuration)) {
      return _cachedFilters!;
    }

    // Fetch fresh filters
    try {
      final List<dynamic> filtersData =
          await _channel.invokeMethod('nosmaiGetFilters');
      final filters = filtersData.map((filter) {
        final filterMap = Map<String, dynamic>.from(filter);
        return NosmaiFilter.fromMap(filterMap);
      }).toList();

      // Update cache
      _updateFilterCache(filters);

      return filters;
    } catch (e) {
      print('Failed to get filters: $e');
      return [];
    }
  }

  /// Clear filter cache (both Flutter memory and native cache)
  Future<void> clearCache() async {
    // Clear Flutter memory cache
    _cachedFilters = null;
    _lastCacheTime = null;

    // Clear native iOS cache
    try {
      await _channel.invokeMethod('nosmaiClearFilterCache');
    } catch (e) {
      print('Failed to clear native cache: $e');
      // Native cache clear failed, but Flutter cache is cleared
    }
  }

  /// Check if the filter cache is still valid
  static bool _isCacheValid(Duration validityDuration) {
    return _cachedFilters != null &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!) < validityDuration;
  }

  /// Update the filter cache with new data
  static void _updateFilterCache(List<NosmaiFilter> filters) {
    _cachedFilters = filters;
    _lastCacheTime = DateTime.now();
  }

  /// Apply skin smoothing effect
  ///
  /// [intensity] - Smoothing intensity (0.0 to 1.0)
  Future<bool> applySkinSmoothing(double intensity) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (intensity < 0.0 || intensity > 10.0) {
      throw ArgumentError('Intensity must be between 0.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplySkinSmoothing', {
        'intensity': intensity,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply skin smoothing: $e');
      return false;
    }
  }

  /// Apply face slimming effect
  ///
  /// [intensity] - Slimming intensity (0.0 to 1.0)
  Future<bool> applyFaceSlimming(double intensity) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (intensity < 0.0 || intensity > 10.0) {
      throw ArgumentError('Intensity must be between 0.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyFaceSlimming', {
        'intensity': intensity,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply face slimming: $e');
      return false;
    }
  }

  /// Apply eye enlargement effect
  ///
  /// [intensity] - Enlargement intensity (0.0 to 1.0)
  Future<bool> applyEyeEnlargement(double intensity) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (intensity < 0.0 || intensity > 10.0) {
      throw ArgumentError('Intensity must be between 0.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyEyeEnlargement', {
        'intensity': intensity,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply eye enlargement: $e');
      return false;
    }
  }

  /// Apply skin whitening effect
  ///
  /// [intensity] - Whitening intensity (0.0 to 1.0)
  Future<bool> applySkinWhitening(double intensity) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (intensity < 0.0 || intensity > 10.0) {
      throw ArgumentError('Intensity must be between 0.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplySkinWhitening', {
        'intensity': intensity,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply skin whitening: $e');
      return false;
    }
  }

  /// Apply nose size adjustment
  ///
  /// [intensity] - Nose size adjustment intensity (0.0 to 1.0)
  Future<bool> applyNoseSize(double intensity) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (intensity < 0.0 || intensity > 100.0) {
      throw ArgumentError('Intensity must be between 0.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyNoseSize', {
        'intensity': intensity,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply nose size: $e');
      return false;
    }
  }

  /// Apply brightness filter
  ///
  /// [brightness] - Brightness value (-0.5 to 0.5)
  Future<bool> applyBrightnessFilter(double brightness) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (brightness < -0.5 || brightness > 0.5) {
      throw ArgumentError('Brightness must be between -0.5 and 0.5');
    }

    try {
      final result =
          await _channel.invokeMethod('nosmaiApplyBrightnessFilter', {
        'brightness': brightness,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply brightness filter: $e');
      return false;
    }
  }

  /// Apply contrast filter
  ///
  /// [contrast] - Contrast value (1.0 to 4.0, 1.0 = normal)
  Future<bool> applyContrastFilter(double contrast) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (contrast < 1.0 || contrast > 4.0) {
      throw ArgumentError('Contrast must be between 1.0 and 4.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyContrastFilter', {
        'contrast': contrast,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply contrast filter: $e');
      return false;
    }
  }

  /// Apply RGB color filter
  ///
  /// [red] - Red channel adjustment (-1.0 to 1.0)
  /// [green] - Green channel adjustment (-1.0 to 1.0)
  /// [blue] - Blue channel adjustment (-1.0 to 1.0)
  Future<bool> applyRGBFilter({
    required double red,
    required double green,
    required double blue,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (red < 0.0 ||
        red > 2.0 ||
        green < 0.0 ||
        green > 2.0 ||
        blue < 0.0 ||
        blue > 2.0) {
      throw ArgumentError('RGB values must be between 0.0 and 2.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyRGBFilter', {
        'red': red,
        'green': green,
        'blue': blue,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply RGB filter: $e');
      return false;
    }
  }

  /// Apply sharpening filter
  ///
  /// [level] - Sharpening level (0.0 to 10.0)
  Future<bool> applySharpening(double level) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (level < 0.0 || level > 10.0) {
      throw ArgumentError('Sharpening level must be between 0.0 and 10.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplySharpening', {
        'level': level,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply sharpening: $e');
      return false;
    }
  }

  /// Apply makeup blend level filter
  ///
  /// [filterName] - Name of the makeup filter
  /// [level] - Blend level (0.0 to 1.0)
  Future<bool> applyMakeupBlendLevel(String filterName, double level) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (level < 0.0 || level > 1.0) {
      throw ArgumentError('Blend level must be between 0.0 and 1.0');
    }

    try {
      final result =
          await _channel.invokeMethod('nosmaiApplyMakeupBlendLevel', {
        'filterName': filterName,
        'level': level,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply makeup blend level: $e');
      return false;
    }
  }

  /// Apply grayscale filter
  Future<bool> applyGrayscaleFilter() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyGrayscaleFilter');
      return result == true;
    } catch (e) {
      print('Failed to apply grayscale filter: $e');
      return false;
    }
  }

  /// Apply hue filter
  ///
  /// [hueAngle] - Hue angle in degrees (0.0 to 360.0)
  Future<bool> applyHue(double hueAngle) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (hueAngle < 0.0 || hueAngle > 360.0) {
      throw ArgumentError('Hue angle must be between 0.0 and 360.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyHue', {
        'hueAngle': hueAngle,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply hue filter: $e');
      return false;
    }
  }

  /// Apply white balance filter
  ///
  /// [temperature] - Color temperature adjustment (-1.0 to 1.0)
  /// [tint] - Tint adjustment (-1.0 to 1.0)
  Future<bool> applyWhiteBalance({
    required double temperature,
    required double tint,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (temperature < -1.0 || temperature > 1.0 || tint < -1.0 || tint > 1.0) {
      throw ArgumentError(
          'Temperature and tint values must be between -1.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiApplyWhiteBalance', {
        'temperature': temperature,
        'tint': tint,
      });
      return result == true;
    } catch (e) {
      print('Failed to apply white balance: $e');
      return false;
    }
  }

  /// Adjust HSB (Hue, Saturation, Brightness)
  ///
  /// [hue] - Hue adjustment (-1.0 to 1.0)
  /// [saturation] - Saturation adjustment (-1.0 to 1.0)
  /// [brightness] - Brightness adjustment (-1.0 to 1.0)
  Future<bool> adjustHSB({
    required double hue,
    required double saturation,
    required double brightness,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    if (hue < -1.0 ||
        hue > 1.0 ||
        saturation < -1.0 ||
        saturation > 1.0 ||
        brightness < -1.0 ||
        brightness > 1.0) {
      throw ArgumentError('HSB values must be between -1.0 and 1.0');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiAdjustHSB', {
        'hue': hue,
        'saturation': saturation,
        'brightness': brightness,
      });
      return result == true;
    } catch (e) {
      print('Failed to adjust HSB: $e');
      return false;
    }
  }

  /// Reset HSB filter
  Future<bool> resetHSBFilter() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiResetHSBFilter');
      return result == true;
    } catch (e) {
      print('Failed to reset HSB filter: $e');
      return false;
    }
  }

  /// Remove all built-in filters
  Future<bool> removeBuiltInFilters() async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result = await _channel.invokeMethod('nosmaiRemoveBuiltInFilters');
      return result == true;
    } catch (e) {
      print('Failed to remove built-in filters: $e');
      return false;
    }
  }

  /// Check if beauty filters are enabled
  Future<bool> isBeautyFilterEnabled() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiIsBeautyFilterEnabled');
      return result == true;
    } catch (e) {
      print('Failed to check beauty filter status: $e');
      return false;
    }
  }

  /// Check if cloud filters are enabled/available
  Future<bool> isCloudFilterEnabled() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiIsCloudFilterEnabled');
      return result == true;
    } catch (e) {
      print('Failed to check cloud filter status: $e');
      return false;
    }
  }

  /// Clear all beauty effects
  Future<bool> clearBeautyEffects() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiClearBeautyEffects');
      return result == true;
    } catch (e) {
      print('Failed to clear beauty effects: $e');
      return false;
    }
  }

  /// Switch between front and back camera
  ///
  /// Returns true if switch is successful
  Future<bool> switchCamera() async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiSwitchCamera');
      return result == true;
    } catch (e) {
      print('Failed to switch camera: $e');
      return false;
    }
  }

  /// Enable or disable video mirroring
  ///
  /// [enable] - True to enable mirroring, false to disable
  Future<bool> enableMirror(bool enable) async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiEnableMirror', {
        'enable': enable,
      });
      return result == true;
    } catch (e) {
      print('Failed to set mirror mode: $e');
      return false;
    }
  }

  /// Enable or disable local video preview
  ///
  /// [enable] - True to enable local preview, false to disable
  Future<bool> enableLocalPreview(bool enable) async {
    if (!_isInitialized) return false;

    try {
      final result = await _channel.invokeMethod('nosmaiEnableLocalPreview', {
        'enable': enable,
      });
      return result == true;
    } catch (e) {
      print('Failed to set local preview: $e');
      return false;
    }
  }

  /// Get processing performance metrics
  ///
  /// Returns a map containing FPS, processing time, and other metrics
  Future<Map<String, dynamic>?> getProcessingMetrics() async {
    if (!_isInitialized) return null;

    try {
      final result = await _channel.invokeMethod('nosmaiGetProcessingMetrics');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      print('Failed to get processing metrics: $e');
      return null;
    }
  }

  /// Check if video processing is currently active
  Future<bool> isProcessing() async {
    try {
      final result = await _channel.invokeMethod('nosmaiIsProcessing');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Check if streaming is currently active
  Future<bool> isStreaming() async {
    try {
      final result = await _channel.invokeMethod('nosmaiIsStreaming');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Inject Nosmai preview into an existing AgoraVideoView
  ///
  /// [viewId] - The platform view ID from AgoraVideoView's onAgoraVideoViewCreated callback
  /// This allows us to display processed frames in the existing AgoraVideoView
  Future<bool> injectPreviewIntoView(int viewId) async {
    if (!_isInitialized) {
      throw StateError(
          'Nosmai processor not initialized. Call initialize() first.');
    }

    try {
      final result =
          await _channel.invokeMethod('nosmaiInjectPreviewIntoView', {
        'viewId': viewId,
      });
      return result == true;
    } catch (e) {
      print('Failed to inject preview into view: $e');
      return false;
    }
  }

  /// Dispose the processor and clean up resources
  Future<void> dispose() async {
    if (_isInitialized) {
      await stopStreaming();
      await stopProcessing();
      _isInitialized = false;
    }
  }
}

/// Beauty effect configuration
class NosmaiBeautyConfig {
  final double skinSmoothing;
  final double faceSlimming;
  final double eyeEnlargement;

  const NosmaiBeautyConfig({
    this.skinSmoothing = 0.0,
    this.faceSlimming = 0.0,
    this.eyeEnlargement = 0.0,
  });

  /// Apply all beauty effects using this configuration
  Future<bool> applyTo(NosmaiEffect processor) async {
    try {
      final results = await Future.wait([
        processor.applySkinSmoothing(skinSmoothing),
        processor.applyFaceSlimming(faceSlimming),
        processor.applyEyeEnlargement(eyeEnlargement),
      ]);

      return results.every((result) => result);
    } catch (e) {
      print('Failed to apply beauty config: $e');
      return false;
    }
  }
}

/// Processing metrics data
class NosmaiProcessingMetrics {
  final double? currentFPS;
  final double? averageProcessingTime;
  final int? framesProcessed;
  final int? framesDropped;

  const NosmaiProcessingMetrics({
    this.currentFPS,
    this.averageProcessingTime,
    this.framesProcessed,
    this.framesDropped,
  });

  factory NosmaiProcessingMetrics.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NosmaiProcessingMetrics();

    return NosmaiProcessingMetrics(
      currentFPS: map['currentFPS']?.toDouble(),
      averageProcessingTime: map['averageProcessingTime']?.toDouble(),
      framesProcessed: map['framesProcessed']?.toInt(),
      framesDropped: map['framesDropped']?.toInt(),
    );
  }

  @override
  String toString() {
    return 'NosmaiProcessingMetrics('
        'FPS: $currentFPS, '
        'avgProcessingTime: ${averageProcessingTime}ms, '
        'processed: $framesProcessed, '
        'dropped: $framesDropped)';
  }
}
