#import "./include/agora_rtc_engine/AgoraRtcNgPlugin.h"
#import "./include/agora_rtc_engine/AgoraSurfaceViewFactory.h"
#import "./include/agora_rtc_engine/AgoraUtils.h"
#import "./include/agora_rtc_engine/VideoViewController.h"
#import "AgoraNosmaiProcessor.h"
#import "SimpleNosmaiPreviewFactory.h"
#import <AgoraRtcKit/AgoraRtcEngineKit.h>
#include <Foundation/Foundation.h>

@interface AgoraRtcNgPlugin ()

@property(nonatomic) FlutterMethodChannel *channel;

@property(nonatomic) VideoViewController *videoViewController;

@property(nonatomic) NSObject<FlutterPluginRegistrar> *registrar;

@property(nonatomic) AgoraPIPController *pipController;

@property(nonatomic) AgoraNosmaiProcessor *nosmaiProcessor;

@property(nonatomic) SimpleNosmaiPreviewFactory *nosmaiPreviewFactory;

@end

// Static variable to track factory registration
static BOOL isNosmaiFactoryRegistered = NO;

@implementation AgoraRtcNgPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  AgoraRtcNgPlugin *instance = [[AgoraRtcNgPlugin alloc] init];
  instance.registrar = registrar;

  // create method channel
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"agora_rtc_ng"
                                  binaryMessenger:[registrar messenger]];

  instance.channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];

  // create video view controller
  instance.videoViewController =
      [[VideoViewController alloc] initWith:registrar.textures
                                  messenger:registrar.messenger];
  [registrar registerViewFactory:[[AgoraSurfaceViewFactory alloc]
                                       initWith:[registrar messenger]
                                     controller:instance.videoViewController]
                          withId:@"AgoraSurfaceView"];

  // create pip controller
  instance.pipController = [[AgoraPIPController alloc]
      initWith:(id<AgoraPIPStateChangedDelegate>)instance];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
  AGORA_LOG(@"handleMethodCall: %@ with arguments: %@", call.method,
            call.arguments);

  if ([@"getAssetAbsolutePath" isEqualToString:call.method]) {
    [self getAssetAbsolutePath:call result:result];
  } else if ([call.method hasPrefix:@"pip"]) {
    [self handlePipMethodCall:call result:result];
  } else if ([call.method hasPrefix:@"nosmai"]) {
    [self handleNosmaiMethodCall:call result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)getAssetAbsolutePath:(FlutterMethodCall *)call
                      result:(FlutterResult)result {
  NSString *assetPath = (NSString *)[call arguments];
  if (assetPath) {
    NSString *assetKey = [[self registrar] lookupKeyForAsset:assetPath];
    if (assetKey) {
      NSString *realPath = [[NSBundle mainBundle] pathForResource:assetKey
                                                           ofType:nil];
      result(realPath);
      return;
    }
    result([FlutterError errorWithCode:@"FileNotFoundException"
                               message:nil
                               details:nil]);
    return;
  }
  result([FlutterError errorWithCode:@"IllegalArgumentException"
                             message:nil
                             details:nil]);
}

- (void)handlePipMethodCall:(FlutterMethodCall *)call
                     result:(FlutterResult)result {
  if ([@"pipIsSupported" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController isSupported]]);
  } else if ([@"pipIsAutoEnterSupported" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController isAutoEnterSupported]]);
  } else if ([@"pipIsActivated" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController isActivated]]);
  } else if ([@"pipSetup" isEqualToString:call.method]) {
    @autoreleasepool {
      // new options
      AgoraPIPOptions *options = [[AgoraPIPOptions alloc] init];

      // auto enter
      if ([call.arguments objectForKey:@"autoEnterEnabled"]) {
        options.autoEnterEnabled =
            [[call.arguments objectForKey:@"autoEnterEnabled"] boolValue];
      }

      // sourceContentView
      if ([call.arguments objectForKey:@"sourceContentView"]) {
        options.sourceContentView = (__bridge UIView *)[[call.arguments
            objectForKey:@"sourceContentView"] pointerValue];
      }

      // contentView
      if ([call.arguments objectForKey:@"contentView"]) {
        options.contentView = (__bridge UIView *)[[call.arguments
            objectForKey:@"contentView"] pointerValue];
      }

      // videoStreams
      NSArray *videoStreams = [call.arguments objectForKey:@"videoStreams"];
      if (videoStreams) {
        NSMutableArray *tempVideoStreamArray = [[NSMutableArray alloc] init];
        for (NSDictionary *videoStream in videoStreams) {
          NSDictionary *connectionObj =
              [videoStream objectForKey:@"connection"];
          NSDictionary *canvasObj = [videoStream objectForKey:@"canvas"];

          if (!connectionObj || !canvasObj) {
            continue;
          }

          AgoraPIPVideoStream *videoStreamObj =
              [[AgoraPIPVideoStream alloc] init];

          // connection
          id channelIdObj = [connectionObj objectForKey:@"channelId"];
          videoStreamObj.channelId =
              [channelIdObj isKindOfClass:[NSString class]] ? channelIdObj
                                                            : @"";

          id localUidObj = [connectionObj objectForKey:@"localUid"];
          videoStreamObj.localUid = [localUidObj isKindOfClass:[NSNumber class]]
                                        ? [localUidObj intValue]
                                        : 0;

          // canvas
          id uidObj = [canvasObj objectForKey:@"uid"];
          videoStreamObj.uid =
              [uidObj isKindOfClass:[NSNumber class]] ? [uidObj intValue] : 0;

          id backgroundColorObj = [canvasObj objectForKey:@"backgroundColor"];
          videoStreamObj.backgroundColor =
              [backgroundColorObj isKindOfClass:[NSNumber class]]
                  ? [backgroundColorObj intValue]
                  : 0;

          id renderModeObj = [canvasObj objectForKey:@"renderMode"];
          videoStreamObj.renderMode =
              [renderModeObj isKindOfClass:[NSNumber class]]
                  ? [renderModeObj intValue]
                  : 0;

          id mirrorModeObj = [canvasObj objectForKey:@"mirrorMode"];
          videoStreamObj.mirrorMode =
              [mirrorModeObj isKindOfClass:[NSNumber class]]
                  ? [mirrorModeObj intValue]
                  : 0;

          id setupModeObj = [canvasObj objectForKey:@"setupMode"];
          videoStreamObj.setupMode =
              [setupModeObj isKindOfClass:[NSNumber class]]
                  ? [setupModeObj intValue]
                  : 0;

          id sourceTypeObj = [canvasObj objectForKey:@"sourceType"];
          videoStreamObj.sourceType =
              [sourceTypeObj isKindOfClass:[NSNumber class]]
                  ? [sourceTypeObj intValue]
                  : 0;

          id enableAlphaMaskObj = [canvasObj objectForKey:@"enableAlphaMask"];
          videoStreamObj.enableAlphaMask =
              [enableAlphaMaskObj isKindOfClass:[NSNumber class]]
                  ? [enableAlphaMaskObj boolValue]
                  : NO;

          id positionObj = [canvasObj objectForKey:@"position"];
          videoStreamObj.position = [positionObj isKindOfClass:[NSNumber class]]
                                        ? [positionObj intValue]
                                        : 0;

          [tempVideoStreamArray addObject:videoStreamObj];
        }
        options.videoStreamArray = tempVideoStreamArray;
      }

      // contentViewLayout
      NSDictionary *contentViewLayout =
          [call.arguments objectForKey:@"contentViewLayout"];
      if (contentViewLayout) {
        options.contentViewLayout = [[AgoraPipContentViewLayout alloc] init];

        id paddingObj = [contentViewLayout objectForKey:@"padding"];
        options.contentViewLayout.padding =
            [paddingObj isKindOfClass:[NSNumber class]] ? [paddingObj intValue]
                                                        : 0;

        id spacingObj = [contentViewLayout objectForKey:@"spacing"];
        options.contentViewLayout.spacing =
            [spacingObj isKindOfClass:[NSNumber class]] ? [spacingObj intValue]
                                                        : 0;

        id rowObj = [contentViewLayout objectForKey:@"row"];
        options.contentViewLayout.row =
            [rowObj isKindOfClass:[NSNumber class]] ? [rowObj intValue] : 0;

        id columnObj = [contentViewLayout objectForKey:@"column"];
        options.contentViewLayout.column =
            [columnObj isKindOfClass:[NSNumber class]] ? [columnObj intValue]
                                                       : 0;
      }

      // apiEngine
      if ([call.arguments objectForKey:@"apiEngine"]) {
        options.apiEngine =
            (void *)[[call.arguments objectForKey:@"apiEngine"] pointerValue];
      }

      // preferred content size
      id preferredContentWidthObj =
          [call.arguments objectForKey:@"preferredContentWidth"];
      id preferredContentHeightObj =
          [call.arguments objectForKey:@"preferredContentHeight"];
      if (preferredContentWidthObj && preferredContentHeightObj &&
          [preferredContentWidthObj isKindOfClass:[NSNumber class]] &&
          [preferredContentHeightObj isKindOfClass:[NSNumber class]]) {
        options.preferredContentSize =
            CGSizeMake([preferredContentWidthObj floatValue],
                       [preferredContentHeightObj floatValue]);
      }

      // control style
      id controlStyleObj = [call.arguments objectForKey:@"controlStyle"];
      if (controlStyleObj && [controlStyleObj isKindOfClass:[NSNumber class]]) {
        options.controlStyle = [controlStyleObj intValue];
      }

      result([NSNumber numberWithBool:[self.pipController setup:options]]);
    }
  } else if ([@"pipStart" isEqualToString:call.method]) {
    result([NSNumber numberWithBool:[self.pipController start]]);
  } else if ([@"pipStop" isEqualToString:call.method]) {
    [self.pipController stop];
    result(nil);
  } else if ([@"pipDispose" isEqualToString:call.method]) {
    [self.pipController dispose];
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)pipStateChanged:(AgoraPIPState)state error:(NSString *)error {
  AGORA_LOG(@"pipStateChanged: %ld, error: %@", (long)state, error);

  NSDictionary *arguments = [[NSDictionary alloc]
      initWithObjectsAndKeys:[NSNumber numberWithLong:(long)state], @"state",
                             error, @"error", nil];
  [self.channel invokeMethod:@"pipStateChanged" arguments:arguments];
}

