/*
 * NosmaiTypes.h
 * Nosmai SDK Types and Enumerations - PROFESSIONAL INTERFACE
 *
 * Created by Nosmai SDK Team
 * Copyright © 2024 Nosmai. All rights reserved.
 */

#ifndef NOSMAI_TYPES_H
#define NOSMAI_TYPES_H

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - SDK State Management

/**
 * SDK initialization and runtime states
 */
typedef NS_ENUM(NSInteger, NosmaiState) {
  NosmaiStateUninitialized = 0,  // SDK not initialized
  NosmaiStateInitializing,       // License verification in progress
  NosmaiStateReady,              // SDK ready to use
  NosmaiStateError,              // Initialization failed
  NosmaiStatePaused,             // SDK paused (app in background)
  NosmaiStateTerminated          // SDK terminated
};

#pragma mark - Camera Types

/**
 * Camera position enumeration
 */
typedef NS_ENUM(NSInteger, NosmaiCameraPosition) {
  NosmaiCameraPositionBack = 0,
  NosmaiCameraPositionFront
};

/**
 * Camera state enumeration
 */
typedef NS_ENUM(NSInteger, NosmaiCameraState) {
  NosmaiCameraStateStopped = 0,
  NosmaiCameraStateStarting,
  NosmaiCameraStateRunning,
  NosmaiCameraStateStopping,
  NosmaiCameraStateError
};

/**
 * Video orientation modes
 */
typedef NS_ENUM(NSInteger, NosmaiVideoOrientation) {
  NosmaiVideoOrientationPortrait = 0,
  NosmaiVideoOrientationPortraitUpsideDown,
  NosmaiVideoOrientationLandscapeLeft,
  NosmaiVideoOrientationLandscapeRight
};

#pragma mark - Effect Types

/**
 * Effect loading state
 */
typedef NS_ENUM(NSInteger, NosmaiEffectState) {
  NosmaiEffectStateNotLoaded = 0,
  NosmaiEffectStateLoading,
  NosmaiEffectStateReady,
  NosmaiEffectStateError
};

#pragma mark - Error Codes

/**
 * SDK error codes
 */
typedef NS_ENUM(NSInteger, NosmaiErrorCode) {
  NosmaiErrorCodeUnknown = 1000,
  NosmaiErrorCodeLicenseInvalid = 1001,
  NosmaiErrorCodeLicenseExpired = 1002,
  NosmaiErrorCodeNetworkError = 1003,
  NosmaiErrorCodeCameraPermissionDenied = 1004,
  NosmaiErrorCodeCameraNotAvailable = 1005,
  NosmaiErrorCodeEffectLoadFailed = 1006,
  NosmaiErrorCodeInitializationFailed = 1007,
  NosmaiErrorCodeResourceNotFound = 1008,
  NosmaiErrorCodeInvalidParameter = 1009,
  NosmaiErrorCodeMemoryError = 1010,
  NosmaiErrorCodeFeatureNotEnabled = 403
};

#pragma mark - Completion Blocks

/**
 * SDK initialization completion block
 */
typedef void (^NosmaiInitializationCompletion)(BOOL success,
                                               NSError* _Nullable error);

/**
 * Effect loading completion block
 */
typedef void (^NosmaiEffectLoadCompletion)(BOOL success,
                                           NSError* _Nullable error);

/**
 * Cloud filter download progress block
 */
typedef void (^NosmaiDownloadProgress)(float progress);

/**
 * Cloud filter download completion block
 */
typedef void (^NosmaiDownloadCompletion)(BOOL success,
                                         NSString* _Nullable localPath,
                                         NSError* _Nullable error);

#pragma mark - Constants

/**
 * Error domain for Nosmai SDK
 */
extern NSErrorDomain const NosmaiErrorDomain;

/**
 * Current SDK version
 */
extern NSString* const NosmaiSDKVersion;

/**
 * Notification names
 */
extern NSNotificationName const NosmaiStateDidChangeNotification;
extern NSNotificationName const NosmaiCameraStateDidChangeNotification;
extern NSNotificationName const NosmaiEffectStateDidChangeNotification;

#pragma mark - Face Detection

/**
 * Face information structure
 */
