//
//  AgoraNosmaiProcessor.mm
//  agora_rtc_engine
//
//  Created by Claude Code
//  Objective-C++ implementation for direct frame pushing to Agora
//

#import "AgoraNosmaiProcessor.h"
#import <AgoraRtcKit/AgoraRtcEngineKit.h>
#import <AgoraRtcKit/AgoraObjects.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import "NosmaiPreviewView.h"
#import <nosmai/Nosmai.h>

// Use the Iris framework for pushing frames through method channel
#import <Flutter/Flutter.h>

// Global reference to the preview view for easy access
static NosmaiPreviewView *globalPreviewView = nil;

@interface AgoraNosmaiProcessor () <AVCaptureVideoDataOutputSampleBufferDelegate>

// Private methods for safe filter application
- (void)clearBeautyEffectsSynchronously;
- (void)applySkinSmoothingSynchronously:(float)intensity;
- (void)applyFaceSlimmingSynchronously:(float)intensity;
- (void)applyEyeEnlargementSynchronously:(float)intensity;

@property (nonatomic, assign) void *apiEngine;
@property (nonatomic, weak) AgoraRtcEngineKit *agoraEngine; // Weak reference to avoid retain cycles
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

@end

@implementation AgoraNosmaiProcessor

- (instancetype)initWithApiEngine:(void *)apiEngine licenseKey:(NSString *)licenseKey {

    self = [super init];
    if (self) {
        self.apiEngine = apiEngine;
        self.nosmaiLicenseKey = licenseKey;
        self.frameQueue = dispatch_queue_create("nosmai.frame.queue", DISPATCH_QUEUE_SERIAL);
        self.isUsingFrontCamera = YES; // Default to front camera
        self.mirrorEnabled = NO; // Default to no mirroring
        

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
        

        [self setupNosmaiSDK];
    }
    return self;
}

#pragma mark - Engine Management

- (void)setAgoraEngineInstance:(AgoraRtcEngineKit *)engine {

    self.agoraEngine = engine;
}

- (void)createCustomAgoraEngine:(NSString *)appId {

    
    @try {
        // Create engine config
        AgoraRtcEngineConfig *config = [[AgoraRtcEngineConfig alloc] init];
        config.appId = appId;
        
        // Create our own engine instance for frame pushing
        AgoraRtcEngineKit *customEngine = [AgoraRtcEngineKit sharedEngineWithConfig:config delegate:nil];
        
        if (customEngine) {
            self.agoraEngine = customEngine;
            
            // Configure for external video source (matching Flutter's setup from logs)
            [customEngine enableVideo];
            [customEngine setExternalVideoSource:YES useTexture:NO sourceType:AgoraExternalVideoSourceTypeVideoFrame];
            
            // Configure video encoder to match main engine settings
            AgoraVideoEncoderConfiguration *videoConfig = [[AgoraVideoEncoderConfiguration alloc] init];
            videoConfig.dimensions = CGSizeMake(720, 1280);
            videoConfig.frameRate = AgoraVideoFrameRateFps30;
            videoConfig.bitrate = AgoraVideoBitrateStandard;
            videoConfig.orientationMode = AgoraVideoOutputOrientationModeFixedPortrait;
            videoConfig.mirrorMode = AgoraVideoMirrorModeDisabled; // Disable mirroring to fix flip
            [customEngine setVideoEncoderConfiguration:videoConfig];
            
            // Enable local preview - this should make processed frames visible
            [customEngine startPreview];
            

        } else {

        }
        
    } @catch (NSException *exception) {

    }
}

- (AgoraRtcEngineKit *)getCustomEngine {
    return self.agoraEngine;
}

#pragma mark - Setup

