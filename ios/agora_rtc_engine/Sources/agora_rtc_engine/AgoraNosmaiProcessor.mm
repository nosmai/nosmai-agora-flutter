//
//  AgoraNosmaiProcessor.mm
//  agora_rtc_engine
//
//  Objective-C++ implementation for direct frame pushing to Agora
//

#import "AgoraNosmaiProcessor.h"
#import <AgoraRtcKit/AgoraRtcEngineKit.h>
#import <AgoraRtcKit/AgoraObjects.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import "NosmaiPreviewView.h"`
#import <nosmai/Nosmai.h>

#import <Flutter/Flutter.h>

// Global reference to the preview view for easy access
static NosmaiPreviewView *globalPreviewView = nil;

// Simple flag to track initialization status
static BOOL isNosmaiSDKInitialized = NO;

@interface AgoraNosmaiProcessor () <AVCaptureVideoDataOutputSampleBufferDelegate>

// Private methods for safe filter application
- (void)clearBeautyEffectsSynchronously;
- (void)applySkinSmoothingSynchronously:(float)intensity;
- (void)applyFaceSlimmingSynchronously:(float)intensity;
- (void)applyEyeEnlargementSynchronously:(float)intensity;

@property (nonatomic, assign) void *apiEngine;
@property (nonatomic, weak) AgoraRtcEngineKit *agoraEngine;
@property (nonatomic, strong) AgoraRtcEngineKit *customEngine;
@property (nonatomic, strong) NSObject *nosmaiSDK;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, weak) UIView *previewView;
@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, assign) BOOL isDeallocationInProgress;
@property (nonatomic, strong) dispatch_queue_t frameQueue;
@property (nonatomic, assign) BOOL isStreaming;
@property (nonatomic, strong) NSString *nosmaiLicenseKey;
@property (nonatomic, assign) BOOL callbackActive;
@property (nonatomic, strong) AVSampleBufferDisplayLayer *processedFrameDisplayLayer;
@property (nonatomic, assign) BOOL isUsingFrontCamera;
@property (nonatomic, assign) BOOL mirrorEnabled;
@property (nonatomic, assign) BOOL cameraResourcesReleased;
@property (nonatomic, assign) BOOL processingStoppedForCameraLight;


+ (AgoraRtcEngineKit *)sharedNativeSingletonEngine;
+ (AgoraRtcEngineKit *)sharedNativeSingletonEngine:(NSString *)appId;

@end

@implementation AgoraNosmaiProcessor

#pragma mark - Singleton Engine (Architecture)

+ (AgoraRtcEngineKit *)sharedNativeSingletonEngine:(NSString *)appId {
    static AgoraRtcEngineKit *_singletonEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"🏭 Creating native singleton AgoraRtcEngineKit with App ID: %@", appId);
        
        // Create the singleton engine with the provided App ID
        if (appId && appId.length > 0) {
            _singletonEngine = [AgoraRtcEngineKit sharedEngineWithAppId:appId delegate:nil];
            
            if (_singletonEngine) {
                NSLog(@"✅ Native singleton engine created (address: %p)", _singletonEngine);
                
                // Configure external video source ONCE for the singleton engine
                [_singletonEngine setExternalVideoSource:YES useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
                
                // Configure video encoder for mobile portrait
                AgoraVideoEncoderConfiguration *config = [[AgoraVideoEncoderConfiguration alloc] init];
                config.dimensions = CGSizeMake(720, 1280);
                config.frameRate = AgoraVideoFrameRateFps15;
                config.bitrate = AgoraVideoBitrateStandard;
                config.orientationMode = AgoraVideoOutputOrientationModeFixedPortrait;
                [_singletonEngine setVideoEncoderConfiguration:config];
                
                [_singletonEngine enableVideo];
                NSLog(@"🔧 Native singleton engine configured for NosmaiSDK integration");
            } else {
                NSLog(@"❌ Failed to create native singleton engine");
            }
        } else {
            NSLog(@"❌ No App ID provided, cannot create singleton engine");
        }
    });
    
    return _singletonEngine;
}

+ (AgoraRtcEngineKit *)sharedNativeSingletonEngine {
    // Backward compatibility: fallback to Info.plist if no App ID provided
    NSString *appId = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"AgoraAppId"] ?: @"";
    return [self sharedNativeSingletonEngine:appId];
}

- (instancetype)initWithApiEngine:(void *)apiEngine licenseKey:(NSString *)licenseKey {

    self = [super init];
    if (self) {
        self.apiEngine = apiEngine;
        self.nosmaiLicenseKey = licenseKey;
        self.frameQueue = dispatch_queue_create("nosmai.frame.queue", DISPATCH_QUEUE_SERIAL);
        self.isUsingFrontCamera = YES; // Default to front camera
        self.mirrorEnabled = NO; // Default to no mirroring
        self.processingStoppedForCameraLight = NO;
        
        // Setup app lifecycle notifications for camera session management
        [self setupAppLifecycleNotifications];

        [self setupNosmaiSDK];
    }
    return self;
}

- (instancetype)initWithAgoraEngine:(AgoraRtcEngineKit *)engine licenseKey:(NSString *)licenseKey {

    self = [super init];
    if (self) {
        self.agoraEngine = engine;
        self.nosmaiLicenseKey = licenseKey;
        self.frameQueue = dispatch_queue_create("nosmai.frame.queue", DISPATCH_QUEUE_SERIAL);
        self.isUsingFrontCamera = YES; // Default to front camera
        self.processingStoppedForCameraLight = NO;
        
        // Setup app lifecycle notifications for camera session management
        [self setupAppLifecycleNotifications];

        [self setupNosmaiSDK];
    }
    return self;
}

#pragma mark - Engine Management

- (void)setAgoraEngineInstance:(AgoraRtcEngineKit *)engine {
    NSLog(@"🔧 Setting AgoraRtcEngineKit instance: %@", engine);
    self.agoraEngine = engine;
    
    // CRITICAL: Pass the AgoraRtcEngineKit instance to the underlying NosmaiSDK
    // This enables proper video frame processing and streaming integration
    id localNosmaiSDK = self.nosmaiSDK;
    if (localNosmaiSDK && engine) {
        SEL setEngineSelector = NSSelectorFromString(@"setAgoraEngineInstance:");
        if ([localNosmaiSDK respondsToSelector:setEngineSelector]) {
            @try {
                [localNosmaiSDK performSelector:setEngineSelector withObject:engine];
                NSLog(@"✅ AgoraRtcEngineKit instance successfully set on NosmaiSDK");
            } @catch (NSException *exception) {
                NSLog(@"❌ Exception setting AgoraRtcEngineKit on NosmaiSDK: %@", exception.reason);
            }
        } else {
            NSLog(@"⚠️ NosmaiSDK does not respond to setAgoraEngineInstance: - checking for alternative methods");
            
            // Try alternative method names that might exist in NosmaiSDK
            SEL altSelector1 = NSSelectorFromString(@"setAgoraEngine:");
            SEL altSelector2 = NSSelectorFromString(@"configureAgoraEngine:");
            
            if ([localNosmaiSDK respondsToSelector:altSelector1]) {
                @try {
                    [localNosmaiSDK performSelector:altSelector1 withObject:engine];
                    NSLog(@"✅ AgoraRtcEngineKit instance set via setAgoraEngine:");
                } @catch (NSException *exception) {
                    NSLog(@"❌ Exception with setAgoraEngine:: %@", exception.reason);
                }
            } else if ([localNosmaiSDK respondsToSelector:altSelector2]) {
                @try {
                    [localNosmaiSDK performSelector:altSelector2 withObject:engine];
                    NSLog(@"✅ AgoraRtcEngineKit instance set via configureAgoraEngine:");
                } @catch (NSException *exception) {
                    NSLog(@"❌ Exception with configureAgoraEngine:: %@", exception.reason);
                }
            } else {
                NSLog(@"⚠️ NosmaiSDK does not support any known Agora engine setting methods");
            }
        }
    } else if (!localNosmaiSDK) {
        NSLog(@"❌ NosmaiSDK is nil, cannot set AgoraRtcEngineKit instance");
    } else if (!engine) {
        NSLog(@"❌ AgoraRtcEngineKit instance is nil, cannot set on NosmaiSDK");
    }
}

- (void)createCustomAgoraEngine:(NSString *)appId {
    NSLog(@"🔧 createCustomAgoraEngine called with appId: %@", appId);
    
    // NATIVE SINGLETON APPROACH (Architecture)
    // Use the singleton engine with provided App ID instead of Info.plist
    self.agoraEngine = [[self class] sharedNativeSingletonEngine:appId];
    
    if (self.agoraEngine) {
        NSLog(@"✅ Connected to native singleton engine (address: %p)", self.agoraEngine);
    } else {
        NSLog(@"❌ Failed to get native singleton engine");
    }
    
    // Enable streaming mode
    self.isStreaming = YES;
    
    if (self.agoraEngine) {
        NSLog(@"✅ Streaming mode enabled with AgoraRtcEngineKit for frame pushing");
    } else {
        NSLog(@"⚠️ Streaming mode enabled but no AgoraRtcEngineKit available - local preview only");
    }
}

- (AgoraRtcEngineKit *)getCustomEngine {
    return self.agoraEngine;
}

#pragma mark - Setup

- (void)setupNosmaiSDK {
    // Simple initialization without shared instances to avoid deadlocks
    Class sdkClass = NSClassFromString(@"NosmaiSDK");
    if (!sdkClass) {
        NSLog(@"❌ NosmaiSDK class not found - make sure NosmaiCameraSDK framework is linked");
        return;
    }
    
    // Skip shared instance approach - just create new instance directly
    SEL initSelector = NSSelectorFromString(@"initWithLicense:");
    if ([sdkClass respondsToSelector:initSelector]) {
        self.nosmaiSDK = [sdkClass performSelector:initSelector withObject:_nosmaiLicenseKey];
        if (self.nosmaiSDK) {
            [self setupBasicConfiguration];
        } else {
            NSLog(@"❌ NosmaiSDK initWithLicense failed - check license key");
        }
    } else {
        NSLog(@"❌ NosmaiSDK initialization methods not found");
    }
}

- (void)setupBasicConfiguration {
    if (!self.nosmaiSDK) {
        NSLog(@"❌ setupBasicConfiguration called but nosmaiSDK is nil");
        return;
    }
    
    NSLog(@"🔧 ...");
    
    // Simple camera configuration - use front camera
    SEL configureSelector = NSSelectorFromString(@"configureCamera:sessionPreset:");
    if ([self.nosmaiSDK respondsToSelector:configureSelector]) {
        [self.nosmaiSDK performSelector:configureSelector withObject:@(2) withObject:@"AVCaptureSessionPresetHigh"];
    }
    
    // Enable live frame output
    SEL setLiveOutputSelector = NSSelectorFromString(@"setLiveFrameOutputEnabled:");
    if ([self.nosmaiSDK respondsToSelector:setLiveOutputSelector]) {
        [self.nosmaiSDK performSelector:setLiveOutputSelector withObject:@YES];
    }
    
    // Setup simple callback
    [self setupSimpleCallback];
    
}

- (void)setupSimpleCallback {
    if (!self.nosmaiSDK) return;
    
    NSLog(@"🔧 Setting up simple pixel buffer callback...");
    
    void (^pixelBufferCallback)(CVPixelBufferRef, CMTime) = ^(CVPixelBufferRef pixelBuffer, CMTime timestamp) {
        double timestampSeconds = CMTimeGetSeconds(timestamp);
        
        // Send frames as-is to both local and remote
        // With videoMirrored = NO at capture level:
        // - Front camera: Provides mirrored frames (natural selfie view) 
        // - Back camera: Provides normal unmirrored frames
        // Both will see the actual camera view
        
        [self sendFrameToAgora:pixelBuffer timestamp:timestampSeconds];
        
        if (globalPreviewView) {
            [globalPreviewView displayFrame:pixelBuffer];
        }
    };
    
    SEL setCallbackSelector = NSSelectorFromString(@"setCVPixelBufferCallback:");
    if ([self.nosmaiSDK respondsToSelector:setCallbackSelector]) {
        [self.nosmaiSDK performSelector:setCallbackSelector withObject:pixelBufferCallback];
    }
}

- (void)initializeWithLicense {
    id localNosmaiSDK = self.nosmaiSDK;
    
    if (!localNosmaiSDK) {
        NSLog(@"❌ initializeWithLicense called but nosmaiSDK is nil");
        return;
    }
    
    NSLog(@"🔧 Starting license initialization for shared instance...");
    
    @try {
        if (!localNosmaiSDK) {
            NSLog(@"❌ Local NosmaiSDK reference became nil during initialization");
            return;
        }
        
        SEL isInitializedSelector = NSSelectorFromString(@"isInitialized");
        if ([localNosmaiSDK respondsToSelector:isInitializedSelector]) {
            @try {
                // Safe method call with proper type checking
                id result = [localNosmaiSDK performSelector:isInitializedSelector];
                BOOL isAlreadyInitialized = NO;
                
                if ([result isKindOfClass:[NSNumber class]]) {
                    isAlreadyInitialized = [result boolValue];
                } else if ([result respondsToSelector:@selector(boolValue)]) {
                    isAlreadyInitialized = [result boolValue];
                } else {
                    isAlreadyInitialized = YES;
                }
                
                
            if (isAlreadyInitialized) {
                if (self.processingStoppedForCameraLight) {
                    NSLog(@"⚠️ NosmaiSDK processing was stopped for camera light, restarting...");
                    @try {
                        SEL startSelector = NSSelectorFromString(@"startProcessing");
                        if ([localNosmaiSDK respondsToSelector:startSelector]) {
                            [localNosmaiSDK performSelector:startSelector];
                            self.processingStoppedForCameraLight = NO;
                            NSLog(@"✅ NosmaiSDK processing restarted");
                        }
                    } @catch (NSException *processingException) {
                        NSLog(@"❌ Exception restarting processing: %@", processingException.reason);
                    }
                }
                
                NSLog(@"🔧 Proceeding with validation and setup...");
                [self validateLicenseAndSetupWithSDK:localNosmaiSDK];
                [self ensureCallbackSetup];
                return;
            }
            } @catch (NSException *initException) {
                NSLog(@"❌ Exception checking initialization state: %@", initException.reason);
                // Continue with normal initialization if check fails
            }
        } else {
            NSLog(@"ℹ️ isInitialized method not available, proceeding with initialization");
        }
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception during shared instance license check: %@", exception.reason);
        // Continue with normal initialization
    }
    
    // Initialize with license key on shared instance using local reference
    SEL initSelector = NSSelectorFromString(@"initializeWithLicense:");
    if ([localNosmaiSDK respondsToSelector:initSelector]) {
        @try {
            id result = [localNosmaiSDK performSelector:initSelector withObject:_nosmaiLicenseKey];
            BOOL success = NO;
            if (result && [result respondsToSelector:@selector(boolValue)]) {
                success = [result boolValue];
            }
            
            if (success) {
                NSLog(@"✅ NosmaiSDK license accepted");
            } else {
                NSLog(@"⚠️ NosmaiSDK license initialization returned false or unexpected type");
            }
            [self validateLicenseAndSetupWithSDK:localNosmaiSDK];
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception during license initialization: %@", exception.reason);
            [self validateLicenseAndSetupWithSDK:localNosmaiSDK];
        }
    } else {
        // Some versions might not need separate license initialization
        NSLog(@"ℹ️ NosmaiSDK doesn't require separate license initialization");
        [self validateLicenseAndSetupWithSDK:localNosmaiSDK];
    }
    
    [self ensureCallbackSetup];
}