@interface NosmaiFaceInfo : NSObject
@property(nonatomic, assign) CGRect boundingBox;
@property(nonatomic, assign) NSInteger faceID;
@property(nonatomic, assign) float confidence;
@property(nonatomic, assign) BOOL hasLandmarks;
@end

#pragma mark - Configuration

/**
 * Camera configuration
 */
@interface NosmaiCameraConfig : NSObject
@property(nonatomic, assign) NosmaiCameraPosition position;
@property(nonatomic, strong) NSString* sessionPreset;
@property(nonatomic, assign) NSInteger frameRate;
@property(nonatomic, assign) NosmaiVideoOrientation orientation;
@property(nonatomic, assign) BOOL enableMirroring;
@property(nonatomic, assign) AVCaptureFlashMode flashMode;
@end

/**
 * SDK configuration
 */
@interface NosmaiConfig : NSObject
@property(nonatomic, strong) NSString* apiKey;
@property(nonatomic, assign) BOOL enableDebugLogging;
@property(nonatomic, assign) BOOL enableFaceDetection;
@property(nonatomic, assign) NSTimeInterval licenseCheckTimeout;
@property(nonatomic, strong, nullable) NSString* cloudFilterCachePath;
@end

#pragma mark - External Input Types

/**
 * External input pixel format types
 */
typedef NS_ENUM(NSInteger, NosmaiPixelFormat) {
  NosmaiPixelFormatRGBA32 = 0,  // 32-bit RGBA (8 bits per channel)
  NosmaiPixelFormatBGRA32 =
      1,  // 32-bit BGRA (8 bits per channel) - iOS standard
  NosmaiPixelFormatRGB24 = 2,      // 24-bit RGB (8 bits per channel, no alpha)
  NosmaiPixelFormatYUV420P = 3,    // YUV 420 planar format
  NosmaiPixelFormatNV12 = 4,       // YUV 420 semi-planar format
  NosmaiPixelFormatNV21 = 5,       // YUV 420 semi-planar format (Android)
  NosmaiPixelFormatGrayscale = 6,  // 8-bit grayscale
  NosmaiPixelFormatYUV422 = 7,     // YUV 422 format
  NosmaiPixelFormatAuto = 8        // Auto-detect format
};

/**
 * External input source types
 */
typedef NS_ENUM(NSInteger, NosmaiInputSourceType) {
  NosmaiInputSourceTypeNone = 0,
  NosmaiInputSourceTypeCamera = 1,
  NosmaiInputSourceTypeExternalData = 2,
  NosmaiInputSourceTypeVideoFile = 3,
  NosmaiInputSourceTypeImage = 4
};

/**
 * Input source state
 */
typedef NS_ENUM(NSInteger, NosmaiInputState) {
  NosmaiInputStateInactive = 0,
  NosmaiInputStateInitializing = 1,
  NosmaiInputStateActive = 2,
  NosmaiInputStatePaused = 3,
  NosmaiInputStateError = 4
};

/**
 * Input source conflict handling strategies
 */
typedef NS_ENUM(NSInteger, NosmaiConflictStrategy) {
  NosmaiConflictStrategyAutoStopPrevious =
      0,  // Automatically stop previous source (default)
  NosmaiConflictStrategyErrorOnConflict = 1,  // Return error if conflict occurs
  NosmaiConflictStrategyQueueRequest = 2,     // Queue the request for later
  NosmaiConflictStrategyPriorityBased = 3     // Use priority system
};

/**
 * External frame data
 */
@interface NosmaiExternalFrameData : NSObject
@property(nonatomic, strong) NSData* pixelData;
@property(nonatomic, assign) NSInteger width;
@property(nonatomic, assign) NSInteger height;
@property(nonatomic, assign) NSInteger stride;
@property(nonatomic, assign) NosmaiPixelFormat pixelFormat;
@property(nonatomic, assign) NSTimeInterval timestamp;
@end

/**
 * External input completion blocks
 */
typedef void (^NosmaiExternalInputCompletion)(BOOL success,
                                              NSError* _Nullable error);

/**
 * SDK processing modes
 */