- (void)setupNosmaiSDK {
    // Get NosmaiSDK class and check if it exists
    Class sdkClass = NSClassFromString(@"NosmaiSDK");
    if (!sdkClass) {
        return;
    }
    
    // Try to get shared instance first (preferred pattern from reference)
    SEL sharedInstanceSelector = NSSelectorFromString(@"sharedInstance");
    if ([sdkClass respondsToSelector:sharedInstanceSelector]) {
        self.nosmaiSDK = [sdkClass performSelector:sharedInstanceSelector];
        if (self.nosmaiSDK) {
            [self initializeWithLicense];
            return;
        }
    }
    
    // Fallback to class method initialization
    SEL initSelector = NSSelectorFromString(@"initWithLicense:");
    if ([sdkClass respondsToSelector:initSelector]) {
        self.nosmaiSDK = [sdkClass performSelector:initSelector withObject:_nosmaiLicenseKey];
        if (self.nosmaiSDK) {
            [self validateLicenseAndSetup];
        } else {
        }
    } else {
    }
}

- (void)initializeWithLicense {
    if (!self.nosmaiSDK) return;
    
    // Initialize with license key on shared instance
    SEL initSelector = NSSelectorFromString(@"initializeWithLicense:");
    if ([self.nosmaiSDK respondsToSelector:initSelector]) {
        BOOL result = [[self.nosmaiSDK performSelector:initSelector withObject:_nosmaiLicenseKey] boolValue];
        if (result) {
            [self validateLicenseAndSetup];
        } else {
        }
    } else {
        // Some versions might not need separate license initialization
        [self validateLicenseAndSetup];
    }
}

- (void)validateLicenseAndSetup {
    if (!self.nosmaiSDK) return;
    
    // Check if license allows beauty effects and cloud filters
    SEL isBeautyEnabledSelector = NSSelectorFromString(@"isBeautyEffectEnabled");
    SEL isCloudEnabledSelector = NSSelectorFromString(@"isCloudFilterEnabled");
    
    BOOL beautyEnabled = NO, cloudEnabled = NO;
    
    if ([self.nosmaiSDK respondsToSelector:isBeautyEnabledSelector]) {
        @try {
            // Method returns BOOL directly, not NSNumber
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:isBeautyEnabledSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:isBeautyEnabledSelector];
            [invocation invoke];
            [invocation getReturnValue:&beautyEnabled];
        } @catch (NSException *exception) {
        }
    }
    
    if ([self.nosmaiSDK respondsToSelector:isCloudEnabledSelector]) {
        @try {
            // Method returns BOOL directly, not NSNumber
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:isCloudEnabledSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:isCloudEnabledSelector];
            [invocation invoke];
            [invocation getReturnValue:&cloudEnabled];
        } @catch (NSException *exception) {
        }
    }
    
    [self configureNosmaiForExternalProcessing];
}

- (void)configureNosmaiForExternalProcessing {
    if (!self.nosmaiSDK) return;
    
    
    // Try simple configuration first
    SEL configureSelector = NSSelectorFromString(@"configureCameraWithPosition:sessionPreset:");
    if ([self.nosmaiSDK respondsToSelector:configureSelector]) {
        // Use front camera by default, high quality preset
        NSNumber *position = @(1); // Front camera
        NSString *preset = @"AVCaptureSessionPresetHigh";
        [self.nosmaiSDK performSelector:configureSelector withObject:position withObject:preset];
    }
    
    // Enable live frame output for external processing
    SEL setLiveOutputSelector = NSSelectorFromString(@"setLiveFrameOutputEnabled:");
    if ([self.nosmaiSDK respondsToSelector:setLiveOutputSelector]) {
        [self.nosmaiSDK performSelector:setLiveOutputSelector withObject:@YES];
    } else {
    }
    
    [self setupCVPixelBufferCallback];
}

