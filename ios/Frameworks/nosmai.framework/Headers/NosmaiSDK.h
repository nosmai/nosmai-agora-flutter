/*
 * NosmaiSDK.h
 * Nosmai SDK - Simple and Powerful iOS Filter Framework
 *
 * Created by Nosmai SDK Team
 * Copyright © 2024 Nosmai. All rights reserved.
 */

#ifndef NOSMAI_SDK_H
#define NOSMAI_SDK_H

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#define UIView NSView
#endif
#import "NosmaiTypes.h"


NS_ASSUME_NONNULL_BEGIN

/**
 * NosmaiSDK - Simple interface for applying filters to camera preview
 *
 * This SDK provides an easy-to-use interface for applying real-time filters
 * to camera input. Initialize with a license key and start applying filters
 * with just a few lines of code.
 *
 * Face detection is handled automatically when needed - no manual setup
 * required.
 */
@interface NosmaiSDK : NSObject

#pragma mark - Delegate

/**
 * Set delegate for SDK events (optional)
 */
@property(nonatomic, weak, nullable) id<NosmaiDelegate> delegate;

#pragma mark - Initialization

/**
 * Initialize the SDK with a license key
 *
 * @param licenseKey Your Nosmai license key
 * @return An initialized SDK instance, or nil if license validation fails
 */
+ (nullable instancetype)initWithLicense:(NSString*)licenseKey;

/**
 * Get the shared SDK instance (must be initialized with license first)
 */
+ (nullable instancetype)sharedInstance;

#pragma mark - Camera Setup

/**
 * Configure camera input (required before starting)
 *
 * @param position Front or back camera
 * @param sessionPreset AVFoundation session preset (e.g.,
 * AVCaptureSessionPresetHigh)
 */
- (void)configureCameraWithPosition:(NosmaiCameraPosition)position
                      sessionPreset:(nullable NSString*)sessionPreset;

/**
 * Set the preview view where camera output will be displayed
 *
 * @param view The UIView to use for preview
 */
- (void)setPreviewView:(UIView*)view;

#pragma mark - Processing Control

/**
 * Start processing video input
 */
- (void)startProcessing;

/**
 * Stop processing video input
 */
- (void)stopProcessing;

#pragma mark - External Frame Processing

/**
 * Initialize SDK for offscreen processing without preview view
 *
 * @param width The width of frames that will be processed
 * @param height The height of frames that will be processed
 * @return YES if initialization was successful, NO otherwise
 */
- (BOOL)initializeOffscreenWithWidth:(NSInteger)width height:(NSInteger)height;

/**
 * Set the processing mode for the SDK
 *
 * @param mode The processing mode to use
 */
- (void)setProcessingMode:(NosmaiProcessingMode)mode;

/**
 * Get the current processing mode
 *
 * @return The current processing mode
 */
- (NosmaiProcessingMode)getProcessingMode;

/**
 * Process an external CVPixelBuffer frame
 *
 * @param pixelBuffer The pixel buffer to process
 * @param mirror Whether to mirror the frame horizontally
 * @return YES if processing was successful, NO otherwise
 */
- (BOOL)processFrame:(CVPixelBufferRef)pixelBuffer mirror:(BOOL)mirror;

/**
 * Process an external CMSampleBuffer frame
 *
 * @param sampleBuffer The sample buffer to process
 * @param mirror Whether to mirror the frame horizontally
 * @return YES if processing was successful, NO otherwise
 */
- (BOOL)processSampleBuffer:(CMSampleBufferRef)sampleBuffer mirror:(BOOL)mirror;

/**
 * Process an external frame asynchronously with completion callback
 *
 * @param pixelBuffer The pixel buffer to process
 * @param mirror Whether to mirror the frame horizontally
 * @param completion Callback when processing is complete
 */
- (void)processFrameAsync:(CVPixelBufferRef)pixelBuffer
                   mirror:(BOOL)mirror
               completion:(void (^)(BOOL success, NSError* error))completion;

/**
 * Check if external processing is available
 *
 * @return YES if external processing is available, NO otherwise
 */
- (BOOL)isExternalProcessingAvailable;

/**
 * Get processing performance metrics
 *
 * @return Dictionary with metrics like FPS, processing time, frames processed
 */
- (NSDictionary*)getProcessingMetrics;

#pragma mark - Video Recording Support

/**
 * Set callback for receiving video frames during recording
 * @param callback Block that receives RGBA frame data
 */
- (void)setRecordingCallback:(void (^)(const uint8_t* data,
                                       int width,
                                       int height,
                                       double timestamp))callback;

/**
 * Enable or disable frame capture for recording
 * @param enabled YES to start capturing frames, NO to stop
 */
- (void)setRecordingEnabled:(BOOL)enabled;

