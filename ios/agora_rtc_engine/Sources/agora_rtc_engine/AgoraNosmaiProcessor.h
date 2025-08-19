//
//  AgoraNosmaiProcessor.h
//  agora_rtc_engine
//
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@class AgoraRtcEngineKit;

NS_ASSUME_NONNULL_BEGIN

@protocol AgoraNosmaiFrameDelegate <NSObject>
@optional
- (void)onNosmaiProcessedFrame:(CVPixelBufferRef)pixelBuffer timestamp:(double)timestamp;
@end

@interface AgoraNosmaiProcessor : NSObject

// Public property to store Agora engine pointer from Flutter
@property(nonatomic, assign) void *agoraEnginePtr;

// Initialization
- (instancetype)initWithApiEngine:(void *)apiEngine licenseKey:(NSString *)licenseKey;
- (instancetype)initWithAgoraEngine:(AgoraRtcEngineKit *)engine licenseKey:(NSString *)licenseKey;

// Method to set AgoraRtcEngineKit instance after initialization
- (void)setAgoraEngineInstance:(AgoraRtcEngineKit *)engine;

// Method to create custom AgoraRtcEngineKit instance for frame pushing
- (void)createCustomAgoraEngine:(NSString *)appId;

// Method to get the custom engine for Flutter integration
- (AgoraRtcEngineKit *)getCustomEngine;

// Core processing controls
- (void)startProcessing;
- (void)stopProcessing;
- (void)startLiveStreaming;
- (void)stopLiveStreaming;

// Preview management
- (void)setPreviewView:(UIView *)view;
- (void)updatePreviewBounds;
- (UIView *)createNativePreviewView;
- (void)attachPreviewToView:(UIView *)view;

// Filter controls
- (void)applyFilterWithPath:(NSString *)path completion:(void (^_Nullable)(BOOL success, NSError *_Nullable error))completion;
- (void)clearFilter;
- (nullable NSDictionary *)getAvailableFilters;
- (NSArray *)getLocalFilters;

// Camera controls
- (BOOL)switchCamera;
- (void)enableMirror:(BOOL)enable;
- (void)enableLocalPreview:(BOOL)enable;

// Beauty effects
- (void)applySkinSmoothing:(float)intensity;
- (void)applyFaceSlimming:(float)intensity;
- (void)applyEyeEnlargement:(float)intensity;
- (void)applySkinWhitening:(float)intensity;
- (void)applyNoseSize:(float)intensity;
- (void)applyBrightnessFilter:(float)brightness;
- (void)applyContrastFilter:(float)contrast;
- (void)applySharpening:(float)level;
- (void)applyRGBFilter:(float)red green:(float)green blue:(float)blue;
- (void)applyMakeupBlendLevel:(NSString *)filterName level:(float)level;
- (void)applyGrayscaleFilter;
- (void)applyHue:(float)hueAngle;
- (void)applyWhiteBalance:(float)temperature tint:(float)tint;
- (void)adjustHSB:(float)hue saturation:(float)saturation brightness:(float)brightness;
- (void)resetHSBFilter;
- (void)removeBuiltInFilters;
- (void)clearBeautyEffects;

// Filter management
- (NSArray *)getCloudFilters;
- (void)downloadCloudFilter:(NSString *)filterId
                 completion:(void (^)(NSDictionary *result))completionBlock;

- (NSArray *)getFilters;
- (void)clearFilterCache;

// Status methods
- (BOOL)isBeautyFilterEnabled;
- (BOOL)isCloudFilterEnabled;

// Processing state
- (BOOL)isProcessing;
- (BOOL)isStreaming;

// Performance metrics
- (nullable NSDictionary *)getProcessingMetrics;

// Frame delegate
@property(nonatomic, weak) id<AgoraNosmaiFrameDelegate> frameDelegate;

// Global preview view methods
+ (UIView *)createGlobalPreviewView;
+ (void)destroyGlobalPreviewView;

// Platform view lifecycle management (safe cleanup without disturbing existing flow)
- (void)notifyPlatformViewCreated:(int64_t)viewId;
- (void)notifyPlatformViewDestroyed:(int64_t)viewId;

// Callback management (ensures proper setup for shared instances)
- (void)ensureCallbackSetup;

// Camera resource management (to turn off camera light properly)
- (void)releaseAllCameraResources;

// Processing restart after camera light management
- (void)restartProcessingIfStoppedForCameraLight;

@end

NS_ASSUME_NONNULL_END