typedef NS_ENUM(NSInteger, NosmaiProcessingMode) {
  NosmaiProcessingModeLive = 0,       // Internal camera with preview
  NosmaiProcessingModeOffscreen = 1,  // External frames only
  NosmaiProcessingModeHybrid = 2      // Both modes
};

#pragma mark - Recording Types

/**
 * Video recording quality presets
 */
typedef NS_ENUM(NSInteger, NosmaiVideoQuality) {
  NosmaiVideoQualityLow = 0,     // 480p, 1 Mbps
  NosmaiVideoQualityMedium = 1,  // 720p, 2.5 Mbps
  NosmaiVideoQualityHigh = 2,    // 1080p, 4 Mbps
  NosmaiVideoQualityUltra = 3    // 1080p, 8 Mbps
};

/**
 * Recording configuration
 */
@interface NosmaiRecordingConfig : NSObject

/**
 * Video quality preset (default: NosmaiVideoQualityHigh)
 */
@property(nonatomic, assign) NosmaiVideoQuality videoQuality;

/**
 * Include audio in recording (default: YES)
 */
@property(nonatomic, assign) BOOL includeAudio;

/**
 * Maximum recording duration in seconds (0 = unlimited, default: 0)
 */
@property(nonatomic, assign) NSTimeInterval maxDuration;

/**
 * Custom output directory (nil = default temp directory)
 */
@property(nonatomic, strong, nullable) NSURL* outputDirectory;

/**
 * Custom video dimensions (CGSizeZero = use preview size)
 */
@property(nonatomic, assign) CGSize videoSize;

/**
 * Frame rate (0 = default 30 fps)
 */
@property(nonatomic, assign) NSInteger frameRate;

/**
 * Create default configuration
 */
+ (instancetype)defaultConfig;

@end

#pragma mark - Delegate Protocols

/**
 * Main SDK delegate
 */
@protocol NosmaiDelegate <NSObject>
@optional
- (void)nosmaiDidChangeState:(NosmaiState)newState;
- (void)nosmaiDidFailWithError:(NSError*)error;
- (void)nosmaiDidDetectFaces:(NSArray<NosmaiFaceInfo*>*)faces;
- (void)nosmaiDidUpdateFilters:
    (NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters;
- (void)nosmaiInputSourceDidChange:(NosmaiInputSourceType)oldSource
                         newSource:(NosmaiInputSourceType)newSource;
- (void)nosmaiDidProcessExternalFrame:(BOOL)success
                                error:(NSError* _Nullable)error;

/**
 * Called when a processed frame is available from the SDK
 * @param processedFrame The processed CMSampleBuffer with filters applied
 * @param timestamp The frame timestamp
 */
- (void)frameAvailable:(CMSampleBufferRef)processedFrame
             timestamp:(NSTimeInterval)timestamp;

/**
 * Called when a processed pixel buffer is available from the SDK
 * @param processedPixelBuffer The processed CVPixelBufferRef with filters
 * applied
 * @param timestamp The frame timestamp
 */
- (void)pixelBufferAvailable:(CVPixelBufferRef)processedPixelBuffer
                   timestamp:(NSTimeInterval)timestamp;

/**
 * Called after processing a frame with performance metrics
 * @param success Whether processing was successful
 * @param processingTime Time taken to process the frame in milliseconds
 * @param error Error information if processing failed
 */
- (void)nosmaiDidProcessFrame:(BOOL)success
               processingTime:(double)processingTime
                        error:(NSError* _Nullable)error;
@end

/**
 * Camera delegate
 */
@protocol NosmaiCameraDelegate <NSObject>
@optional
- (void)nosmaiCameraDidChangeState:(NosmaiCameraState)newState;
- (void)nosmaiCameraDidFailWithError:(NSError*)error;
- (void)nosmaiCameraDidCaptureFrame;
@end

/**
 * Effects delegate
 */
@protocol NosmaiEffectsDelegate <NSObject>
@optional
- (void)nosmaiEffectDidChangeState:(NosmaiEffectState)newState
                         forEffect:(NSString*)effectID;
- (void)nosmaiEffectDidFailWithError:(NSError*)error
                           forEffect:(NSString*)effectID;
@end

NS_ASSUME_NONNULL_END

#endif /* NOSMAI_TYPES_H */
