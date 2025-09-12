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
        _mirrorModeEnabled = NO;
    }
    return self;
}

#pragma mark - Preview View Management

- (void)setLocalPreviewView:(UIView *)view {
    if (!view) {
        _localPreviewView = nil;
        return;
    }
    
    @try {
        _localPreviewView = view;
        
#if HAS_NOSMAI_FRAMEWORK
        if (self.nosmaiSDK) {
            if ([NSThread isMainThread]) {
                [self.nosmaiSDK setPreviewView:view];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (_localPreviewView == view) {
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
    return _localPreviewView;
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
                NSLog(@"NosmaiAgora: Same channel but different user (multi-host) - restarting camera for user: %lu", (unsigned long)userId);
                [self stopCamera];
                [NSThread sleepForTimeInterval:0.2]; // Small delay to ensure camera is released
            } else {
                NSLog(@"NosmaiAgora: Already active for same channel and user");
                return YES;
            }
        }
        
        // If active with different channel, cleanup first
        if (self.isCustomCameraActive && ![self.currentChannelId isEqualToString:channelId]) {
            NSLog(@"NosmaiAgora: Switching channels - cleaning up first");
            [self teardownStreaming];
            [NSThread sleepForTimeInterval:0.1]; // Small delay
        }
        
        // Ensure singleton is initialized
        if (!self.agoraInitialized || !self.agoraEngine) {
            NSLog(@"NosmaiAgora: Initializing Agora engine");
            if (![self initAgoraWithAppId:appId]) {
                NSLog(@"NosmaiAgora: Failed to initialize Agora");
                return NO;
            }
        }
        
        NSLog(@"NosmaiAgora: Configuring video settings");
        
        // Configure video and audio
        [self.agoraEngine enableVideo];
        [self.agoraEngine setClientRole:AgoraClientRoleBroadcaster];
        [self.agoraEngine adjustPlaybackSignalVolume:0];
        [self.agoraEngine muteAllRemoteAudioStreams:YES];
        [self.agoraEngine enableAudio];
        [self.agoraEngine muteAllRemoteAudioStreams:YES];
        NSLog(@"NosmaiAgora: Enabled audio publishing, muted remote audio playback");
        
        // Set up external video source
        [self.agoraEngine setExternalVideoSource:YES useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
        NSLog(@"NosmaiAgora: External video source setup completed");
        
        // Configure video encoder (720p portrait with fixed orientation)
        AgoraVideoEncoderConfiguration *videoConfig = [[AgoraVideoEncoderConfiguration alloc] 
                                                        initWithSize:CGSizeMake(720, 1280)
                                                        frameRate:AgoraVideoFrameRateFps30
                                                        bitrate:1800
                                                        orientationMode:AgoraVideoOutputOrientationModeFixedPortrait
                                                        mirrorMode:AgoraVideoMirrorModeDisabled];
        [self.agoraEngine setVideoEncoderConfiguration:videoConfig];
        NSLog(@"NosmaiAgora: Video encoder configuration completed - Fixed Portrait Mode");
        
        // Join channel
        NSLog(@"NosmaiAgora: JOINING: channel=%@, nativeUserId=%lu, token=%@...", 
              channelId, (unsigned long)userId, [token substringToIndex:MIN(20, token.length)]);
        
        int joinResult = [self.agoraEngine joinChannelByToken:token channelId:channelId info:nil uid:userId joinSuccess:nil];
        NSLog(@"NosmaiAgora: Join channel result: %d", joinResult);
        
        if (joinResult != 0) {
            NSLog(@"NosmaiAgora: JOIN_FAILED: Error code %d", joinResult);
            return NO;
        }
        
        // Store channel info
        self.currentChannelId = channelId;
        self.currentUserId = userId;
        self.isCustomCameraActive = YES;
        
        // Initialize camera if needed
        if (startCameraImmediately) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.isCustomCameraActive) {
                    [self setupCamera];
                    // Allow pushing frames after camera setup
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        self.allowPush = YES;
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
        
        return YES;
        
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)teardownStreaming {
    
    // First stop frame pushing
    self.allowPush = NO;
    self.channelJoined = NO;
    
    // Stop camera
    [self stopCamera];
    [NSThread sleepForTimeInterval:0.2];
    
    // Clear frame processing
#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiSDK) {
        [self.nosmaiSDK setCVPixelBufferCallback:nil];
    }
#endif
    
    // Disable external video source
    if (self.agoraEngine) {
        [self.agoraEngine setExternalVideoSource:NO useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
    }
    
    // Leave channel and destroy engine
    if (self.agoraEngine) {
        [self.agoraEngine leaveChannel:nil];
        [NSThread sleepForTimeInterval:0.2];
        [AgoraRtcEngineKit destroy];
        self.agoraEngine = nil;
        self.agoraInitialized = NO;
    }
    
    // Clear state variables
    self.currentChannelId = nil;
    self.currentUserId = 0;
    self.isCustomCameraActive = NO;
    
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
    if (self.captureSession && self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }
    self.captureSession = nil;
    self.captureDevice = nil;
    self.videoDataOutput = nil;
    
#if HAS_NOSMAI_FRAMEWORK
    if (self.nosmaiSDK) {
        [self.nosmaiSDK stopProcessing];
        [self.nosmaiSDK setLiveFrameOutputEnabled:NO];
        [self.nosmaiSDK setCVPixelBufferCallback:nil];
    }
#endif
}

- (void)pushFrameToAgora:(CVPixelBufferRef)pixelBuffer {
    if (!self.agoraEngine || !self.allowPush) {
        return;
    }
    
    AgoraVideoFrame *videoFrame = [[AgoraVideoFrame alloc] init];
    videoFrame.format = AgoraVideoFormatCVPixelI420;
    videoFrame.textureBuf = pixelBuffer;
    videoFrame.rotation = 0; // No rotation
    videoFrame.time = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000); // Convert to CMTime with nanosecond scale
    
    [self.agoraEngine pushExternalVideoFrame:videoFrame];
}

#pragma mark - Agora Controls

- (BOOL)enableVideo {
    if (!self.agoraEngine) return NO;
    return [self.agoraEngine enableVideo] == 0;
}

- (BOOL)enableLocalVideo:(BOOL)enabled {
    if (!self.agoraEngine) return NO;
    return [self.agoraEngine enableLocalVideo:enabled] == 0;
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

// Additional filter methods following same pattern...

- (BOOL)applyExposure:(float)exposure {
    // Note: Exposure might need custom implementation or HSB adjustment
    @try {
        exposure = fmaxf(-10.0f, fminf(10.0f, exposure));
        // Implement via HSB or custom filter if available
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
        // Use HSB adjustment for saturation with default values for hue and brightness
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
        NSLog(@"NosmaiAgora: Applied white balance: temp=%f, tint=%f", temperatureK, tint);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"NosmaiAgora: Failed to apply white balance: %@", exception.reason);
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
            // Remove grayscale by resetting or removing the filter
            [self.nosmaiSDK removeBuiltInFilterByName:@"grayscale"];
        }
        self.grayscaleEnabled = enabled;
        NSLog(@"NosmaiAgora: Grayscale %@", enabled ? @"enabled" : @"disabled");
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
        if (success) {
            NSLog(@"NosmaiAgora: ✅ Effect applied successfully: %@", effectPath);
        } else {
            NSLog(@"NosmaiAgora: ❌ Failed to apply effect: %@", effectPath);
        }
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
            NSLog(@"NosmaiAgora: ✅ Effect applied successfully (async): %@", effectPath);
        } else {
            NSLog(@"NosmaiAgora: ❌ Failed to apply effect (async): %@", effectPath);
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
    
    self.channelJoined = YES;
    self.currentChannelId = channel;
    self.currentUserId = uid;
    self.allowPush = YES;
    
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
        
        // Set initial mirror state to OFF for all cameras (user can toggle manually)
        self.mirrorModeEnabled = NO;
        
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
    
    // Apply horizontal flip transform
    CGAffineTransform transform = CGAffineTransformMakeScale(-1, 1);
    transform = CGAffineTransformTranslate(transform, -ciImage.extent.size.width, 0);
    CIImage *mirroredImage = [ciImage imageByApplyingTransform:transform];
    
    // Create new pixel buffer
    CVPixelBufferRef newPixelBuffer = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, 
                       CVPixelBufferGetWidth(pixelBuffer),
                       CVPixelBufferGetHeight(pixelBuffer),
                       CVPixelBufferGetPixelFormatType(pixelBuffer),
                       NULL, &newPixelBuffer);
    
    if (!newPixelBuffer) {
        return sampleBuffer;
    }
    
    // Render mirrored image to new pixel buffer
    CIContext *context = [CIContext context];
    [context render:mirroredImage toCVPixelBuffer:newPixelBuffer];
    
    // Create new sample buffer with mirrored pixel buffer
    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timingInfo);
    
    CMVideoFormatDescriptionRef formatDescription = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, newPixelBuffer, &formatDescription);
    
    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                           newPixelBuffer,
                                           formatDescription,
                                           &timingInfo,
                                           &newSampleBuffer);
    
    // Clean up
    CVPixelBufferRelease(newPixelBuffer);
    if (formatDescription) {
        CFRelease(formatDescription);
    }
    
    return newSampleBuffer ? newSampleBuffer : sampleBuffer;
}