// Legacy method that uses self.nosmaiSDK (kept for compatibility)
- (void)validateLicenseAndSetup {
    [self validateLicenseAndSetupWithSDK:self.nosmaiSDK];
}

// New method that accepts SDK reference to prevent race conditions
- (void)validateLicenseAndSetupWithSDK:(id)sdkInstance {
    if (!sdkInstance) {
        NSLog(@"❌ validateLicenseAndSetupWithSDK called but sdkInstance is nil");
        return;
    }
    
    NSLog(@"🔧 Starting license validation and setup with local SDK reference...");
    
    // Check if license allows beauty effects and cloud filters
    SEL isBeautyEnabledSelector = NSSelectorFromString(@"isBeautyEffectEnabled");
    SEL isCloudEnabledSelector = NSSelectorFromString(@"isCloudFilterEnabled");
    
    BOOL beautyEnabled = NO, cloudEnabled = NO;
    
    if ([sdkInstance respondsToSelector:isBeautyEnabledSelector]) {
        @try {
            // Method returns BOOL directly, not NSNumber
            NSMethodSignature *signature = [sdkInstance methodSignatureForSelector:isBeautyEnabledSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:sdkInstance];
            [invocation setSelector:isBeautyEnabledSelector];
            [invocation invoke];
            [invocation getReturnValue:&beautyEnabled];
            NSLog(@"🎨 Beauty effects enabled: %@", beautyEnabled ? @"YES" : @"NO");
        } @catch (NSException *exception) {
            NSLog(@"⚠️ Could not check beauty effects status: %@", exception.reason);
        }
    }
    
    if ([sdkInstance respondsToSelector:isCloudEnabledSelector]) {
        @try {
            // Method returns BOOL directly, not NSNumber
            NSMethodSignature *signature = [sdkInstance methodSignatureForSelector:isCloudEnabledSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:sdkInstance];
            [invocation setSelector:isCloudEnabledSelector];
            [invocation invoke];
            [invocation getReturnValue:&cloudEnabled];
            NSLog(@"☁️ Cloud filters enabled: %@", cloudEnabled ? @"YES" : @"NO");
        } @catch (NSException *exception) {
            NSLog(@"⚠️ Could not check cloud filters status: %@", exception.reason);
        }
    }
    
    NSLog(@"🔧 Proceeding to configure NosmaiSDK for external processing...");
    [self configureNosmaiForExternalProcessingWithSDK:sdkInstance];
}

// Legacy method that uses self.nosmaiSDK (kept for compatibility)
- (void)configureNosmaiForExternalProcessing {
    [self configureNosmaiForExternalProcessingWithSDK:self.nosmaiSDK];
}

// New method that accepts SDK reference to prevent race conditions
- (void)configureNosmaiForExternalProcessingWithSDK:(id)sdkInstance {
    if (!sdkInstance) {
        NSLog(@"❌ configureNosmaiForExternalProcessingWithSDK called but sdkInstance is nil");
        return;
    }
    
    NSLog(@"🔧 Configuring NosmaiSDK for external processing with local SDK reference...");
    
    @try {
        // Check if already configured for shared instance to avoid re-configuration
        SEL isConfiguredSelector = NSSelectorFromString(@"isConfigured");
        if ([sdkInstance respondsToSelector:isConfiguredSelector]) {
            BOOL isAlreadyConfigured = [[sdkInstance performSelector:isConfiguredSelector] boolValue];
            if (isAlreadyConfigured) {
                NSLog(@"✅ NosmaiSDK already configured on shared instance, ensuring callbacks");
                [self setupCVPixelBufferCallback];
                return;
            }
        } else {
            NSLog(@"ℹ️ isConfigured method not available, proceeding with configuration");
        }
        
        // Try simple configuration first - explicitly configure front camera
        SEL configureSelector = NSSelectorFromString(@"configureCameraWithPosition:sessionPreset:");
        if ([sdkInstance respondsToSelector:configureSelector]) {
            // CRITICAL: Fix camera position constant - AVCaptureDevicePositionFront = 2, not 1!
            NSNumber *position = @(2); // Front camera (AVCaptureDevicePositionFront = 2)
            NSString *preset = @"AVCaptureSessionPresetHigh";
            [sdkInstance performSelector:configureSelector withObject:position withObject:preset];
            NSLog(@"✅ Camera configured with FRONT position (2) and high preset");
        } else {
            NSLog(@"⚠️ Camera configuration method not available");
        }
        
        // Enable live frame output for external processing
        SEL setLiveOutputSelector = NSSelectorFromString(@"setLiveFrameOutputEnabled:");
        if ([sdkInstance respondsToSelector:setLiveOutputSelector]) {
            [sdkInstance performSelector:setLiveOutputSelector withObject:@YES];
            NSLog(@"✅ Live frame output enabled");
        } else {
            NSLog(@"⚠️ Live frame output method not available - using fallback");
        }
        
        NSLog(@"🔧 Proceeding to setup CVPixelBuffer callback...");
        [self setupCVPixelBufferCallback];
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception in configureNosmaiForExternalProcessingWithSDK: %@", exception.reason);
        // Still try to setup callback even if configuration fails
        [self setupCVPixelBufferCallback];
    }
}

- (void)ensureCallbackSetup {
    NSLog(@"🔧 Ensuring CVPixelBuffer callback is properly set up...");
    
    // Reset callback status to force re-setup
    self.callbackActive = NO;
    
    // Always setup callback regardless of shared/new instance
    [self setupCVPixelBufferCallback];
    
    NSLog(@"✅ CVPixelBuffer callback setup ensured");
}

- (void)setupCVPixelBufferCallback {
    if (!self.nosmaiSDK) {
        NSLog(@"❌ setupCVPixelBufferCallback called but nosmaiSDK is nil");
        return;
    }
    
    NSLog(@"🔧 Setting up pixel buffer callback...");
    
    @try {
        __weak typeof(self) weakSelf = self;
        void (^pixelBufferCallback)(CVPixelBufferRef, double) = ^(CVPixelBufferRef pixelBuffer, double timestamp) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.isDeallocationInProgress || !pixelBuffer) return;
            
            // Send processed frames to Agora for streaming
            [strongSelf sendFrameToAgora:pixelBuffer timestamp:timestamp];
            
            // Display processed frames in preview
            if (globalPreviewView) {
                [globalPreviewView displayFrame:pixelBuffer];
            }
            
            // Mark callback as active (for status tracking)
            if (!strongSelf.callbackActive) {
                strongSelf.callbackActive = YES;
                NSLog(@"✅ CVPixelBuffer callback is active");
            }
        };
        
        // Try the standard callback method
        SEL setCallbackSelector = NSSelectorFromString(@"setCVPixelBufferCallback:");
        if ([self.nosmaiSDK respondsToSelector:setCallbackSelector]) {
            [self.nosmaiSDK performSelector:setCallbackSelector withObject:pixelBufferCallback];
            NSLog(@"✅ CVPixelBuffer callback set successfully");
            NSLog(@"🔧 Enabling live frame output for callback");
            return;
        }
        
        // Try alternative callback methods
        NSArray *alternativeSelectors = @[@"setPixelBufferCallback:", @"setFrameCallback:"];
        for (NSString *selectorName in alternativeSelectors) {
            SEL altSelector = NSSelectorFromString(selectorName);
            if ([self.nosmaiSDK respondsToSelector:altSelector]) {
                [self.nosmaiSDK performSelector:altSelector withObject:pixelBufferCallback];
                NSLog(@"✅ Alternative callback (%@) set successfully", selectorName);
                return;
            }
        }
        
        NSLog(@"⚠️ No suitable callback method found - frame processing may not work");
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception in setupCVPixelBufferCallback: %@", exception.reason);
    }
    
    NSLog(@"✅ CVPixelBuffer callback setup completed");
}

#pragma mark - Core Processing Controls

- (void)startProcessing {
    if (self.isProcessing) {
        NSLog(@"⚠️ Processing already active, skipping startProcessing");
        return;
    }
    
    NSLog(@"🎬 Starting NosmaiSDK processing...");
    self.isProcessing = YES;
    
    // Clear the camera light stop flag if it was set
    if (self.processingStoppedForCameraLight) {
        NSLog(@"🔄 Clearing camera light stop flag");
        self.processingStoppedForCameraLight = NO;
    }
    
    // Start NosmaiSDK processing if we have an instance
    if (self.nosmaiSDK) {
        @try {
            // Just start processing without checking isProcessing
            // The isProcessing method might not exist or could be causing the crash
            SEL startSelector = NSSelectorFromString(@"startProcessing");
            if ([self.nosmaiSDK respondsToSelector:startSelector]) {
                [self.nosmaiSDK performSelector:startSelector];
                NSLog(@"✅ NosmaiSDK startProcessing called");
                
                // Ensure callbacks are active
                [self ensureCallbackSetup];
            } else {
                NSLog(@"⚠️ NosmaiSDK doesn't respond to startProcessing");
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception starting NosmaiSDK processing: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ NosmaiSDK is nil, cannot start processing");
    }
    
    // Setup camera if not already initialized
    if (!self.captureSession) {
        [self setupCustomCamera];
    }
    
    // Start camera immediately when processor starts
    [self startCameraCapture];
}

- (void)stopProcessing {
    if (!self.isProcessing) {
        NSLog(@"⚠️ Processing already stopped, skipping stopProcessing");
        return;
    }
    
    NSLog(@"🛑 Stopping NosmaiSDK processing...");
    
    // Stop NosmaiSDK processing if we have an instance
    if (self.nosmaiSDK) {
        @try {
            // Just stop processing without checking isProcessing
            // The isProcessing method might not exist or could be causing issues
            SEL stopSelector = NSSelectorFromString(@"stopProcessing");
            if ([self.nosmaiSDK respondsToSelector:stopSelector]) {
                [self.nosmaiSDK performSelector:stopSelector];
                NSLog(@"✅ NosmaiSDK stopProcessing called");
                
                // Mark that we stopped for camera management
                self.processingStoppedForCameraLight = YES;
            } else {
                NSLog(@"⚠️ NosmaiSDK doesn't respond to stopProcessing");
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception stopping NosmaiSDK processing: %@", exception.reason);
        }
    }
    
    // CRITICAL: DO NOT stop streaming when just turning off camera
    // The isStreaming flag should remain true for viewers to continue seeing frames
    // [self stopLiveStreaming]; // REMOVED - this was causing viewer preview to stop
    
    // CRITICAL: Properly release camera resources to turn off camera light
    [self releaseAllCameraResources];
    
    self.isProcessing = NO;
    
    NSLog(@"✅ stopProcessing completed - camera off but streaming preserved");
}

- (void)startLiveStreaming {
    // CRITICAL: Create local strong reference to prevent deallocation during method execution
    id localNosmaiSDK = self.nosmaiSDK;
    if (!localNosmaiSDK) {
        NSLog(@"❌ startLiveStreaming called but nosmaiSDK is nil");
        return;
    }
    
    NSLog(@"🔧 Starting live streaming with local NosmaiSDK reference: %p", localNosmaiSDK);
    

    
    // OPTIMIZATION: Only setup custom camera if NosmaiSDK doesn't have its own camera
    // This reduces camera conflicts with Flutter's camera and NosmaiSDK's internal camera
    SEL hasCameraSelector = NSSelectorFromString(@"hasActiveCamera");
    BOOL nosmaiHasCamera = NO;
    if ([localNosmaiSDK respondsToSelector:hasCameraSelector]) {
        @try {
            id result = [localNosmaiSDK performSelector:hasCameraSelector];
            if (result && [result respondsToSelector:@selector(boolValue)]) {
                nosmaiHasCamera = [result boolValue];
            } else {
                NSLog(@"⚠️ hasActiveCamera returned unexpected type: %@", result);
                nosmaiHasCamera = NO; // Default to no camera
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception checking camera state: %@", exception.reason);
            nosmaiHasCamera = NO; // Default to no camera
        }
    }
    
    if (!nosmaiHasCamera && !self.captureSession) {
        NSLog(@"🔧 NosmaiSDK doesn't have active camera, setting up custom camera...");
        NSLog(@"🔍 Before setupCustomCamera: isUsingFrontCamera=%@", self.isUsingFrontCamera ? @"YES" : @"NO");
        [self setupCustomCamera];
        [self startCameraCapture];
    } else {
        NSLog(@"✅ NosmaiSDK has active camera (hasCamera=%@), skipping custom camera setup to avoid conflicts", nosmaiHasCamera ? @"YES" : @"NO");
    }
    
    // Skip processing state check - let NosmaiSDK handle duplicates internally
    // Documentation shows currentState method exists but avoiding complex state checking
    BOOL alreadyProcessing = NO; // Always assume not processing for simplicity
    
    if (alreadyProcessing) {
        NSLog(@"✅ NosmaiSDK already processing on shared instance");
        self.isStreaming = YES;
        
        // Restart processing if it was stopped for camera light management
        [self restartProcessingIfStoppedForCameraLight];
        
        // Ensure callbacks are still active for this instance
        [self ensureCallbackSetup];
    } else {
        // Wait a bit for camera to initialize, then start processing
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Use captured local reference to prevent crashes
            id capturedNosmaiSDK = localNosmaiSDK;
            if (capturedNosmaiSDK) {
                // Start NosmaiSDK processing
                SEL startSelector = NSSelectorFromString(@"startProcessing");
                if ([capturedNosmaiSDK respondsToSelector:startSelector]) {
                    [capturedNosmaiSDK performSelector:startSelector];
                    NSLog(@"✅ NosmaiSDK processing started via captured reference");
                }
            } else {
                NSLog(@"❌ Captured NosmaiSDK reference is nil in dispatch block");
            }
            
            self.isStreaming = YES;
            
            // Restart processing if it was stopped for camera light management
            [self restartProcessingIfStoppedForCameraLight];

        });
    }
}

- (void)stopLiveStreaming {
    
    // CRITICAL: DO NOT call stopProcessing on shared NosmaiSDK instance
    // This would clear callbacks and break second stream attempts
    // Instead, just update our streaming flag - the shared instance should keep running
    
    self.isStreaming = NO;
    
    // KEEP the singleton engine alive - never clear it (architecture)
    // The same engine will be reused for the next stream
    NSLog(@"✅ Stream stopped - keeping native singleton engine alive (address: %p)", self.agoraEngine);
}

#pragma mark - Preview Management

- (void)setPreviewView:(UIView *)view {
    self.previewView = view;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Remove existing layers safely
        if (view.layer.sublayers) {
            for (CALayer *layer in [view.layer.sublayers copy]) {
                [layer removeFromSuperlayer];
            }
        }
        
        // Create and setup processed frame display layer
        [self setupProcessedFrameDisplayLayer];
        
        if (self.processedFrameDisplayLayer) {
            self.processedFrameDisplayLayer.frame = view.bounds;
            [view.layer addSublayer:self.processedFrameDisplayLayer];
            // Ensure mirror transform is correct on attach
            [self applyPreviewMirrorTransform];

        }
    });
}

- (void)updatePreviewBounds {
    if (!self.previewView) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update processed frame display layer
        if (self.processedFrameDisplayLayer) {
            self.processedFrameDisplayLayer.frame = self.previewView.bounds;
        }
    });
}