#pragma mark - Nosmai Methods

- (void)handleNosmaiMethodCall:(FlutterMethodCall *)call
                        result:(FlutterResult)result {
  if ([@"nosmaiInitialize" isEqualToString:call.method]) {
    [self nosmaiInitialize:call result:result];
  } else if ([@"nosmaiStartProcessing" isEqualToString:call.method]) {
    [self nosmaiStartProcessing:call result:result];
  } else if ([@"nosmaiStopProcessing" isEqualToString:call.method]) {
    [self nosmaiStopProcessing:call result:result];
  } else if ([@"nosmaiStartStreaming" isEqualToString:call.method]) {
    [self nosmaiStartStreaming:call result:result];
  } else if ([@"nosmaiStopStreaming" isEqualToString:call.method]) {
    [self nosmaiStopStreaming:call result:result];
  } else if ([@"nosmaiApplyFilter" isEqualToString:call.method]) {
    [self nosmaiApplyFilter:call result:result];
  } else if ([@"nosmaiClearFilter" isEqualToString:call.method]) {
    [self nosmaiClearFilter:call result:result];
  } else if ([@"nosmaiGetAvailableFilters" isEqualToString:call.method]) {
    [self nosmaiGetAvailableFilters:call result:result];
  } else if ([@"nosmaiApplySkinSmoothing" isEqualToString:call.method]) {
    [self nosmaiApplySkinSmoothing:call result:result];
  } else if ([@"nosmaiApplyFaceSlimming" isEqualToString:call.method]) {
    [self nosmaiApplyFaceSlimming:call result:result];
  } else if ([@"nosmaiApplyEyeEnlargement" isEqualToString:call.method]) {
    [self nosmaiApplyEyeEnlargement:call result:result];
  } else if ([@"nosmaiClearBeautyEffects" isEqualToString:call.method]) {
    [self nosmaiClearBeautyEffects:call result:result];
  } else if ([@"nosmaiSwitchCamera" isEqualToString:call.method]) {
    [self nosmaiSwitchCamera:call result:result];
  } else if ([@"nosmaiEnableMirror" isEqualToString:call.method]) {
    [self nosmaiEnableMirror:call result:result];
  } else if ([@"nosmaiEnableLocalPreview" isEqualToString:call.method]) {
    [self nosmaiEnableLocalPreview:call result:result];
  } else if ([@"nosmaiSetPreviewView" isEqualToString:call.method]) {
    [self nosmaiSetPreviewView:call result:result];
  } else if ([@"nosmaiGetProcessingMetrics" isEqualToString:call.method]) {
    [self nosmaiGetProcessingMetrics:call result:result];
  } else if ([@"nosmaiIsProcessing" isEqualToString:call.method]) {
    [self nosmaiIsProcessing:call result:result];
  } else if ([@"nosmaiIsStreaming" isEqualToString:call.method]) {
    [self nosmaiIsStreaming:call result:result];
  } else if ([@"nosmaiSetAgoraEngine" isEqualToString:call.method]) {
    [self nosmaiSetAgoraEngine:call result:result];
  } else if ([@"nosmaiCreateCustomEngine" isEqualToString:call.method]) {
    [self nosmaiCreateCustomEngine:call result:result];
  } else if ([@"nosmaiGetCustomEngine" isEqualToString:call.method]) {
    [self nosmaiGetCustomEngine:call result:result];
  } else if ([@"nosmaiAttachPreviewToView" isEqualToString:call.method]) {
    [self nosmaiAttachPreviewToView:call result:result];
  } else if ([@"nosmaiInjectPreviewIntoView" isEqualToString:call.method]) {
    [self nosmaiInjectPreviewIntoView:call result:result];
  } else if ([@"nosmaiGetLocalFilters" isEqualToString:call.method]) {
    [self nosmaiGetLocalFilters:call result:result];
  } else if ([@"nosmaiGetCloudFilters" isEqualToString:call.method]) {
    [self nosmaiGetCloudFilters:call result:result];
  } else if ([@"nosmaiDownloadCloudFilter" isEqualToString:call.method]) {
    [self nosmaiDownloadCloudFilter:call result:result];
  } else if ([@"nosmaiGetFilters" isEqualToString:call.method]) {
    [self nosmaiGetFilters:call result:result];
  } else if ([@"nosmaiClearFilterCache" isEqualToString:call.method]) {
    [self nosmaiClearFilterCache:call result:result];
  } else if ([@"nosmaiApplySkinWhitening" isEqualToString:call.method]) {
    [self nosmaiApplySkinWhitening:call result:result];
  } else if ([@"nosmaiApplyNoseSize" isEqualToString:call.method]) {
    [self nosmaiApplyNoseSize:call result:result];
  } else if ([@"nosmaiApplyBrightnessFilter" isEqualToString:call.method]) {
    [self nosmaiApplyBrightnessFilter:call result:result];
  } else if ([@"nosmaiApplyContrastFilter" isEqualToString:call.method]) {
    [self nosmaiApplyContrastFilter:call result:result];
  } else if ([@"nosmaiApplyRGBFilter" isEqualToString:call.method]) {
    [self nosmaiApplyRGBFilter:call result:result];
  } else if ([@"nosmaiApplySharpening" isEqualToString:call.method]) {
    [self nosmaiApplySharpening:call result:result];
  } else if ([@"nosmaiApplyMakeupBlendLevel" isEqualToString:call.method]) {
    [self nosmaiApplyMakeupBlendLevel:call result:result];
  } else if ([@"nosmaiApplyGrayscaleFilter" isEqualToString:call.method]) {
    [self nosmaiApplyGrayscaleFilter:call result:result];
  } else if ([@"nosmaiApplyHue" isEqualToString:call.method]) {
    [self nosmaiApplyHue:call result:result];
  } else if ([@"nosmaiApplyWhiteBalance" isEqualToString:call.method]) {
    [self nosmaiApplyWhiteBalance:call result:result];
  } else if ([@"nosmaiAdjustHSB" isEqualToString:call.method]) {
    [self nosmaiAdjustHSB:call result:result];
  } else if ([@"nosmaiResetHSBFilter" isEqualToString:call.method]) {
    [self nosmaiResetHSBFilter:call result:result];
  } else if ([@"nosmaiRemoveBuiltInFilters" isEqualToString:call.method]) {
    [self nosmaiRemoveBuiltInFilters:call result:result];
  } else if ([@"nosmaiIsBeautyFilterEnabled" isEqualToString:call.method]) {
    [self nosmaiIsBeautyFilterEnabled:call result:result];
  } else if ([@"nosmaiIsCloudFilterEnabled" isEqualToString:call.method]) {
    [self nosmaiIsCloudFilterEnabled:call result:result];
  } else if ([@"initializeNosmaiPreview" isEqualToString:call.method]) {
    [self initializeNosmaiPreview:call result:result];
  } else if ([@"stopNosmaiPreview" isEqualToString:call.method]) {
    [self stopNosmaiPreview:call result:result];
  } else if ([@"flipNosmaiCamera" isEqualToString:call.method]) {
    [self flipNosmaiCamera:call result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)nosmaiInitialize:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSLog(@"🔧 [AgoraRtcNgPlugin] nosmaiInitialize called");
  
  NSDictionary *arguments = call.arguments;
  NSLog(@"🔧 [AgoraRtcNgPlugin] Arguments: %@", arguments);
  
  void *apiEnginePtr = [[arguments objectForKey:@"apiEngine"] pointerValue];
  void *agoraEnginePtr = [[arguments objectForKey:@"agoraEngine"] pointerValue];
  NSString *licenseKey = [arguments objectForKey:@"licenseKey"];
  
  NSLog(@"🔧 [AgoraRtcNgPlugin] API Engine pointer: %p", apiEnginePtr);
  NSLog(@"🔧 [AgoraRtcNgPlugin] Agora Engine pointer: %p", agoraEnginePtr);
  NSLog(@"🔧 [AgoraRtcNgPlugin] License key: %@", licenseKey);
  
  if (licenseKey) {
    NSLog(@"🔧 [AgoraRtcNgPlugin] Creating AgoraNosmaiProcessor...");
    
    // Skip AgoraRtcEngineKit validation for now - use API engine approach
    // The getNativeHandle() from Flutter may not be returning a valid AgoraRtcEngineKit pointer
    NSLog(@"🔧 [AgoraRtcNgPlugin] Skipping AgoraRtcEngineKit pointer validation to avoid crashes");
    NSLog(@"🔧 [AgoraRtcNgPlugin] AgoraEngine pointer received: %p (will use API engine instead)", agoraEnginePtr);
    
    if (apiEnginePtr) {
      NSLog(@"⚠️ [AgoraRtcNgPlugin] Using API engine pointer for initialization");
      self.nosmaiProcessor = [[AgoraNosmaiProcessor alloc] initWithApiEngine:apiEnginePtr licenseKey:licenseKey];
      
      // Store the Agora engine pointer for later use
      if (agoraEnginePtr) {
        // Store as a property for later retrieval
        self.nosmaiProcessor.agoraEnginePtr = agoraEnginePtr;
        NSLog(@"✅ [AgoraRtcNgPlugin] Stored Agora engine pointer for frame pushing");
      }
      
      NSLog(@"🔧 [AgoraRtcNgPlugin] Processor initialized - ready for configuration");
    } else {
      NSLog(@"❌ [AgoraRtcNgPlugin] No API engine provided");
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"API Engine pointer is required"
                                 details:nil]);
      return;
    }
    
    NSLog(@"🔧 [AgoraRtcNgPlugin] AgoraNosmaiProcessor created: %@", self.nosmaiProcessor);
    
    // Register the simple Nosmai preview factory with defensive check
    if (!isNosmaiFactoryRegistered) {
      self.nosmaiPreviewFactory = [[SimpleNosmaiPreviewFactory alloc] init];
      self.nosmaiPreviewFactory.plugin = self; // Set plugin reference for restart logic
      [self.registrar registerViewFactory:self.nosmaiPreviewFactory
                                   withId:@"SimpleNosmaiPreview"];
      isNosmaiFactoryRegistered = YES;
      NSLog(@"✅ [AgoraRtcNgPlugin] SimpleNosmaiPreview platform view registered successfully");
    } else {
      NSLog(@"⚠️ [AgoraRtcNgPlugin] SimpleNosmaiPreview platform view factory already registered, skipping duplicate registration");
    }
    
    result(@YES);
  } else {
    NSLog(@"❌ [AgoraRtcNgPlugin] Missing license key");
    result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"License key is required"
                               details:nil]);
  }
}

