//
//  NosmaiAgoraBridge.m
//  Agora Flutter SDK - Nosmai Integration
//
//  Created by Agora Team
//  Copyright © 2024. All rights reserved.
//

#import "NosmaiAgoraBridge.h"
#import <Photos/Photos.h>

@interface NosmaiAgoraBridge () <AgoraRtcEngineDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AgoraRtcEngineKit *agoraEngine;
#if HAS_NOSMAI_FRAMEWORK
@property (nonatomic, strong) NosmaiSDK *nosmaiSDK;
@property (nonatomic, strong) NosmaiCamera *nosmaiCamera;
#endif
@property (nonatomic, assign) BOOL nosmaiInitialized;
@property (nonatomic, assign) BOOL agoraInitialized;
@property (nonatomic, assign) BOOL isCustomCameraActive;
@property (nonatomic, assign) BOOL channelJoined;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) NSDate *recordingStartTime;
@property (nonatomic, strong) NSString *currentChannelId;
@property (nonatomic, assign) NSUInteger currentUserId;
@property (nonatomic, assign) BOOL allowPush;

// camera properties
@property (nonatomic, assign) BOOL isStandaloneCameraActive;
@property (nonatomic, assign) NosmaiCameraPosition currentCameraPosition;

// Camera and video capture
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *captureDevice;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;

// Filter state tracking
@property (nonatomic, assign) float skinSmoothingLevel;
@property (nonatomic, assign) float skinWhiteningLevel;
@property (nonatomic, assign) float faceSlimmingLevel;
@property (nonatomic, assign) float eyeEnlargementLevel;
@property (nonatomic, assign) float noseSizeLevel;
@property (nonatomic, assign) float brightnessLevel;
@property (nonatomic, assign) float contrastLevel;
@property (nonatomic, assign) float hueLevel;
@property (nonatomic, assign) float lipstickLevel;
@property (nonatomic, assign) float blusherLevel;
@property (nonatomic, assign) float redMultiplier;
@property (nonatomic, assign) float greenMultiplier;
@property (nonatomic, assign) float blueMultiplier;
@property (nonatomic, assign) float exposureLevel;
@property (nonatomic, assign) float saturationLevel;
@property (nonatomic, assign) float sharpenLevel;
@property (nonatomic, assign) float whiteBalanceTemp;
@property (nonatomic, assign) float whiteBalanceTint;
@property (nonatomic, assign) BOOL grayscaleEnabled;

// HSB adjustment values
@property (nonatomic, assign) float hsbHue;
@property (nonatomic, assign) float hsbSaturation;
@property (nonatomic, assign) float hsbBrightness;

// Preview view for NosmaiSDK
@property (nonatomic, strong) UIView *localPreviewView;

// Mirror state for frame processing
@property (nonatomic, assign) BOOL mirrorModeEnabled;

// Thread-safe cleanup flag (atomic to prevent race conditions)
@property (atomic, assign) BOOL isCleaningUp;

// Serial queue for preview view access (thread-safe)
@property (nonatomic, strong) dispatch_queue_t previewAccessQueue;

@property (nonatomic, strong) CIContext *sharedCIContext;

@property (atomic, assign) BOOL isProcessingFrame;

@end

@implementation NosmaiAgoraBridge

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static NosmaiAgoraBridge *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NosmaiAgoraBridge alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self resetFilterStates];
        _videoDataOutputQueue = dispatch_queue_create("com.agora.nosmai.videoQueue", DISPATCH_QUEUE_SERIAL);
        _previewAccessQueue = dispatch_queue_create("com.agora.nosmai.previewQueue", DISPATCH_QUEUE_SERIAL);
        _mirrorModeEnabled = NO;
        _isCleaningUp = NO;
        _isProcessingFrame = NO;

        _sharedCIContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,  
            kCIContextPriorityRequestLow: @NO
        }];
    }
    return self;
}

#pragma mark - Preview View Management

- (void)setLocalPreviewView:(UIView *)view {
    dispatch_sync(self.previewAccessQueue, ^{
        _localPreviewView = view;
    });

    if (!view) {
        return;
    }

    @try {
#if HAS_NOSMAI_FRAMEWORK
        if (self.nosmaiSDK) {
            if ([NSThread isMainThread]) {
                [self.nosmaiSDK setPreviewView:view];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // ✅ Thread-safe getter in async block
                    __block UIView *currentView = nil;
                    dispatch_sync(self.previewAccessQueue, ^{
                        currentView = _localPreviewView;
                    });
                    if (currentView == view) {
                        [self.nosmaiSDK setPreviewView:view];
                    }
                });
            }
        }
#endif
    } @catch (NSException *exception) {
        // Handle exception silently
    }
}

- (UIView *)getLocalPreviewView {
    __block UIView *view = nil;
    dispatch_sync(self.previewAccessQueue, ^{
        view = _localPreviewView;
    });
    return view;
}

#pragma mark - Private Methods

- (void)resetFilterStates {
    _skinSmoothingLevel = 0.0f;
    _skinWhiteningLevel = 0.0f;
    _faceSlimmingLevel = 0.0f;
    _eyeEnlargementLevel = 0.0f;
    _noseSizeLevel = 0.0f;
    _brightnessLevel = 0.0f;
    _contrastLevel = 1.0f;
    _hueLevel = 0.0f;
    _lipstickLevel = 0.0f;
    _blusherLevel = 0.0f;
    _redMultiplier = 1.0f;
    _greenMultiplier = 1.0f;
    _blueMultiplier = 1.0f;
    _exposureLevel = 0.0f;
    _saturationLevel = 1.0f;
    _sharpenLevel = 0.0f;
    _whiteBalanceTemp = 5000.0f;
    _whiteBalanceTint = 0.0f;
    _grayscaleEnabled = NO;

    // ✅ Reset HSB filter states
    _hsbHue = 0.0f;
    _hsbSaturation = 1.0f;
    _hsbBrightness = 1.0f;
}

- (BOOL)hasActiveFilters {
    return _skinSmoothingLevel > 0.0f ||
           _skinWhiteningLevel > 0.0f ||
           _faceSlimmingLevel > 0.0f ||
           _eyeEnlargementLevel > 0.0f ||
           _noseSizeLevel > 0.0f ||
           _brightnessLevel != 0.0f ||
           _contrastLevel != 1.0f ||
           _hueLevel != 0.0f ||
           _lipstickLevel > 0.0f ||
           _blusherLevel > 0.0f ||
           _redMultiplier != 1.0f ||
           _greenMultiplier != 1.0f ||
           _blueMultiplier != 1.0f ||
           _exposureLevel != 0.0f ||
           _saturationLevel != 1.0f ||
           _sharpenLevel > 0.0f ||
           _whiteBalanceTemp != 5000.0f ||
           _whiteBalanceTint != 0.0f ||
           _grayscaleEnabled;
}