- (void)setupProcessedFrameDisplayLayer {
    if (self.processedFrameDisplayLayer) {
        [self.processedFrameDisplayLayer removeFromSuperlayer];
    }
    
    self.processedFrameDisplayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.processedFrameDisplayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.processedFrameDisplayLayer.backgroundColor = [UIColor blackColor].CGColor;
    // Apply initial transform based on current state
    [self applyPreviewMirrorTransform];

}

- (void)displayProcessedFrame:(CVPixelBufferRef)pixelBuffer {
    if (!self.processedFrameDisplayLayer || !pixelBuffer) {
        static int nullCount = 0;
        nullCount++;
        if (nullCount % 30 == 0) {
            NSLog(@"❌ displayProcessedFrame called but layer=%@ pixelBuffer=%@", 
                  self.processedFrameDisplayLayer, pixelBuffer);
        }
        return;
    }
    
    static int debugCount = 0;
    debugCount++;
    if (debugCount % 30 == 0) {

    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // Create format description from pixel buffer
            CMVideoFormatDescriptionRef formatDescription;
            OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
                kCFAllocatorDefault,
                pixelBuffer,
                &formatDescription
            );
            
            if (status != noErr) {

                return;
            }
            
            // Create sample timing info
            CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
            timingInfo.duration = CMTimeMake(1, 30); // 30 FPS
            timingInfo.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            timingInfo.decodeTimeStamp = kCMTimeInvalid;
            
            // Create sample buffer
            CMSampleBufferRef sampleBuffer;
            status = CMSampleBufferCreateReadyWithImageBuffer(
                kCFAllocatorDefault,
                pixelBuffer,
                formatDescription,
                &timingInfo,
                &sampleBuffer
            );
            
            CFRelease(formatDescription);
            
            if (status != noErr) {

                return;
            }
            
            // Display the sample buffer
            if (self.processedFrameDisplayLayer.isReadyForMoreMediaData) {
                [self.processedFrameDisplayLayer enqueueSampleBuffer:sampleBuffer];
            } else {
                // Layer is not ready - check if it's failed and needs recovery
                if (self.processedFrameDisplayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                    static NSTimeInterval lastRecoveryAttempt = 0;
                    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                    
                    // Attempt recovery once every 2 seconds
                    if (currentTime - lastRecoveryAttempt > 2.0) {
                        lastRecoveryAttempt = currentTime;
                        NSLog(@"⚠️ Display layer failed during enqueue, triggering recovery...");
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self recoverFailedDisplayLayer];
                        });
                    }
                }
            }
            
            CFRelease(sampleBuffer);
            
        } @catch (NSException *exception) {

        }
    });
}


- (UIView *)createNativePreviewView {
    UIView *nativeView = [[UIView alloc] init];
    nativeView.backgroundColor = [UIColor blackColor];
    
    // Setup the processed frame display layer
    [self setupProcessedFrameDisplayLayer];
    
    if (self.processedFrameDisplayLayer) {
        [nativeView.layer addSublayer:self.processedFrameDisplayLayer];
        self.previewView = nativeView; // Keep reference for bounds updates

    }
    
    return nativeView;
}

- (void)attachPreviewToView:(UIView *)view {
    if (!view) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Remove existing layers safely
        if (view.layer.sublayers) {
            for (CALayer *layer in [view.layer.sublayers copy]) {
                [layer removeFromSuperlayer];
            }
        }
        
        // Setup the processed frame display layer
        [self setupProcessedFrameDisplayLayer];
        
        if (self.processedFrameDisplayLayer) {
            self.processedFrameDisplayLayer.frame = view.bounds;
            [view.layer addSublayer:self.processedFrameDisplayLayer];
            self.previewView = view; // Keep reference for bounds updates

        }
    });
}

+ (UIView *)createGlobalPreviewView {
    globalPreviewView = [[NosmaiPreviewView alloc] initWithFrame:CGRectMake(0, 0, 100, 150)];
    globalPreviewView.backgroundColor = [UIColor blackColor];
    return globalPreviewView;
}

+ (void)destroyGlobalPreviewView {
    globalPreviewView = nil;

}

#pragma mark - Filter Controls

- (void)applyFilterWithPath:(NSString *)path completion:(void(^)(BOOL success, NSError *error))completion {
    if (!self.nosmaiSDK || self.isDeallocationInProgress) {
        if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"SDK not available"}]);
        return;
    }
    
    NSLog(@"🎯 applyFilterWithPath called with: '%@'", path ?: @"(null)");
    NSLog(@"🎯 Path length: %lu", (unsigned long)(path ? path.length : 0));
    
    // Handle empty or nil path by clearing all filters
    if (!path || path.length == 0) {
        NSLog(@"🧹 Empty path provided, clearing all filters");
        [self clearFilterInternal];
        if (completion) completion(YES, nil);
        return;
    }
    
    // Check if this is a cloud filter that needs downloading
    if ([self isCloudFilterById:path]) {
        NSLog(@"☁️ Detected cloud filter with ID: %@", path);
        
        // Check if already downloaded using proper SDK method
        SEL isDownloadedSelector = NSSelectorFromString(@"isCloudFilterDownloaded:");
        if ([self.nosmaiSDK respondsToSelector:isDownloadedSelector]) {
            BOOL isDownloaded = [[self.nosmaiSDK performSelector:isDownloadedSelector withObject:path] boolValue];
            if (!isDownloaded) {
                NSLog(@"📥 Cloud filter not downloaded, starting download...");
                [self downloadCloudFilterAndApply:path completion:completion];
                return;
            } else {
                NSLog(@"✅ Cloud filter already downloaded, getting local path...");
                // Get local path for downloaded filter
                SEL getLocalPathSelector = NSSelectorFromString(@"getCloudFilterLocalPath:");
                if ([self.nosmaiSDK respondsToSelector:getLocalPathSelector]) {
                    NSString *localPath = [self.nosmaiSDK performSelector:getLocalPathSelector withObject:path];
                    if (localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                        path = localPath;
                        NSLog(@"📁 Using local path: %@", localPath);
                    } else {
                        NSLog(@"❌ Local path not found or invalid, re-downloading...");
                        [self downloadCloudFilterAndApply:path completion:completion];
                        return;
                    }
                } else {
                    NSLog(@"❌ getCloudFilterLocalPath method not available");
                    if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-8 userInfo:@{NSLocalizedDescriptionKey: @"Cannot get cloud filter local path"}]);
                    return;
                }
            }
        } else {
            NSLog(@"❌ isCloudFilterDownloaded method not available");
            if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-9 userInfo:@{NSLocalizedDescriptionKey: @"Cloud filter download check not supported"}]);
            return;
        }
    } else if (![self isValidLocalFilterPath:path]) {
        NSLog(@"❌ Invalid filter path: %@", path);
        if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-10 userInfo:@{NSLocalizedDescriptionKey: @"Invalid filter path"}]);
        return;
    }
    
    // Dispatch to background queue to avoid blocking main thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            // Clear beauty effects before applying filter to prevent conflicts
            [self clearBeautyEffectsQuietly];
            
            NSLog(@"🎨 Applying filter: %@", [path lastPathComponent]);
            
            // Try applyEffect:completion: method first
            SEL applyEffectSelector = NSSelectorFromString(@"applyEffect:completion:");
            if ([self.nosmaiSDK respondsToSelector:applyEffectSelector]) {
                void (^effectCompletion)(BOOL, NSError*) = ^(BOOL success, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            NSLog(@"✅ Filter applied successfully");
                        } else {
                            NSLog(@"❌ Filter application failed: %@", error.localizedDescription);
                        }
                        if (completion) completion(success, error);
                    });
                };
                
                [self.nosmaiSDK performSelector:applyEffectSelector withObject:path withObject:effectCompletion];
                return;
            }
            
            // Fallback to synchronous method
            SEL applyEffectSyncSelector = NSSelectorFromString(@"applyEffectSync:");
            if ([self.nosmaiSDK respondsToSelector:applyEffectSyncSelector]) {
                BOOL result = [[self.nosmaiSDK performSelector:applyEffectSyncSelector withObject:path] boolValue];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (result) {
                        NSLog(@"✅ Filter applied successfully (sync)");
                    } else {
                        NSLog(@"❌ Filter application failed (sync)");
                    }
                    if (completion) {
                        completion(result, result ? nil : [NSError errorWithDomain:@"NosmaiError" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Filter application failed"}]);
                    }
                });
                return;
            }
            
            NSLog(@"❌ No suitable filter application methods found");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"No suitable method found for applying filter"}]);
            });
            
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-3 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Filter application failed"}]);
            });
        }
    });
}

// Synchronous version of clearBeautyEffects for internal use
- (void)clearBeautyEffectsSynchronously {
    if (!self.nosmaiSDK || self.isDeallocationInProgress) return;
    
    @try {
        // Try different methods to clear beauty effects
        NSArray *clearBeautyMethods = @[
            @"clearAllBeautyFilters",
            @"removeAllBeautyEffects", 
            @"resetBeautyEffects",
            @"clearBeautyEffects"
        ];
        
        BOOL cleared = NO;
        for (NSString *methodName in clearBeautyMethods) {
            SEL selector = NSSelectorFromString(methodName);
            if ([self.nosmaiSDK respondsToSelector:selector]) {
                [self.nosmaiSDK performSelector:selector];
                cleared = YES;
                break;
            }
        }
        
        // If no clear method found, manually reset individual beauty effects to 0
        if (!cleared) {
            [self applySkinSmoothingSynchronously:0.0];
            [self applyFaceSlimmingSynchronously:0.0];  
            [self applyEyeEnlargementSynchronously:0.0];
            
            // Also clear makeup filters (lipstick, blusher, etc.)
            [self applyMakeupBlendLevel:@"LipstickFilter" level:0.0];
            [self applyMakeupBlendLevel:@"BlusherFilter" level:0.0];
        }
        
    } @catch (NSException *exception) {
        NSLog(@"❌ clearBeautyEffectsSynchronously failed with exception: %@", exception);
    }
}

// Synchronous beauty effect methods for internal cleanup
- (void)applySkinSmoothingSynchronously:(float)intensity {
    SEL selector = NSSelectorFromString(@"applySkinSmoothing:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:selector];
            [invocation setArgument:&intensity atIndex:2];
            [invocation invoke];
        } @catch (NSException *exception) {
            NSLog(@"❌ applySkinSmoothingSynchronously failed: %@", exception);
        }
    }
}

- (void)applyFaceSlimmingSynchronously:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyFaceSlimming:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:selector];
            [invocation setArgument:&intensity atIndex:2];
            [invocation invoke];
        } @catch (NSException *exception) {
            NSLog(@"❌ applyFaceSlimmingSynchronously failed: %@", exception);
        }
    }
}

- (void)applyEyeEnlargementSynchronously:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyEyeEnlargement:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:selector];
            [invocation setArgument:&intensity atIndex:2];
            [invocation invoke];
        } @catch (NSException *exception) {
            NSLog(@"❌ applyEyeEnlargementSynchronously failed: %@", exception);
        }
    }
}

- (void)clearFilter {
    if (!self.nosmaiSDK || self.isDeallocationInProgress) return;
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self clearFilterInternal];
    });
}

- (void)clearFilterInternal {
    if (!self.nosmaiSDK || self.isDeallocationInProgress) return;
    
    @try {
        // Use the correct method from NosmaiSDK headers: removeAllFilters
        SEL removeAllSelector = NSSelectorFromString(@"removeAllFilters");
        if ([self.nosmaiSDK respondsToSelector:removeAllSelector]) {
            [self.nosmaiSDK performSelector:removeAllSelector];
            NSLog(@"✅ Successfully cleared filters using removeAllFilters");
            return;
        }
        
        // Fallback method: removeAllBuiltInFilters  
        SEL removeBuiltInSelector = NSSelectorFromString(@"removeAllBuiltInFilters");
        if ([self.nosmaiSDK respondsToSelector:removeBuiltInSelector]) {
            [self.nosmaiSDK performSelector:removeBuiltInSelector];
            NSLog(@"✅ Successfully cleared built-in filters using removeAllBuiltInFilters");
            return;
        }
        
        NSLog(@"❌ No filter clearing methods found");
        
    } @catch (NSException *exception) {
        NSLog(@"❌ clearFilterInternal failed with exception: %@", exception);
    }
}

- (NSDictionary *)getAvailableFilters {
    if (!self.nosmaiSDK) return nil;
    
    SEL getFiltersSelector = NSSelectorFromString(@"getInitialFilters");
    if ([self.nosmaiSDK respondsToSelector:getFiltersSelector]) {
        return [self.nosmaiSDK performSelector:getFiltersSelector];
    }
    return nil;
}