/**
 * @brief Enables or disables the output of processed CVPixelBuffers for live
 * streaming or real-time processing.
 *
 * @discussion This enables the internal recording sink to generate pixel
 * buffers for every processed frame without actually writing them to a file.
 * Use setCVPixelBufferCallback to receive these frames. This is separate from
 * file-based recording.
 *
 * @param enabled YES to start generating live frames, NO to stop.
 */
- (void)setLiveFrameOutputEnabled:(BOOL)enabled;

#pragma mark - Filter Application

/**
 * Apply a Nosmai effect from .nosmai file
 * Face detection is automatically enabled if the filter requires it
 *
 * @param effectPath Path to the .nosmai effect file
 * @param completion Completion callback with success status and error
 */
- (void)applyEffect:(NSString*)effectPath
         completion:(nullable void (^)(BOOL success,
                                       NSError* _Nullable error))completion;

/**
 * Apply a Nosmai effect synchronously (for internal use)
 * Face detection is automatically enabled if the filter requires it
 *
 * @param effectPath Path to the .nosmai effect file
 * @return YES if successful, NO otherwise
 */
- (BOOL)applyEffectSync:(NSString*)effectPath;

/**
 * Download a cloud filter
 *
 * @param filterId The filter ID to download
 * @param progressBlock Optional progress callback (0.0 to 1.0)
 * @param completion Completion callback with success status and local path
 */
- (void)downloadCloudFilter:(NSString*)filterId
                   progress:(nullable void (^)(float progress))progressBlock
                 completion:(void (^)(BOOL success,
                                      NSString* _Nullable localPath,
                                      NSError* _Nullable error))completion;

// Get Local Filters
- (nullable NSArray<NSDictionary*>*)getLocalFilters;

#pragma mark - Cloud Filters

/**
 * Get list of available cloud filters
 * Returns array of filter dictionaries with id, name, isFree, isDownloaded
 *
 * @return NSArray of filter info, nil if cloud filters not enabled
 */
- (nullable NSArray<NSDictionary*>*)getCloudFilters;

/**
 * Download a cloud filter
 *
 * @param filterId The filter ID to download
 * @param progressBlock Optional progress callback (0.0 to 1.0)
 * @param completion Completion callback with success status and local path
 */
- (void)downloadCloudFilter:(NSString*)filterId
                   progress:(nullable void (^)(float progress))progressBlock
                 completion:(void (^)(BOOL success,
                                      NSString* _Nullable localPath,
                                      NSError* _Nullable error))completion;

/**
 * Check if a cloud filter is downloaded
 *
 * @param filterId The filter ID to check
 * @return YES if downloaded, NO otherwise
 */
- (BOOL)isCloudFilterDownloaded:(NSString*)filterId;

/**
 * Get local path for a downloaded cloud filter
 *
 * @param filterId The filter ID
 * @return Local file path if downloaded, nil otherwise
 */
- (nullable NSString*)getCloudFilterLocalPath:(NSString*)filterId;

/**
 * Remove all applied filters
 */
- (void)removeAllFilters;

/**
 * Checks if the current license allows for built-in beauty effects.
 * This includes skin smoothing, face reshape, makeup, and other beauty filters.
 * @return YES if beauty effects are enabled, NO otherwise.
 */
- (BOOL)isBeautyEffectEnabled;

/**
 * Checks if the current license allows for using cloud filters.
 * Use this to control UI elements related to cloud filter functionality.
 * @return YES if cloud filters are enabled, NO otherwise.
 */
- (BOOL)isCloudFilterEnabled;

#pragma mark - Built-in Filter Control (Internal)

- (void)applyRGBFilterWithRed:(float)redAdjustment
                        green:(float)greenAdjustment
                         blue:(float)blueAdjustment;

- (void)applyBrightnessFilter:(float)brightness;

- (void)applyContrastFilter:(float)contrast;

- (void)applyFaceSlimming:(float)level;

- (void)applyEyeEnlargement:(float)level;

- (void)applyNoseSize:(float)level;

- (void)applySkinSmoothing:(float)level;
- (void)applySkinWhitening:(float)level;
- (void)applySharpening:(float)level;
- (void)applyMakeupBlendLevel:(NSString*)filterName level:(float)level;

- (void)applyGrayscaleFilter;
- (void)applyHue:(float)hueAngle;
- (void)resetHSBFilter;
- (void)adjustHSBWithHue:(float)hue
              saturation:(float)saturation
              brightness:(float)brightness;

- (void)applyWhiteBalanceWithTemperature:(float)temperature tint:(float)tint;

- (void)removeAllBuiltInFilters;

- (void)removeBuiltInFilterByName:(NSString*)filterName;

/**
 * Checks if the built-in filter chain has any active filters.
 * @return YES if any built-in filter is active, NO otherwise.
 */
- (BOOL)hasActiveBuiltInFilters;

#pragma mark - Effect Parameter Control