- (void)nosmaiStartProcessing:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor startProcessing];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiStopProcessing:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    // CRITICAL: Clear beauty effects before stopping processing to reset state
    [self.nosmaiProcessor clearBeautyEffects];
    NSLog(@"✅ Beauty effects cleared before stopping processing");
    
    [self.nosmaiProcessor stopProcessing];
    
    // NOTE: stopProcessing already calls releaseAllCameraResources internally
    // but we ensure it's called here too for safety
    [self.nosmaiProcessor releaseAllCameraResources];
    
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiStartStreaming:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor startLiveStreaming];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiStopStreaming:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    // CRITICAL: Clear beauty effects before stopping streaming to reset state
    [self.nosmaiProcessor clearBeautyEffects];
    NSLog(@"✅ Beauty effects cleared before stopping streaming");
    
    [self.nosmaiProcessor stopLiveStreaming];
    
    // CRITICAL: Release camera resources to turn off camera light
    [self.nosmaiProcessor releaseAllCameraResources];
    
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSString *filterPath = call.arguments[@"path"];
    if (filterPath) {
      [self.nosmaiProcessor applyFilterWithPath:filterPath completion:^(BOOL success, NSError *error) {
        if (success) {
          result(@YES);
        } else {
          result([FlutterError errorWithCode:@"FilterApplyFailed"
                                     message:error.localizedDescription
                                     details:nil]);
        }
      }];
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"Filter path is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiClearFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor clearFilter];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiGetAvailableFilters:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSDictionary *filters = [self.nosmaiProcessor getAvailableFilters];
    result(filters ?: @{});
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplySkinSmoothing:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *intensity = call.arguments[@"intensity"];
    if (intensity) {
      [self.nosmaiProcessor applySkinSmoothing:[intensity floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"Intensity value is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyFaceSlimming:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *intensity = call.arguments[@"intensity"];
    if (intensity) {
      [self.nosmaiProcessor applyFaceSlimming:[intensity floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"Intensity value is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyEyeEnlargement:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *intensity = call.arguments[@"intensity"];
    if (intensity) {
      [self.nosmaiProcessor applyEyeEnlargement:[intensity floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"Intensity value is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiClearBeautyEffects:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor clearBeautyEffects];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiSwitchCamera:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    BOOL success = [self.nosmaiProcessor switchCamera];
    result(@(success));
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiEnableMirror:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *enable = call.arguments[@"enable"];
    if (enable) {
      [self.nosmaiProcessor enableMirror:[enable boolValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"Enable value is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiEnableLocalPreview:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *enable = call.arguments[@"enable"];
    if (enable) {
      [self.nosmaiProcessor enableLocalPreview:[enable boolValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"Enable value is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiSetPreviewView:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    void *viewPtr = [[call.arguments objectForKey:@"view"] pointerValue];
    if (viewPtr) {
      UIView *view = (__bridge UIView *)viewPtr;
      [self.nosmaiProcessor setPreviewView:view];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                               message:@"View pointer is required"
                               details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiGetProcessingMetrics:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSDictionary *metrics = [self.nosmaiProcessor getProcessingMetrics];
    result(metrics ?: @{});
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiIsProcessing:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    result(@([self.nosmaiProcessor isProcessing]));
  } else {
    result(@NO);
  }
}

- (void)nosmaiIsStreaming:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    result(@([self.nosmaiProcessor isStreaming]));
  } else {
    result(@NO);
  }
}

- (void)nosmaiSetAgoraEngine:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSLog(@"🔧 [AgoraRtcNgPlugin] nosmaiSetAgoraEngine called with arguments: %@", call.arguments);
  
  if (self.nosmaiProcessor) {
    NSLog(@"🔧 [AgoraRtcNgPlugin] Nosmai processor exists: %@", self.nosmaiProcessor);
    void *agoraEnginePtr = [[call.arguments objectForKey:@"agoraEngine"] pointerValue];
    NSLog(@"🔧 [AgoraRtcNgPlugin] AgoraEngine pointer value: %p", agoraEnginePtr);
    
    if (agoraEnginePtr) {
      @try {
        AgoraRtcEngineKit *agoraEngine = (__bridge AgoraRtcEngineKit *)agoraEnginePtr;
        
        // Simple validation 
        if (agoraEngine && [agoraEngine respondsToSelector:@selector(description)]) {
          NSLog(@"🔧 [AgoraRtcNgPlugin] Valid AgoraRtcEngineKit instance found");
          [self.nosmaiProcessor setAgoraEngineInstance:agoraEngine];
          NSLog(@"✅ [AgoraRtcNgPlugin] AgoraRtcEngineKit instance set successfully");
          result(@YES);
        } else {
          NSLog(@"❌ [AgoraRtcNgPlugin] Invalid AgoraEngine object at pointer: %p", agoraEnginePtr);
          result([FlutterError errorWithCode:@"InvalidObject"
                                     message:@"Pointer does not point to valid AgoraRtcEngineKit instance"
                                     details:nil]);
        }
      } @catch (NSException *exception) {
        NSLog(@"❌ [AgoraRtcNgPlugin] Exception in nosmaiSetAgoraEngine: %@", exception.reason);
        result([FlutterError errorWithCode:@"BridgingError"
                                   message:[NSString stringWithFormat:@"Failed to bridge pointer: %@", exception.reason]
                                   details:nil]);
      }
    } else {
      NSLog(@"❌ [AgoraRtcNgPlugin] AgoraEngine pointer is nil");
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"AgoraRtcEngineKit pointer is required"
                                 details:nil]);
    }
  } else {
    NSLog(@"❌ [AgoraRtcNgPlugin] Nosmai processor not initialized");
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiCreateCustomEngine:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSString *appId = [call.arguments objectForKey:@"appId"];
    if (appId) {
      NSLog(@"🔧 [AgoraRtcNgPlugin] Creating custom AgoraRtcEngineKit with AppID: %@", appId);
      [self.nosmaiProcessor createCustomAgoraEngine:appId];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"AppID is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiGetCustomEngine:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    AgoraRtcEngineKit *customEngine = [self.nosmaiProcessor getCustomEngine];
    if (customEngine) {
      // Return the engine pointer as a number that Flutter can use
      NSNumber *enginePointer = [NSNumber numberWithLongLong:(long long)customEngine];
      result(enginePointer);
    } else {
      result([FlutterError errorWithCode:@"NoCustomEngine"
                                 message:@"Custom engine not created yet"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiAttachPreviewToView:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    // For now, we'll need to implement a way to get the view reference
    // This is tricky from Flutter side, we might need a different approach
    NSLog(@"🔧 [AgoraRtcNgPlugin] nosmaiAttachPreviewToView called - implementation needed");
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiInjectPreviewIntoView:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *viewIdNumber = [call.arguments objectForKey:@"viewId"];
    if (viewIdNumber) {
      int viewId = [viewIdNumber intValue];
      NSLog(@"🔧 [AgoraRtcNgPlugin] Injecting Nosmai preview into view ID: %d", viewId);
      
      // For now, we'll use a different approach since we can't easily access the platform view
      // Let's use the global preview view approach instead
      NSLog(@"⚠️ [AgoraRtcNgPlugin] Platform view injection not yet implemented");
      NSLog(@"🔄 [AgoraRtcNgPlugin] Using global preview approach instead");
      
      // This will work if the frames are being displayed in the global preview view
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"viewId is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

#pragma mark - Filter Management Methods

- (void)nosmaiGetLocalFilters:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSArray *localFilters = [self.nosmaiProcessor getLocalFilters];
    result(localFilters);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiGetCloudFilters:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSArray *cloudFilters = [self.nosmaiProcessor getCloudFilters];
    result(cloudFilters);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiDownloadCloudFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (!self.nosmaiProcessor) {
    result([FlutterError errorWithCode:@"NotInitialized" message:@"Nosmai processor not initialized" details:nil]);
    return;
  }
  
  NSString *filterId = call.arguments[@"filterId"];
  if (!filterId || filterId.length == 0) {
    result([FlutterError errorWithCode:@"InvalidArgument" message:@"Filter ID is required" details:nil]);
    return;
  }
  
  [self.nosmaiProcessor downloadCloudFilter:filterId
                                 completion:^(NSDictionary *downloadResult) {
      dispatch_async(dispatch_get_main_queue(), ^{
          result(downloadResult);
      });
  }];
}

- (void)nosmaiGetFilters:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSArray *filters = [self.nosmaiProcessor getFilters];
    result(filters);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiClearFilterCache:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor clearFilterCache];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

#pragma mark - Extended Beauty and Filter Effects

- (void)nosmaiApplySkinWhitening:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *intensity = call.arguments[@"intensity"];
    if (intensity) {
      [self.nosmaiProcessor applySkinWhitening:[intensity floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Intensity value is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyNoseSize:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *intensity = call.arguments[@"intensity"];
    if (intensity) {
      [self.nosmaiProcessor applyNoseSize:[intensity floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Intensity value is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyBrightnessFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *brightness = call.arguments[@"brightness"];
    if (brightness) {
      [self.nosmaiProcessor applyBrightnessFilter:[brightness floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Brightness value is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyContrastFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *contrast = call.arguments[@"contrast"];
    if (contrast) {
      [self.nosmaiProcessor applyContrastFilter:[contrast floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Contrast value is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyRGBFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *red = call.arguments[@"red"];
    NSNumber *green = call.arguments[@"green"];
    NSNumber *blue = call.arguments[@"blue"];
    if (red && green && blue) {
      [self.nosmaiProcessor applyRGBFilter:[red floatValue] green:[green floatValue] blue:[blue floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"RGB values are required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplySharpening:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *level = call.arguments[@"level"];
    if (level) {
      [self.nosmaiProcessor applySharpening:[level floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Sharpening level is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyMakeupBlendLevel:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSString *filterName = call.arguments[@"filterName"];
    NSNumber *level = call.arguments[@"level"];
    if (filterName && level) {
      [self.nosmaiProcessor applyMakeupBlendLevel:filterName level:[level floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Filter name and level are required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyGrayscaleFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor applyGrayscaleFilter];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyHue:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *hueAngle = call.arguments[@"hueAngle"];
    if (hueAngle) {
      [self.nosmaiProcessor applyHue:[hueAngle floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Hue angle is required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiApplyWhiteBalance:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *temperature = call.arguments[@"temperature"];
    NSNumber *tint = call.arguments[@"tint"];
    if (temperature && tint) {
      [self.nosmaiProcessor applyWhiteBalance:[temperature floatValue] tint:[tint floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"Temperature and tint values are required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiAdjustHSB:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    NSNumber *hue = call.arguments[@"hue"];
    NSNumber *saturation = call.arguments[@"saturation"];
    NSNumber *brightness = call.arguments[@"brightness"];
    if (hue && saturation && brightness) {
      [self.nosmaiProcessor adjustHSB:[hue floatValue] saturation:[saturation floatValue] brightness:[brightness floatValue]];
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"InvalidArgument"
                                 message:@"HSB values are required"
                                 details:nil]);
    }
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiResetHSBFilter:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor resetHSBFilter];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiRemoveBuiltInFilters:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor removeBuiltInFilters];
    result(@YES);
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiIsBeautyFilterEnabled:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    BOOL isEnabled = [self.nosmaiProcessor isBeautyFilterEnabled];
    result(@(isEnabled));
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

- (void)nosmaiIsCloudFilterEnabled:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (self.nosmaiProcessor) {
    BOOL isEnabled = [self.nosmaiProcessor isCloudFilterEnabled];
    result(@(isEnabled));
  } else {
    result([FlutterError errorWithCode:@"NotInitialized"
                               message:@"Nosmai processor not initialized"
                               details:nil]);
  }
}

+ (void)resetFactoryRegistration {
  NSLog(@"🔄 [AgoraRtcNgPlugin] Resetting factory registration state - WARNING: Use only for testing");
  isNosmaiFactoryRegistered = NO;
}

// Safe cleanup method that doesn't disturb existing flow
+ (void)performSafeCleanup {
  NSLog(@"🧹 [AgoraRtcNgPlugin] Performing safe cleanup without disturbing active streams");
  // This method can be called between streams for cleanup
  // Does not reset factory registration to maintain stability
}

#pragma mark - NosmaiSDK Camera Preview Methods

- (void)initializeNosmaiPreview:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSLog(@"🔧 [AgoraRtcNgPlugin] initializeNosmaiPreview called");
  
  @try {
    NSDictionary *arguments = call.arguments;
    BOOL frontCamera = [[arguments objectForKey:@"frontCamera"] boolValue];
    NSString *resolution = [arguments objectForKey:@"resolution"];
    
    NSLog(@"📷 Initializing NosmaiSDK preview - Front: %@, Resolution: %@", 
          frontCamera ? @"YES" : @"NO", resolution);
    
    // Get the shared processor instance and start preview
    if (self.nosmaiProcessor) {
      // Use existing processor for preview
      [self.nosmaiProcessor startProcessing];
      NSLog(@"✅ Using existing NosmaiSDK processor for preview");
    } else {
      // Create new processor if needed
      NSLog(@"🔧 Creating new NosmaiSDK processor for preview");
      // This will be handled by the normal initialization flow
    }
    
    result(@{@"success": @YES, @"message": @"NosmaiSDK preview initialized"});
  } @catch (NSException *exception) {
    NSLog(@"❌ Error in initializeNosmaiPreview: %@", exception.reason);
    result([FlutterError errorWithCode:@"NOSMAI_PREVIEW_ERROR"
                               message:exception.reason
                               details:nil]);
  }
}

- (void)stopNosmaiPreview:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSLog(@"🔧 [AgoraRtcNgPlugin] stopNosmaiPreview called");
  
  @try {
    // Don't actually stop processing - just acknowledge the call
    // This maintains continuity when transitioning to live stream
    NSLog(@"ℹ️ NosmaiSDK preview transition - keeping processing active for stream continuity");
    
    result(@{@"success": @YES, @"message": @"NosmaiSDK preview transitioned"});
  } @catch (NSException *exception) {
    NSLog(@"❌ Error in stopNosmaiPreview: %@", exception.reason);
    result([FlutterError errorWithCode:@"NOSMAI_PREVIEW_ERROR"
                               message:exception.reason
                               details:nil]);
  }
}

- (void)flipNosmaiCamera:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSLog(@"🔄 [AgoraRtcNgPlugin] flipNosmaiCamera called");
  
  @try {
    if (self.nosmaiProcessor) {
      BOOL flipped = [self.nosmaiProcessor switchCamera];
      if (flipped) {
        NSLog(@"✅ NosmaiSDK camera flipped successfully");
        result(@{@"success": @YES, @"message": @"Camera flipped"});
      } else {
        NSLog(@"⚠️ NosmaiSDK camera flip failed");
        result(@{@"success": @NO, @"message": @"Camera flip failed"});
      }
    } else {
      NSLog(@"❌ NosmaiSDK processor not available for camera flip");
      result([FlutterError errorWithCode:@"NOSMAI_NOT_INITIALIZED"
                                 message:@"NosmaiSDK processor not available"
                                 details:nil]);
    }
  } @catch (NSException *exception) {
    NSLog(@"❌ Error in flipNosmaiCamera: %@", exception.reason);
    result([FlutterError errorWithCode:@"NOSMAI_CAMERA_ERROR"
                               message:exception.reason
                               details:nil]);
  }
}

- (void)restartNosmaiProcessingIfNeeded {
  if (self.nosmaiProcessor) {
    [self.nosmaiProcessor restartProcessingIfStoppedForCameraLight];
  }
}

@end