- (NSArray *)getLocalFilters {

    NSMutableArray *localFilters = [NSMutableArray array];
    
    // Get the main bundle
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    // Define potential asset paths that Flutter might use
    NSArray *potentialPaths = @[
        @"flutter_assets/assets/filters",
        @"Frameworks/App.framework/flutter_assets/assets/filters",
        @"assets/filters"
    ];
    
    for (NSString *basePath in potentialPaths) {

        
        // Try to find the directory
        NSString *fullPath = [mainBundle pathForResource:basePath ofType:nil];
        if (fullPath) {

            
            NSError *error;
            NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fullPath error:&error];
            
            if (error) {

                continue;
            }
            
            // Filter for .nosmai files
            NSArray *nosmaiFiles = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.nosmai'"]];

            
            for (NSString *fileName in nosmaiFiles) {
                NSString *filePath = [fullPath stringByAppendingPathComponent:fileName];
                NSString *filterName = [fileName stringByDeletingPathExtension];
                
                // Convert snake_case to Title Case for display name
                NSString *displayName = [self convertToDisplayName:filterName];
                
                // Get file size
                NSError *attributesError;
                NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&attributesError];
                NSNumber *fileSize = attributesError ? @0 : attributes[NSFileSize];
                
                // Extract proper filter metadata from the .nosmai file
                NSDictionary *filterMetadata = nil;
                if ([self.nosmaiSDK respondsToSelector:@selector(getFilterInfoFromPath:)]) {
                    filterMetadata = [self.nosmaiSDK performSelector:@selector(getFilterInfoFromPath:) withObject:filePath];
                    // NSLog(@"🔍 Filter metadata for %@: %@", filterName, filterMetadata);
                }
                
                // Get proper filter type from metadata, fallback based on filename analysis
                NSString *filterType = @"effect"; // Default fallback
                NSString *filterCategory = @"effect"; // Default fallback  
                NSString *sourceType = @"effect"; // Default fallback
                
                if (filterMetadata && [filterMetadata isKindOfClass:[NSDictionary class]]) {
                    // Extract type information from metadata
                    NSString *metadataType = filterMetadata[@"filterType"];
                    if (metadataType && [metadataType isKindOfClass:[NSString class]]) {
                        filterType = metadataType;
                        
                        // Categorize based on the actual type from metadata
                        NSString *lowercaseType = [metadataType lowercaseString];
                        if ([lowercaseType containsString:@"filter"]) {
                            filterCategory = @"filter";
                            sourceType = @"filter";
                        } else if ([lowercaseType containsString:@"beauty"]) {
                            filterCategory = @"beauty";
                            sourceType = @"filter";
                        } else {
                            filterCategory = @"effect";
                            sourceType = @"effect";
                        }
                    }
                } else {
                    // Fallback: Categorize based on filename since metadata extraction failed
                    NSString *lowercaseName = [filterName lowercaseString];
                    
                    // Common filter keywords (color/tone adjustments)
                    NSArray *filterKeywords = @[@"vintage", @"retro", @"warm", @"cool", @"bright", @"dark", 
                                               @"sepia", @"mono", @"contrast", @"vivid", @"soft", @"sharp",
                                               @"lomo", @"film", @"analog", @"classic", @"noir", @"bw",
                                               @"color", @"tone", @"grade", @"cinematic", @"natural",
                                               @"fade", @"trail", @"blue", @"edge", @"vibe", @"crisp",
                                               @"passing", @"going", @"walk", @"youcan", @"undeniable", @"nah"];
                    
                    // Check if it's likely a filter (color/tone adjustment)
                    // Most filters in our library are actually color/tone adjustments
                    BOOL isFilter = NO;
                    for (NSString *keyword in filterKeywords) {
                        if ([lowercaseName containsString:keyword]) {
                            isFilter = YES;
                            break;
                        }
                    }
                    
                    // Additional check: if name doesn't contain obvious effect keywords, assume filter
                    NSArray *effectKeywords = @[@"ascii", @"quad", @"grid", @"prism", @"leak", @"invert"];
                    BOOL hasEffectKeyword = NO;
                    for (NSString *keyword in effectKeywords) {
                        if ([lowercaseName containsString:keyword]) {
                            hasEffectKeyword = YES;
                            break;
                        }
                    }
                    
                    if (hasEffectKeyword) {
                        // Definitely an effect
                        filterType = @"effect";
                        filterCategory = @"effect";
                        sourceType = @"effect";
                    } else if (isFilter || !hasEffectKeyword) {
                        // Either matched filter keyword or no effect keyword - treat as filter
                        filterType = @"filter";
                        filterCategory = @"filter";
                        sourceType = @"filter";
                    } else {
                        // Default to effect if uncertain
                        filterType = @"effect";
                        filterCategory = @"effect";
                        sourceType = @"effect";
                    }
                }
                
                // Create filter dictionary with proper categorization
                NSDictionary *filterInfo = @{
                    @"id": filterName,
                    @"name": filterName,
                    @"displayName": displayName,
                    @"description": [NSString stringWithFormat:@"Local filter: %@", displayName],
                    @"path": filePath,
                    @"fileSize": fileSize,
                    @"type": @"local",
                    @"isDownloaded": @YES,
                    @"isFree": @YES,
                    @"downloadCount": @0,
                    @"price": @0,
                    @"filterCategory": filterCategory, // Proper categorization from metadata
                    @"sourceType": sourceType, // Proper categorization from metadata
                    @"filterType": filterType // Proper categorization from metadata
                };
                
                // PREVIEW FIX: Check for preview data in filter metadata (local filters use image bytes)
                NSMutableDictionary *enhancedFilterInfo = [filterInfo mutableCopy];
                BOOL previewFound = NO;
                
                if (filterMetadata) {
                    // For local filters, check for preview image data (Uint8List/NSData)
                    NSData *previewImageData = filterMetadata[@"previewImage"] ?: filterMetadata[@"preview_image"] ?: filterMetadata[@"thumbnailImage"];
                    if (previewImageData && [previewImageData isKindOfClass:[NSData class]]) {
                        // Convert NSData to base64 string for consistent handling
                        NSString *base64String = [previewImageData base64EncodedStringWithOptions:0];
                        enhancedFilterInfo[@"previewImageBase64"] = base64String;
                        // NSLog(@"✅ Added preview image data from metadata for %@: %lu bytes", filterName, (unsigned long)previewImageData.length);
                        previewFound = YES;
                    } else {
                        // Fallback: check for preview URL string (in case some filters still use URLs)
                        NSString *previewUrl = filterMetadata[@"previewUrl"] ?: filterMetadata[@"preview_url"] ?: filterMetadata[@"previewURL"] ?: filterMetadata[@"thumbnailUrl"];
                        if (previewUrl && previewUrl.length > 0) {
                            enhancedFilterInfo[@"previewUrl"] = previewUrl;
                            // NSLog(@"✅ Added preview URL for %@: %@", filterName, previewUrl);
                            previewFound = YES;
                        }
                    }
                }
                
                // If no preview found in metadata, try to load from SDK or generate one
                if (!previewFound) {
                    // First try to load preview image from NosmaiSDK if available
                    if ([self.nosmaiSDK respondsToSelector:@selector(loadPreviewImageForFilter:)]) {
                        UIImage *sdkPreviewImage = [self.nosmaiSDK performSelector:@selector(loadPreviewImageForFilter:) withObject:filePath];
                        if (sdkPreviewImage) {
                            NSData *imageData = UIImageJPEGRepresentation(sdkPreviewImage, 0.7);
                            if (imageData) {
                                NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                                enhancedFilterInfo[@"previewImageBase64"] = base64String;
                                // NSLog(@"✅ Loaded preview image from SDK for filter %@: %lu bytes", filterName, (unsigned long)imageData.length);
                                previewFound = YES;
                            }
                        }
                    }
                    
                    // If still no preview, generate a default preview image
                    if (!previewFound) {
                        UIImage *previewImage = [self generatePreviewImageForFilter:filterName displayName:displayName];
                        if (previewImage) {
                            NSData *imageData = UIImagePNGRepresentation(previewImage);
                            if (imageData) {
                                NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                                enhancedFilterInfo[@"previewImageBase64"] = base64String;
                                // NSLog(@"✅ Generated fallback preview image for filter %@", filterName);
                            }
                        }
                    }
                }
                
                [localFilters addObject:enhancedFilterInfo];

            }
        } else {

        }
    }
    
    // Also check for individual .nosmai files in the main bundle
    NSArray *allNosmaiFiles = [mainBundle pathsForResourcesOfType:@"nosmai" inDirectory:nil];

    
    for (NSString *filePath in allNosmaiFiles) {
        NSString *fileName = [[filePath lastPathComponent] stringByDeletingPathExtension];
        
        // Check if we already added this filter
        BOOL alreadyAdded = NO;
        for (NSDictionary *existingFilter in localFilters) {
            if ([existingFilter[@"name"] isEqualToString:fileName]) {
                alreadyAdded = YES;
                break;
            }
        }
        
        if (!alreadyAdded) {
            NSString *displayName = [self convertToDisplayName:fileName];
            
            // Get file size
            NSError *attributesError;
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&attributesError];
            NSNumber *fileSize = attributesError ? @0 : attributes[NSFileSize];
            
            // Extract proper filter metadata from the .nosmai file
            NSDictionary *filterMetadata = nil;
            if ([self.nosmaiSDK respondsToSelector:@selector(getFilterInfoFromPath:)]) {
                filterMetadata = [self.nosmaiSDK performSelector:@selector(getFilterInfoFromPath:) withObject:filePath];
            }
            
            // Get proper filter type from metadata, fallback based on filename analysis
            NSString *filterType = @"effect"; // Default fallback
            NSString *filterCategory = @"effect"; // Default fallback
            NSString *sourceType = @"effect"; // Default fallback
            
            if (filterMetadata && [filterMetadata isKindOfClass:[NSDictionary class]]) {
                // Extract type information from metadata
                NSString *metadataType = filterMetadata[@"type"];
                if (metadataType && [metadataType isKindOfClass:[NSString class]]) {
                    filterType = metadataType;
                    
                    // Categorize based on the actual type from metadata
                    NSString *lowercaseType = [metadataType lowercaseString];
                    if ([lowercaseType containsString:@"filter"]) {
                        filterCategory = @"filter";
                        sourceType = @"filter";
                    } else if ([lowercaseType containsString:@"beauty"]) {
                        filterCategory = @"beauty";
                        sourceType = @"filter";
                    } else {
                        filterCategory = @"effect";
                        sourceType = @"effect";
                    }
                }
            } else {
                // Fallback: Categorize based on filename since metadata extraction failed
                NSString *lowercaseName = [fileName lowercaseString];
                
                // Common filter keywords (color/tone adjustments)
                NSArray *filterKeywords = @[@"vintage", @"retro", @"warm", @"cool", @"bright", @"dark", 
                                           @"sepia", @"mono", @"contrast", @"vivid", @"soft", @"sharp",
                                           @"lomo", @"film", @"analog", @"classic", @"noir", @"bw",
                                           @"color", @"tone", @"grade", @"cinematic", @"natural",
                                           @"fade", @"trail", @"blue", @"edge", @"vibe", @"sunset",
                                           @"sunrise", @"golden", @"silver", @"bronze", @"copper",
                                           @"crisp", @"passing", @"going", @"walk", @"youcan", @"undeniable", @"nah"];
                
                // Common effect keywords (animated/special effects)
                NSArray *effectKeywords = @[@"party", @"heart", @"star", @"fire", @"water", @"smoke",
                                           @"lightning", @"rainbow", @"sparkle", @"glitter", @"confetti",
                                           @"snow", @"rain", @"bubble", @"explosion", @"magic",
                                           @"neon", @"glow", @"laser", @"hologram", @"3d",
                                           @"ascii", @"quad", @"grid", @"prism", @"leak", @"invert"];
                
                // Check if it's likely an effect first (more specific)
                BOOL isEffect = NO;
                for (NSString *keyword in effectKeywords) {
                    if ([lowercaseName containsString:keyword]) {
                        isEffect = YES;
                        break;
                    }
                }
                
                // If not an effect, check if it's a filter
                BOOL isFilter = NO;
                if (!isEffect) {
                    for (NSString *keyword in filterKeywords) {
                        if ([lowercaseName containsString:keyword]) {
                            isFilter = YES;
                            break;
                        }
                    }
                }
                
                if (isEffect) {
                    filterType = @"effect";
                    filterCategory = @"effect";
                    sourceType = @"effect";
                    NSLog(@"📊 Categorized '%@' as EFFECT (matched effect keyword)", fileName);
                } else if (isFilter) {
                    filterType = @"filter";
                    filterCategory = @"filter";
                    sourceType = @"filter";
                    NSLog(@"📊 Categorized '%@' as FILTER (matched filter keyword)", fileName);
                } else {
                    // Default to effect if can't determine
                    filterType = @"effect";
                    filterCategory = @"effect";
                    sourceType = @"effect";
                    NSLog(@"📊 Categorized '%@' as EFFECT (default fallback)", fileName);
                }
            }
            
            NSDictionary *filterInfo = @{
                @"id": fileName,
                @"name": fileName,
                @"displayName": displayName,
                @"description": [NSString stringWithFormat:@"Local filter: %@", displayName],
                @"path": filePath,
                @"fileSize": fileSize,
                @"type": @"local",
                @"isDownloaded": @YES,
                @"isFree": @YES,
                @"downloadCount": @0,
                @"price": @0,
                @"filterCategory": filterCategory, // Proper categorization from metadata
                @"sourceType": sourceType, // Proper categorization from metadata  
                @"filterType": filterType // Proper categorization from metadata
            };
            
            // PREVIEW FIX: Check for preview data in filter metadata (individual files - local filters use image bytes)
            NSMutableDictionary *enhancedFilterInfo = [filterInfo mutableCopy];
            
            // Try to get preview from metadata first
            BOOL previewFound = NO;
            if (filterMetadata) {
                // For local filters, check for preview image data (Uint8List/NSData)
                NSData *previewImageData = filterMetadata[@"previewImage"] ?: filterMetadata[@"preview_image"] ?: filterMetadata[@"thumbnailImage"];
                if (previewImageData && [previewImageData isKindOfClass:[NSData class]]) {
                    // Convert NSData to base64 string for consistent handling
                    NSString *base64String = [previewImageData base64EncodedStringWithOptions:0];
                    enhancedFilterInfo[@"previewImageBase64"] = base64String;
                    NSLog(@"✅ Added preview image data for filter %@: %lu bytes", fileName, (unsigned long)previewImageData.length);
                    previewFound = YES;
                } else {
                    // Fallback: check for preview URL string (in case some filters still use URLs)
                    NSString *previewUrl = filterMetadata[@"previewUrl"] ?: filterMetadata[@"preview_url"] ?: filterMetadata[@"previewURL"] ?: filterMetadata[@"thumbnailUrl"];
                    if (previewUrl && previewUrl.length > 0) {
                        enhancedFilterInfo[@"previewUrl"] = previewUrl;
                        NSLog(@"✅ Added preview URL for filter %@: %@", fileName, previewUrl);
                        previewFound = YES;
                    }
                }
            }
            
            // If no preview found in metadata, try to load from SDK or generate one
            if (!previewFound) {
                // First try to load preview image from NosmaiSDK if available
                if ([self.nosmaiSDK respondsToSelector:@selector(loadPreviewImageForFilter:)]) {
                    UIImage *sdkPreviewImage = [self.nosmaiSDK performSelector:@selector(loadPreviewImageForFilter:) withObject:filePath];
                    if (sdkPreviewImage) {
                        NSData *imageData = UIImageJPEGRepresentation(sdkPreviewImage, 0.7);
                        if (imageData) {
                            NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                            enhancedFilterInfo[@"previewImageBase64"] = base64String;
                            NSLog(@"✅ Loaded preview image from SDK for filter %@: %lu bytes", fileName, (unsigned long)imageData.length);
                            previewFound = YES;
                        }
                    }
                }
                
                // If still no preview, generate a default preview image
                if (!previewFound) {
                    UIImage *previewImage = [self generatePreviewImageForFilter:fileName displayName:displayName];
                    if (previewImage) {
                        NSData *imageData = UIImagePNGRepresentation(previewImage);
                        if (imageData) {
                            NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                            enhancedFilterInfo[@"previewImageBase64"] = base64String;
                            NSLog(@"✅ Generated fallback preview image for filter %@", fileName);
                        }
                    }
                }
            }
            
            [localFilters addObject:enhancedFilterInfo];

        }
    }
    

    return [localFilters copy];
}

// Helper method to convert snake_case to Title Case
- (NSString *)convertToDisplayName:(NSString *)snakeCaseName {
    NSArray *components = [snakeCaseName componentsSeparatedByString:@"_"];
    NSMutableArray *capitalizedComponents = [NSMutableArray array];
    
    for (NSString *component in components) {
        if (component.length > 0) {
            NSString *capitalized = [component stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                       withString:[[component substringToIndex:1] uppercaseString]];
            [capitalizedComponents addObject:capitalized];
        }
    }
    
    return [capitalizedComponents componentsJoinedByString:@" "];
}

