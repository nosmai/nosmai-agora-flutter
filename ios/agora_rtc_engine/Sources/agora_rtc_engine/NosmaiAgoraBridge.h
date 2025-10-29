//
//  NosmaiAgoraBridge.h
//  Agora Flutter SDK - Nosmai Integration
//
//  Created by Agora Team
//  Copyright © 2024. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AgoraRtcKit/AgoraRtcEngineKit.h>
#import <AVFoundation/AVFoundation.h>

#if __has_include(<nosmai/Nosmai.h>)
#import <nosmai/Nosmai.h>
#define HAS_NOSMAI_FRAMEWORK 1
#else
#define HAS_NOSMAI_FRAMEWORK 0
#endif

NS_ASSUME_NONNULL_BEGIN

@interface NosmaiAgoraBridge : NSObject
#if HAS_NOSMAI_FRAMEWORK
<NosmaiCameraDelegate>
#endif

#if HAS_NOSMAI_FRAMEWORK
@property (nonatomic, strong, readonly, nullable) NosmaiSDK *nosmaiSDK;
#endif

// Singleton instance
+ (instancetype)sharedInstance;

// Preview view management for NosmaiSDK
- (void)setLocalPreviewView:(UIView *)view;
- (UIView *)getLocalPreviewView;

#pragma mark - Initialization
- (BOOL)initNosmaiWithLicense:(NSString *)licenseKey;
- (BOOL)initAgoraWithAppId:(NSString *)appId;
- (void)releaseAgora;

#pragma mark - Streaming Control
- (BOOL)startCustomCameraWithAppId:(NSString *)appId
                             token:(NSString *)token
                         channelId:(NSString *)channelId
                            userId:(NSUInteger)userId
               startCameraImmediately:(BOOL)startCameraImmediately;
- (BOOL)stopCustomCamera;
- (void)teardownStreaming;

#pragma mark - Agora Controls
- (BOOL)enableVideo;
- (BOOL)enableLocalVideo:(BOOL)enabled;
- (BOOL)startPreview;
- (BOOL)stopPreview;
- (BOOL)setClientRole:(AgoraClientRole)role;
- (BOOL)joinChannelWithToken:(NSString *)token
                   channelId:(NSString *)channelId
                      userId:(NSUInteger)userId;
- (BOOL)leaveChannel;

#pragma mark - Beauty Filters
- (BOOL)applyBrightness:(float)brightness;
- (BOOL)applySkinSmoothing:(float)level;
- (BOOL)applySkinWhitening:(float)level;
- (BOOL)applyFaceSlimming:(float)level;
- (BOOL)applyEyeEnlargement:(float)level;
- (BOOL)applyNoseSize:(float)level;
- (BOOL)applyContrast:(float)contrast;
- (BOOL)applyHue:(float)hue;
- (BOOL)applyRGBWithRed:(float)red green:(float)green blue:(float)blue;
- (BOOL)applyLipstick:(float)intensity;
- (BOOL)applyBlusher:(float)intensity;
- (BOOL)applyExposure:(float)exposure;
- (BOOL)applySaturation:(float)saturation;
- (BOOL)applySharpening:(float)sharpening;
- (BOOL)applyWhiteBalanceWithTemperature:(float)temperatureK tint:(float)tint;
- (BOOL)enableGrayscale:(BOOL)enabled;

#pragma mark - Filter Management
- (BOOL)applyEffect:(NSString *)effectPath;
- (void)applyEffect:(NSString *)effectPath completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (BOOL)removeAllFilters;
- (NSDictionary<NSString *, NSNumber *> *)getCurrentFilterStates;
- (BOOL)hasActiveFilters;
- (BOOL)applyMakeupBlendLevel:(NSString *)filterName level:(float)level;

#pragma mark - Status and Info
- (NSString *)getFlutterEngineInfo;

#pragma mark - Camera Support
- (BOOL)startStreaming;
- (BOOL)stopStreaming;
- (BOOL)startProcessing;
- (BOOL)stopProcessing;
- (BOOL)switchCamera;
- (BOOL)setFlashMode:(NSString *)flashMode;
- (BOOL)setTorchMode:(NSString *)torchMode;

#pragma mark - Streaming Camera Controls
- (BOOL)flipCamera;
- (BOOL)muteMicrophone:(BOOL)muted;
- (BOOL)toggleMirror:(BOOL)enabled;

#pragma mark - Missing Nosmai Camera Methods
- (BOOL)cleanup;
- (void)startRecordingWithCompletion:(void (^)(BOOL success))completion;
- (void)stopRecordingWithCompletion:(void (^)(NSDictionary<NSString *, id> *result))completion;
- (void)capturePhotoWithCompletion:(void (^)(NSDictionary<NSString *, id> *result))completion;
- (void)saveImageToGalleryWithData:(NSData *)imageData name:(NSString *)name completion:(void (^)(NSDictionary<NSString *, id> *result))completion;
- (void)saveVideoToGalleryWithPath:(NSString *)videoPath name:(NSString *)name completion:(void (^)(NSDictionary<NSString *, id> *result))completion;
- (BOOL)adjustHSBWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness;
- (BOOL)resetHSBFilter;
- (BOOL)isBeautyFilterEnabled;
- (BOOL)hasFlash;
- (BOOL)hasTorch;
- (NSString *)getFlashMode;
- (NSString *)getTorchMode;
- (BOOL)configureCameraWithPosition:(NSString *)position sessionPreset:(NSString *)sessionPreset;
// - (BOOL)reinitializePreview;
- (BOOL)detachCameraView;

@end

NS_ASSUME_NONNULL_END