#pragma mark - Initialization

- (BOOL)initNosmaiWithLicense:(NSString *)licenseKey {
#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiInitialized) {
        return YES;
    }
    
    @try {
        // Initialize NosmaiCore like in the reference SDK
        __weak typeof(self) weakSelf = self;
        __block BOOL initResult = NO;
        __block BOOL completed = NO;
        
        [[NosmaiCore shared] initializeWithAPIKey:licenseKey completion:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                completed = YES;
                return;
            }
            
            initResult = success;
            if (success) {
                strongSelf.nosmaiInitialized = YES;

                // Initialize NosmaiSDK as well for backward compatibility
                strongSelf.nosmaiSDK = [NosmaiSDK initWithLicense:licenseKey];

                // 🎯 Set default camera position to FRONT for camera preview
                // (back camera is default for streaming)
                strongSelf.currentCameraPosition = NosmaiCameraPositionFront;

            } else {
            }
            completed = YES;
        }];
        
        // Wait for completion (with timeout)
        NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10.0];
        while (!completed && [timeout timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        
        if (!completed) {
            return NO;
        }
        
        return initResult;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)initAgoraWithAppId:(NSString *)appId {
    if (self.agoraEngine) {
        [self.agoraEngine leaveChannel:nil];
        [AgoraRtcEngineKit destroy];
        self.agoraEngine = nil;
        self.agoraInitialized = NO;
        self.channelJoined = NO;
        self.currentChannelId = nil;
        self.currentUserId = 0;
        self.allowPush = NO;
    }
    
    @try {
        self.agoraEngine = [AgoraRtcEngineKit sharedEngineWithAppId:appId delegate:self];
        if (self.agoraEngine) {
            self.agoraInitialized = YES;
            return YES;
        } else {
            return NO;
        }
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)releaseAgora {
    if (self.agoraEngine) {
        [AgoraRtcEngineKit destroy];
        self.agoraEngine = nil;
        self.agoraInitialized = NO;
    }
}

#pragma mark - Streaming Control

- (BOOL)startCustomCameraWithAppId:(NSString *)appId
                             token:(NSString *)token
                         channelId:(NSString *)channelId
                            userId:(NSUInteger)userId
               startCameraImmediately:(BOOL)startCameraImmediately {
    @try {
        
        // For multi-host scenario: if same channel but different user, need to restart camera
        if (self.isCustomCameraActive && [self.currentChannelId isEqualToString:channelId]) {
            if (self.currentUserId != userId && userId != 0) {
                [self stopCamera];
                [NSThread sleepForTimeInterval:0.2];
            } else {
                return YES;
            }
        }
        
        // If active with different channel, cleanup first
        if (self.isCustomCameraActive && ![self.currentChannelId isEqualToString:channelId]) {
            [self teardownStreaming];
            [NSThread sleepForTimeInterval:0.1]; // Small delay
        }
        
        // Ensure singleton is initialized
        if (!self.agoraInitialized || !self.agoraEngine) {
            if (![self initAgoraWithAppId:appId]) {
                return NO;
            }
        }
        
        
        // Configure video and audio
        [self.agoraEngine enableVideo];
        [self.agoraEngine setClientRole:AgoraClientRoleBroadcaster];
        [self.agoraEngine adjustPlaybackSignalVolume:0];
        [self.agoraEngine muteAllRemoteAudioStreams:YES];
        [self.agoraEngine enableAudio];
        [self.agoraEngine muteAllRemoteAudioStreams:YES];
        
        // Set up external video source
        [self.agoraEngine setExternalVideoSource:YES useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
        
        // Configure video encoder (720p portrait with fixed orientation)
        AgoraVideoEncoderConfiguration *videoConfig = [[AgoraVideoEncoderConfiguration alloc] 
                                                        initWithSize:CGSizeMake(720, 1280)
                                                        frameRate:AgoraVideoFrameRateFps30
                                                        bitrate:1800
                                                        orientationMode:AgoraVideoOutputOrientationModeFixedPortrait
                                                        mirrorMode:AgoraVideoMirrorModeDisabled];
        [self.agoraEngine setVideoEncoderConfiguration:videoConfig];
        
        int joinResult = [self.agoraEngine joinChannelByToken:token channelId:channelId info:nil uid:userId joinSuccess:nil];
        
        if (joinResult != 0) {
            return NO;
        }
        
        // Store channel info
        self.currentChannelId = channelId;
        self.currentUserId = userId;
        self.isCustomCameraActive = YES;
        
        // Initialize camera if needed
        if (startCameraImmediately) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.isCleaningUp) {
                    return;
                }

                if (self.isCustomCameraActive) {
                    [self setupCamera];
                    // Allow pushing frames after camera setup
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // 🛡️ Double-check cleanup flag before enabling push
                        if (!self.isCleaningUp && self.isCustomCameraActive) {
                            self.allowPush = YES;
                        }
                    });
                }
            });
        }
        
        return YES;
        
    } @catch (NSException *exception) {
        return NO;
    }
}

- (BOOL)stopCustomCamera {
    @try {
        
        [self stopCamera];
        
        // Leave channel if joined
        if (self.channelJoined) {
            [self.agoraEngine leaveChannel:nil];
            self.channelJoined = NO;
        }
        
        // Clear frame processing
#if HAS_NOSMAI_FRAMEWORK
        if (self.nosmaiSDK) {
            [self.nosmaiSDK setCVPixelBufferCallback:nil];
        }
#endif
        
        // Disable external video source
        [self.agoraEngine setExternalVideoSource:NO useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
        
        // Reset state flags
        self.isCustomCameraActive = NO;
        self.allowPush = NO;
        self.currentChannelId = nil;
        self.currentUserId = 0;

        [self clearPreviewViewAndCaches];

        return YES;

    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)teardownStreaming {
    self.isCleaningUp = YES;
    self.allowPush = NO;
    self.channelJoined = NO;
    self.isProcessingFrame = NO; 

    [self stopCamera];
    [NSThread sleepForTimeInterval:0.8];
#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiSDK) {
        NSLog(@"🧹 [NosmaiAgora] Clearing Nosmai callback (final check)");
        [self.nosmaiSDK setCVPixelBufferCallback:nil];
    }
#endif

    if (self.agoraEngine) {
        [self.agoraEngine setExternalVideoSource:NO useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
    }
    if (self.agoraEngine) {
        [self.agoraEngine leaveChannel:nil];
        [NSThread sleepForTimeInterval:0.5];
    }

    if (self.agoraEngine) {
        [AgoraRtcEngineKit destroy];
        self.agoraEngine = nil;
        self.agoraInitialized = NO;
    }
    self.currentChannelId = nil;
    self.currentUserId = 0;
    self.isCustomCameraActive = NO;

    [self clearPreviewViewAndCaches];

    self.isCleaningUp = NO;

}

#pragma mark - Helper Methods

- (CIContext *)ensureCIContext {
    if (!self.sharedCIContext) {
        self.sharedCIContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextPriorityRequestLow: @NO
        }];
    }
    return self.sharedCIContext;
}