// Helper method to generate a preview image for filters without existing previews
- (UIImage *)generatePreviewImageForFilter:(NSString *)filterName displayName:(NSString *)displayName {
    // Create a 200x200 image with gradient background
    CGSize imageSize = CGSizeMake(200, 200);
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }
    
    // Generate a color based on filter name hash for variety
    NSUInteger hash = [filterName hash];
    CGFloat hue = (hash % 360) / 360.0;
    UIColor *topColor = [UIColor colorWithHue:hue saturation:0.6 brightness:0.8 alpha:1.0];
    UIColor *bottomColor = [UIColor colorWithHue:hue saturation:0.8 brightness:0.5 alpha:1.0];
    
    // Create gradient background
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(__bridge id)topColor.CGColor, (__bridge id)bottomColor.CGColor];
    CGFloat locations[] = {0.0, 1.0};
    
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);
    CGPoint startPoint = CGPointMake(0, 0);
    CGPoint endPoint = CGPointMake(imageSize.width, imageSize.height);
    CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, 0);
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    // Add filter icon in center
    NSString *iconSymbol = @"✨"; // Default icon
    NSString *lowercaseName = [filterName lowercaseString];
    
    // Choose icon based on filter name
    if ([lowercaseName containsString:@"vintage"] || [lowercaseName containsString:@"retro"]) {
        iconSymbol = @"📷";
    } else if ([lowercaseName containsString:@"blur"]) {
        iconSymbol = @"💫";
    } else if ([lowercaseName containsString:@"color"] || [lowercaseName containsString:@"rainbow"]) {
        iconSymbol = @"🎨";
    } else if ([lowercaseName containsString:@"beauty"] || [lowercaseName containsString:@"smooth"]) {
        iconSymbol = @"✨";
    } else if ([lowercaseName containsString:@"neon"] || [lowercaseName containsString:@"glow"]) {
        iconSymbol = @"💡";
    } else if ([lowercaseName containsString:@"dark"] || [lowercaseName containsString:@"noir"]) {
        iconSymbol = @"🌙";
    } else if ([lowercaseName containsString:@"bright"] || [lowercaseName containsString:@"sunny"]) {
        iconSymbol = @"☀️";
    }
    
    // Draw icon
    NSDictionary *iconAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:60],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    CGSize iconSize = [iconSymbol sizeWithAttributes:iconAttributes];
    CGRect iconRect = CGRectMake((imageSize.width - iconSize.width) / 2,
                                  (imageSize.height - iconSize.height) / 2 - 10,
                                  iconSize.width,
                                  iconSize.height);
    [iconSymbol drawInRect:iconRect withAttributes:iconAttributes];
    
    // Draw display name at bottom
    NSDictionary *textAttributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    // Truncate display name if too long
    NSString *text = displayName;
    if (text.length > 20) {
        text = [[text substringToIndex:17] stringByAppendingString:@"..."];
    }
    
    CGSize textSize = [text sizeWithAttributes:textAttributes];
    CGRect textRect = CGRectMake((imageSize.width - textSize.width) / 2,
                                  imageSize.height - textSize.height - 10,
                                  textSize.width,
                                  textSize.height);
    [text drawInRect:textRect withAttributes:textAttributes];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

#pragma mark - Camera Controls

- (BOOL)switchCamera {
    NSLog(@"📷 Attempting to switch camera from %@ to %@...", 
          self.isUsingFrontCamera ? @"front" : @"back",
          self.isUsingFrontCamera ? @"back" : @"front");
    
    // Initialize camera if not already done
    if (!self.captureSession) {
        NSLog(@"📷 No capture session found, initializing camera...");
        
        // CRITICAL: Do NOT flip camera state here - isUsingFrontCamera is already set correctly
        // The switchCamera method should only be called when we actually want to switch
        // For initial setup, keep the current camera position (which defaults to front)
        
        [self setupCustomCamera];
        
        if (!self.captureSession) {
            NSLog(@"❌ Camera switch failed: Could not initialize capture session");
            return NO;
        }
        [self applyPreviewMirrorTransform];

        NSLog(@"✅ Camera initialized with %@ camera", self.isUsingFrontCamera ? @"front" : @"back");
        // Apply mirroring for the newly initialized camera
        return YES;
    }
    
    // Get the current camera input
    AVCaptureDeviceInput *currentCameraInput = nil;
    for (AVCaptureInput *input in self.captureSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                currentCameraInput = deviceInput;
                break;
            }
        }
    }
    
    if (!currentCameraInput) {
        NSLog(@"❌ Camera switch failed: No current camera input found");
        return NO;
    }
    
    // Get the new camera device
    AVCaptureDevicePosition newPosition = self.isUsingFrontCamera ? 
        AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    
    AVCaptureDevice *newCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                    mediaType:AVMediaTypeVideo
                                                                     position:newPosition];
    
    if (!newCamera) {
        NSLog(@"❌ Camera switch failed: New camera device not available");
        return NO;
    }
    
    // Create new input
    NSError *error;
    AVCaptureDeviceInput *newCameraInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:&error];
    
    if (!newCameraInput) {
        NSLog(@"❌ Camera switch failed: Could not create new camera input - %@", error.localizedDescription);
        return NO;
    }
    
    // Switch cameras
    [self.captureSession beginConfiguration];
    
    [self.captureSession removeInput:currentCameraInput];
    
    if ([self.captureSession canAddInput:newCameraInput]) {
        [self.captureSession addInput:newCameraInput];
        
        // Update connection settings
        AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection.isVideoOrientationSupported) {
            connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        }
        
        // Update mirroring based on camera position
        if (connection.isVideoMirroringSupported) {
            // Front camera: Mirror capture so remote viewers see mirrored view (same as local)
            // Back camera: No mirror so remote viewers see normal view
            connection.videoMirrored = (newPosition == AVCaptureDevicePositionFront) ? YES : NO;
            NSLog(@"📷 Camera switch: videoMirrored = %@ for %@ camera", 
                  (newPosition == AVCaptureDevicePositionFront) ? @"YES" : @"NO",
                  (newPosition == AVCaptureDevicePositionFront) ? @"front" : @"back");
        }
        
        [self.captureSession commitConfiguration];
        
        // Update state
        self.isUsingFrontCamera = (newPosition == AVCaptureDevicePositionFront);
        

        [self applyPreviewMirrorTransform];

        // CRITICAL: Update mirroring in globalPreviewView to match camera position
        // This ensures local preview appears correctly for the user
        if (globalPreviewView) {
            [globalPreviewView updateMirrorMode:self.isUsingFrontCamera cameraIsFront:self.isUsingFrontCamera];
            NSLog(@"🪞 Updated globalPreviewView mirror mode: %@ camera", self.isUsingFrontCamera ? @"front" : @"back");
        }
        
        // Notify NosmaiSDK about the camera position change if available
        if (self.nosmaiSDK) {
            SEL configureCameraSelector = NSSelectorFromString(@"configureCameraWithPosition:sessionPreset:");
            if ([self.nosmaiSDK respondsToSelector:configureCameraSelector]) {
                NSNumber *position = @(newPosition);
                NSString *preset = @"AVCaptureSessionPresetHigh";
                [self.nosmaiSDK performSelector:configureCameraSelector withObject:position withObject:preset];
                NSLog(@"🔄 Notified NosmaiSDK about camera switch");
            }
        }
        
        NSLog(@"✅ Successfully switched to %@ camera", 
              self.isUsingFrontCamera ? @"front" : @"back");
        
        // Restart processing if it was stopped for camera light management
        [self restartProcessingIfStoppedForCameraLight];
        
        return YES;
        
    } else {
        NSLog(@"❌ Camera switch failed: Cannot add new camera input to session");
        [self.captureSession commitConfiguration];
        return NO;
    }
}

- (void)enableMirror:(BOOL)enable {
    NSLog(@"🪞 enableMirror called with enable=%@ (current isUsingFrontCamera=%@)", 
          enable ? @"YES" : @"NO", self.isUsingFrontCamera ? @"YES" : @"NO");
    
    self.mirrorEnabled = enable;
    [self applyPreviewMirrorTransform];
    
    // CRITICAL: Apply mirroring based on user preference (enable parameter)
    // The 'enable' parameter represents the user's mirror preference from Flutter:
    // - enable=YES means user wants mirroring enabled (regardless of camera)
    // - enable=NO means user wants mirroring disabled (regardless of camera)
    if (self.captureSession && self.videoOutput) {
        AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection && connection.isVideoMirroringSupported) {
            // Apply the user's mirror preference directly to the capture session
            BOOL shouldMirror = enable;
            if (connection.videoMirrored != shouldMirror) {
                [self.captureSession beginConfiguration];
                connection.videoMirrored = shouldMirror;
                [self.captureSession commitConfiguration];
                NSLog(@"🔧 Applied capture session mirroring: %@ (user preference: %@)",
                      shouldMirror ? @"YES" : @"NO",
                      enable ? @"enabled" : @"disabled");
            }
        }
    }
    
    // Also update globalPreviewView if available
    if (globalPreviewView) {
        [globalPreviewView updateMirrorMode:enable cameraIsFront:self.isUsingFrontCamera];
        NSLog(@"🪞 Updated globalPreviewView mirror via enableMirror: %@ (camera: %@)", 
              enable ? @"enabled" : @"disabled", 
              self.isUsingFrontCamera ? @"front" : @"back");
    }
}

#pragma mark - Preview Mirroring Helper

// - (void)applyPreviewMirrorTransform {
//     // For front camera, upstream frames are mirrored by default in many pipelines.
//     // We flip the preview layer to UNMIRROR when mirrorEnabled is NO.
//     BOOL shouldFlipHorizontally = self.isUsingFrontCamera ? !self.mirrorEnabled : NO;
    
//     dispatch_async(dispatch_get_main_queue(), ^{
//         if (self.processedFrameDisplayLayer) {
//             self.processedFrameDisplayLayer.transform = shouldFlipHorizontally
//                 ? CATransform3DMakeScale(-1.0, 1.0, 1.0)
//                 : CATransform3DIdentity;
//         }
//         if (globalPreviewView) {
//             [globalPreviewView updateMirrorMode:shouldFlipHorizontally];
//         }
//     });
// }

- (void)applyPreviewMirrorTransform {
    // Apply mirror transform based on user's mirror preference (mirrorEnabled)
    // This allows users to control mirroring regardless of camera position
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.processedFrameDisplayLayer) {
            if (self.mirrorEnabled) {
                // User wants mirroring: apply horizontal flip transform
                self.processedFrameDisplayLayer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0);
                NSLog(@"🪞 Mirror enabled: Applying horizontal flip transform");
            } else {
                // User doesn't want mirroring: show normal view
                self.processedFrameDisplayLayer.transform = CATransform3DIdentity;
                NSLog(@"🪞 Mirror disabled: Showing normal view");
            }
        }
    });
}


- (void)enableLocalPreview:(BOOL)enable {

    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (enable) {
            // Start pushing frames to the local preview
            if (self.agoraEngine) {
                // The external video frames are already being pushed to Agora
                // The local preview should show automatically when startPreview is called

            }
            
            // Restart processing if it was stopped for camera light management
            [self restartProcessingIfStoppedForCameraLight];
        } else {

        }
    });
}

#pragma mark - Beauty Effects

- (void)applySkinSmoothing:(float)intensity {
    NSLog(@"🎨 Beauty: Skin smoothing %.2f", intensity);
    [self applySkinSmoothingInternal:intensity];
}

- (void)applySkinSmoothingInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applySkinSmoothing:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
            NSLog(@"✅ Applied skin smoothing through NosmaiSDK: %.2f", intensity);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply skin smoothing: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applySkinSmoothing:");
    }
}

- (void)applyFaceSlimming:(float)intensity {
    NSLog(@"🎨 Beauty: Face slimming %.2f", intensity);
    [self applyFaceSlimmingInternal:intensity];
}

- (void)applyFaceSlimmingInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyFaceSlimming:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
            NSLog(@"✅ Applied face slimming through NosmaiSDK: %.2f", intensity);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply face slimming: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyFaceSlimming:");
    }
}

- (void)applyEyeEnlargement:(float)intensity {
    NSLog(@"🎨 Beauty: Eye enlargement %.2f", intensity);
    [self applyEyeEnlargementInternal:intensity];
}

- (void)applyEyeEnlargementInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyEyeEnlargement:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
            NSLog(@"✅ Applied eye enlargement through NosmaiSDK: %.2f", intensity);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply eye enlargement: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyEyeEnlargement:");
    }
}

- (void)applySkinWhitening:(float)intensity {
    NSLog(@"🎨 Beauty: Skin whitening %.2f", intensity);
    [self applySkinWhiteningInternal:intensity];
}

- (void)applySkinWhiteningInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applySkinWhitening:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
            NSLog(@"✅ Applied skin whitening through NosmaiSDK: %.2f", intensity);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply skin whitening: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applySkinWhitening:");
    }
}

- (void)applyNoseSize:(float)intensity {
    NSLog(@"🎨 Beauty: Nose size %.2f", intensity);
    [self applyNoseSizeInternal:intensity];
}

- (void)applyNoseSizeInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyNoseSize:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
            NSLog(@"✅ Applied nose size through NosmaiSDK: %.2f", intensity);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply nose size: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyNoseSize:");
    }
}

- (void)applyBrightnessFilter:(float)brightness {
    NSLog(@"🎨 Beauty: Brightness %.2f", brightness);
    SEL selector = NSSelectorFromString(@"applyBrightnessFilter:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(brightness)];
            NSLog(@"✅ Applied brightness through NosmaiSDK: %.2f", brightness);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply brightness: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyBrightnessFilter:");
    }
}

- (void)applyContrastFilter:(float)contrast {
    NSLog(@"🎨 Beauty: Contrast %.2f", contrast);
    SEL selector = NSSelectorFromString(@"applyContrastFilter:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(contrast)];
            NSLog(@"✅ Applied contrast through NosmaiSDK: %.2f", contrast);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply contrast: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyContrastFilter:");
    }
}

- (void)applySharpening:(float)level {
    NSLog(@"🎨 Beauty: Sharpening %.2f", level);
    SEL selector = NSSelectorFromString(@"applySharpening:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(level)];
            NSLog(@"✅ Applied sharpening through NosmaiSDK: %.2f", level);
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply sharpening: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applySharpening:");
    }
}

- (void)applyRGBFilter:(float)red green:(float)green blue:(float)blue {
    NSLog(@"🎨 Beauty: RGB Filter R:%.2f G:%.2f B:%.2f", red, green, blue);
    SEL selector = NSSelectorFromString(@"applyRGBFilterWithRed:green:blue:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:selector];
            [invocation setArgument:&red atIndex:2];
            [invocation setArgument:&green atIndex:3];
            [invocation setArgument:&blue atIndex:4];
            [invocation invoke];
            NSLog(@"✅ Applied RGB filter through NosmaiSDK");
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply RGB filter: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyRGBFilterWithRed:green:blue:");
    }
}

