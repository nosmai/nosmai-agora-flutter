/*
 * NOSMAI SDK - API Configuration Implementation
 *
 * Created by NOSMAI, LLC on 2025/6/24.
 * https://nosmai.com
 * Copyright © 2025 NOSMAI. All rights reserved.
 */
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NosmaiRecordingState) {
  NosmaiRecordingStateIdle,
  NosmaiRecordingStateStarting,
  NosmaiRecordingStateRecording,
  NosmaiRecordingStateStopping,
  NosmaiRecordingStateError
};

@interface NosmaiVideoRecorder : NSObject

@property(nonatomic, readonly) NosmaiRecordingState state;
@property(nonatomic, readonly) BOOL isRecording;
@property(nonatomic, readonly) NSTimeInterval recordingDuration;
@property(nonatomic, readonly) CGSize videoSize;
@property (nonatomic, strong) NSURL *originalOutputURL;  
@property (nonatomic, strong) NSURL *standbyOutputURL;   

- (instancetype)initWithVideoSize:(CGSize)videoSize;

- (void)startRecordingToURL:(NSURL*)outputURL
                 completion:(void (^)(BOOL success,
                                      NSError* _Nullable error))completion;

- (void)stopRecordingWithCompletion:
    (void (^)(NSURL* _Nullable outputURL, NSError* _Nullable error))completion;

- (void)appendPixelBuffer:(CVPixelBufferRef)pixelBuffer
                   atTime:(CMTime)presentationTime;

- (void)processFrameData:(const uint8_t*)data
                   width:(int)width
                  height:(int)height
               timestamp:(double)timestamp;

- (void)processCVPixelBuffer:(CVPixelBufferRef)pixelBuffer
                   timestamp:(double)timestamp;

// Audio support methods (add these before @end)

/**
 * Set whether to include audio in recording
 * Must be called before startRecordingToURL
 *
 * @param includeAudio YES to include audio, NO for video only
 */
- (void)setIncludeAudio:(BOOL)includeAudio;

/**
 * Add audio input to the recorder
 * Call this after startRecordingToURL if recording with separate audio
 *
 * @param audioInput The audio asset writer input
 */
- (void)addAudioInput:(AVAssetWriterInput*)audioInput;

- (void)prewarmRecordingPipeline;

/**
 * Update the video size for recording
 * Must be called when recorder is idle (not recording)
 *
 * @param newSize The new video size to use
 */
- (void)updateVideoSize:(CGSize)newSize;

@end

NS_ASSUME_NONNULL_END