- (void)setupCVPixelBufferCallback {
    
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
        }
    };
    
    // Try the standard callback method
    SEL setCallbackSelector = NSSelectorFromString(@"setCVPixelBufferCallback:");
    if ([self.nosmaiSDK respondsToSelector:setCallbackSelector]) {
        [self.nosmaiSDK performSelector:setCallbackSelector withObject:pixelBufferCallback];
        return;
    }
    
    // Try alternative callback methods
    NSArray *alternativeSelectors = @[@"setPixelBufferCallback:", @"setFrameCallback:"];
    for (NSString *selectorName in alternativeSelectors) {
        SEL altSelector = NSSelectorFromString(selectorName);
        if ([self.nosmaiSDK respondsToSelector:altSelector]) {
            [self.nosmaiSDK performSelector:altSelector withObject:pixelBufferCallback];
            return;
        }
    }
    
}

#pragma mark - Core Processing Controls

- (void)startProcessing {
    if (self.isProcessing) return;
    self.isProcessing = YES;
    
    // Setup camera if not already initialized
    if (!self.captureSession) {
        [self setupCustomCamera];
    }
    
    // Start camera immediately when processor starts
    [self startCameraCapture];
    

}

- (void)stopProcessing {
    if (!self.isProcessing) return;
    

    
    // Stop streaming first
    [self stopLiveStreaming];
    
    // Now stop camera capture completely
    [self stopCameraCapture];
    
    self.isProcessing = NO;

}

- (void)startLiveStreaming {
    if (!self.nosmaiSDK) return;
    

    
    // Setup camera if not already initialized
    if (!self.captureSession) {
        [self setupCustomCamera];
    }
    
    // Start custom camera capture first (if not already started)
    [self startCameraCapture];
    
    // Wait a bit for camera to initialize, then start processing
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Start NosmaiSDK processing
        SEL startSelector = NSSelectorFromString(@"startProcessing");
        if ([self.nosmaiSDK respondsToSelector:startSelector]) {
            [self.nosmaiSDK performSelector:startSelector];

        }
        
        self.isStreaming = YES;

    });
}

- (void)stopLiveStreaming {

    
    // Stop NosmaiSDK processing first
    SEL stopSelector = NSSelectorFromString(@"stopProcessing");
    if ([self.nosmaiSDK respondsToSelector:stopSelector]) {
        [self.nosmaiSDK performSelector:stopSelector];
    }
    
    self.isStreaming = NO;

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
}