- (void)applyMakeupBlendLevel:(NSString *)filterName level:(float)level {
    NSLog(@"🧪 Applying makeup blend level - Filter: %@, Level: %.3f", filterName, level);
    
    // Validate input parameters
    if (!filterName || filterName.length == 0) {
        NSLog(@"❌ applyMakeupBlendLevel failed: filterName is nil or empty");
        return;
    }
    
    if (!self.nosmaiSDK) {
        NSLog(@"❌ applyMakeupBlendLevel failed: nosmaiSDK is nil");
        return;
    }
    
    // Create a strong local reference to prevent deallocation during method execution
    id localSDK = self.nosmaiSDK;
    if (!localSDK) {
        NSLog(@"❌ NosmaiSDK is nil, cannot apply makeup blend level");
        return;
    }
    
    SEL selector = NSSelectorFromString(@"applyMakeupBlendLevel:level:");
    if ([localSDK respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [localSDK methodSignatureForSelector:selector];
            if (!signature) {
                NSLog(@"❌ Could not get method signature for applyMakeupBlendLevel:level:");
                return;
            }
            
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:localSDK];
            [invocation setSelector:selector];
            [invocation setArgument:&filterName atIndex:2];
            [invocation setArgument:&level atIndex:3];
            [invocation retainArguments]; // Prevent arguments from being deallocated
            [invocation invoke];
            NSLog(@"✅ Applied makeup blend level: %@ with level %.3f", filterName, level);
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception applying makeup blend level (%@): %@ - %@", filterName, exception.name, exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support applyMakeupBlendLevel:level: method");
        
        // Try alternative methods for lipstick specifically
        if ([filterName isEqualToString:@"LipstickFilter"]) {
            NSLog(@"🔧 Trying alternative lipstick methods...");
            
            // Try the documented method from SDK guide
            SEL lipstickSelector = NSSelectorFromString(@"applyLipstickWithBlendLevel:");
            if ([localSDK respondsToSelector:lipstickSelector]) {
                @try {
                    NSMethodSignature *signature = [localSDK methodSignatureForSelector:lipstickSelector];
                    if (!signature) {
                        NSLog(@"❌ Could not get method signature for applyLipstickWithBlendLevel:");
                        return;
                    }
                    
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:localSDK];
                    [invocation setSelector:lipstickSelector];
                    [invocation setArgument:&level atIndex:2];
                    [invocation retainArguments]; // Prevent arguments from being deallocated
                    [invocation invoke];
                    NSLog(@"✅ Applied lipstick using applyLipstickWithBlendLevel: %.3f", level);
                } @catch (NSException *exception) {
                    NSLog(@"❌ Exception with applyLipstickWithBlendLevel: %@ - %@", exception.name, exception.reason);
                }
            } else {
                NSLog(@"❌ applyLipstickWithBlendLevel: method also not available");
                
                // List available methods for debugging
                NSLog(@"🔍 Available methods in NosmaiSDK:");
                unsigned int methodCount;
                Method *methods = class_copyMethodList([localSDK class], &methodCount);
                for (unsigned int i = 0; i < methodCount; i++) {
                    SEL methodSEL = method_getName(methods[i]);
                    NSString *methodName = NSStringFromSelector(methodSEL);
                    if ([methodName containsString:@"lipstick"] || [methodName containsString:@"Lipstick"] || 
                        [methodName containsString:@"makeup"] || [methodName containsString:@"Makeup"]) {
                        NSLog(@"🔍 Found makeup/lipstick method: %@", methodName);
                    }
                }
                free(methods);
            }
        }
    }
}

- (void)applyGrayscaleFilter {
    SEL selector = NSSelectorFromString(@"applyGrayscaleFilter");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        [self.nosmaiSDK performSelector:selector];
    }
}

- (void)applyHue:(float)hueAngle {
    SEL selector = NSSelectorFromString(@"applyHue:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.nosmaiSDK];
        [invocation setSelector:selector];
        [invocation setArgument:&hueAngle atIndex:2];
        [invocation invoke];
    }
}

- (void)applyWhiteBalance:(float)temperature tint:(float)tint {
    // Use the correct method name from NosmaiSDK headers: applyWhiteBalanceWithTemperature:tint:
    SEL selector = NSSelectorFromString(@"applyWhiteBalanceWithTemperature:tint:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.nosmaiSDK];
        [invocation setSelector:selector];
        [invocation setArgument:&temperature atIndex:2];
        [invocation setArgument:&tint atIndex:3];
        [invocation invoke];
    }
}

- (void)adjustHSB:(float)hue saturation:(float)saturation brightness:(float)brightness {
    NSLog(@"🎨 HSB Adjustment - Hue: %.3f, Saturation: %.3f, Brightness: %.3f", hue, saturation, brightness);
    
    // Use the correct method name from NosmaiSDK headers: adjustHSBWithHue:saturation:brightness:
    SEL selector = NSSelectorFromString(@"adjustHSBWithHue:saturation:brightness:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:selector];
            [invocation setArgument:&hue atIndex:2];
            [invocation setArgument:&saturation atIndex:3];
            [invocation setArgument:&brightness atIndex:4];
            [invocation invoke];
            NSLog(@"✅ Successfully applied HSB adjustment through NosmaiSDK");
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to apply HSB adjustment: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support adjustHSBWithHue:saturation:brightness: method");
    }
}

- (void)resetHSBFilter {
    SEL selector = NSSelectorFromString(@"resetHSBFilter");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        [self.nosmaiSDK performSelector:selector];
    }
}

- (void)removeBuiltInFilters {
    SEL selector = NSSelectorFromString(@"removeAllBuiltInFilters");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector];
            NSLog(@"✅ Removed built-in filters through NosmaiSDK");
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to remove built-in filters: %@", exception.reason);
        }
    } else {
        NSLog(@"❌ NosmaiSDK doesn't support removeAllBuiltInFilters");
    }
}

- (BOOL)isBeautyFilterEnabled {
    // Use the correct method name from NosmaiSDK headers: isBeautyEffectEnabled
    SEL selector = NSSelectorFromString(@"isBeautyEffectEnabled");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSNumber *result = [self.nosmaiSDK performSelector:selector];
            return [result boolValue];
        } @catch (NSException *exception) {
            NSLog(@"❌ isBeautyEffectEnabled failed with exception: %@", exception);
            return NO;
        }
    }
    return NO;
}

- (BOOL)isCloudFilterEnabled {
    SEL selector = NSSelectorFromString(@"isCloudFilterEnabled");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSNumber *result = [self.nosmaiSDK performSelector:selector];
            return [result boolValue];
        } @catch (NSException *exception) {
            NSLog(@"❌ isCloudFilterEnabled failed with exception: %@", exception);
            return NO;
        }
    }
    return NO;
}

- (NSArray *)getCloudFilters {
    SEL selector = NSSelectorFromString(@"getCloudFilters");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSArray *cloudFilters = [self.nosmaiSDK performSelector:selector];
            
            if (cloudFilters && cloudFilters.count > 0) {
                // Process each cloud filter to enhance data like nosmai_flutter plugin
                NSMutableArray *enhancedFilters = [NSMutableArray array];
                
                for (NSDictionary *filter in cloudFilters) {
                    NSMutableDictionary *enhancedFilter = [filter mutableCopy];
                    
                    // Safely get filter path, handling NSNull
                    id pathValue = filter[@"path"];
                    id localPathValue = filter[@"localPath"];
                    NSString *filterPath = nil;
                    
                    if ([pathValue isKindOfClass:[NSString class]]) {
                        filterPath = pathValue;
                    } else if ([localPathValue isKindOfClass:[NSString class]]) {
                        filterPath = localPathValue;
                    }
                    
                    // If no path found, try to construct download path for cloud filters
                    if (!filterPath || filterPath.length == 0) {
                        NSString *filterId = filter[@"id"] ?: filter[@"filterId"];
                        NSString *filterName = filter[@"name"];
                        NSString *category = filter[@"filterCategory"];
                        
                        if (filterId && filterName && category) {
                            // Try to construct the expected download path
                            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                            if (paths.count > 0) {
                                NSString *cachesDir = paths[0];
                                NSString *cloudFiltersDir = [cachesDir stringByAppendingPathComponent:@"NosmaiCloudFilters"];
                                
                                // Try different possible filename patterns
                                NSString *normalizedName = [[filterName lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
                                NSArray *possibleFilenames = @[
                                    [NSString stringWithFormat:@"%@_%@_%@.nosmai", category, normalizedName, filterId],
                                    [NSString stringWithFormat:@"%@_%@.nosmai", category, filterId],
                                    [NSString stringWithFormat:@"%@.nosmai", filterId],
                                    [NSString stringWithFormat:@"special-effects_%@_%@.nosmai", normalizedName, filterId],
                                ];
                                
                                for (NSString *filename in possibleFilenames) {
                                    NSString *possiblePath = [cloudFiltersDir stringByAppendingPathComponent:filename];
                                    if ([[NSFileManager defaultManager] fileExistsAtPath:possiblePath]) {
                                        filterPath = possiblePath;
                                        enhancedFilter[@"path"] = filterPath;
                                        enhancedFilter[@"isDownloaded"] = @YES;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    
                    // Properly categorize cloud filters
                    NSString *filterType = @"effect"; // Default fallback
                    NSString *filterCategory = @"effect"; // Default fallback
                    NSString *sourceType = @"effect"; // Default fallback
                    
                    // First, check if filterCategory is already provided by cloud service
                    if (filter[@"sourceType"] && ![filter[@"sourceType"] isKindOfClass:[NSNull class]]) {
                        NSString *cloudCategory = [filter[@"sourceType"] description];
                        filterCategory = cloudCategory;
                        
                        // Map cloud categories to our source types
                        NSString *lowercaseCategory = [cloudCategory lowercaseString];
                        if ([lowercaseCategory containsString:@"filter"] || [lowercaseCategory containsString:@"color"] || [lowercaseCategory containsString:@"tone"]) {
                            sourceType = @"filter";
                            filterType = @"filter";
                        } else if ([lowercaseCategory containsString:@"beauty"]) {
                            sourceType = @"filter";
                            filterType = @"filter";
                            filterCategory = @"beauty";
                        } else {
                            sourceType = @"effect";
                            filterType = @"effect";
                        }
                    } else {
                        // Fallback: Categorize based on filter name
                        NSString *filterName = filter[@"name"] ? [filter[@"name"] description] : @"";
                        NSString *lowercaseName = [filterName lowercaseString];
                        
                        // Common filter keywords (color/tone adjustments)
                        NSArray *filterKeywords = @[@"vintage", @"retro", @"warm", @"cool", @"bright", @"dark", 
                                                   @"sepia", @"mono", @"contrast", @"vivid", @"soft", @"sharp",
                                                   @"lomo", @"film", @"analog", @"classic", @"noir", @"bw",
                                                   @"color", @"tone", @"grade", @"cinematic", @"natural",
                                                   @"fade", @"trail", @"blue", @"edge", @"vibe", @"alpine",
                                                   @"amber", @"arctic", @"azure", @"bold", @"chill", @"sunset",
                                                   @"sunrise", @"golden", @"silver", @"bronze", @"copper"];
                        
                        // Common effect keywords (animated/special effects)
                        NSArray *effectKeywords = @[@"party", @"heart", @"star", @"fire", @"water", @"smoke",
                                                   @"lightning", @"rainbow", @"sparkle", @"glitter", @"confetti",
                                                   @"snow", @"rain", @"bubble", @"explosion", @"magic",
                                                   @"neon", @"glow", @"laser", @"hologram", @"3d", @"special"];
                        
                        // Check if it's likely an effect first (more specific)
                        BOOL isEffect = NO;
                        for (NSString *keyword in effectKeywords) {
                            if ([lowercaseName containsString:keyword]) {
                                isEffect = YES;
                                NSLog(@"☁️ Cloud filter '%@' categorized as EFFECT (matched: %@)", filterName, keyword);
                                break;
                            }
                        }
                        
                        // If not an effect, check if it's a filter
                        BOOL isFilter = NO;
                        if (!isEffect) {
                            for (NSString *keyword in filterKeywords) {
                                if ([lowercaseName containsString:keyword]) {
                                    isFilter = YES;
                                    NSLog(@"☁️ Cloud filter '%@' categorized as FILTER (matched: %@)", filterName, keyword);
                                    break;
                                }
                            }
                        }
                        
                        if (isEffect) {
                            filterType = @"effect";
                            filterCategory = @"effect";
                            sourceType = @"effect";
                        } else if (isFilter) {
                            filterType = @"filter";
                            filterCategory = @"filter";
                            sourceType = @"filter";
                        } else {
                            // Default to effect if can't determine
                            filterType = @"effect";
                            filterCategory = @"effect";
                            sourceType = @"effect";
                            NSLog(@"☁️ Cloud filter '%@' categorized as EFFECT (default)", filterName);
                        }
                    }
                    
                    // Set the categorization fields
                    enhancedFilter[@"filterCategory"] = filterCategory;
                    enhancedFilter[@"sourceType"] = sourceType;
                    enhancedFilter[@"filterType"] = filterType;
                    
                    // Add type field for cloud filters - required by NosmaiFilter.fromMap
                    if (enhancedFilter[@"type"]) {
                        enhancedFilter[@"originalType"] = enhancedFilter[@"type"];
                    }
                    enhancedFilter[@"type"] = @"cloud";
                    
                    [enhancedFilters addObject:enhancedFilter];
                }
                
                return enhancedFilters;
            }
            
            return cloudFilters ?: @[];
        } @catch (NSException *exception) {
            NSLog(@"❌ getCloudFilters failed with exception: %@", exception);
            return @[];
        }
    }
    return @[];
}

- (void)downloadCloudFilter:(NSString *)filterId
                 completion:(void(^)(NSDictionary *result))completionBlock {
    
    if (!completionBlock) {
        NSLog(@"❌ ERROR: downloadCloudFilter  completionBlock . Operation cancel.");
        return;
    }
    

    if ([[NosmaiSDK sharedInstance] isCloudFilterDownloaded:filterId]) {
        NSString *localPath = [[NosmaiSDK sharedInstance] getCloudFilterLocalPath:filterId];
        if (localPath && localPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            NSLog(@"✅ Filter pehle se downloaded hai. Path: %@", localPath);
            completionBlock(@{
                @"success": @YES,
                @"localPath": localPath,
                @"path": localPath,
                @"message": @"Already downloaded"
            });
            return;
        }
    }
    
    NSLog(@"📥 New filter download start: %@", filterId);


    [[NosmaiSDK sharedInstance] downloadCloudFilter:filterId
                                          progress:nil 
                                        completion:^(BOOL success, NSString *localPath, NSError *error) {
        
        if (success && localPath && localPath.length > 0) {
            NSLog(@"✅ Download complete! Path: %@", localPath);
            completionBlock(@{
                @"success": @YES,
                @"localPath": localPath,
                @"path": localPath
            });
        } else {
            NSString *errorMessage = error ? error.localizedDescription : @"Download failed for unknown reason.";
            NSLog(@"❌ Download failed: %@", errorMessage);
            completionBlock(@{
                @"success": @NO,
                @"error": errorMessage,
                @"details": [NSString stringWithFormat:@"Filter ID: %@", filterId]
            });
        }
    }];
    

}

- (NSArray *)getFilters {
    SEL selector = NSSelectorFromString(@"getFilters");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSArray *result = [self.nosmaiSDK performSelector:selector];
            return result ?: @[];
        } @catch (NSException *exception) {
            NSLog(@"❌ getFilters failed with exception: %@", exception);
            return @[];
        }
    }
    return @[];
}

- (void)clearFilterCache {
    SEL selector = NSSelectorFromString(@"clearFilterCache");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        [self.nosmaiSDK performSelector:selector];
    }
}

- (void)clearBeautyEffects {
    [self clearBeautyEffectsQuietly];
}

// Quiet version for internal use (no async dispatch)
- (void)clearBeautyEffectsQuietly {
    @try {
        // Use NosmaiSDK to clear beauty effects
        [self removeBuiltInFilters];
        NSLog(@"✅ Beauty effects cleared using NosmaiSDK");
        
    } @catch (NSException *exception) {
        
        // Fallback: manually reset individual beauty effects to 0
        @try {
            [self applySkinSmoothingInternal:0.0];
            [self applyFaceSlimmingInternal:0.0];
            [self applyEyeEnlargementInternal:0.0];
            [self applySkinWhiteningInternal:0.0];
            [self applyNoseSizeInternal:50.0]; // Reset to neutral nose size
            
            // Also clear makeup filters (lipstick, blusher, etc.)
            [self applyMakeupBlendLevel:@"LipstickFilter" level:0.0];
            [self applyMakeupBlendLevel:@"BlusherFilter" level:0.0];
            
            NSLog(@"✅ Beauty effects cleared manually as fallback");
        } @catch (NSException *fallbackException) {
            NSLog(@"❌ Manual beauty effects clear also failed: %@", fallbackException.reason);
        }
    }
}

#pragma mark - Processing State

- (BOOL)isProcessing {
    return _isProcessing;
}

- (BOOL)isStreaming {
    return _isStreaming;
}

- (NSDictionary *)getProcessingMetrics {
    SEL selector = NSSelectorFromString(@"getProcessingMetrics");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        return [self.nosmaiSDK performSelector:selector];
    }
    return nil;
}

#pragma mark - Private Methods

- (CVPixelBufferRef)createHorizontallyFlippedPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return NULL;
    
    // Get pixel buffer properties
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    
    // Create a new pixel buffer for the flipped image
    CVPixelBufferRef flippedBuffer = NULL;
    NSDictionary *attributes = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @(YES)
    };
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          pixelFormat,
                                          (__bridge CFDictionaryRef)attributes,
                                          &flippedBuffer);
    
    if (status != kCVReturnSuccess || !flippedBuffer) {
        NSLog(@"❌ Failed to create flipped pixel buffer");
        return NULL;
    }
    
    // Lock both buffers
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(flippedBuffer, 0);
    
    // Get buffer info
    void *srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    void *dstBaseAddress = CVPixelBufferGetBaseAddress(flippedBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    // Perform horizontal flip by copying pixels in reverse order
    for (size_t y = 0; y < height; y++) {
        uint8_t *srcRow = (uint8_t *)srcBaseAddress + y * bytesPerRow;
        uint8_t *dstRow = (uint8_t *)dstBaseAddress + y * bytesPerRow;
        
        // Copy pixels in reverse order (horizontal flip)
        for (size_t x = 0; x < width; x++) {
            size_t srcX = x;
            size_t dstX = width - 1 - x;
            
            // Copy BGRA pixel (4 bytes)
            memcpy(dstRow + dstX * 4, srcRow + srcX * 4, 4);
        }
    }
    
    // Unlock buffers
    CVPixelBufferUnlockBaseAddress(flippedBuffer, 0);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    return flippedBuffer;
}