#pragma mark - Display Processed Frame

- (void)displayFrameInPreview:(CVPixelBufferRef)pixelBuffer {
    if (!_localPreviewView || !pixelBuffer) {
        return;
    }
    
    // Convert CVPixelBuffer to UIImage and display
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
            
            if (cgImage) {
                UIImage *image = [UIImage imageWithCGImage:cgImage];
                CGImageRelease(cgImage);
                
                // Mirror applied at capture level, not display level
                
                // Create or update image view
                UIImageView *imageView = (UIImageView *)[_localPreviewView viewWithTag:999];
                if (!imageView) {
                    imageView = [[UIImageView alloc] initWithFrame:_localPreviewView.bounds];
                    imageView.tag = 999;
                    imageView.contentMode = UIViewContentModeScaleAspectFill;
                    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    [_localPreviewView addSubview:imageView];
                }
                imageView.image = image;
            }
        } @catch (NSException *exception) {
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
        
        // For Camera Mode: Use NosmaiCore.camera directly (not storing in property)
        NosmaiCamera *camera = [[NosmaiCore shared] camera];
        if (!camera) {
            return NO;
        }
        
        // Store reference for later use
        self.nosmaiCamera = camera;
        
        // Configure camera for recording (like reference implementation)
        NosmaiCameraConfig *config = [[NosmaiCameraConfig alloc] init];
        config.position = self.currentCameraPosition; // Use current position
        config.sessionPreset = @"AVCaptureSessionPresetHigh"; // High quality for recording
        config.frameRate = 30;
        
        [camera updateConfiguration:config];
        [camera setDelegate:self];
        
        // Essential dual attachment (like reference implementation)
        if (self.localPreviewView) {
            [camera attachToView:self.localPreviewView];
            
            // Also set preview view for NosmaiSDK (dual attachment)
            if (self.nosmaiSDK) {
                [self.nosmaiSDK setPreviewView:self.localPreviewView];
            }
        }
        
        // Start camera capture first (like reference implementation)
        BOOL success = [camera startCapture];
        if (success) {
            
            // Then start NosmaiSDK processing (like reference implementation)
            if (self.nosmaiSDK) {
                [self.nosmaiSDK startProcessing];
                NSLog(@"NosmaiAgora: NosmaiSDK processing started");
            }
            
            self.isStandaloneCameraActive = YES;
            self.currentCameraPosition = camera.position;
            NSLog(@"NosmaiAgora: Camera started at position: %@", 
                  (self.currentCameraPosition == NosmaiCameraPositionFront) ? @"front" : @"back");
        } else {
            NSLog(@"NosmaiAgora: Failed to start NosmaiCore.camera");
        }
        
        return success;
    } @catch (NSException *exception) {
        NSLog(@"NosmaiAgora: Failed to start camera processing: %@", exception.reason);
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)stopProcessing {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        NSLog(@"NosmaiAgora: Stopping camera processing");
        
        // Stop SDK processing first (like reference implementation)
        if (self.nosmaiSDK) {
            [self.nosmaiSDK stopProcessing];
            NSLog(@"NosmaiAgora: NosmaiSDK processing stopped");
        }
        
        // Then stop camera capture (like reference implementation)
        if (self.nosmaiCamera) {
            [self.nosmaiCamera stopCapture];
            [self.nosmaiCamera detachFromView];
            NSLog(@"NosmaiAgora: NosmaiCamera stopped and detached");
        }
        
        self.isStandaloneCameraActive = NO;
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"NosmaiAgora: Failed to stop camera processing: %@", exception.reason);
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)switchCamera {
#if HAS_NOSMAI_FRAMEWORK
    if (!self.isStandaloneCameraActive || !self.nosmaiCamera) {
        NSLog(@"NosmaiAgora: Camera not active, cannot switch");
        return NO;
    }
    
    @try {
        NSLog(@"NosmaiAgora: Switching camera");
        
        BOOL success = [self.nosmaiCamera switchCamera];
        if (success) {
            // Update current position
            self.currentCameraPosition = (self.currentCameraPosition == NosmaiCameraPositionFront) ? 
                NosmaiCameraPositionBack : NosmaiCameraPositionFront;
            NSLog(@"NosmaiAgora: Camera switched to %@", 
                  (self.currentCameraPosition == NosmaiCameraPositionFront) ? @"front" : @"back");
        } else {
            NSLog(@"NosmaiAgora: Failed to switch camera");
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
        } else {
            [self.captureSession commitConfiguration];
            return NO;
        }
        
        // Fix video orientation for consistent portrait mode
        [self fixVideoOrientationForCamera:newDevice];
        
        // Mirror state remains as user set it - no automatic change on camera flip
        
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
        
        // Use Agora's muteLocalAudioStream for streaming mode
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
        
        // Check if camera has torch capability first
        if (![camera hasTorch]) {
            return NO;
        }
        
        // Check if camera is capturing
        if (![camera isCapturing]) {
            return NO;
        }
        
        AVCaptureTorchMode mode = AVCaptureTorchModeOff;
        if ([torchMode isEqualToString:@"auto"]) {
            mode = AVCaptureTorchModeAuto;
        } else if ([torchMode isEqualToString:@"on"]) {
            mode = AVCaptureTorchModeOn;
        }
        
        BOOL success = [camera setTorchMode:mode];
        return success;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
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

- (NSDictionary<NSString *, id> *)saveImageToGallery:(NSData *)imageData name:(NSString *)name {
    
    if (!imageData) {
        return @{
            @"success": @NO,
            @"error": @"Image data is required"
        };
    }
    
    // Convert data to UIImage
    UIImage *image = [UIImage imageWithData:imageData];
    if (!image) {
        return @{
            @"success": @NO,
            @"error": @"Could not create image from data"
        };
    }
    
    // Check authorization status
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        return @{
            @"success": @NO,
            @"error": @"Photo library access denied"
        };
    }
    
    if (status == PHAuthorizationStatusNotDetermined) {
        // For async operations, we'll need to modify this to use completion blocks
        return @{
            @"success": @NO,
            @"error": @"Photo library permission not determined - request permission first"
        };
    }
    
    @try {
        __block NSString *assetId = nil;
        __block NSError *saveError = nil;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            assetId = request.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:^(BOOL success, NSError *error) {
            if (error) {
                saveError = error;
            }
            dispatch_semaphore_signal(semaphore);
        }];
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        if (saveError) {
                return @{
                @"success": @NO,
                @"error": saveError.localizedDescription
            };
        }
        
        return @{
            @"success": @YES,
            @"assetId": assetId ?: @""
        };
        
    } @catch (NSException *exception) {
        return @{
            @"success": @NO,
            @"error": exception.reason ?: @"Image save failed"
        };
    }
}

