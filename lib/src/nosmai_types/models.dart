/// Nosmai Agora Integration Data Models
///
/// This file contains all the data model classes used by the Nosmai Agora integration.

import 'dart:typed_data';
import 'enums.dart';

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

/// Helper function to safely parse doubles from various types
double? _parseDoubleSafely(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
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
  final NosmaiFilterType type;
  final NosmaiFilterCategory filterCategory;
  final NosmaiFilterSourceType sourceType;

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
  bool get isCloudFilter => type == NosmaiFilterType.cloud;

  /// Check if this is a local filter
  bool get isLocalFilter => type == NosmaiFilterType.local;

  /// Check if this is a filter (vs effect)
  bool get isFilter => sourceType == NosmaiFilterSourceType.filter;

  /// Check if this is an effect (vs filter)
  bool get isEffect => sourceType == NosmaiFilterSourceType.effect;

  factory NosmaiFilter.fromMap(Map<String, dynamic> map) {
    // Parse type
    NosmaiFilterType parsedType = NosmaiFilterType.local;
    final typeString = map['type']?.toString().toLowerCase();
    if (typeString == 'cloud') {
      parsedType = NosmaiFilterType.cloud;
    }

    // Parse source type
    NosmaiFilterSourceType parsedSourceType = NosmaiFilterSourceType.effect;
    final sourceTypeString = map['filterType']?.toString().toLowerCase() ??
                           map['sourceType']?.toString().toLowerCase();
    if (sourceTypeString == 'filter') {
      parsedSourceType = NosmaiFilterSourceType.filter;
    }

    // Parse filter category
    NosmaiFilterCategory parsedFilterCategory = NosmaiFilterCategory.unknown;
    final categoryString = (map['category'] ?? map['filterCategory'])?.toString().toLowerCase();
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

    // Parse path
    String finalPath = '';
    final pathValue = map['path'];
    if (pathValue != null && pathValue.toString() != 'null') {
      finalPath = pathValue.toString();
    }

    return NosmaiFilter(
      id: map['id']?.toString() ??
          map['filterId']?.toString() ??
          map['name']?.toString() ??
          '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? map['name']?.toString() ?? '',
      path: finalPath,
      fileSize: _parseIntSafely(map['fileSize']) ?? 0,
      type: parsedType,
      filterCategory: parsedFilterCategory,
      sourceType: parsedSourceType,
      isFree: map['isFree'] as bool? ?? true,
      isDownloaded: map['isDownloaded'] as bool? ?? false,
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
      'type': type == NosmaiFilterType.cloud ? 'cloud' : 'local',
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
      progress: _parseDoubleSafely(map['progress']) ?? 0.0,
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

/// Recording result information
class NosmaiRecordingResult {
  final bool success;
  final String? videoPath;
  final double duration;
  final int fileSize;
  final String? error;

  const NosmaiRecordingResult({
    required this.success,
    this.videoPath,
    required this.duration,
    required this.fileSize,
    this.error,
  });

  factory NosmaiRecordingResult.fromMap(Map<String, dynamic> map) {
    return NosmaiRecordingResult(
      success: map['success'] as bool? ?? false,
      videoPath: map['videoPath']?.toString(),
      duration: _parseDoubleSafely(map['duration']) ?? 0.0,
      fileSize: _parseIntSafely(map['fileSize']) ?? 0,
      error: map['error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'videoPath': videoPath,
      'duration': duration,
      'fileSize': fileSize,
      'error': error,
    };
  }
}

/// Photo capture result
class NosmaiPhotoResult {
  final bool success;
  final String? imagePath;
  final List<int>? imageData;
  final String? error;
  final int? width;
  final int? height;

  const NosmaiPhotoResult({
    required this.success,
    this.imagePath,
    this.imageData,
    this.error,
    this.width,
    this.height,
  });

  factory NosmaiPhotoResult.fromMap(Map<String, dynamic> map) {
    try {
      final success = map['success'] as bool? ?? false;
      final imagePath = map['imagePath']?.toString();
      final error = map['error']?.toString();
      final width = _parseIntSafely(map['width']);
      final height = _parseIntSafely(map['height']);

      List<int>? imageData;
      if (map['imageData'] != null) {
        try {
          final rawImageData = map['imageData'];
          if (rawImageData is List<int>) {
            imageData = rawImageData;
          } else if (rawImageData is Uint8List) {
            imageData = rawImageData.toList();
          } else if (rawImageData is List) {
            imageData = rawImageData.map((e) => e as int).toList();
          }
        } catch (e) {
          imageData = null;
        }
      }

      return NosmaiPhotoResult(
        success: success,
        imagePath: imagePath,
        imageData: imageData,
        error: error,
        width: width,
        height: height,
      );
    } catch (e) {
      return NosmaiPhotoResult(
        success: false,
        error: 'Failed to parse photo result: ${e.toString()}',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'imagePath': imagePath,
      'imageData': imageData,
      'error': error,
      'width': width,
      'height': height,
    };
  }
}

/// Gallery save result
class NosmaiGalleryResult {
  final bool success;
  final String? path;
  final String? error;

  const NosmaiGalleryResult({
    required this.success,
    this.path,
    this.error,
  });

  factory NosmaiGalleryResult.fromMap(Map<String, dynamic> map) {
    return NosmaiGalleryResult(
      success: map['success'] as bool? ?? false,
      path: map['path']?.toString(),
      error: map['error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'path': path,
      'error': error,
    };
  }
}

/// Camera capabilities information
class NosmaiCameraCapabilities {
  final bool hasFlash;
  final bool hasTorch;
  final bool hasFrontCamera;
  final bool hasBackCamera;
  final bool supportsAutoFocus;
  final List<NosmaiSessionPreset> supportedPresets;

  const NosmaiCameraCapabilities({
    required this.hasFlash,
    required this.hasTorch,
    required this.hasFrontCamera,
    required this.hasBackCamera,
    required this.supportsAutoFocus,
    required this.supportedPresets,
  });

  factory NosmaiCameraCapabilities.fromMap(Map<String, dynamic> map) {
    List<NosmaiSessionPreset> presets = [];
    final presetsData = map['supportedPresets'];
    if (presetsData is List) {
      presets = presetsData
          .map((preset) => NosmaiSessionPresetExtension.fromString(preset.toString()))
          .toList();
    }

    return NosmaiCameraCapabilities(
      hasFlash: map['hasFlash'] as bool? ?? false,
      hasTorch: map['hasTorch'] as bool? ?? false,
      hasFrontCamera: map['hasFrontCamera'] as bool? ?? false,
      hasBackCamera: map['hasBackCamera'] as bool? ?? false,
      supportsAutoFocus: map['supportsAutoFocus'] as bool? ?? false,
      supportedPresets: presets,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hasFlash': hasFlash,
      'hasTorch': hasTorch,
      'hasFrontCamera': hasFrontCamera,
      'hasBackCamera': hasBackCamera,
      'supportsAutoFocus': supportsAutoFocus,
      'supportedPresets': supportedPresets.map((preset) => preset.value).toList(),
    };
  }
}

/// Beauty filter state information
class NosmaiBeautyFilterState {
  final bool enabled;
  final Map<NosmaiBeautyFilterType, double> values;

  const NosmaiBeautyFilterState({
    required this.enabled,
    required this.values,
  });

  factory NosmaiBeautyFilterState.fromMap(Map<String, dynamic> map) {
    final enabled = map['enabled'] as bool? ?? false;
    final Map<NosmaiBeautyFilterType, double> values = {};

    // Parse individual filter values
    final valuesMap = map['values'] as Map<String, dynamic>? ?? {};
    for (final filterType in NosmaiBeautyFilterType.values) {
      final key = filterType.name;
      final value = _parseDoubleSafely(valuesMap[key]) ?? 0.0;
      values[filterType] = value;
    }

    return NosmaiBeautyFilterState(
      enabled: enabled,
      values: values,
    );
  }

  Map<String, dynamic> toMap() {
    final valuesMap = <String, double>{};
    values.forEach((filterType, value) {
      valuesMap[filterType.name] = value;
    });

    return {
      'enabled': enabled,
      'values': valuesMap,
    };
  }
}

/// HSB color adjustment values
class NosmaiHSBAdjustment {
  final double hue; // -180.0 to 180.0
  final double saturation; // 0.0 to 2.0
  final double brightness; // -1.0 to 1.0

  const NosmaiHSBAdjustment({
    required this.hue,
    required this.saturation,
    required this.brightness,
  });

  factory NosmaiHSBAdjustment.fromMap(Map<String, dynamic> map) {
    return NosmaiHSBAdjustment(
      hue: _parseDoubleSafely(map['hue']) ?? 0.0,
      saturation: _parseDoubleSafely(map['saturation']) ?? 1.0,
      brightness: _parseDoubleSafely(map['brightness']) ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hue': hue,
      'saturation': saturation,
      'brightness': brightness,
    };
  }

  /// Get default HSB values (no adjustment)
  static const NosmaiHSBAdjustment defaultValues = NosmaiHSBAdjustment(
    hue: 0.0,
    saturation: 1.0,
    brightness: 0.0,
  );

  /// Check if this is the default (no adjustment)
  bool get isDefault {
    return hue == 0.0 && saturation == 1.0 && brightness == 0.0;
  }
}

/// Effect parameter information
class NosmaiEffectParameter {
  final String name;
  final String type;
  final double defaultValue;
  final String passId;
  final double? minValue;
  final double? maxValue;

  const NosmaiEffectParameter({
    required this.name,
    required this.type,
    required this.defaultValue,
    required this.passId,
    this.minValue,
    this.maxValue,
  });

  factory NosmaiEffectParameter.fromMap(Map<String, dynamic> map) {
    return NosmaiEffectParameter(
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      defaultValue: _parseDoubleSafely(map['defaultValue']) ?? 0.0,
      passId: map['passId']?.toString() ?? '',
      minValue: _parseDoubleSafely(map['minValue']),
      maxValue: _parseDoubleSafely(map['maxValue']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'defaultValue': defaultValue,
      'passId': passId,
      'minValue': minValue,
      'maxValue': maxValue,
    };
  }
}