- (void)sendFrameToAgora:(CVPixelBufferRef)pixelBuffer timestamp:(double)timestamp {
    if (!pixelBuffer) return;
    
    // Auto-restart processing if it was stopped for camera light management
    [self restartProcessingIfStoppedForCameraLight];
    
    // Log frame receipt (reduced frequency to avoid spam)
    static int frameCount = 0;
    frameCount++;
    
    @try {
        BOOL result = NO;
        
        // If we don't have an engine but we're streaming, get the singleton
        if (!self.agoraEngine && self.isStreaming) {
            // Always use the native singleton engine - never the Flutter recreated one
            self.agoraEngine = [[self class] sharedNativeSingletonEngine];
            if (self.agoraEngine && frameCount % 30 == 0) {
                NSLog(@"🔄 Re-acquired native singleton engine for frame pushing");
            }
        }
        
        // Use main engine if available and streaming, otherwise use API engine approach
        if (self.agoraEngine && self.isStreaming) {
            // Use main engine for frame pushing
            AgoraVideoFrame *videoFrame = [[AgoraVideoFrame alloc] init];
            videoFrame.format = 12; // BGRA format (same as Swift implementation)
            videoFrame.textureBuf = pixelBuffer;
            videoFrame.rotation = 0; // No rotation - handle in encoder config
            videoFrame.time = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            
            result = [self.agoraEngine pushExternalVideoFrame:videoFrame];
            
        } else if (self.apiEngine && self.isStreaming) {
            // Use API engine approach - push frames directly via Iris API
            result = [self pushFrameViaIrisAPI:pixelBuffer];
            

        }
    } @catch (NSException *exception) {

    }
}

- (BOOL)pushFrameViaIrisAPI:(CVPixelBufferRef)pixelBuffer {
    if (!self.apiEngine || !pixelBuffer) {
        return NO;
    }
    
    @try {
        // Get the Iris RTC API from the engine pointer
        void *irisRtcApi = self.apiEngine;
        if (!irisRtcApi) {
            return NO;
        }
        
        // Create video frame structure for Iris API
        // This mimics what the Flutter plugin does internally
        
        // Get pixel buffer dimensions
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        
        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        
        // Push the frame data to Agora via external video source
        // The API engine should handle the frame pushing internally
        
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        
        return YES;
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception in pushFrameViaIrisAPI: %@", exception.reason);
        return NO;
    }
}

- (BOOL)pushFrameToFlutterEngine:(CVPixelBufferRef)pixelBuffer {
    // Method placeholder - not currently used
    return NO;
}

- (void)setupCustomCamera {

    
    self.captureSession = [[AVCaptureSession alloc] init];
    
    // Configure session for portrait
    [self.captureSession beginConfiguration];
    self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    
    // Add camera input (default to front camera)
    AVCaptureDevicePosition initialPosition = self.isUsingFrontCamera ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    NSLog(@"🔍 setupCustomCamera: isUsingFrontCamera=%@ initialPosition=%ld", 
          self.isUsingFrontCamera ? @"YES" : @"NO", (long)initialPosition);
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                  mediaType:AVMediaTypeVideo
                                                                   position:initialPosition];
    
    if (camera) {
        NSError *error;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
        if (input && [self.captureSession canAddInput:input]) {
            [self.captureSession addInput:input];

        } else {

            return;
        }
    }
    
    // Add video output
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setSampleBufferDelegate:self queue:self.frameQueue];
    self.videoOutput.videoSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    
    // Configure orientation
    AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    if (connection.isVideoMirroringSupported) {
        // Front camera: Mirror capture so remote viewers see mirrored view (same as local)
        // Back camera: No mirror so remote viewers see normal view
        AVCaptureDevicePosition position = self.isUsingFrontCamera ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        BOOL shouldMirror = (position == AVCaptureDevicePositionFront);
        connection.videoMirrored = shouldMirror;
        NSLog(@"📷 Initial setup: videoMirrored = %@ for %@ camera", 
              shouldMirror ? @"YES" : @"NO",
              (position == AVCaptureDevicePositionFront) ? @"front" : @"back");
    }
    
    if ([self.captureSession canAddOutput:self.videoOutput]) {
        [self.captureSession addOutput:self.videoOutput];

    }
    
    // Setup raw camera preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.captureSession commitConfiguration];
    
    // CRITICAL: Apply initial mirror transform based on camera position
    [self applyPreviewMirrorTransform];
    
    // Also update globalPreviewView with initial mirror state
    if (globalPreviewView) {
        [globalPreviewView updateMirrorMode:self.isUsingFrontCamera cameraIsFront:self.isUsingFrontCamera];
        NSLog(@"🪞 Applied initial mirror state: %@ camera", self.isUsingFrontCamera ? @"front" : @"back");
    }
}

- (void)startCameraCapture {
    if (!self.captureSession) return;
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (!self.captureSession.isRunning) {
            [self.captureSession startRunning];

        }
    });
}

- (void)stopCameraCapture {
    if (!self.captureSession) return;
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (self.captureSession.isRunning) {
            [self.captureSession stopRunning];

        }
    });
}

- (void)releaseAllCameraResources {
    // Prevent multiple simultaneous calls
    if (self.cameraResourcesReleased) {
        NSLog(@"ℹ️ Camera resources already released, skipping duplicate call");
        return;
    }
    
    self.cameraResourcesReleased = YES;
    
    // Stop our custom camera capture session
    [self stopCameraCapture];
    
    // Wait a bit for camera to stop properly
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Release custom camera session completely
        if (self.captureSession) {
            [self.captureSession beginConfiguration];
            
            // Remove all inputs to release camera
            for (AVCaptureInput *input in [self.captureSession.inputs copy]) {
                [self.captureSession removeInput:input];
                NSLog(@"🔧 Removed camera input to release camera lock");
            }
            
            // Remove all outputs
            for (AVCaptureOutput *output in [self.captureSession.outputs copy]) {
                [self.captureSession removeOutput:output];
            }
            
            [self.captureSession commitConfiguration];
            self.captureSession = nil;
            self.videoOutput = nil;
        }
        
        // CRITICAL: Try to release NosmaiSDK camera resources
        [self releaseNosmaiCameraResources];
        
        // Last resort: Try stopping NosmaiSDK processing temporarily to release camera
        // then restart it to preserve shared instance functionality
        [self temporarilyStopNosmaiToReleaseCamera];
        
        // Reset flag after a delay to allow future releases if needed
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.cameraResourcesReleased = NO;
        });
    });
}

- (void)releaseNosmaiCameraResources {
    if (!self.nosmaiSDK) return;
    
    NSLog(@"🔧 Attempting to release NosmaiSDK camera resources...");
    
    @try {
        // First try to stop the internal camera session
        SEL stopCaptureSelector = NSSelectorFromString(@"stopCaptureSession");
        if ([self.nosmaiSDK respondsToSelector:stopCaptureSelector]) {
            [self.nosmaiSDK performSelector:stopCaptureSelector];
            NSLog(@"✅ NosmaiSDK capture session stopped");
        }
        
        // Try to stop the camera directly
        SEL stopCameraSelector = NSSelectorFromString(@"stopCamera");
        if ([self.nosmaiSDK respondsToSelector:stopCameraSelector]) {
            [self.nosmaiSDK performSelector:stopCameraSelector];
            NSLog(@"✅ NosmaiSDK camera stopped");
        }
        
        // Alternative: Try to pause camera without affecting processing
        SEL pauseCameraSelector = NSSelectorFromString(@"pauseCamera");
        if ([self.nosmaiSDK respondsToSelector:pauseCameraSelector]) {
            [self.nosmaiSDK performSelector:pauseCameraSelector];
            NSLog(@"✅ NosmaiSDK camera paused");
        }
        
        // Try to close camera input  
        SEL closeCameraSelector = NSSelectorFromString(@"closeCamera");
        if ([self.nosmaiSDK respondsToSelector:closeCameraSelector]) {
            [self.nosmaiSDK performSelector:closeCameraSelector];
            NSLog(@"✅ NosmaiSDK camera closed");
        }
        
        // Try to suspend the session
        SEL suspendSelector = NSSelectorFromString(@"suspendSession");
        if ([self.nosmaiSDK respondsToSelector:suspendSelector]) {
            [self.nosmaiSDK performSelector:suspendSelector];
            NSLog(@"✅ NosmaiSDK session suspended");
        }
        
        // Alternative method names that might exist
        NSArray *cameraStopMethods = @[
            @"stopVideoCapture",
            @"stopCameraInput",
            @"releaseCameraSession",
            @"deactivateCamera",
            @"deinitCamera",
            @"destroyCamera"
        ];
        
        for (NSString *methodName in cameraStopMethods) {
            SEL selector = NSSelectorFromString(methodName);
            if ([self.nosmaiSDK respondsToSelector:selector]) {
                [self.nosmaiSDK performSelector:selector];
                NSLog(@"✅ NosmaiSDK method %@ called successfully", methodName);
                break; // Stop after first successful method
            }
        }
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception while releasing NosmaiSDK camera: %@", exception.reason);
    }
    
    NSLog(@"✅ Camera resources release attempted - checking if camera light turns off");
}

- (void)temporarilyStopNosmaiToReleaseCamera {
    if (!self.nosmaiSDK) return;
    
    NSLog(@"🔧 Temporarily stopping NosmaiSDK to force camera release...");
    
    @try {
        // Try stopping NosmaiSDK processing to force camera release
        SEL stopSelector = NSSelectorFromString(@"stopProcessing");
        if ([self.nosmaiSDK respondsToSelector:stopSelector]) {
            [self.nosmaiSDK performSelector:stopSelector];
            self.processingStoppedForCameraLight = YES; // Mark that we stopped for camera light
            NSLog(@"⚠️ NosmaiSDK processing stopped to release camera - marked for restart");
            
            // Wait a moment for camera to be released
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSLog(@"📱 Camera light should be OFF now - NosmaiSDK stopped");
                
                // CONSERVATIVE: Don't auto-restart processing here
                // Let the next stream initialization handle restart when needed
                // This prevents potential conflicts and timing issues
                NSLog(@"🔄 NosmaiSDK stopped for camera light - will restart on next stream initialization");
            });
        } else {
            NSLog(@"⚠️ NosmaiSDK stopProcessing method not available");
        }
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception while temporarily stopping NosmaiSDK: %@", exception.reason);
    }
}

- (void)restartProcessingIfStoppedForCameraLight {
    if (self.processingStoppedForCameraLight && self.isStreaming) {
        NSLog(@"🔄 Restarting NosmaiSDK processing after camera light management...");
        
        @try {
            SEL startSelector = NSSelectorFromString(@"startProcessing");
            if ([self.nosmaiSDK respondsToSelector:startSelector]) {
                [self.nosmaiSDK performSelector:startSelector];
                self.processingStoppedForCameraLight = NO; // Clear the flag
                NSLog(@"✅ NosmaiSDK processing restarted successfully for viewers");
            } else {
                NSLog(@"⚠️ NosmaiSDK startProcessing method not available");
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception while restarting NosmaiSDK processing: %@", exception.reason);
        }
    }
}

- (void)releaseAllCameraResourcesSync {
    
    // Stop custom camera session immediately (synchronous for dealloc)
    if (self.captureSession && self.captureSession.isRunning) {
        [self.captureSession stopRunning];
        NSLog(@"🔧 Custom camera session stopped in dealloc");
    }
    
    // Release custom camera session completely
    if (self.captureSession) {
        [self.captureSession beginConfiguration];
        
        // Remove all inputs to release camera
        for (AVCaptureInput *input in [self.captureSession.inputs copy]) {
            [self.captureSession removeInput:input];
        }
        
        // Remove all outputs
        for (AVCaptureOutput *output in [self.captureSession.outputs copy]) {
            [self.captureSession removeOutput:output];
        }
        
        [self.captureSession commitConfiguration];
        self.captureSession = nil;
        self.videoOutput = nil;
        NSLog(@"✅ Custom camera session released in dealloc");
    }
    
    // CRITICAL: Do NOT access shared NosmaiSDK instance in dealloc
    // This can cause race conditions with new instances trying to initialize
    // The shared instance should persist and be managed by new processor instances
    NSLog(@"ℹ️ Skipping NosmaiSDK camera release in dealloc to avoid race conditions with new instances");
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (!self.nosmaiSDK) return;
    
    // Ensure proper orientation
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    // Process frame through Nosmai with conditional mirroring
    SEL processSelector = NSSelectorFromString(@"processSampleBuffer:mirror:");
    if ([self.nosmaiSDK respondsToSelector:processSelector]) {
        NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:processSelector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.nosmaiSDK];
        [invocation setSelector:processSelector];
        [invocation setArgument:&sampleBuffer atIndex:2];
        
        // CRITICAL: Don't mirror the frames - send them as-is to Nosmai
        // Mirroring should be handled at the display level, not at processing level
        BOOL mirror = NO; // Send unmirrored frames to Nosmai
        [invocation setArgument:&mirror atIndex:3];
        [invocation invoke];
        
        // The processed frames will be delivered through the CVPixelBufferCallback
    }
}

#pragma mark - Dealloc