/**
 * Get all available parameters for the currently loaded effect
 *
 * @return NSArray of NSDictionary objects containing parameter metadata
 *         Each dictionary contains: name, type, defaultValue, passId
 *         Returns nil if no effect is active
 */
- (nullable NSArray<NSDictionary*>*)getEffectParameters;

/**
 * Set a parameter value for the currently loaded effect
 *
 * @param parameterName The name of the parameter to set
 * @param value The float value to set
 * @return YES if successful, NO if parameter not found or effect not active
 */
- (BOOL)setEffectParameter:(NSString*)parameterName value:(float)value;

/**
 * Get the current value of a parameter in the current effect
 *
 * @param parameterName The name of the parameter to query
 * @return The current parameter value, or 0.0 if not found
 */
- (float)getEffectParameterValue:(NSString*)parameterName;

#pragma mark - Local Filter Discovery

/**
 * Get initial filters (local and cached) for immediate UI display
 * This method runs synchronously and returns all locally available filters
 * organized by their filterType
 *
 * @return NSDictionary with filter types as keys and arrays of filters as
 * values
 */
- (NSDictionary<NSString*, NSArray<NSDictionary*>*>*)getInitialFilters;

/**
 * Fetch cloud filters asynchronously
 * This method triggers a background network request to get available cloud
 * filters Once complete, it calls the delegate method nosmaiDidUpdateFilters:
 * with the merged and organized list of all filters
 */
- (void)fetchCloudFilters;

/**
 * Load preview image for a specific filter
 *
 * Generates or loads a cached preview image that demonstrates the filter's
 * effect. Useful for displaying filter thumbnails in UI before applying.
 *
 * @param filterPath Path to the .nosmai filter file
 * @return Preview image showing filter effect, nil if loading fails
 */
- (UIImage*)loadPreviewImageForFilter:(NSString*)filterPath;

#pragma mark - Camera Control

/**
 * Switch between front and back camera
 *
 * @return YES if successful, NO otherwise
 */
- (BOOL)switchCamera;

/**
 * Set callback for receiving raw CVPixelBuffer frames
 *
 * Provides access to processed video frames as CVPixelBufferRef objects.
 * Useful for custom processing, analysis, or external rendering.
 * Called on background thread - dispatch to main queue if needed for UI
 * updates.
 *
 * @param callback Block that receives pixel buffer and timestamp
 *                 - pixelBuffer: Processed video frame with applied effects
 *                 - timestamp: Frame timestamp in seconds
 */
- (void)setCVPixelBufferCallback:(void (^)(CVPixelBufferRef pixelBuffer,
                                           double timestamp))callback;

#pragma mark - Cleanup

/**
 * Release all resources (call when done using SDK)
 */
- (void)cleanup;

#pragma mark - Memory Management

/**
 * Force comprehensive memory cleanup
 * This method aggressively clears all caches and releases unused resources
 * Call this when experiencing memory pressure or after heavy filter usage
 */
- (void)forceMemoryCleanup;

/**
 * Clear all filter-related caches
 * This includes preview images, decrypted data, and filter chain caches
 */
- (void)clearFiltersCache;

/**
 * Force filter chain rebuild
 * This ensures filters are properly applied and visible
 */
- (void)forceFilterChainRebuild;

/**
 * Get current cache size in bytes
 * @return Total size of cached decrypted filter data
 */
- (size_t)getCacheSize;

/**
 * Get number of cached filters
 * @return Number of filters currently cached in memory
 */
- (size_t)getCacheCount;

/**
 * Set maximum cache size (default: 50MB)
 * When cache exceeds this size, automatic cleanup will remove oldest entries
 * @param maxSizeBytes Maximum cache size in bytes
 */
- (void)setMaxCacheSize:(size_t)maxSizeBytes;

/**
 * Enable/disable automatic cache cleanup (default: enabled)
 * @param enabled Whether to automatically cleanup cache when limit is reached
 */
- (void)enableAutomaticCacheCleanup:(BOOL)enabled;

/**
 * Force cache cleanup using LRU strategy
 * Removes least recently used filter cache entries until under size limit
 */
- (void)forceCacheCleanup;

/**
 * Clear cache entry for specific filter
 * @param filterName Name of the filter to remove from cache
 * @return YES if entry was found and removed
 */
- (BOOL)clearCacheEntryForFilter:(NSString*)filterName;

#pragma mark - Filter Information Utilities

/**
 * Get filter information from .nosmai file
 * Extracts filter metadata from manifest including type, name, displayName, and
 * preview
 * @param filePath Path to .nosmai filter file
 * @return Dictionary containing filter info: type, name, displayName, preview
 * (nil if file invalid)
 */
- (nullable NSDictionary*)getFilterInfoFromPath:(NSString*)filePath;

@end

NS_ASSUME_NONNULL_END

#endif /* NOSMAI_SDK_H */
