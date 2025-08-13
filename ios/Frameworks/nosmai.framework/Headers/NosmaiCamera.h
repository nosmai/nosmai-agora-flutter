/*
 * NosmaiCamera.h
 * Nosmai SDK Camera Management Interface
 *
 * Created by Nosmai SDK Team
 * Copyright © 2024 Nosmai. All rights reserved.
 */

#ifndef NOSMAI_CAMERA_H
#define NOSMAI_CAMERA_H

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "NosmaiTypes.h"

@class NosmaiSDK;

NS_ASSUME_NONNULL_BEGIN

/**
 * NosmaiCamera - Professional Camera Management
 *
 * This class provides a clean interface for camera operations including
 * capture control, configuration, and preview management.
 */
@interface NosmaiCamera : NSObject

#pragma mark - Properties

/**
 * Current camera state
 */
@property(nonatomic, readonly) NosmaiCameraState state;

/**
 * Current camera position (front/back)
 */
@property(nonatomic, readonly) NosmaiCameraPosition position;

/**
 * Current camera configuration
 */
@property(nonatomic, readonly) NosmaiCameraConfig* configuration;

/**
 * Camera delegate for state changes and events
 */
@property(nonatomic, weak, nullable) id<NosmaiCameraDelegate> delegate;

/**
 * Indicates if camera is currently capturing
 */
@property(nonatomic, readonly) BOOL isCapturing;

/**
 * Indicates if camera was paused while capturing (for resume functionality)
 */
@property(nonatomic, readonly) BOOL wasPausedWhileCapturing;

/**
 * The view currently attached for preview
 */
@property(nonatomic, readonly, weak, nullable) UIView* previewView;

#pragma mark - Initialization

/**
 * Initialize camera with internal SDK instance
 *
 * @param internalSDK The internal NosmaiSDK instance
 * @return Initialized camera instance
 */
- (instancetype)initWithInternalSDK:(NosmaiSDK*)internalSDK
    NS_DESIGNATED_INITIALIZER;

/**
 * Unavailable. Use initWithInternalSDK: instead.
 */
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Preview Management

/**
 * Attach camera preview to a view
 *
 * @param view The UIView to display camera preview
 */
- (void)attachToView:(UIView*)view;

/**
 * Detach camera preview from current view
 */
- (void)detachFromView;

/**
 * Update preview orientation
 *
 * @param orientation The desired video orientation
 */
- (void)updatePreviewOrientation:(NosmaiVideoOrientation)orientation;

#pragma mark - Capture Control

/**
 * Start camera capture
 *
 * @return YES if capture started successfully, NO otherwise
 */
- (BOOL)startCapture;

/**
 * Stop camera capture
 */
- (void)stopCapture;

/**
 * Pause camera capture (maintains session)
 */
- (void)pauseCapture;

/**
 * Resume camera capture after pause
 */
- (void)resumeCapture;

#pragma mark - Camera Configuration

/**
 * Switch between front and back camera
 *
 * @return YES if switch was successful, NO otherwise
 */
- (BOOL)switchCamera;

/**
 * Switch to specific camera position
 *
 * @param position The desired camera position
 * @return YES if switch was successful, NO otherwise
 */
- (BOOL)switchToPosition:(NosmaiCameraPosition)position;

/**
 * Update camera configuration
 *
 * @param config The new camera configuration
 */
- (void)updateConfiguration:(NosmaiCameraConfig*)config;

/**
 * Set video quality preset
 *
 * @param preset AVCaptureSessionPreset value
 */
- (void)setVideoQualityPreset:(AVCaptureSessionPreset)preset;

/**
 * Set frame rate
 *
 * @param frameRate Desired frame rate (e.g., 30, 60)
 * @return YES if frame rate was set successfully
 */
- (BOOL)setFrameRate:(NSInteger)frameRate;

#pragma mark - Camera Capabilities

/**
 * Check if device has front camera
 *
 * @return YES if front camera is available
 */
+ (BOOL)hasFrontCamera;

/**
 * Check if device has back camera
 *
 * @return YES if back camera is available
 */
+ (BOOL)hasBackCamera;

/**
 * Check if flash is available for current camera
 *
 * @return YES if flash is available
 */
- (BOOL)hasFlash;

/**
 * Check if torch is available for current camera
 *
 * @return YES if torch is available
 */
- (BOOL)hasTorch;

#pragma mark - Flash and Torch Control

/**
 * Set flash mode
 *
 * @param flashMode AVCaptureFlashMode value
 * @return YES if flash mode was set successfully
 */
- (BOOL)setFlashMode:(AVCaptureFlashMode)flashMode;

/**
 * Set torch mode
 *
 * @param torchMode AVCaptureTorchMode value
 * @return YES if torch mode was set successfully
 */
- (BOOL)setTorchMode:(AVCaptureTorchMode)torchMode;

#pragma mark - Focus and Exposure

/**
 * Set focus point of interest
 *
 * @param point Focus point in view coordinates (0,0 to 1,1)
 * @return YES if focus point was set successfully
 */
- (BOOL)setFocusPointOfInterest:(CGPoint)point;

/**
 * Set exposure point of interest
 *
 * @param point Exposure point in view coordinates (0,0 to 1,1)
 * @return YES if exposure point was set successfully
 */
- (BOOL)setExposurePointOfInterest:(CGPoint)point;

/**
 * Reset focus and exposure to auto
 */
- (void)resetFocusAndExposure;

#pragma mark - Video Recording

/**
 * Start video recording to file
 *
 * @param outputURL URL for the output video file
 * @param completion Block called when recording starts or fails
 */
- (void)startRecordingToURL:(NSURL*)outputURL
                 completion:
                     (nullable void (^)(NSError* _Nullable error))completion;

/**
 * Stop video recording
 *
 * @param completion Block called when recording stops with final URL
 */
- (void)stopRecordingWithCompletion:
    (void (^)(NSURL* _Nullable outputURL, NSError* _Nullable error))completion;

/**
 * Check if currently recording video
 *
 * @return YES if recording is in progress
 */
- (BOOL)isRecording;

#pragma mark - Zoom Control

/**
 * Set zoom factor
 *
 * @param zoomFactor The desired zoom factor (1.0 = no zoom)
 * @return YES if zoom was set successfully
 */
- (BOOL)setZoomFactor:(CGFloat)zoomFactor;

/**
 * Get current zoom factor
 *
 * @return Current zoom factor
 */
- (CGFloat)currentZoomFactor;

/**
 * Get maximum zoom factor for current camera
 *
 * @return Maximum zoom factor
 */
- (CGFloat)maxZoomFactor;

/**
 * Smoothly zoom to factor with animation
 *
 * @param zoomFactor Target zoom factor
 * @param duration Animation duration in seconds
 */
- (void)rampToZoomFactor:(CGFloat)zoomFactor
            withDuration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END

#endif /* NOSMAI_CAMERA_H */