- (void)displayProcessedFrame:(CVPixelBufferRef)pixelBuffer {
    if (!self.processedFrameDisplayLayer || !pixelBuffer) {
        static int nullCount = 0;
        nullCount++;
        if (nullCount % 30 == 0) {
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
                
                static int displayCount = 0;
                displayCount++;
                if (displayCount % 60 == 0) { // Log every 60 frames (2 seconds at 30fps)
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
    
    
    // Handle empty or nil path by clearing all filters
    if (!path || path.length == 0) {
        [self clearFilterInternal];
        if (completion) completion(YES, nil);
        return;
    }
    
    // Check if this is a cloud filter that needs downloading
    if ([self isCloudFilterById:path]) {
        
        // Check if already downloaded using proper SDK method
        SEL isDownloadedSelector = NSSelectorFromString(@"isCloudFilterDownloaded:");
        if ([self.nosmaiSDK respondsToSelector:isDownloadedSelector]) {
            BOOL isDownloaded = [[self.nosmaiSDK performSelector:isDownloadedSelector withObject:path] boolValue];
            if (!isDownloaded) {
                [self downloadCloudFilterAndApply:path completion:completion];
                return;
            } else {
                // Get local path for downloaded filter
                SEL getLocalPathSelector = NSSelectorFromString(@"getCloudFilterLocalPath:");
                if ([self.nosmaiSDK respondsToSelector:getLocalPathSelector]) {
                    NSString *localPath = [self.nosmaiSDK performSelector:getLocalPathSelector withObject:path];
                    if (localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                        path = localPath;
                    } else {
                        [self downloadCloudFilterAndApply:path completion:completion];
                        return;
                    }
                } else {
                    if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-8 userInfo:@{NSLocalizedDescriptionKey: @"Cannot get cloud filter local path"}]);
                    return;
                }
            }
        } else {
            if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-9 userInfo:@{NSLocalizedDescriptionKey: @"Cloud filter download check not supported"}]);
            return;
        }
    } else if (![self isValidLocalFilterPath:path]) {
        if (completion) completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-10 userInfo:@{NSLocalizedDescriptionKey: @"Invalid filter path"}]);
        return;
    }
    
    // Dispatch to background queue to avoid blocking main thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            // Clear beauty effects before applying filter to prevent conflicts
            [self clearBeautyEffectsQuietly];
            
            
            // Try applyEffect:completion: method first
            SEL applyEffectSelector = NSSelectorFromString(@"applyEffect:completion:");
            if ([self.nosmaiSDK respondsToSelector:applyEffectSelector]) {
                void (^effectCompletion)(BOOL, NSError*) = ^(BOOL success, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                        } else {
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
                    } else {
                    }
                    if (completion) {
                        completion(result, result ? nil : [NSError errorWithDomain:@"NosmaiError" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Filter application failed"}]);
                    }
                });
                return;
            }
            
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
        }
        
    } @catch (NSException *exception) {
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
            return;
        }
        
        // Fallback method: removeAllBuiltInFilters  
        SEL removeBuiltInSelector = NSSelectorFromString(@"removeAllBuiltInFilters");
        if ([self.nosmaiSDK respondsToSelector:removeBuiltInSelector]) {
            [self.nosmaiSDK performSelector:removeBuiltInSelector];
            return;
        }
        
        
    } @catch (NSException *exception) {
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
                    NSString *lowercaseName = [filterName lowercaseString];
                    
                    // Common filter keywords (color/tone adjustments)
                    NSArray *filterKeywords = @[@"vintage", @"retro", @"warm", @"cool", @"bright", @"dark", 
                                               @"sepia", @"mono", @"contrast", @"vivid", @"soft", @"sharp",
                                               @"lomo", @"film", @"analog", @"classic", @"noir", @"bw",
                                               @"color", @"tone", @"grade", @"cinematic", @"natural",
                                               @"fade", @"trail", @"blue", @"edge", @"vibe"];
                    
                    // Check if it's likely a filter (color/tone adjustment)
                    BOOL isFilter = NO;
                    for (NSString *keyword in filterKeywords) {
                        if ([lowercaseName containsString:keyword]) {
                            isFilter = YES;
                            break;
                        }
                    }
                    
                    if (isFilter) {
                        filterType = @"filter";
                        filterCategory = @"filter";
                        sourceType = @"filter";
                    } else {
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
                
                [localFilters addObject:filterInfo];

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
                                           @"fade", @"trail", @"blue", @"edge", @"vibe"];
                
                // Check if it's likely a filter (color/tone adjustment)
                BOOL isFilter = NO;
                for (NSString *keyword in filterKeywords) {
                    if ([lowercaseName containsString:keyword]) {
                        isFilter = YES;
                        break;
                    }
                }
                
                if (isFilter) {
                    filterType = @"filter";
                    filterCategory = @"filter";
                    sourceType = @"filter";
                } else {
                    filterType = @"effect";
                    filterCategory = @"effect";
                    sourceType = @"effect";
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
            
            [localFilters addObject:filterInfo];

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

#pragma mark - Camera Controls

- (BOOL)switchCamera {
          self.isUsingFrontCamera ? @"front" : @"back",
          self.isUsingFrontCamera ? @"back" : @"front");
    
    // Initialize camera if not already done
    if (!self.captureSession) {
        [self setupCustomCamera];
        
        if (!self.captureSession) {
            return NO;
        }
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
        return NO;
    }
    
    // Get the new camera device
    AVCaptureDevicePosition newPosition = self.isUsingFrontCamera ? 
        AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    
    AVCaptureDevice *newCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                    mediaType:AVMediaTypeVideo
                                                                     position:newPosition];
    
    if (!newCamera) {
        return NO;
    }
    
    // Create new input
    NSError *error;
    AVCaptureDeviceInput *newCameraInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:&error];
    
    if (!newCameraInput) {
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
        
        // Apply mirroring for front camera
        if (connection.isVideoMirroringSupported) {
            connection.videoMirrored = (newPosition == AVCaptureDevicePositionFront) ? YES : NO;
        }
        
        [self.captureSession commitConfiguration];
        
        // Update state
        self.isUsingFrontCamera = (newPosition == AVCaptureDevicePositionFront);
        
        // Update the display layer mirroring
        if (globalPreviewView) {
            [globalPreviewView updateMirrorMode:self.isUsingFrontCamera];
        }
        
        // Notify NosmaiSDK about the camera position change if available
        if (self.nosmaiSDK) {
            SEL configureCameraSelector = NSSelectorFromString(@"configureCameraWithPosition:sessionPreset:");
            if ([self.nosmaiSDK respondsToSelector:configureCameraSelector]) {
                NSNumber *position = @(newPosition);
                NSString *preset = @"AVCaptureSessionPresetHigh";
                [self.nosmaiSDK performSelector:configureCameraSelector withObject:position withObject:preset];
            }
        }
        
              self.isUsingFrontCamera ? @"front" : @"back");
        return YES;
        
    } else {
        [self.captureSession commitConfiguration];
        return NO;
    }
}