- (void)clearPreviewViewAndCaches {
    __block UIView *previewView = nil;
    dispatch_sync(self.previewAccessQueue, ^{
        previewView = _localPreviewView;
        _localPreviewView = nil;
    });

#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiSDK) {
        [self.nosmaiSDK setPreviewView:nil];
        [self.nosmaiSDK setCVPixelBufferCallback:nil];
        [self.nosmaiSDK setLiveFrameOutputEnabled:NO];
    }
#endif

    if (previewView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImageView *imageView = (UIImageView *)[previewView viewWithTag:999];
            if (imageView) {
                imageView.image = nil;
                [imageView removeFromSuperview];
            }
        });
    }

    if (self.sharedCIContext) {
        [self.sharedCIContext clearCaches];
        self.sharedCIContext = nil;
    }

    self.isProcessingFrame = NO;
}

#pragma mark - Camera Management

- (void)setupCamera {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) {
        return;
    }
    
    @try {
        BOOL offscreenInit = [self.nosmaiSDK initializeOffscreenWithWidth:720 height:1280];
        if (!offscreenInit) {
            return;
        }
        
        [self.nosmaiSDK setProcessingMode:NosmaiProcessingModeOffscreen];
        
        [self.nosmaiSDK setLiveFrameOutputEnabled:YES];
        
        __weak typeof(self) weakSelf = self;
        [self.nosmaiSDK setCVPixelBufferCallback:^(CVPixelBufferRef pixelBuffer, double timestamp) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            // 🛡️ CRITICAL: Check cleanup flag FIRST in callback
            if (strongSelf.isCleaningUp) {
                return; // Abort immediately if cleanup is in progress
            }

            if (strongSelf.localPreviewView && pixelBuffer) {
                [strongSelf displayFrameInPreview:pixelBuffer];
            }

            if (strongSelf.allowPush && strongSelf.channelJoined) {
                [strongSelf pushFrameToAgora:pixelBuffer];
            }
        }];
        
        [self setupAVCaptureSession];
        
    } @catch (NSException *exception) {
    }
#endif
}

- (void)stopCamera {

    // 🎯 STEP 1: Clear callback FIRST (before stopping processing)
    // This prevents new frames from being queued
#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiSDK) {
        [self.nosmaiSDK setCVPixelBufferCallback:nil];
        [self.nosmaiSDK setLiveFrameOutputEnabled:NO];
    }
#endif

    // 🎯 STEP 2: Stop capture session (stops new frame generation)
    if (self.captureSession && self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }

    // 🎯 STEP 3: Wait for in-flight frames to complete (CRITICAL)
    // This ensures all frames in the callback queue are processed
    [NSThread sleepForTimeInterval:0.3];

#if HAS_NOSMAI_FRAMEWORK
    // 🎯 STEP 4: Stop Nosmai processing
    if (self.nosmaiSDK) {
        [self.nosmaiSDK stopProcessing];
    }

    if (self.nosmaiCamera) {
        [self.nosmaiCamera stopCapture];
        [self.nosmaiCamera detachFromView];
        [self.nosmaiCamera setDelegate:nil];
        self.nosmaiCamera = nil;
    }
#endif

    // 🎯 STEP 5: Nullify resources
    self.captureSession = nil;
    self.captureDevice = nil;
    self.videoDataOutput = nil;

}

- (void)pushFrameToAgora:(CVPixelBufferRef)pixelBuffer {
    // 🛡️ Safety check: Don't push frames during cleanup
    if (self.isCleaningUp || !self.agoraEngine || !self.allowPush) {
        return;
    }

    AgoraVideoFrame *videoFrame = [[AgoraVideoFrame alloc] init];
    videoFrame.format = AgoraVideoFormatCVPixelI420;
    videoFrame.textureBuf = pixelBuffer;
    videoFrame.rotation = 0;
    videoFrame.time = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000); 

    [self.agoraEngine pushExternalVideoFrame:videoFrame];
}

#pragma mark - Agora Controls

- (BOOL)enableVideo {
    if (!self.agoraEngine) return NO;
    return [self.agoraEngine enableVideo] == 0;
}

- (BOOL)enableLocalVideo:(BOOL)enabled {
    if (!self.agoraEngine) return NO;
    self.allowPush = enabled;
    return YES;
}

- (BOOL)startStreaming {
    if (!self.agoraEngine) return NO;
    return [self.agoraEngine startPreview] == 0;
}

- (BOOL)stopStreaming {
    if (!self.agoraEngine) return NO;
    return [self.agoraEngine stopPreview] == 0;
}

- (BOOL)setClientRole:(AgoraClientRole)role {
    if (!self.agoraEngine) return NO;
    return [self.agoraEngine setClientRole:role] == 0;
}

- (BOOL)joinChannelWithToken:(NSString *)token channelId:(NSString *)channelId userId:(NSUInteger)userId {
    if (!self.agoraEngine) return NO;
    
    if (self.channelJoined && [self.currentChannelId isEqualToString:channelId]) {
        return YES;
    }
    
    int result = [self.agoraEngine joinChannelByToken:token channelId:channelId info:nil uid:userId joinSuccess:nil];
    return result == 0;
}

- (BOOL)leaveChannel {
    if (!self.agoraEngine) return NO;
    
    int result = [self.agoraEngine leaveChannel:nil];
    self.channelJoined = NO;
    self.allowPush = NO;
    return result == 0;
}

#pragma mark - Beauty Filters