- (NSDictionary<NSString *, id> *)saveVideoToGallery:(NSString *)videoPath name:(NSString *)name {
    
    if (!videoPath) {
        return @{
            @"success": @NO,
            @"error": @"Video path is required"
        };
    }
    
    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        return @{
            @"success": @NO,
            @"error": @"Video file not found"
        };
    }
    
    // Check authorization status
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        return @{
            @"success": @NO,
            @"error": @"Photo library access denied"
        };
    }
    
    if (status == PHAuthorizationStatusNotDetermined) {
        return @{
            @"success": @NO,
            @"error": @"Photo library permission not determined - request permission first"
        };
    }
    
    @try {
        __block NSString *assetId = nil;
        __block NSError *saveError = nil;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
            assetId = request.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:^(BOOL success, NSError *error) {
            if (error) {
                saveError = error;
            }
            dispatch_semaphore_signal(semaphore);
        }];
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        if (saveError) {
                return @{
                @"success": @NO,
                @"error": saveError.localizedDescription
            };
        }
        
        return @{
            @"success": @YES,
            @"assetId": assetId ?: @"",
            @"path": videoPath
        };
        
    } @catch (NSException *exception) {
        return @{
            @"success": @NO,
            @"error": exception.reason ?: @"Video save failed"
        };
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
        // Check beauty filter status via Nosmai SDK
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
#else
    return NO;
#endif
}