- (void)enableMirror:(BOOL)enable {

    self.mirrorEnabled = enable;
}

- (void)enableLocalPreview:(BOOL)enable {

    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (enable) {
            // Start pushing frames to the local preview
            if (self.agoraEngine) {
                // The external video frames are already being pushed to Agora
                // The local preview should show automatically when startPreview is called

            }
        } else {

        }
    });
}

#pragma mark - Beauty Effects

- (void)applySkinSmoothing:(float)intensity {
    [self applySkinSmoothingInternal:intensity];
}

- (void)applySkinSmoothingInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applySkinSmoothing:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyFaceSlimming:(float)intensity {
    [self applyFaceSlimmingInternal:intensity];
}

- (void)applyFaceSlimmingInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyFaceSlimming:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyEyeEnlargement:(float)intensity {
    [self applyEyeEnlargementInternal:intensity];
}

- (void)applyEyeEnlargementInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyEyeEnlargement:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applySkinWhitening:(float)intensity {
    [self applySkinWhiteningInternal:intensity];
}

- (void)applySkinWhiteningInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applySkinWhitening:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyNoseSize:(float)intensity {
    [self applyNoseSizeInternal:intensity];
}

- (void)applyNoseSizeInternal:(float)intensity {
    SEL selector = NSSelectorFromString(@"applyNoseSize:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(intensity)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyBrightnessFilter:(float)brightness {
    SEL selector = NSSelectorFromString(@"applyBrightnessFilter:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(brightness)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyContrastFilter:(float)contrast {
    SEL selector = NSSelectorFromString(@"applyContrastFilter:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(contrast)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applySharpening:(float)level {
    SEL selector = NSSelectorFromString(@"applySharpening:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector withObject:@(level)];
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyRGBFilter:(float)red green:(float)green blue:(float)blue {
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
        } @catch (NSException *exception) {
        }
    } else {
    }
}

- (void)applyMakeupBlendLevel:(NSString *)filterName level:(float)level {
    SEL selector = NSSelectorFromString(@"applyMakeupBlendLevel:level:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.nosmaiSDK];
        [invocation setSelector:selector];
        [invocation setArgument:(__bridge void *)filterName atIndex:2];
        [invocation setArgument:&level atIndex:3];
        [invocation invoke];
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
    // Use the correct method name from NosmaiSDK headers: adjustHSBWithHue:saturation:brightness:
    SEL selector = NSSelectorFromString(@"adjustHSBWithHue:saturation:brightness:");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:self.nosmaiSDK];
        [invocation setSelector:selector];
        [invocation setArgument:&hue atIndex:2];
        [invocation setArgument:&saturation atIndex:3];
        [invocation setArgument:&brightness atIndex:4];
        [invocation invoke];
    }
}

- (void)resetHSBFilter {
    SEL selector = NSSelectorFromString(@"resetHSBFilter");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        [self.nosmaiSDK performSelector:selector];
    }
}

- (void)removeBuiltInFilters {
    SEL selector = NSSelectorFromString(@"removeBuiltInFilters");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            [self.nosmaiSDK performSelector:selector];
        } @catch (NSException *exception) {
        }
    } else {
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
                    if (filter[@"filterCategory"] && ![filter[@"filterCategory"] isKindOfClass:[NSNull class]]) {
                        NSString *cloudCategory = [filter[@"filterCategory"] description];
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
                                                   @"amber", @"arctic", @"azure", @"bold", @"chill"];
                        
                        // Check if it's likely a filter (color/tone adjustment)
                        BOOL isFilter = NO;
                        for (NSString *keyword in filterKeywords) {
                            if ([lowercaseName containsString:keyword]) {
                                isFilter = YES;
                                break;
                            }
                        }
                        
                        if (isFilter) {
                            filterType = @"filter";
                            filterCategory = @"filter";
                            sourceType = @"filter";
                        } else {
                            filterType = @"effect";
                            filterCategory = @"effect";
                            sourceType = @"effect";
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
            return @[];
        }
    }
    return @[];
}