- (BOOL)applyBrightness:(float)brightness {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        brightness = fmaxf(-1.0f, fminf(1.0f, brightness));
        [self.nosmaiSDK applyBrightnessFilter:brightness];
        self.brightnessLevel = brightness;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applySkinSmoothing:(float)level {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        level = fmaxf(0.0f, fminf(10.0f, level));
        [self.nosmaiSDK applySkinSmoothing:level];
        self.skinSmoothingLevel = level;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applySkinWhitening:(float)level {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        level = fmaxf(0.0f, fminf(10.0f, level));
        [self.nosmaiSDK applySkinWhitening:level];
        self.skinWhiteningLevel = level;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyFaceSlimming:(float)level {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        level = fmaxf(0.0f, fminf(10.0f, level));
        [self.nosmaiSDK applyFaceSlimming:level];
        self.faceSlimmingLevel = level;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyEyeEnlargement:(float)level {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        level = fmaxf(0.0f, fminf(10.0f, level));
        [self.nosmaiSDK applyEyeEnlargement:level];
        self.eyeEnlargementLevel = level;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyNoseSize:(float)level {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        level = fmaxf(0.0f, fminf(100.0f, level));
        [self.nosmaiSDK applyNoseSize:level];
        self.noseSizeLevel = level;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyContrast:(float)contrast {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        contrast = fmaxf(0.0f, fminf(2.0f, contrast));
        [self.nosmaiSDK applyContrastFilter:contrast];
        self.contrastLevel = contrast;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyHue:(float)hue {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        [self.nosmaiSDK applyHue:hue];
        self.hueLevel = hue;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyRGBWithRed:(float)red green:(float)green blue:(float)blue {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        [self.nosmaiSDK applyRGBFilterWithRed:red green:green blue:blue];
        self.redMultiplier = red;
        self.greenMultiplier = green;
        self.blueMultiplier = blue;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyLipstick:(float)intensity {
    // Using "lipstick" as per official Nosmai SDK implementation
    @try {
        intensity = fmaxf(0.0f, fminf(10.0f, intensity));
        // Use raw intensity value as in official SDK
        BOOL result = [self applyMakeupBlendLevel:@"lipstick" level:intensity];
        if (result) {
            self.lipstickLevel = intensity;
        }
        return result;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (BOOL)applyBlusher:(float)intensity {
    // Using "blusher" as per official Nosmai SDK implementation
    @try {
        intensity = fmaxf(0.0f, fminf(50.0f, intensity));
        // Use raw intensity value as in official SDK
        BOOL result = [self applyMakeupBlendLevel:@"blusher" level:intensity];
        if (result) {
            self.blusherLevel = intensity;
        }
        return result;
    } @catch (NSException *exception) {
        return NO;
    }
}


- (BOOL)applyExposure:(float)exposure {
    // Note: Exposure might need custom implementation or HSB adjustment
    @try {
        exposure = fmaxf(-10.0f, fminf(10.0f, exposure));
        self.exposureLevel = exposure;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (BOOL)applySaturation:(float)saturation {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        saturation = fmaxf(0.0f, fminf(2.0f, saturation));
        float currentHue = self.hueLevel; // Default 0.0 (no hue shift)
        float currentBrightness = (self.brightnessLevel == 0.0f) ? 1.0f : self.brightnessLevel; // Default 1.0 (normal brightness)
        [self.nosmaiSDK adjustHSBWithHue:currentHue saturation:saturation brightness:currentBrightness];
        self.saturationLevel = saturation;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applySharpening:(float)sharpening {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        sharpening = fmaxf(0.0f, fminf(1.5f, sharpening));
        [self.nosmaiSDK applySharpening:sharpening];
        self.sharpenLevel = sharpening;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)applyWhiteBalanceWithTemperature:(float)temperatureK tint:(float)tint {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        temperatureK = fmaxf(1000.0f, fminf(12000.0f, temperatureK));
        tint = fmaxf(-200.0f, fminf(200.0f, tint));
        [self.nosmaiSDK applyWhiteBalanceWithTemperature:temperatureK tint:tint];
        self.whiteBalanceTemp = temperatureK;
        self.whiteBalanceTint = tint;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)enableGrayscale:(BOOL)enabled {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        if (enabled) {
            [self.nosmaiSDK applyGrayscaleFilter];
        } else {
            [self.nosmaiSDK removeBuiltInFilterByName:@"grayscale"];
        }
        self.grayscaleEnabled = enabled;
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"NosmaiAgora: Failed to set grayscale: %@", exception.reason);
        return NO;
    }
#else
    return NO;
#endif
}

#pragma mark - Filter Management

- (BOOL)applyEffect:(NSString *)effectPath {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) {
        NSLog(@"NosmaiAgora: ❌ NosmaiSDK not initialized for applyEffect");
        return NO;
    }
    
    if (!effectPath || [effectPath length] == 0) {
        NSLog(@"NosmaiAgora: ❌ Effect path is empty");
        return NO;
    }
    
    @try {
        // Apply effect synchronously like reference implementation
        BOOL success = [self.nosmaiSDK applyEffectSync:effectPath];
        return success;
    } @catch (NSException *exception) {
        NSLog(@"NosmaiAgora: ❌ Exception while applying effect: %@", exception.reason);
        return NO;
    }
#else
    return NO;
#endif
}

- (void)applyEffect:(NSString *)effectPath completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) {
        NSError *error = [NSError errorWithDomain:@"NosmaiAgoraBridge" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"NosmaiSDK not initialized"}];
        if (completion) completion(NO, error);
        return;
    }
    
    if (!effectPath || [effectPath length] == 0) {
        NSError *error = [NSError errorWithDomain:@"NosmaiAgoraBridge" 
                                             code:-2 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Effect path is empty"}];
        if (completion) completion(NO, error);
        return;
    }
    
    // Apply effect asynchronously like reference implementation
    [self.nosmaiSDK applyEffect:effectPath completion:^(BOOL success, NSError *error) {
        if (success) {
        } else {
        }
        if (completion) completion(success, error);
    }];
#else
    NSError *error = [NSError errorWithDomain:@"NosmaiAgoraBridge" 
                                         code:-3 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Nosmai framework not available"}];
    if (completion) completion(NO, error);
#endif
}

- (BOOL)removeAllFilters {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        [self.nosmaiSDK removeAllBuiltInFilters];
        [self.nosmaiSDK removeAllFilters];
        [self resetFilterStates];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (NSDictionary<NSString *, NSNumber *> *)getCurrentFilterStates {
    return @{
        @"skinSmoothing": @(self.skinSmoothingLevel),
        @"skinWhitening": @(self.skinWhiteningLevel),
        @"faceSlimming": @(self.faceSlimmingLevel),
        @"eyeEnlargement": @(self.eyeEnlargementLevel),
        @"noseSize": @(self.noseSizeLevel),
        @"brightness": @(self.brightnessLevel),
        @"contrast": @(self.contrastLevel),
        @"hue": @(self.hueLevel),
        @"lipstick": @(self.lipstickLevel),
        @"blusher": @(self.blusherLevel),
        @"redMultiplier": @(self.redMultiplier),
        @"greenMultiplier": @(self.greenMultiplier),
        @"blueMultiplier": @(self.blueMultiplier),
        @"exposure": @(self.exposureLevel),
        @"saturation": @(self.saturationLevel),
        @"sharpen": @(self.sharpenLevel),
        @"whiteBalanceTemp": @(self.whiteBalanceTemp),
        @"whiteBalanceTint": @(self.whiteBalanceTint)
    };
}

- (BOOL)applyMakeupBlendLevel:(NSString *)filterName level:(float)level {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        [self.nosmaiSDK applyMakeupBlendLevel:filterName level:level];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

#pragma mark - Status and Info

- (NSString *)getFlutterEngineInfo {
    NSMutableString *info = [NSMutableString string];
    
    if (self.agoraEngine) {
        [info appendString:@"Native Engine: Active\n"];
        [info appendFormat:@"Channel Joined: %@\n", self.channelJoined ? @"YES" : @"NO"];
        [info appendFormat:@"Channel ID: %@\n", self.currentChannelId ?: @"None"];
        [info appendFormat:@"User ID: %lu\n", (unsigned long)self.currentUserId];
    } else {
        [info appendString:@"Native Engine: Not initialized\n"];
    }
    
    return info;
}

#pragma mark - AgoraRtcEngineDelegate

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinChannel:(NSString *)channel withUid:(NSUInteger)uid elapsed:(NSInteger)elapsed {

    if (self.isCleaningUp) {
        NSLog(@"[NosmaiAgora] Ignoring didJoinChannel - cleanup in progress");
        return;
    }

    self.channelJoined = YES;
    self.currentChannelId = channel;
    self.currentUserId = uid;
    self.allowPush = YES;
    NSLog(@"[NosmaiAgora] Joined channel: %@ with uid: %lu", channel, (unsigned long)uid);

}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinedOfUid:(NSUInteger)uid elapsed:(NSInteger)elapsed {
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didLeaveChannelWithStats:(AgoraChannelStats *)stats {
    self.channelJoined = NO;
    self.allowPush = NO;
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOfflineOfUid:(NSUInteger)uid reason:(AgoraUserOfflineReason)reason {
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOccurError:(AgoraErrorCode)errorCode {
}

#pragma mark - AVCaptureSession Setup

- (void)setupAVCaptureSession {
    @try {
        // Create capture session
        self.captureSession = [[AVCaptureSession alloc] init];
        [self.captureSession beginConfiguration];
        
        // Set session preset
        if ([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
            self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
        }
        
        // Get front camera
        AVCaptureDevice *frontCamera = nil;
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in devices) {
            if (device.position == AVCaptureDevicePositionFront) {
                frontCamera = device;
                break;
            }
        }
        
        if (!frontCamera) {
            return;
        }
        
        self.captureDevice = frontCamera;
        
        // Create input
        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:frontCamera error:&error];
        if (error || !input) {
            return;
        }
        
        if ([self.captureSession canAddInput:input]) {
            [self.captureSession addInput:input];
        }
        
        // Create video data output
        self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        self.videoDataOutput.videoSettings = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
        };
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
        
        // Set sample buffer delegate
        [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
        
        if ([self.captureSession canAddOutput:self.videoDataOutput]) {
            [self.captureSession addOutput:self.videoDataOutput];
        }
        
        // Fix video orientation for initial camera setup
        [self fixVideoOrientationForCamera:frontCamera];
        
        self.mirrorModeEnabled = YES;
        
        [self.captureSession commitConfiguration];
        
        // Start capture session
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self.captureSession startRunning];
        });
        
    } @catch (NSException *exception) {
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output 
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
       fromConnection:(AVCaptureConnection *)connection {
#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiSDK) {
        CMSampleBufferRef processedBuffer = sampleBuffer;
        
        // Apply mirror transform if needed
        if (self.mirrorModeEnabled) {
            processedBuffer = [self mirrorSampleBuffer:sampleBuffer];
        }
        
        // Send frame to Nosmai for processing (always with mirror=NO since we handle it manually)
        BOOL success = [self.nosmaiSDK processSampleBuffer:processedBuffer mirror:NO];
        
        // Clean up mirrored buffer if created
        if (processedBuffer != sampleBuffer) {
            CFRelease(processedBuffer);
        }
        
    }
#endif
}

#pragma mark - Mirror Helper

- (CMSampleBufferRef)mirrorSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        return sampleBuffer;
    }

    // Create CIImage from pixel buffer
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    if (!ciImage) {
        return sampleBuffer;
    }

    // Apply horizontal flip transform
    CGAffineTransform transform = CGAffineTransformMakeScale(-1, 1);
    transform = CGAffineTransformTranslate(transform, -ciImage.extent.size.width, 0);
    CIImage *mirroredImage = [ciImage imageByApplyingTransform:transform];

    // Create new pixel buffer
    CVPixelBufferRef newPixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          CVPixelBufferGetWidth(pixelBuffer),
                                          CVPixelBufferGetHeight(pixelBuffer),
                                          CVPixelBufferGetPixelFormatType(pixelBuffer),
                                          NULL, &newPixelBuffer);

    if (status != kCVReturnSuccess || !newPixelBuffer) {
        return sampleBuffer;
    }

    // ✅ Use shared CIContext instead of creating new one (CRITICAL FIX for memory leak)
    [[self ensureCIContext] render:mirroredImage toCVPixelBuffer:newPixelBuffer];

    // Create new sample buffer with mirrored pixel buffer
    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timingInfo);

    CMVideoFormatDescriptionRef formatDescription = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, newPixelBuffer, &formatDescription);

    if (formatDescription) {
        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                               newPixelBuffer,
                                               formatDescription,
                                               &timingInfo,
                                               &newSampleBuffer);
        CFRelease(formatDescription);
    }

    // ✅ Always release newPixelBuffer (we created it with CVPixelBufferCreate)
    CVPixelBufferRelease(newPixelBuffer);

    // ✅ Return newSampleBuffer if successful, otherwise original
    return newSampleBuffer ? newSampleBuffer : sampleBuffer;
}

#pragma mark - Display Processed Frame

- (void)displayFrameInPreview:(CVPixelBufferRef)pixelBuffer {
    if (self.isCleaningUp) {
        return;
    }
    if (!pixelBuffer) {
        return;
    }
    if (self.isProcessingFrame) {
        return;
    }
    self.isProcessingFrame = YES;

    __block UIView *currentPreviewView = nil;
    dispatch_sync(self.previewAccessQueue, ^{
        currentPreviewView = _localPreviewView;
    });

    if (!currentPreviewView) {
        self.isProcessingFrame = NO;
        return;
    }

    CVPixelBufferRetain(pixelBuffer);

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                if (self.isCleaningUp) {
                    CVPixelBufferRelease(pixelBuffer);
                    self.isProcessingFrame = NO;
                    return;
                }

                __block UIView *previewView = nil;
                dispatch_sync(self.previewAccessQueue, ^{
                    previewView = _localPreviewView;
                });

                if (!previewView) {
                    CVPixelBufferRelease(pixelBuffer);
                    self.isProcessingFrame = NO;
                    return;
                }

                CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
                if (!ciImage) {
                    CVPixelBufferRelease(pixelBuffer);
                    self.isProcessingFrame = NO;
                    return;
                }

                CGImageRef cgImage = [[self ensureCIContext] createCGImage:ciImage fromRect:ciImage.extent];

                if (cgImage) {
                    UIImage *image = [UIImage imageWithCGImage:cgImage];
                    CGImageRelease(cgImage);

                    UIImageView *imageView = (UIImageView *)[previewView viewWithTag:999];
                    if (!imageView) {
                        imageView = [[UIImageView alloc] initWithFrame:previewView.bounds];
                        imageView.tag = 999;
                        imageView.contentMode = UIViewContentModeScaleAspectFill;
                        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                        [previewView addSubview:imageView];
                    } else {
                        imageView.image = nil;
                    }
                    imageView.image = image;
                }

                CVPixelBufferRelease(pixelBuffer);

            } @catch (NSException *exception) {
                CVPixelBufferRelease(pixelBuffer);
                NSLog(@"⚠️ Exception in displayFrameInPreview: %@", exception);
            } @finally {
                self.isProcessingFrame = NO;
            }
        } 
    });
}

#pragma mark - Camera Support

- (BOOL)startProcessing {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiInitialized) {
        return NO;
    }

    @try {

        UIView *previewView = self.localPreviewView;
        if (!previewView) {
            NSLog(@"⚠️ [NosmaiAgora] startProcessing aborted: no preview view registered");
            return NO;
        }

        if (self.nosmaiCamera) {
            [self.nosmaiCamera stopCapture];
            [self.nosmaiCamera detachFromView];
            self.nosmaiCamera = nil;
            [NSThread sleepForTimeInterval:0.3];
        }

        // Now safe to stop SDK and switch modes
        if (self.nosmaiSDK) {
            @try {
                [self.nosmaiSDK stopProcessing];
                [NSThread sleepForTimeInterval:0.2];
                [self.nosmaiSDK setProcessingMode:NosmaiProcessingModeLive];

            } @catch (NSException *e) {
            }
        }

        // For Camera Mode: Use NosmaiCore.camera directly (not storing in property)
        NosmaiCamera *camera = [[NosmaiCore shared] camera];
        if (!camera) {
            return NO;
        }
        
        self.nosmaiCamera = camera;
        
        NosmaiCameraConfig *config = [[NosmaiCameraConfig alloc] init];
        config.position = self.currentCameraPosition; 
        config.sessionPreset = @"AVCaptureSessionPresetHigh"; 
        config.frameRate = 30;
        
        [camera updateConfiguration:config];
        [camera setDelegate:self];
        
        if (previewView) {
            [camera attachToView:previewView];

            // Also set preview view for NosmaiSDK (dual attachment)
            if (self.nosmaiSDK) {
                [self.nosmaiSDK setPreviewView:previewView];
            }
        } else {
        }

        if (self.nosmaiSDK) {
            [self.nosmaiSDK startProcessing];
            [NSThread sleepForTimeInterval:0.1];
        }

        // Now safe to start camera capture
        BOOL success = [camera startCapture];
        if (success) {
            self.isStandaloneCameraActive = YES;
            self.currentCameraPosition = camera.position;
        } else {
            if (self.nosmaiSDK) {
                [self.nosmaiSDK stopProcessing];
            }
        }

        return success;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)stopProcessing {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        self.isProcessingFrame = NO;

        if (self.nosmaiSDK) {
            [self.nosmaiSDK stopProcessing];
        }

        if (self.nosmaiCamera) {
            [self.nosmaiCamera stopCapture];
            [self.nosmaiCamera detachFromView];
            [self.nosmaiCamera setDelegate:nil];
            self.nosmaiCamera = nil;
        }

        [self clearPreviewViewAndCaches];
        self.isStandaloneCameraActive = NO;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)switchCamera {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.isStandaloneCameraActive || !self.nosmaiCamera) {
        return NO;
    }
    
    @try {
        
        BOOL success = [self.nosmaiCamera switchCamera];
        if (success) {
            // Update current position
            self.currentCameraPosition = (self.currentCameraPosition == NosmaiCameraPositionFront) ? 
                NosmaiCameraPositionBack : NosmaiCameraPositionFront;
        } else {
        }
        return success;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

#pragma mark - Streaming Camera Controls

- (BOOL)flipCamera {
#if HAS_NOSMAI_FRAMEWORK

    if (!self.isCustomCameraActive || !self.captureDevice) {
        return NO;
    }

    @try {

        // Get the current camera position
        AVCaptureDevicePosition currentPosition = self.captureDevice.position;
        AVCaptureDevicePosition newPosition = (currentPosition == AVCaptureDevicePositionFront) ?
            AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;

        // Find the new camera device
        AVCaptureDevice *newDevice = nil;
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in devices) {
            if (device.position == newPosition) {
                newDevice = device;
                break;
            }
        }

        if (!newDevice) {
            return NO;
        }

        // Switch the camera device
        [self.captureSession beginConfiguration];

        // Remove the old input
        AVCaptureDeviceInput *oldInput = nil;
        for (AVCaptureDeviceInput *input in self.captureSession.inputs) {
            if ([input.device hasMediaType:AVMediaTypeVideo]) {
                oldInput = input;
                break;
            }
        }

        if (oldInput) {
            [self.captureSession removeInput:oldInput];
        }

        // Add the new input
        NSError *error = nil;
        AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&error];
        if (newInput && [self.captureSession canAddInput:newInput]) {
            [self.captureSession addInput:newInput];
            self.captureDevice = newDevice;

            self.currentCameraPosition = (newPosition == AVCaptureDevicePositionFront) ?
                NosmaiCameraPositionFront : NosmaiCameraPositionBack;
        } else {
            [self.captureSession commitConfiguration];
            return NO;
        }
        [self fixVideoOrientationForCamera:newDevice];

        [self.captureSession commitConfiguration];

        return YES;

    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)muteMicrophone:(BOOL)muted {
#if HAS_NOSMAI_FRAMEWORK
    
    if (!self.agoraEngine) {
        return NO;
    }
    
    @try {
        
        int result = [self.agoraEngine muteLocalAudioStream:muted];
        BOOL success = (result == 0);
        
        
        return success;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)toggleMirror:(BOOL)enabled {
#if HAS_NOSMAI_FRAMEWORK
    
    @try {
        
        // Store mirror state - this will be used in frame processing
        self.mirrorModeEnabled = enabled;
        
        return YES;
        
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

#pragma mark - Video Orientation Helper

- (void)fixVideoOrientationForCamera:(AVCaptureDevice *)camera {
    @try {
        
        // Find the video connection
        AVCaptureConnection *videoConnection = nil;
        for (AVCaptureConnection *connection in self.videoDataOutput.connections) {
            for (AVCaptureInputPort *port in connection.inputPorts) {
                if ([port.mediaType isEqualToString:AVMediaTypeVideo]) {
                    videoConnection = connection;
                    break;
                }
            }
            if (videoConnection) break;
        }
        
        if (!videoConnection) {
            return;
        }
        
        // Set consistent portrait orientation
        if ([videoConnection isVideoOrientationSupported]) {
            videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
        } else {
        }
        
        // Disable AVCapture level mirroring - we'll handle mirroring at NosmaiSDK level
        if ([videoConnection isVideoMirroringSupported]) {
            videoConnection.videoMirrored = NO;
        }
        
        // Mirror control handled through self.mirrorModeEnabled and NosmaiSDK processing
        
    } @catch (NSException *exception) {
    }
}

- (BOOL)setFlashMode:(NSString *)flashMode {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        
        // Check if we're in camera mode
        if (!self.isStandaloneCameraActive) {
            return NO;
        }
        
        // Get current camera from NosmaiCore
        NosmaiCamera *camera = [[NosmaiCore shared] camera];
        if (!camera) {
            return NO;
        }
        
        // Check if camera has flash capability first
        if (![camera hasFlash]) {
            return NO;
        }
        
        // Check if camera is capturing
        if (![camera isCapturing]) {
            return NO;
        }
        
        AVCaptureFlashMode mode = AVCaptureFlashModeOff;
        if ([flashMode isEqualToString:@"auto"]) {
            mode = AVCaptureFlashModeAuto;
        } else if ([flashMode isEqualToString:@"on"]) {
            mode = AVCaptureFlashModeOn;
        }
        
        BOOL success = [camera setFlashMode:mode];
        return success;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)setTorchMode:(NSString *)torchMode {
    @try {
        // Get current capture device
        AVCaptureDevice *currentDevice = nil;
        
        if (self.captureDevice) {
            // Use the device from our capture session
            currentDevice = self.captureDevice;
        } else {
            // Fallback: get the default video device
            currentDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        }
        
        if (!currentDevice) {
            return NO;
        }
        
        // Check if device has torch capability
        if (![currentDevice hasTorch]) {
            return NO;
        }
        
        // Convert string to AVCaptureTorchMode
        AVCaptureTorchMode mode = AVCaptureTorchModeOff;
        if ([torchMode isEqualToString:@"auto"]) {
            mode = AVCaptureTorchModeAuto;
        } else if ([torchMode isEqualToString:@"on"]) {
            mode = AVCaptureTorchModeOn;
        }
        
        if (![currentDevice isTorchModeSupported:mode]) {
            return NO;
        }
        
        NSError *error = nil;
        if (![currentDevice lockForConfiguration:&error]) {
            return NO;
        }
        
        currentDevice.torchMode = mode;
        
        [currentDevice unlockForConfiguration];
        
        return YES;
        
    } @catch (NSException *exception) {
        return NO;
    }
}

#pragma mark - Missing Nosmai Camera Methods

- (BOOL)cleanup {
    @try {
        // Cleanup Nosmai SDK and other resources
        [self releaseAgora];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)startRecordingWithCompletion:(void (^)(BOOL success))completion {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        
        if (!self.nosmaiInitialized) {
            completion(NO);
            return;
        }
        
        // Check if we're in camera mode
        if (!self.isStandaloneCameraActive) {
            completion(NO);
            return;
        }
        
        // Get current camera from NosmaiCore
        NosmaiCamera *camera = [[NosmaiCore shared] camera];
        if (!camera || !camera.isCapturing) {
            completion(NO);
            return;
        }
        
        // Use NosmaiCore's startRecordingWithCompletion method (async pattern like reference)
        [[NosmaiCore shared] startRecordingWithCompletion:^(BOOL success, NSError *error) {
            if (success) {
                self.isRecording = YES;
                self.recordingStartTime = [NSDate date]; // Record start time
                completion(YES);
            } else {
                NSString *errorMessage = error ? error.localizedDescription : @"Failed to start recording";
                completion(NO);
            }
        }];
        
    } @catch (NSException *exception) {
        completion(NO);
    }
#else
    completion(NO);
#endif
}

- (void)stopRecordingWithCompletion:(void (^)(NSDictionary<NSString *, id> *result))completion {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        
        if (!self.nosmaiInitialized) {
            completion(@{
                @"success": @NO,
                @"error": @"Nosmai not initialized"
            });
            return;
        }
        
        if (!self.isRecording) {
            completion(@{
                @"success": @NO,
                @"error": @"No recording in progress"
            });
            return;
        }
        
        // Check if we're in camera mode
        if (!self.isStandaloneCameraActive) {
            completion(@{
                @"success": @NO,
                @"error": @"Camera mode not active"
            });
            return;
        }
        
        // Check minimum recording duration (AVFoundation requires at least 3-5 seconds)
        if (self.recordingStartTime) {
            NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.recordingStartTime];
            if (elapsed < 3.0) {
                completion(@{
                    @"success": @NO,
                    @"error": [NSString stringWithFormat:@"Recording too short (%.1fs). Minimum 3 seconds required.", elapsed]
                });
                return;
            }
        }
        
        // Use NosmaiCore's stopRecordingWithCompletion method (async pattern like reference)
        [[NosmaiCore shared] stopRecordingWithCompletion:^(NSURL *videoURL, NSError *error) {
            self.isRecording = NO;
            self.recordingStartTime = nil; // Reset start time
            
            if (videoURL && !error) {
                NSTimeInterval duration = [[NosmaiCore shared] currentRecordingDuration];
                
                // Get file size
                NSError *fileError = nil;
                NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:videoURL.path error:&fileError];
                NSNumber *fileSize = fileError ? @0 : fileAttributes[NSFileSize];
                
                completion(@{
                    @"success": @YES,
                    @"videoPath": videoURL.path,
                    @"duration": @(duration),
                    @"fileSize": fileSize
                });
                
            } else {
                NSString *errorMessage = error ? error.localizedDescription : @"Failed to stop recording";
                completion(@{
                    @"success": @NO,
                    @"error": errorMessage
                });
            }
        }];
        
    } @catch (NSException *exception) {
        completion(@{
            @"success": @NO,
            @"error": exception.reason ?: @"Recording failed"
        });
    }
#else
    completion(@{@"success": @NO, @"error": @"Nosmai framework not available"});
#endif
}

- (void)capturePhotoWithCompletion:(void (^)(NSDictionary<NSString *, id> *result))completion {
#if HAS_NOSMAI_FRAMEWORK
    
    if (!self.nosmaiInitialized) {
        completion(@{
            @"success": @NO,
            @"error": @"Nosmai not initialized"
        });
        return;
    }
    
    // Check if we're in camera mode
    if (!self.isStandaloneCameraActive) {
        completion(@{
            @"success": @NO,
            @"error": @"Camera mode not active"
        });
        return;
    }
    
    // Get current camera from NosmaiCore
    NosmaiCamera *camera = [[NosmaiCore shared] camera];
    if (!camera) {
        completion(@{
            @"success": @NO,
            @"error": @"Camera not available for photo capture"
        });
        return;
    }
    
    
    // Use NosmaiCore's photo capture method (async pattern like reference implementation)
    [[NosmaiCore shared] capturePhoto:^(UIImage *image, NSError *error) {
        if (image) {
            // Convert UIImage to data
            NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
            
            // Create result dictionary
            completion(@{
                @"success": @YES,
                @"imageData": imageData ?: [NSData data],
                @"width": @(image.size.width),
                @"height": @(image.size.height)
            });
        } else {
            // Handle error case
            NSString *errorMessage = error ? error.localizedDescription : @"Unknown error occurred while capturing photo";
            completion(@{
                @"success": @NO,
                @"error": errorMessage
            });
        }
    }];
#else
    completion(@{@"success": @NO, @"error": @"Nosmai framework not available"});
#endif
}

- (void)saveImageToGalleryWithData:(NSData *)imageData name:(NSString *)name completion:(void (^)(NSDictionary<NSString *, id> *result))completion {

    if (!imageData) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Image data is required"
            });
        }
        return;
    }

    // Convert data to UIImage
    UIImage *image = [UIImage imageWithData:imageData];
    if (!image) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Could not create image from data"
            });
        }
        return;
    }

    // Check authorization status
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Photo library access denied"
            });
        }
        return;
    }

    if (status == PHAuthorizationStatusNotDetermined) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Photo library permission not determined - request permission first"
            });
        }
        return;
    }

    // ✅ Async operation without semaphore - no deadlock risk
    @try {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL success, NSError *error) {
            if (completion) {
                if (success && !error) {
                    completion(@{
                        @"success": @YES,
                        @"assetId": @""
                    });
                } else {
                    completion(@{
                        @"success": @NO,
                        @"error": error ? error.localizedDescription : @"Image save failed"
                    });
                }
            }
        }];
    } @catch (NSException *exception) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": exception.reason ?: @"Image save failed"
            });
        }
    }
}

