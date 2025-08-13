/*
 * NosmaiCore.h
 * Nosmai SDK - Professional Camera Filter Framework
 *
 * Created by Nosmai SDK Team
 * Copyright © 2024 Nosmai. All rights reserved.
 */

#ifndef NOSMAI_CORE_H
#define NOSMAI_CORE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "NosmaiTypes.h"

@class NosmaiCamera;
@class NosmaiEffectsEngine;

NS_ASSUME_NONNULL_BEGIN

/**
 * NosmaiCore - Main SDK Interface
 *
 * This is the primary entry point for the Nosmai SDK. It provides a singleton
 * interface for SDK initialization, camera management, and effects processing.
 *
 * Example usage:
 * @code
 * [[NosmaiCore shared] initializeWithAPIKey:@"your-api-key" completion:^(BOOL
 * success, NSError *error) { if (success) {
 *         [[NosmaiCore shared].camera attachToView:previewView];
 *         [[NosmaiCore shared].camera startCapture];
 *     }
 * }];
 * @endcode
 */
@interface NosmaiCore : NSObject

#pragma mark - Singleton

/**
 * Returns the shared instance of Nosmai SDK
 *
 * @return The singleton instance
 */
+ (instancetype)shared;

#pragma mark - Properties

/**
 * Current SDK state
 */
@property(nonatomic, readonly) NosmaiState state;

/**
 * Camera interface for managing video capture
 */
@property(nonatomic, readonly, nullable) NosmaiCamera* camera;

/**
 * Effects engine for applying filters and effects
 */
@property(nonatomic, readonly, nullable) NosmaiEffectsEngine* effects;

/**
 * SDK configuration (read-only after initialization)
 */
@property(nonatomic, readonly, nullable) NosmaiConfig* configuration;

/**
 * SDK delegate for state changes and events
 */
@property(nonatomic, weak, nullable) id<NosmaiDelegate> delegate;

/**
 * SDK version string
 */
@property(nonatomic, readonly) NSString* version;

/**
 * Indicates if SDK is initialized and ready
 */
@property(nonatomic, readonly) BOOL isInitialized;

#pragma mark - Initialization

/**
 * Initialize the SDK with an API key
 *
 * This method performs asynchronous license verification and SDK
 * initialization. The completion block is called on the main thread.
 *
 * @param apiKey Your Nosmai API key for license verification
 * @param completion Block called when initialization completes or fails
 */
- (void)initializeWithAPIKey:(NSString*)apiKey
                  completion:(NosmaiInitializationCompletion)completion;

/**
 * Initialize the SDK with custom configuration
 *
 * @param config Custom SDK configuration
 * @param completion Block called when initialization completes or fails
 */
- (void)initializeWithConfig:(NosmaiConfig*)config
                  completion:(NosmaiInitializationCompletion)completion;

#pragma mark - Lifecycle

/**
 * Pause SDK operations (typically when app goes to background)
 *
 * This method pauses camera capture and effect processing to save resources.
 */
- (void)pause;

/**
 * Resume SDK operations (typically when app becomes active)
 *
 * This method resumes camera capture and effect processing.
 */
- (void)resume;

/**
 * Clean up and release all SDK resources
 *
 * Call this method when you're done using the SDK to free up resources.
 * After calling this, you'll need to initialize again before using the SDK.
 */
- (void)cleanup;

#pragma mark - State Management

/**
 * Get current license status
 *
 * @return YES if license is valid, NO otherwise
 */
- (BOOL)isLicenseValid;

/**
 * Get license error message if any
 *
 * @return Error message string, or nil if license is valid
 */
- (nullable NSString*)licenseError;

/**
 * Retry license verification
 *
 * Use this method to retry license verification if it failed during
 * initialization.
 *
 * @param completion Block called when verification completes
 */
- (void)retryLicenseVerification:(void (^)(BOOL success,
                                           NSError* _Nullable error))completion;

#pragma mark - Video Recording

/**
 * Check if currently recording
 *
 * @return YES if recording is in progress
 */
@property(nonatomic, readonly) BOOL isRecording;

// /**
//  * Current recording configuration (uses default if not set)
//  */
// @property(nonatomic, strong, nullable)
//     NosmaiRecordingConfig* recordingConfiguration;

/**
 * Start video recording with default settings
 *
 * Uses preview view size and default configuration.
 * Saves to temporary directory with auto-generated filename.
 */
- (void)startRecording;

/**
 * Stop video recording
 *
 * Stops recording and saves video to temporary directory.
 */
- (void)stopRecording;

/**
 * Start video recording with completion handler
 *
 * @param completion Block called when recording starts or fails
 */
- (void)startRecordingWithCompletion:
    (nullable void (^)(BOOL success, NSError* _Nullable error))completion;

/**
 * Stop video recording with completion handler
 *
 * @param completion Block called when recording stops with video URL
 */
- (void)stopRecordingWithCompletion:
    (nullable void (^)(NSURL* _Nullable videoURL,
                       NSError* _Nullable error))completion;

/**
 * Get current recording duration
 *
 * @return Recording duration in seconds, 0 if not recording
 */
- (NSTimeInterval)currentRecordingDuration;

#pragma mark - Photo Capture

/**
 * Capture photo with applied filters
 *
 * @param completion Block called with filtered photo or error
 */
- (void)capturePhoto:(void (^)(UIImage* _Nullable image,
                               NSError* _Nullable error))completion;

#pragma mark - Debugging

/**
 * Enable or disable debug logging
 *
 * @param enabled YES to enable debug logs, NO to disable
 */
- (void)setDebugLoggingEnabled:(BOOL)enabled;

/**
 * Get current debug log status
 *
 * @return YES if debug logging is enabled
 */
- (BOOL)isDebugLoggingEnabled;

/**
 * Export current SDK state for debugging
 *
 * @return Dictionary containing current SDK state information
 */
- (NSDictionary<NSString*, id>*)exportDebugInfo;

#pragma mark - Live Frame Streaming

/**
 @brief A callback block that gets triggered for every processed frame.

 @discussion Set this property to a block to start receiving live, filtered
 video frames. The frames are provided as `CVPixelBufferRef`, which is ideal for
 real-time processing or live streaming. Set this property to `nil` to stop
 receiving frames and conserve resources.

 The callback is executed on a background processing thread for maximum
 performance.
 */
@property(nonatomic, copy, nullable) void (^liveFrameStreamCallback)
    (CVPixelBufferRef pixelBuffer, double timestamp);

#pragma mark - Unavailable Methods

/**
 * Unavailable. Use +shared instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * Unavailable. Use +shared instead.
 */
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif /* NOSMAI_CORE_H */