- (NSDictionary *)downloadCloudFilter:(NSString *)filterId {
    // First check if already downloaded and return local path - like nosmai_flutter plugin
    SEL isDownloadedSelector = NSSelectorFromString(@"isCloudFilterDownloaded:");
    if ([self.nosmaiSDK respondsToSelector:isDownloadedSelector]) {
        BOOL isDownloaded = [[self.nosmaiSDK performSelector:isDownloadedSelector withObject:filterId] boolValue];
        if (isDownloaded) {
            // Get local path for already downloaded filter
            SEL getLocalPathSelector = NSSelectorFromString(@"getCloudFilterLocalPath:");
            if ([self.nosmaiSDK respondsToSelector:getLocalPathSelector]) {
                NSString *localPath = [self.nosmaiSDK performSelector:getLocalPathSelector withObject:filterId];
                if (localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                    return @{@"success": @YES, @"localPath": localPath, @"path": localPath, @"message": @"Already downloaded"};
                }
            }
        }
    }
    
    
    // Use the correct 3-parameter download method
    SEL downloadSelector = NSSelectorFromString(@"downloadCloudFilter:progress:completion:");
    if ([self.nosmaiSDK respondsToSelector:downloadSelector]) {
        // Since this method needs to return synchronously but the SDK method is async,
        // we'll use a semaphore to wait for completion
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSDictionary *downloadResult = nil;
        
        @try {
            // Use NSInvocation to call the 3-parameter method
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:downloadSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:downloadSelector];
            
            // Set arguments: filterId, progressBlock (nil), completion block
            [invocation setArgument:&filterId atIndex:2];
            
            id progressBlock = nil;
            [invocation setArgument:&progressBlock atIndex:3];
            
            id completionBlock = ^(BOOL success, NSString *localPath, NSError *error) {
                if (success && localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                    downloadResult = @{@"success": @YES, @"localPath": localPath, @"path": localPath};
                } else {
                    downloadResult = @{
                        @"success": @NO, 
                        @"error": error.localizedDescription ?: @"Download failed",
                        @"details": [NSString stringWithFormat:@"Filter ID: %@", filterId]
                    };
                }
                dispatch_semaphore_signal(semaphore);
            };
            [invocation setArgument:&completionBlock atIndex:4];
            
            [invocation invoke];
            
            // Wait for completion (timeout after 30 seconds)
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC);
            if (dispatch_semaphore_wait(semaphore, timeout) == 0) {
                return downloadResult ?: @{@"success": @NO, @"error": @"Download completed with no result"};
            } else {
                return @{@"success": @NO, @"error": @"Download timed out"};
            }
        } @catch (NSException *exception) {
            return @{@"success": @NO, @"error": exception.reason ?: @"Unknown error"};
        }
    }
    return @{@"success": @NO, @"error": @"Method not available"};
}