- (void)saveVideoToGalleryWithPath:(NSString *)videoPath name:(NSString *)name completion:(void (^)(NSDictionary<NSString *, id> *result))completion {

    if (!videoPath) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Video path is required"
            });
        }
        return;
    }

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Video file not found"
            });
        }
        return;
    }

    // Check authorization status
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Photo library access denied"
            });
        }
        return;
    }

    if (status == PHAuthorizationStatusNotDetermined) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": @"Photo library permission not determined - request permission first"
            });
        }
        return;
    }

    @try {
        NSURL *videoURL = [NSURL fileURLWithPath:videoPath];

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
        } completionHandler:^(BOOL success, NSError *error) {
            if (completion) {
                if (success && !error) {
                    completion(@{
                        @"success": @YES,
                        @"assetId": @"",
                        @"path": videoPath
                    });
                } else {
                    completion(@{
                        @"success": @NO,
                        @"error": error ? error.localizedDescription : @"Video save failed"
                    });
                }
            }
        }];
    } @catch (NSException *exception) {
        if (completion) {
            completion(@{
                @"success": @NO,
                @"error": exception.reason ?: @"Video save failed"
            });
        }
    }
}

- (BOOL)adjustHSBWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        // Store HSB values
        self.hsbHue = hue;
        self.hsbSaturation = saturation;
        self.hsbBrightness = brightness;
        
        // Apply HSB adjustment via Nosmai SDK
        [self.nosmaiSDK adjustHSBWithHue:hue saturation:saturation brightness:brightness];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)resetHSBFilter {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.nosmaiSDK) return NO;
    
    @try {
        // Reset HSB values to defaults
        self.hsbHue = 0.0f;
        self.hsbSaturation = 1.0f;
        self.hsbBrightness = 1.0f;
        
        // Reset HSB filter via Nosmai SDK
        [self.nosmaiSDK resetHSBFilter];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)isBeautyFilterEnabled {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        // Check if beauty features are enabled by license
        if (self.nosmaiSDK && [self.nosmaiSDK respondsToSelector:@selector(isBeautyEffectEnabled)]) {
            return [self.nosmaiSDK isBeautyEffectEnabled];
        }
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"isBeautyFilterEnabled: Exception - %@", exception.reason);
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)hasFlash {
    @try {
        AVCaptureDevice *currentDevice = nil;

        if (self.captureDevice) {
            currentDevice = self.captureDevice;
        }
#if HAS_NOSMAI_FRAMEWORK
        else if (self.isStandaloneCameraActive && self.nosmaiCamera) {
            NosmaiCamera *camera = [[NosmaiCore shared] camera];
            if (camera && camera.isCapturing) {
                NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
                for (AVCaptureDevice *device in devices) {
                    if (device.position == AVCaptureDevicePositionBack) {
                        currentDevice = device;
                        break;
                    }
                }
            }
        }
#endif
        else {
            NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            for (AVCaptureDevice *device in devices) {
                if (device.position == AVCaptureDevicePositionBack) {
                    currentDevice = device;
                    break;
                }
            }
        }

        if (!currentDevice) {
            return NO;
        }

        // Return actual flash capability
        return [currentDevice hasFlash];

    } @catch (NSException *exception) {
        return NO;
    }
}