- (void)dealloc {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"🧹 App lifecycle observers removed in dealloc");
    // Simple dealloc without complex semaphore management
    self.isDeallocationInProgress = YES;
    
    NSLog(@"🗑️ AgoraNosmaiProcessor dealloc started - instance: %p", self);
    
    // CRITICAL: Only clean up our own resources, avoid touching shared NosmaiSDK
    // This prevents race conditions with new instances initializing
    
    // SAFE: Only release our custom camera session (not shared NosmaiSDK)
    if (self.captureSession && self.captureSession.isRunning) {
        [self.captureSession stopRunning];
        NSLog(@"🔧 Custom camera session stopped in dealloc");
    }
    
    if (self.captureSession) {
        [self.captureSession beginConfiguration];
        for (AVCaptureInput *input in [self.captureSession.inputs copy]) {
            [self.captureSession removeInput:input];
        }
        for (AVCaptureOutput *output in [self.captureSession.outputs copy]) {
            [self.captureSession removeOutput:output];
        }
        [self.captureSession commitConfiguration];
        self.captureSession = nil;
        self.videoOutput = nil;
        NSLog(@"✅ Custom camera session cleaned up in dealloc");
    }
    
    NSLog(@"✅ AgoraNosmaiProcessor dealloc completed safely - instance: %p", self);
    
    // Clean up layers safely on main thread - but only if we're the actual owner
    if ([NSThread isMainThread]) {
        // We're already on main thread, clean up directly
        if (self.previewLayer) {
            [self.previewLayer removeFromSuperlayer];
        }
        if (self.processedFrameDisplayLayer) {
            [self.processedFrameDisplayLayer removeFromSuperlayer];
        }
    } else {
        // Dispatch to main thread for safe cleanup
        AVCaptureVideoPreviewLayer *rawLayerRef = self.previewLayer;
        AVSampleBufferDisplayLayer *processedLayerRef = self.processedFrameDisplayLayer;
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (rawLayerRef) {
                [rawLayerRef removeFromSuperlayer];
            }
            if (processedLayerRef) {
                [processedLayerRef removeFromSuperlayer];
            }
        });
    }
    

}

#pragma mark - Cloud Filter Helpers

- (BOOL)isCloudFilterById:(NSString *)identifier {
    if (!identifier || identifier.length == 0) return NO;
    
    NSLog(@"🔍 Checking if cloud filter by ID: '%@'", identifier);
    
    // Check if it's a local file path first
    if ([identifier hasPrefix:@"/"] || [identifier hasSuffix:@".nosmai"]) {
        NSLog(@"❌ Detected as local filter (has path or .nosmai extension)");
        return NO;
    }
    
    // Query the SDK to see if this is a valid cloud filter ID
    SEL getCloudFiltersSelector = NSSelectorFromString(@"getCloudFilters");
    if ([self.nosmaiSDK respondsToSelector:getCloudFiltersSelector]) {
        NSArray *cloudFilters = [self.nosmaiSDK performSelector:getCloudFiltersSelector];
        if (cloudFilters && [cloudFilters isKindOfClass:[NSArray class]]) {
            for (NSDictionary *filter in cloudFilters) {
                if ([filter isKindOfClass:[NSDictionary class]]) {
                    NSString *filterId = filter[@"id"] ?: filter[@"filterId"];
                    if ([filterId isEqualToString:identifier]) {
                        NSLog(@"✅ Confirmed as cloud filter ID from SDK");
                        return YES;
                    }
                }
            }
        }
    }
    
    // Fallback pattern matching for cloud filter IDs
    if ([identifier length] < 100 && ![identifier containsString:@"/"] && 
        ([identifier containsString:@"_"] || [identifier rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound)) {
        NSLog(@"✅ Detected as likely cloud filter (pattern match)");
        return YES;
    }
    
    NSLog(@"❌ Not identified as cloud filter");
    return NO;
}

- (BOOL)isValidLocalFilterPath:(NSString *)path {
    if (!path || path.length == 0) return NO;
    
    // Check if file exists and has correct extension
    BOOL isValidPath = [[NSFileManager defaultManager] fileExistsAtPath:path] && [path hasSuffix:@".nosmai"];
    
    if (!isValidPath) {
        NSLog(@"❌ Invalid local filter path: file doesn't exist or wrong extension");
    }
    
    return isValidPath;
}

- (void)downloadCloudFilterAndApply:(NSString *)filterId completion:(void(^)(BOOL success, NSError *error))completion {
    NSLog(@"🌐 Starting download for cloud filter: %@", filterId);
    
    // Skip complex download and just try to get the local path directly
    // If the filter shows as downloaded but path is empty, it might be a caching issue
    SEL getLocalPathSelector = NSSelectorFromString(@"getCloudFilterLocalPath:");
    if ([self.nosmaiSDK respondsToSelector:getLocalPathSelector]) {
        NSString *localPath = [self.nosmaiSDK performSelector:getLocalPathSelector withObject:filterId];
        if (localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            NSLog(@"✅ Found existing local path for cloud filter: %@", localPath);
            [self applyLocalFilterAtPath:localPath completion:completion];
            return;
        } else {
            NSLog(@"⚠️ Local path not found or invalid: %@", localPath ?: @"(null)");
        }
    }
    
    // Use the correct 3-parameter download method
    SEL downloadSelector = NSSelectorFromString(@"downloadCloudFilter:progress:completion:");
    if ([self.nosmaiSDK respondsToSelector:downloadSelector]) {
        NSLog(@"📥 Using download method with progress");
        
        id downloadCompletion = [^(BOOL success, NSString *localPath, NSError *error) {
            if (success && localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                NSLog(@"✅ Cloud filter downloaded successfully to: %@", localPath);
                [self applyLocalFilterAtPath:localPath completion:completion];
            } else {
                NSLog(@"❌ Cloud filter download failed: %@", error.localizedDescription ?: @"Unknown error");
                if (completion) {
                    completion(NO, error ?: [NSError errorWithDomain:@"NosmaiError" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Cloud filter download failed"}]);
                }
            }
        } copy];
        
        // Use NSInvocation to call the 3-parameter method
        NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:downloadSelector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.nosmaiSDK];
        [invocation setSelector:downloadSelector];
        
        // Set arguments: filterId, progressBlock (nil), completion block
        [invocation setArgument:&filterId atIndex:2];
        
        id progressBlock = nil;
        [invocation setArgument:&progressBlock atIndex:3];
        [invocation setArgument:&downloadCompletion atIndex:4];
        
        [invocation invoke];
        return;
    }
    
    NSLog(@"❌ No download methods available, will report error");
    if (completion) {
        completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Cloud filter download not supported"}]);
    }
}

// Separate method for applying local filters to avoid recursion
- (void)applyLocalFilterAtPath:(NSString *)localPath completion:(void(^)(BOOL success, NSError *error))completion {
    if (!localPath || ![[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        NSLog(@"❌ Local filter file not found: %@", localPath);
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-7 userInfo:@{NSLocalizedDescriptionKey: @"Local filter file not found"}]);
        }
        return;
    }
    
    NSLog(@"🎨 Applying local filter: %@", localPath);
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            // Clear beauty effects first for clean filter application
            [self clearBeautyEffectsQuietly];
            
            // Use the correct NosmaiSDK method for applying effects
            SEL applyEffectSelector = NSSelectorFromString(@"applyEffect:completion:");
            if ([self.nosmaiSDK respondsToSelector:applyEffectSelector]) {
                NSLog(@"✅ Using applyEffect:completion: method");
                
                void (^effectCompletion)(BOOL, NSError*) = ^(BOOL success, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(success, error);
                    });
                };
                
                [self.nosmaiSDK performSelector:applyEffectSelector withObject:localPath withObject:effectCompletion];
                return;
            }
            
            // Fallback to synchronous method
            SEL applyEffectSyncSelector = NSSelectorFromString(@"applyEffectSync:");
            if ([self.nosmaiSDK respondsToSelector:applyEffectSyncSelector]) {
                NSLog(@"✅ Using applyEffectSync: method");
                
                BOOL result = [[self.nosmaiSDK performSelector:applyEffectSyncSelector withObject:localPath] boolValue];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(result, result ? nil : [NSError errorWithDomain:@"NosmaiError" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Filter application failed"}]);
                    }
                });
                return;
            }
            
            NSLog(@"❌ No suitable filter application methods found");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"No suitable method found for applying filter"}]);
                }
            });
            
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception during filter application: %@", exception.reason);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-3 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Filter application failed"}]);
                }
            });
        }
    });
}

#pragma mark - App Lifecycle Management

- (void)setupAppLifecycleNotifications {
    NSLog(@"🔧 Setting up app lifecycle notifications for camera session management");
    
    // Listen for app becoming active (returning from background)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Listen for app going to background
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    // Listen for app entering background
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    // Listen for app entering foreground
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    NSLog(@"📱 App became active - checking camera session restoration");
    
    // Always refresh the video output connection when app becomes active
    // This fixes the "failed" status of AVSampleBufferDisplayLayer
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Also recover globalPreviewView if needed
        if (globalPreviewView) {
            [globalPreviewView flushDisplayLayer];
            if (globalPreviewView.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                NSLog(@"⚠️ globalPreviewView display layer is failed, recovering...");
                [globalPreviewView recoverDisplayLayer];
            }
        }
        
        [self refreshVideoOutputConnection];
    });
    
    if (self.isProcessing && self.captureSession) {
        // Additional camera session restoration if needed
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self restoreCameraSessionAfterBackground];
        });
    } else {
        NSLog(@"⚠️ Camera session restoration skipped - not processing");
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    NSLog(@"📱 App will resign active - preparing camera session for background");
    // Don't stop the camera here as it may be needed for ongoing stream
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    NSLog(@"📱 App entered background - camera session may be suspended");
    // Camera session is automatically suspended by iOS
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    NSLog(@"📱 App will enter foreground - preparing to restore camera session");
    
    // Immediately flush and prepare display layer when entering foreground
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.processedFrameDisplayLayer) {
            // Flush any pending frames to clear potential failed state
            [self.processedFrameDisplayLayer flush];
            NSLog(@"🔧 Flushed display layer on foreground entry");
            
            // If layer is already in failed state, mark for immediate recovery
            if (self.processedFrameDisplayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                NSLog(@"⚠️ Display layer already in failed state on foreground entry!");
                // Will be recovered in applicationDidBecomeActive
            }
        }
    });
}

- (void)restoreCameraSessionAfterBackground {
    if (!self.isProcessing) {
        NSLog(@"⚠️ Camera session restoration skipped - not processing");
        return;
    }
    
    NSLog(@"🔄 Restoring camera session after background");
    
    @try {
        // Check if capture session is running
        if (self.captureSession && !self.captureSession.isRunning) {
            NSLog(@"📷 Restarting capture session after background");
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [self.captureSession startRunning];
                NSLog(@"✅ Capture session restarted after background");
                
                // Re-enable Agora video after camera restoration
                dispatch_async(dispatch_get_main_queue(), ^{
                    AgoraRtcEngineKit *engine = [AgoraNosmaiProcessor sharedNativeSingletonEngine];
                    if (engine) {
                        [engine enableVideo];
                        NSLog(@"🔄 Agora video re-enabled after background");
                    }
                });
            });
        }
        
        // Also restart NosmaiSDK processing if it was stopped
        if (self.nosmaiSDK) {
            SEL startProcessingSelector = NSSelectorFromString(@"startProcessing");
            if ([self.nosmaiSDK respondsToSelector:startProcessingSelector]) {
                [self.nosmaiSDK performSelector:startProcessingSelector];
                NSLog(@"🔄 NosmaiSDK processing restarted after background");
            }
        }
        
        // Force refresh of video output connection
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self refreshVideoOutputConnection];
        });
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception during camera session restoration: %@", exception.reason);
    }
}

- (void)recoverFailedDisplayLayer {
    if (!self.processedFrameDisplayLayer) return;
    
    NSLog(@"🔧 Recovering failed display layer...");
    
    // First try to flush the layer
    [self.processedFrameDisplayLayer flush];
    
    // Check if still failed after flush
    if (self.processedFrameDisplayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        NSLog(@"⚠️ Flush didn't recover layer, recreating...");
        
        // Store references
        UIView *parentView = (UIView *)self.processedFrameDisplayLayer.superlayer.delegate;
        if (!parentView) parentView = self.previewView;
        
        // Remove old layer
        [self.processedFrameDisplayLayer removeFromSuperlayer];
        self.processedFrameDisplayLayer = nil;
        
        // Recreate layer
        [self setupProcessedFrameDisplayLayer];
        
        // Re-add to view
        if (self.processedFrameDisplayLayer && parentView) {
            self.processedFrameDisplayLayer.frame = parentView.bounds;
            [parentView.layer addSublayer:self.processedFrameDisplayLayer];
            [self applyPreviewMirrorTransform];
            NSLog(@"✅ Display layer recreated and re-added to view");
        }
    } else {
        NSLog(@"✅ Display layer recovered with flush");
    }
}

- (void)refreshVideoOutputConnection {
    NSLog(@"🔄 Refreshing video output connection after background");
    
    @try {
        // CRITICAL: Reset the display layer to fix "failed" status
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.processedFrameDisplayLayer) {
                // First attempt to flush the layer
                [self.processedFrameDisplayLayer flush];
                
                // Check if layer is still in failed state
                if (self.processedFrameDisplayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                    NSLog(@"⚠️ Display layer is in failed state, recreating...");
                    
                    // Store the parent view before removing the layer
                    UIView *parentView = (UIView *)self.processedFrameDisplayLayer.superlayer.delegate;
                    if (!parentView) {
                        parentView = self.previewView;
                    }
                    
                    // Reset the layer's status by recreating it
                    [self.processedFrameDisplayLayer removeFromSuperlayer];
                    self.processedFrameDisplayLayer = nil;
                    
                    // Recreate the display layer
                    [self setupProcessedFrameDisplayLayer];
                    
                    // CRITICAL: Re-add the layer to the parent view
                    if (self.processedFrameDisplayLayer && parentView) {
                        self.processedFrameDisplayLayer.frame = parentView.bounds;
                        [parentView.layer addSublayer:self.processedFrameDisplayLayer];
                        
                        // Re-apply mirror transform after recreating layer
                        [self applyPreviewMirrorTransform];
                        
                        NSLog(@"✅ Processed frame display layer recreated and re-added to view");
                    } else {
                        NSLog(@"❌ Failed to re-add display layer - no parent view");
                    }
                } else {
                    NSLog(@"✅ Display layer flushed successfully, status is good");
                }
            } else {
                NSLog(@"⚠️ No display layer to refresh");
            }
        });
        
        // Ensure video output is properly connected
        if (self.videoOutput && self.captureSession) {
            // Check if output is still connected
            if (![self.captureSession.outputs containsObject:self.videoOutput]) {
                NSLog(@"⚠️ Video output disconnected, reconnecting...");
                if ([self.captureSession canAddOutput:self.videoOutput]) {
                    [self.captureSession addOutput:self.videoOutput];
                    NSLog(@"✅ Video output reconnected");
                }
            }
        }
        
        // Re-initialize video source connection to Agora if needed
        AgoraRtcEngineKit *engine = [AgoraNosmaiProcessor sharedNativeSingletonEngine];
        if (engine) {
            // Trigger a fresh video frame to ensure the pipeline is active
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"✅ Video pipeline refreshed successfully");
            });
        }
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Exception during video output refresh: %@", exception.reason);
    }
}

@end