- (BOOL)hasFlash {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        // Check device capability using static method
        BOOL hasFlash = [NosmaiCamera hasBackCamera]; // Assuming back camera has flash
        return hasFlash;
    } @catch (NSException *exception) {
        return NO;
    }
#endif
    return NO;
}

- (BOOL)hasTorch {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        // Check device capability using static method
        BOOL hasTorch = [NosmaiCamera hasBackCamera]; // Assuming back camera has torch
        return hasTorch;
    } @catch (NSException *exception) {
        return NO;
    }
#endif
    return NO;
}

- (NSString *)getFlashMode {
#if HAS_NOSMAI_FRAMEWORK
    @try {
        // Note: NosmaiCamera doesn't provide getter for flash mode
        // Return default value since we can't retrieve current state
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
#if HAS_NOSMAI_FRAMEWORK
    @try {
        // Note: NosmaiCamera doesn't provide getter for torch mode
        // Return default value since we can't retrieve current state
        NSString *modeString = @"off"; // Default assumption
        return modeString;
    } @catch (NSException *exception) {
        return @"off";
    }
#else
    return @"off";
#endif
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
        
        // Detach camera view without stopping camera entirely
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
// Add basic delegate methods to conform to NosmaiCameraDelegate protocol
- (void)cameraDidStartCapture {
}

- (void)cameraDidStopCapture {
}

- (void)cameraDidFailToStartCaptureWithError:(NSError *)error {
}
#endif

@end