- (BOOL)hasTorch {
  
    // Native iOS torch capability check
    @try {
        // Get current capture device
        AVCaptureDevice *currentDevice = nil;
        
        if (self.captureDevice) {
            // Use the device from our capture session
            currentDevice = self.captureDevice;
        } else {
            // Fallback: check default video device
            currentDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        }
        
        if (!currentDevice) {
            return NO;
        }
        
        return [currentDevice hasTorch];
        
    } @catch (NSException *exception) {
        return NO;
    }
}

- (NSString *)getFlashMode {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        NSString *modeString = @"off"; // Default assumption
        return modeString;
    } @catch (NSException *exception) {
        return @"off";
    }
#else
    return @"off";
#endif
}

- (NSString *)getTorchMode {

    // Native iOS torch mode getter
    @try {
        // Get current capture device
        AVCaptureDevice *currentDevice = nil;
        
        if (self.captureDevice) {
            // Use the device from our capture session
            currentDevice = self.captureDevice;
        } else {
            // Fallback: get the default video device
            currentDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        }
        
        if (!currentDevice || ![currentDevice hasTorch]) {
            return @"off";
        }
        
        // Convert AVCaptureTorchMode to string
        switch (currentDevice.torchMode) {
            case AVCaptureTorchModeOn:
                return @"on";
            case AVCaptureTorchModeAuto:
                return @"auto";
            case AVCaptureTorchModeOff:
            default:
                return @"off";
        }
        
    } @catch (NSException *exception) {
        return @"off";
    }
}

- (BOOL)configureCameraWithPosition:(NSString *)position sessionPreset:(NSString *)sessionPreset {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        
        BOOL isFront = [position.lowercaseString isEqualToString:@"front"];
        
        if (self.nosmaiCamera) {
            [self.nosmaiCamera switchToPosition:isFront ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
        }
        
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)detachCameraView {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        
        self.localPreviewView = nil;
        
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

#pragma mark - NosmaiCameraDelegate Methods

#if HAS_NOSMAI_FRAMEWORK
- (void)cameraDidStartCapture {
}

- (void)cameraDidStopCapture {
}

- (void)cameraDidFailToStartCaptureWithError:(NSError *)error {
}
#endif

@end