- (NSArray *)getFilters {
    SEL selector = NSSelectorFromString(@"getFilters");
    if ([self.nosmaiSDK respondsToSelector:selector]) {
        @try {
            NSArray *result = [self.nosmaiSDK performSelector:selector];
            return result ?: @[];
        } @catch (NSException *exception) {
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
        
    } @catch (NSException *exception) {
        
        // Fallback: manually reset individual beauty effects to 0
        @try {
            [self applySkinSmoothingInternal:0.0];
            [self applyFaceSlimmingInternal:0.0];
            [self applyEyeEnlargementInternal:0.0];
            [self applySkinWhiteningInternal:0.0];
            [self applyNoseSizeInternal:50.0]; // Reset to neutral nose size
        } @catch (NSException *fallbackException) {
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

- (void)sendFrameToAgora:(CVPixelBufferRef)pixelBuffer timestamp:(double)timestamp {
    if (!pixelBuffer) return;
    
    // Log frame receipt (reduced frequency to avoid spam)
    static int frameCount = 0;
    frameCount++;
    
    @try {
        BOOL result = NO;
        
        // Always push frames to custom engine for both streaming and local preview
        if (self.agoraEngine) {
            AgoraVideoFrame *videoFrame = [[AgoraVideoFrame alloc] init];
            videoFrame.format = 12; // BGRA format (same as Swift implementation)
            videoFrame.textureBuf = pixelBuffer;
            videoFrame.rotation = 0; // No rotation - handle in encoder config
            videoFrame.time = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            
            result = [self.agoraEngine pushExternalVideoFrame:videoFrame];
        }
        
        if (frameCount % 30 == 0) { // Log every 30 frames
            NSString *mode = self.isStreaming ? @"streaming & local preview" : @"local preview only";
            if (result) {

            } else {

            }
        }
        
    } @catch (NSException *exception) {

    }
}

- (BOOL)pushFrameViaIrisAPI:(CVPixelBufferRef)pixelBuffer {
    // Method placeholder - not currently used
    return NO;
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
        connection.videoMirrored = NO; // Disable mirroring at capture level
    }
    
    if ([self.captureSession canAddOutput:self.videoOutput]) {
        [self.captureSession addOutput:self.videoOutput];

    }
    
    // Setup raw camera preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.captureSession commitConfiguration];

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
        
        // Mirror input for front camera to get natural selfie processing
        BOOL mirror = self.isUsingFrontCamera;
        [invocation setArgument:&mirror atIndex:3];
        [invocation invoke];
        
        // The processed frames will be delivered through the CVPixelBufferCallback
    }
}

#pragma mark - Dealloc

- (void)dealloc {

    
    // Set flag to prevent new operations
    self.isDeallocationInProgress = YES;
    
    // Clean up Nosmai callbacks first (most critical)
    if (self.nosmaiSDK) {
        SEL setCallbackSelector = NSSelectorFromString(@"setCVPixelBufferCallback:");
        if ([self.nosmaiSDK respondsToSelector:setCallbackSelector]) {
            NSMethodSignature *signature = [self.nosmaiSDK methodSignatureForSelector:setCallbackSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:self.nosmaiSDK];
            [invocation setSelector:setCallbackSelector];
            
            id nilCallback = nil;
            [invocation setArgument:&nilCallback atIndex:2];
            [invocation invoke];
        }
        
        SEL stopSelector = NSSelectorFromString(@"stopProcessing");
        if ([self.nosmaiSDK respondsToSelector:stopSelector]) {
            [self.nosmaiSDK performSelector:stopSelector];
        }
    }
    
    // Stop camera session safely
    if (self.captureSession && self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }
    
    // Clean up layers safely on main thread
    AVCaptureVideoPreviewLayer *rawLayerRef = self.previewLayer;
    AVSampleBufferDisplayLayer *processedLayerRef = self.processedFrameDisplayLayer;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (rawLayerRef) {
            [rawLayerRef removeFromSuperlayer];
        }
        if (processedLayerRef) {
            [processedLayerRef removeFromSuperlayer];
        }
    });
    

}

#pragma mark - Cloud Filter Helpers

- (BOOL)isCloudFilterById:(NSString *)identifier {
    if (!identifier || identifier.length == 0) return NO;
    
    
    // Check if it's a local file path first
    if ([identifier hasPrefix:@"/"] || [identifier hasSuffix:@".nosmai"]) {
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
                        return YES;
                    }
                }
            }
        }
    }
    
    // Fallback pattern matching for cloud filter IDs
    if ([identifier length] < 100 && ![identifier containsString:@"/"] && 
        ([identifier containsString:@"_"] || [identifier rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound)) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isValidLocalFilterPath:(NSString *)path {
    if (!path || path.length == 0) return NO;
    
    // Check if file exists and has correct extension
    BOOL isValidPath = [[NSFileManager defaultManager] fileExistsAtPath:path] && [path hasSuffix:@".nosmai"];
    
    if (!isValidPath) {
    }
    
    return isValidPath;
}

- (void)downloadCloudFilterAndApply:(NSString *)filterId completion:(void(^)(BOOL success, NSError *error))completion {
    
    // Skip complex download and just try to get the local path directly
    // If the filter shows as downloaded but path is empty, it might be a caching issue
    SEL getLocalPathSelector = NSSelectorFromString(@"getCloudFilterLocalPath:");
    if ([self.nosmaiSDK respondsToSelector:getLocalPathSelector]) {
        NSString *localPath = [self.nosmaiSDK performSelector:getLocalPathSelector withObject:filterId];
        if (localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            [self applyLocalFilterAtPath:localPath completion:completion];
            return;
        } else {
        }
    }
    
    // Use the correct 3-parameter download method
    SEL downloadSelector = NSSelectorFromString(@"downloadCloudFilter:progress:completion:");
    if ([self.nosmaiSDK respondsToSelector:downloadSelector]) {
        
        id downloadCompletion = [^(BOOL success, NSString *localPath, NSError *error) {
            if (success && localPath && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
                [self applyLocalFilterAtPath:localPath completion:completion];
            } else {
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
    
    if (completion) {
        completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"Cloud filter download not supported"}]);
    }
}

// Separate method for applying local filters to avoid recursion
- (void)applyLocalFilterAtPath:(NSString *)localPath completion:(void(^)(BOOL success, NSError *error))completion {
    if (!localPath || ![[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-7 userInfo:@{NSLocalizedDescriptionKey: @"Local filter file not found"}]);
        }
        return;
    }
    
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            // Clear beauty effects first for clean filter application
            [self clearBeautyEffectsQuietly];
            
            // Use the correct NosmaiSDK method for applying effects
            SEL applyEffectSelector = NSSelectorFromString(@"applyEffect:completion:");
            if ([self.nosmaiSDK respondsToSelector:applyEffectSelector]) {
                
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
                
                BOOL result = [[self.nosmaiSDK performSelector:applyEffectSyncSelector withObject:localPath] boolValue];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(result, result ? nil : [NSError errorWithDomain:@"NosmaiError" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Filter application failed"}]);
                    }
                });
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"No suitable method found for applying filter"}]);
                }
            });
            
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, [NSError errorWithDomain:@"NosmaiError" code:-3 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Filter application failed"}]);
                }
            });
        }
    });
}

@end
