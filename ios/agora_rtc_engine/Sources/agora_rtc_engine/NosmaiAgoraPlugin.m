//
//  NosmaiAgoraPlugin.m
//  Agora Flutter SDK - Nosmai Integration
//
//  Created by Agora Team
//  Copyright © 2024. All rights reserved.
//

#import "NosmaiAgoraPlugin.h"
#import "NosmaiAgoraBridge.h"

@interface NosmaiAgoraPlugin ()

@property (nonatomic, strong) FlutterMethodChannel *channel;

@end

@implementation NosmaiAgoraPlugin

static __weak NosmaiAgoraPlugin *sSharedPlugin = nil;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"nosmai_agora"
              binaryMessenger:[registrar messenger]];
    NosmaiAgoraPlugin* instance = [[NosmaiAgoraPlugin alloc] init];
    instance.channel = channel;
    sSharedPlugin = instance;
    [registrar addMethodCallDelegate:instance channel:channel];
}

+ (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    NosmaiAgoraPlugin *plugin = sSharedPlugin;
    if (plugin.channel) {
        [plugin.channel setMethodCallHandler:nil];
        plugin.channel = nil;
    }
    [[NosmaiAgoraBridge sharedInstance] teardownStreaming];
    sSharedPlugin = nil;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
    
    // SDK Initialization
    if ([call.method isEqualToString:@"initialize"]) {
        NSString *licenseKey = call.arguments[@"licenseKey"];
        BOOL initResult = [bridge initNosmaiWithLicense:licenseKey];
        result(@(initResult));
        
    } else if ([call.method isEqualToString:@"initAgora"]) {
        NSString *appId = call.arguments[@"appId"];
        BOOL agoraInitResult = [bridge initAgoraWithAppId:appId];
        result(@(agoraInitResult));
        
    } else if ([call.method isEqualToString:@"releaseAgora"]) {
        [bridge releaseAgora];
        result(@(YES));
        
    // Streaming Control
    } else if ([call.method isEqualToString:@"startCustomCamera"]) {
        NSString *appId = call.arguments[@"appId"];
        NSString *token = call.arguments[@"token"];
        NSString *channelId = call.arguments[@"channelId"];
        NSNumber *userIdNum = call.arguments[@"userId"];
        NSNumber *startCameraImmediately = call.arguments[@"startCameraImmediately"];
        
        NSUInteger userId = userIdNum ? [userIdNum unsignedIntegerValue] : 0;
        BOOL startImmediately = startCameraImmediately ? [startCameraImmediately boolValue] : YES;
        
        BOOL startResult = [bridge startCustomCameraWithAppId:appId
                                                        token:token
                                                    channelId:channelId
                                                       userId:userId
                                          startCameraImmediately:startImmediately];
        result(@(startResult));
        
    } else if ([call.method isEqualToString:@"stopCustomCamera"]) {
        BOOL stopResult = [bridge stopCustomCamera];
        result(@(stopResult));
        
    } else if ([call.method isEqualToString:@"teardownStreaming"]) {
        [bridge teardownStreaming];
        result(@(YES));
        
    // Agora Controls
    } else if ([call.method isEqualToString:@"enableVideo"]) {
        BOOL enableVideoResult = [bridge enableVideo];
        result(@(enableVideoResult));
        
    } else if ([call.method isEqualToString:@"enableLocalVideo"]) {
        NSNumber *enabled = call.arguments[@"enabled"];
        BOOL enableLocalVideoResult = [bridge enableLocalVideo:enabled ? [enabled boolValue] : NO];
        result(@(enableLocalVideoResult));
        
    } else if ([call.method isEqualToString:@"startProcessing"]) {
        BOOL startProcessingResult = [bridge startProcessing];
        result(@(startProcessingResult));

    } else if ([call.method isEqualToString:@"stopProcessing"]) {
        // ✅ Fixed: Call correct method stopProcessing instead of stopStreaming
        BOOL stopProcessingResult = [bridge stopProcessing];
        result(@(stopProcessingResult));
        
    } else if ([call.method isEqualToString:@"setClientRole"]) {
        NSNumber *role = call.arguments[@"role"];
        AgoraClientRole clientRole = role ? (AgoraClientRole)[role integerValue] : AgoraClientRoleBroadcaster;
        BOOL setClientRoleResult = [bridge setClientRole:clientRole];
        result(@(setClientRoleResult));
        
    } else if ([call.method isEqualToString:@"joinChannel"]) {
        NSString *token = call.arguments[@"token"];
        NSString *channelId = call.arguments[@"channelId"];
        NSNumber *userIdNum = call.arguments[@"userId"];
        NSUInteger userId = userIdNum ? [userIdNum unsignedIntegerValue] : 0;
        
        BOOL joinResult = [bridge joinChannelWithToken:token channelId:channelId userId:userId];
        result(@(joinResult));
        
    } else if ([call.method isEqualToString:@"leaveChannel"]) {
        BOOL leaveResult = [bridge leaveChannel];
        result(@(leaveResult));
        
    // Beauty Filters
    } else if ([call.method isEqualToString:@"applyBrightness"]) {
        NSNumber *brightness = call.arguments[@"brightness"];
        BOOL brightnessResult = [bridge applyBrightness:brightness ? [brightness floatValue] : 0.0f];
        result(@(brightnessResult));
        
    } else if ([call.method isEqualToString:@"applySkinSmoothing"]) {
        NSNumber *level = call.arguments[@"level"];
        BOOL skinSmoothingResult = [bridge applySkinSmoothing:level ? [level floatValue] : 0.0f];
        result(@(skinSmoothingResult));
        
    } else if ([call.method isEqualToString:@"applySkinWhitening"]) {
        NSNumber *level = call.arguments[@"level"];
        BOOL skinWhiteningResult = [bridge applySkinWhitening:level ? [level floatValue] : 0.0f];
        result(@(skinWhiteningResult));
        
    } else if ([call.method isEqualToString:@"applyFaceSlimming"]) {
        NSNumber *level = call.arguments[@"level"];
        BOOL faceSlimmingResult = [bridge applyFaceSlimming:level ? [level floatValue] : 0.0f];
        result(@(faceSlimmingResult));
        
    } else if ([call.method isEqualToString:@"applyEyeEnlargement"]) {
        NSNumber *level = call.arguments[@"level"];
        BOOL eyeEnlargementResult = [bridge applyEyeEnlargement:level ? [level floatValue] : 0.0f];
        result(@(eyeEnlargementResult));
        
    } else if ([call.method isEqualToString:@"applyNoseSize"]) {
        NSNumber *level = call.arguments[@"level"];
        BOOL noseSizeResult = [bridge applyNoseSize:level ? [level floatValue] : 0.0f];
        result(@(noseSizeResult));
        
    } else if ([call.method isEqualToString:@"applyContrast"]) {
        NSNumber *contrast = call.arguments[@"contrast"];
        BOOL contrastResult = [bridge applyContrast:contrast ? [contrast floatValue] : 1.0f];
        result(@(contrastResult));
        
    } else if ([call.method isEqualToString:@"applyHue"]) {
        NSNumber *hue = call.arguments[@"hue"];
        BOOL hueResult = [bridge applyHue:hue ? [hue floatValue] : 0.0f];
        result(@(hueResult));
        
    } else if ([call.method isEqualToString:@"applyRGB"]) {
        NSNumber *red = call.arguments[@"red"];
        NSNumber *green = call.arguments[@"green"];
        NSNumber *blue = call.arguments[@"blue"];
        BOOL rgbResult = [bridge applyRGBWithRed:red ? [red floatValue] : 1.0f
                                           green:green ? [green floatValue] : 1.0f
                                            blue:blue ? [blue floatValue] : 1.0f];
        result(@(rgbResult));
        
    } else if ([call.method isEqualToString:@"applyLipstick"]) {
        NSNumber *intensity = call.arguments[@"intensity"];
        BOOL lipstickResult = [bridge applyLipstick:intensity ? [intensity floatValue] : 0.0f];
        result(@(lipstickResult));
        
    } else if ([call.method isEqualToString:@"applyBlusher"]) {
        NSNumber *intensity = call.arguments[@"intensity"];
        BOOL blusherResult = [bridge applyBlusher:intensity ? [intensity floatValue] : 0.0f];
        result(@(blusherResult));
        
    } else if ([call.method isEqualToString:@"applyExposure"]) {
        NSNumber *exposure = call.arguments[@"exposure"];
        BOOL exposureResult = [bridge applyExposure:exposure ? [exposure floatValue] : 0.0f];
        result(@(exposureResult));
        
    } else if ([call.method isEqualToString:@"applySaturation"]) {
        NSNumber *saturation = call.arguments[@"saturation"];
        BOOL saturationResult = [bridge applySaturation:saturation ? [saturation floatValue] : 1.0f];
        result(@(saturationResult));
        
    } else if ([call.method isEqualToString:@"applySharpening"]) {
        NSNumber *sharpening = call.arguments[@"sharpening"];
        BOOL sharpeningResult = [bridge applySharpening:sharpening ? [sharpening floatValue] : 0.0f];
        result(@(sharpeningResult));
        
    } else if ([call.method isEqualToString:@"applyWhiteBalance"]) {
        NSNumber *temperatureK = call.arguments[@"temperatureK"];
        NSNumber *tint = call.arguments[@"tint"];
        BOOL whiteBalanceResult = [bridge applyWhiteBalanceWithTemperature:temperatureK ? [temperatureK floatValue] : 5000.0f
                                                                       tint:tint ? [tint floatValue] : 0.0f];
        result(@(whiteBalanceResult));
        
    } else if ([call.method isEqualToString:@"enableGrayscale"]) {
        NSNumber *enabled = call.arguments[@"enabled"];
        BOOL grayscaleResult = [bridge enableGrayscale:enabled ? [enabled boolValue] : NO];
        result(@(grayscaleResult));
        
    } else if ([call.method isEqualToString:@"removeAllFilters"]) {
        BOOL removeFiltersResult = [bridge removeAllFilters];
        result(@(removeFiltersResult));
        
    } else if ([call.method isEqualToString:@"applyMakeupBlendLevel"]) {
        NSString *filterName = call.arguments[@"filterName"];
        NSNumber *level = call.arguments[@"level"];
        BOOL makeupResult = [bridge applyMakeupBlendLevel:filterName ? filterName : @""
                                                    level:level ? [level floatValue] : 0.0f];
        result(@(makeupResult));
        
    // Status and Info
    } else if ([call.method isEqualToString:@"getCurrentFilterStates"]) {
        NSDictionary<NSString *, NSNumber *> *filterStates = [bridge getCurrentFilterStates];
        result(filterStates);
        
    } else if ([call.method isEqualToString:@"hasActiveFilters"]) {
        BOOL hasActiveFilters = [bridge hasActiveFilters];
        result(@(hasActiveFilters));
        
    } else if ([call.method isEqualToString:@"getFlutterEngineInfo"]) {
        NSString *engineInfo = [bridge getFlutterEngineInfo];
        result(engineInfo);
        
    // Filter and effect methods
    } else if ([call.method isEqualToString:@"getLocalFilters"]) {
        [self handleGetLocalFilters:call result:result];
        
    } else if ([call.method isEqualToString:@"getCloudFilters"]) {
        [self handleGetCloudFilters:call result:result];
        
    } else if ([call.method isEqualToString:@"getFilters"]) {
        [self handleGetFilters:call result:result];
        
    } else if ([call.method isEqualToString:@"applyFilter"]) {
        [self handleApplyEffect:call result:result];
        
    } else if ([call.method isEqualToString:@"removeAllFilters"]) {
        BOOL removeFiltersResult = [bridge removeAllFilters];
        result(@(removeFiltersResult));
        
    } else if ([call.method isEqualToString:@"isCloudFilterEnabled"]) {
        [self handleIsCloudFilterEnabled:call result:result];
        
    } else if ([call.method isEqualToString:@"downloadCloudFilter"]) {
        [self handleDownloadCloudFilter:call result:result];
        
    // Camera Support
    } else if ([call.method isEqualToString:@"startCameraPreview"]) {
        BOOL startResult = [bridge startProcessing];
        result(@(startResult));
        
    } else if ([call.method isEqualToString:@"stopCameraPreview"]) {
        BOOL stopResult = [bridge stopProcessing];
        result(@(stopResult));
        
    } else if ([call.method isEqualToString:@"switchCamera"]) {
        BOOL switchResult = [bridge switchCamera];
        result(@(switchResult));
        
    // Streaming specific camera controls
    } else if ([call.method isEqualToString:@"flipCamera"]) {
        BOOL flipResult = [bridge flipCamera];
        result(@(flipResult));
        
    } else if ([call.method isEqualToString:@"muteMicrophone"]) {
        NSNumber *muted = call.arguments[@"muted"];
        BOOL muteResult = [bridge muteMicrophone:muted ? [muted boolValue] : YES];
        result(@(muteResult));
        
    } else if ([call.method isEqualToString:@"toggleMirror"]) {
        NSNumber *enabled = call.arguments[@"enabled"];
        BOOL mirrorResult = [bridge toggleMirror:enabled ? [enabled boolValue] : YES];
        result(@(mirrorResult));
        
    } else if ([call.method isEqualToString:@"setFlashMode"]) {
        NSString *flashMode = call.arguments[@"flashMode"];
        BOOL flashResult = [bridge setFlashMode:flashMode ? flashMode : @"off"];
        result(@(flashResult));
        
    } else if ([call.method isEqualToString:@"setTorchMode"]) {
        NSString *torchMode = call.arguments[@"torchMode"];
        BOOL torchResult = [bridge setTorchMode:torchMode ? torchMode : @"off"];
        result(@(torchResult));
        
        
    // Missing Nosmai camera methods
    } else if ([call.method isEqualToString:@"cleanup"]) {
        BOOL cleanupResult = [bridge cleanup];
        result(@(cleanupResult));
        
    } else if ([call.method isEqualToString:@"startRecording"]) {
        [bridge startRecordingWithCompletion:^(BOOL success) {
            result(@(success));
        }];
        
    } else if ([call.method isEqualToString:@"stopRecording"]) {
        [bridge stopRecordingWithCompletion:^(NSDictionary<NSString *, id> *stopRecResult) {
            result(stopRecResult);
        }];
        
    } else if ([call.method isEqualToString:@"capturePhoto"]) {
        [bridge capturePhotoWithCompletion:^(NSDictionary<NSString *, id> *photoResult) {
            result(photoResult);
        }];
        
    } else if ([call.method isEqualToString:@"saveImageToGallery"]) {
        FlutterStandardTypedData *typedData = call.arguments[@"imageData"];
        NSString *imageName = call.arguments[@"name"];

        NSData *imageData = nil;
        if (typedData && [typedData isKindOfClass:[FlutterStandardTypedData class]]) {
            imageData = typedData.data;
        }

        // ✅ Use new async method with completion handler
        [bridge saveImageToGalleryWithData:imageData ?: [NSData data]
                                      name:imageName ?: @"nosmai_image"
                                completion:^(NSDictionary<NSString *, id> *imageSaveResult) {
            result(imageSaveResult);
        }];

    } else if ([call.method isEqualToString:@"saveVideoToGallery"]) {
        NSString *videoPath = call.arguments[@"videoPath"];
        NSString *videoName = call.arguments[@"name"];

        // ✅ Use new async method with completion handler
        [bridge saveVideoToGalleryWithPath:videoPath ?: @""
                                      name:videoName ?: @"nosmai_video"
                                completion:^(NSDictionary<NSString *, id> *videoSaveResult) {
            result(videoSaveResult);
        }];
        
    } else if ([call.method isEqualToString:@"adjustHSB"]) {
        NSNumber *hue = call.arguments[@"hue"];
        NSNumber *saturation = call.arguments[@"saturation"];
        NSNumber *brightness = call.arguments[@"brightness"];
        BOOL hsbResult = [bridge adjustHSBWithHue:hue ? [hue doubleValue] : 0.0
                                       saturation:saturation ? [saturation doubleValue] : 1.0
                                       brightness:brightness ? [brightness doubleValue] : 0.0];
        result(@(hsbResult));
        
    } else if ([call.method isEqualToString:@"resetHSBFilter"]) {
        BOOL resetHsbResult = [bridge resetHSBFilter];
        result(@(resetHsbResult));
        
    } else if ([call.method isEqualToString:@"isBeautyFilterEnabled"]) {
        BOOL beautyEnabled = [bridge isBeautyFilterEnabled];
        result(@(beautyEnabled));
        
    } else if ([call.method isEqualToString:@"hasFlash"]) {
        BOOL flashCapability = [bridge hasFlash];
        result(@(flashCapability));
        
    } else if ([call.method isEqualToString:@"hasTorch"]) {
        BOOL torchCapability = [bridge hasTorch];
        result(@(torchCapability));
        
    } else if ([call.method isEqualToString:@"getFlashMode"]) {
        NSString *currentFlashMode = [bridge getFlashMode];
        result(currentFlashMode);
        
    } else if ([call.method isEqualToString:@"getTorchMode"]) {
        NSString *currentTorchMode = [bridge getTorchMode];
        result(currentTorchMode);
        
    } else if ([call.method isEqualToString:@"configureCamera"]) {
        NSString *position = call.arguments[@"position"];
        NSString *sessionPreset = call.arguments[@"sessionPreset"];
        BOOL configureCameraResult = [bridge configureCameraWithPosition:position ?: @"front"
                                                           sessionPreset:sessionPreset ?: @"high"];
        result(@(configureCameraResult));
        
    
    } else if ([call.method isEqualToString:@"detachCameraView"]) {
        BOOL detachResult = [bridge detachCameraView];
        result(@(detachResult));
        
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - Filter Implementation Methods

- (void)handleGetLocalFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
    @try {
        NSArray *filters = [self discoverLocalFilters];
        result(filters);
    } @catch (NSException *exception) {
        result([FlutterError errorWithCode:@"LOCAL_FILTERS_ERROR"
                                   message:exception.reason
                                   details:nil]);
    }
}

- (void)handleGetCloudFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
    @try {
        NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
        
        if (!bridge.nosmaiSDK) {
            result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                                       message:@"SDK must be initialized before getting cloud filters"
                                       details:@"Please call initNosmai() first"]);
            return;
        }
        
        // Get cloud filters from NosmaiSDK
        NSArray<NSDictionary *> *cloudFilters = [bridge.nosmaiSDK getCloudFilters];
        
        if (!cloudFilters || cloudFilters.count == 0) {
            cloudFilters = @[];
        } else {
            
            NSMutableArray *processedFilters = [NSMutableArray array];
            
            for (NSDictionary *filter in cloudFilters) {
                NSMutableDictionary *processedFilter = [filter mutableCopy];
                NSString *filterId = filter[@"id"];
                BOOL isDownloaded = [filter[@"isDownloaded"] boolValue];
               
                if (isDownloaded && filterId) {
                    NSString *localPath = [bridge.nosmaiSDK getCloudFilterLocalPath:filterId];
                    if (localPath && localPath.length > 0) {
                        processedFilter[@"path"] = localPath;
                        processedFilter[@"localPath"] = localPath;
                        
                        // Load preview image and convert to base64
                        UIImage *previewImage = [bridge.nosmaiSDK loadPreviewImageForFilter:localPath];
                        if (previewImage) {
                            NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
                            if (imageData) {
                                NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                                processedFilter[@"previewImageBase64"] = base64String;
                                processedFilter[@"previewUrl"] = base64String;
                            }
                        }
                    }
                }
                
                // Set preview URL from original filter data if available
                if (filter[@"previewUrl"] && ![filter[@"previewUrl"] isKindOfClass:[NSNull class]]) {
                    processedFilter[@"previewUrl"] = filter[@"previewUrl"];
                }
                if (filter[@"thumbnailUrl"] && ![filter[@"thumbnailUrl"] isKindOfClass:[NSNull class]]) {
                    processedFilter[@"previewUrl"] = filter[@"thumbnailUrl"];
                }
                
                // Determine filterType based on filterCategory (following reference implementation)
                NSString *filterType = filter[@"filterType"] ?: @"effect"; // default
                NSString *filterCategory = filter[@"filterCategory"];
                
                if (filterCategory && [filterCategory isKindOfClass:[NSString class]]) {
                    if ([filterCategory isEqualToString:@"cloud-filters"] || 
                        [filterCategory isEqualToString:@"fx-and-filters"] ||
                        [filterCategory hasPrefix:@"fx-and-filters"]) {
                        filterType = @"filter";
                    } else if ([filterCategory isEqualToString:@"beauty-effects"] || 
                               [filterCategory isEqualToString:@"special-effects"] ||
                               [filterCategory hasPrefix:@"special-effects"]) {
                        filterType = @"effect";
                    }
                }
                
                processedFilter[@"filterType"] = filterType;
                processedFilter[@"type"] = @"cloud";
                
                [processedFilters addObject:processedFilter];
            }
            
            cloudFilters = [processedFilters copy];
        }
        
        result(cloudFilters);
    } @catch (NSException *exception) {
        result([FlutterError errorWithCode:@"CLOUD_FILTERS_ERROR"
                                   message:exception.reason
                                   details:nil]);
    }
}

- (void)handleGetFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
    @try {
        NSMutableArray *allFilters = [NSMutableArray array];
        
        NSArray *localFilters = [self discoverLocalFilters];
        [allFilters addObjectsFromArray:localFilters];
        
        NSArray *cloudFilters = @[];
        [allFilters addObjectsFromArray:cloudFilters];
        
        result([allFilters copy]);
    } @catch (NSException *exception) {
        result([FlutterError errorWithCode:@"GET_FILTERS_ERROR"
                                   message:exception.reason
                                   details:nil]);
    }
}

- (void)handleIsCloudFilterEnabled:(FlutterMethodCall*)call result:(FlutterResult)result {

    result(@(YES));
}

- (void)handleDownloadCloudFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *filterId = call.arguments[@"filterId"];
    
    if (!filterId || [filterId length] == 0) {
        result(@{
            @"success": @(NO),
            @"error": @"filterId is required"
        });
        return;
    }
    
    NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
    
    if (!bridge.nosmaiSDK) {
        result(@{
            @"success": @(NO),
            @"error": @"SDK not initialized"
        });
        return;
    }
    
    [bridge.nosmaiSDK downloadCloudFilter:filterId
                                 progress:^(float progress) {
    }
                               completion:^(BOOL success, NSString *localPath, NSError *error) {
        if (success && localPath && localPath.length > 0) {
            result(@{
                @"success": @(YES),
                @"localPath": localPath,
                @"path": localPath
            });
        } else {
            NSString *errorMessage = error ? error.localizedDescription : @"Download failed";
            result(@{
                @"success": @(NO),
                @"error": errorMessage
            });
        }
    }];
}

- (void)handleApplyEffect:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *effectPath = call.arguments[@"path"];
    
    if (!effectPath || [effectPath length] == 0) {
        result([FlutterError errorWithCode:@"INVALID_ARGS"
                                   message:@"path is required"
                                   details:nil]);
        return;
    }
    
    NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
    
    if (!bridge.nosmaiSDK) {
        result(@(NO));
        return;
    }
    
    BOOL success = [bridge applyEffect:effectPath];
    result(@(success));
}

#pragma mark - Helper Methods

- (NSArray *)discoverLocalFilters {
    NSLog(@"[NosmaiAgoraPlugin] discoverLocalFilters method started");
    NSMutableArray *localFilters = [NSMutableArray array];
    
    // First try to get filters from Nosmai SDK's getInitialFilters (like reference implementation)
    NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
    if (bridge.nosmaiSDK) {
        @try {
            NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters = [bridge.nosmaiSDK getInitialFilters];
            
            for (NSString *key in organizedFilters.allKeys) {
                NSArray *filters = organizedFilters[key];
                for (int i = 0; i < filters.count; i++) {
                    NSDictionary *filter = filters[i];
                    NSMutableDictionary *filterForLogging = [filter mutableCopy];
                    
                    // Remove image data fields to avoid cluttering logs
                    [filterForLogging removeObjectForKey:@"previewImageBase64"];
                    [filterForLogging removeObjectForKey:@"previewImage"];
                    [filterForLogging removeObjectForKey:@"thumbnailData"];
                    [filterForLogging removeObjectForKey:@"imageData"];
                    
                }
            }
            
            
            if (organizedFilters && organizedFilters.count > 0) {
                for (NSString *filterType in organizedFilters.allKeys) {
                    NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
                    
                    for (NSDictionary *filter in filtersOfType) {
                        NSMutableDictionary *enhancedFilter = [filter mutableCopy];
                        
                        if (!enhancedFilter[@"name"] || [enhancedFilter[@"name"] isKindOfClass:[NSNull class]]) {
                            continue;
                        }
                        
                        // Set filterType from the dictionary key (this is the key fix!)
                        enhancedFilter[@"filterType"] = filterType;
                        enhancedFilter[@"type"] = @"local";
                        
                        // Ensure other required fields
                        if (!enhancedFilter[@"isDownloaded"]) {
                            enhancedFilter[@"isDownloaded"] = @YES;
                        }
                        if (!enhancedFilter[@"isFree"]) {
                            enhancedFilter[@"isFree"] = @YES;
                        }
                        
                        [localFilters addObject:enhancedFilter];
                    }
                }
                
                return [localFilters copy];
            }
        } @catch (NSException *exception) {
        }
    }
    
    NSArray *discoveredFilterNames = [self discoverNosmaiFiltersInAssets];
    
    for (NSString *filterName in discoveredFilterNames) {
        // Try multiple filter path structures to match reference implementation
        NSArray *filterPaths = @[
            [NSString stringWithFormat:@"assets/Nosmai_Filters/%@/%@.nosmai", filterName, filterName],
            [NSString stringWithFormat:@"assets/filters/%@/%@.nosmai", filterName, filterName],
            [NSString stringWithFormat:@"assets/filters/%@.nosmai", filterName]
        ];
        
        NSString *filePath = nil;
        for (NSString *pathTemplate in filterPaths) {
            NSString *assetKey = [FlutterDartProject lookupKeyForAsset:pathTemplate];
            NSString *tempPath = [[NSBundle mainBundle] pathForResource:assetKey ofType:nil];
            if (tempPath && [[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
                filePath = tempPath;
                break;
            }
        }
        
        if (filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSMutableDictionary *filterInfo = [NSMutableDictionary dictionary];
            
            filterInfo[@"id"] = filterName;
            filterInfo[@"name"] = filterName;
            filterInfo[@"path"] = filePath;
            
            NSString *displayName = [self createDisplayNameFromFilterName:filterName];
            filterInfo[@"displayName"] = displayName;
            
            NSError *error = nil;
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
            if (!error && fileAttributes) {
                filterInfo[@"fileSize"] = fileAttributes[NSFileSize];
            } else {
                filterInfo[@"fileSize"] = @0;
            }
            
            filterInfo[@"type"] = @"local";
            
            // Get proper filter type from SDK metadata first (following Agora implementation)
            NSString *filterType = @"effect"; // default fallback
            NSString *filterCategory = @"effect"; // default fallback
            NSDictionary *filterMetadata = nil;
            
            // Try to get filter metadata from SDK
            if (bridge.nosmaiSDK && [bridge.nosmaiSDK respondsToSelector:@selector(getFilterInfoFromPath:)]) {
                filterMetadata = [bridge.nosmaiSDK performSelector:@selector(getFilterInfoFromPath:) withObject:filePath];
            }
            
            if (filterMetadata && [filterMetadata isKindOfClass:[NSDictionary class]]) {
                // Extract type information from metadata (check both 'type' and 'filterType' fields)
                NSString *metadataType = filterMetadata[@"filterType"] ?: filterMetadata[@"type"];
                if (metadataType && [metadataType isKindOfClass:[NSString class]]) {
                    filterType = metadataType;
                    
                    // Categorize based on the actual type from metadata
                    NSString *lowercaseType = [metadataType lowercaseString];
                    if ([lowercaseType containsString:@"filter"]) {
                        filterCategory = @"filter";
                    } else if ([lowercaseType containsString:@"beauty"]) {
                        filterCategory = @"beauty";
                    } else {
                        filterCategory = @"effect";
                    }
                }
                
                // Update other fields from metadata if available
                if (filterMetadata[@"id"]) {
                    filterInfo[@"id"] = filterMetadata[@"id"];
                    filterInfo[@"name"] = filterMetadata[@"id"];
                }
                if (filterMetadata[@"displayName"]) {
                    filterInfo[@"displayName"] = filterMetadata[@"displayName"];
                }
                if (filterMetadata[@"description"]) {
                    filterInfo[@"description"] = filterMetadata[@"description"];
                }
                if (filterMetadata[@"version"]) {
                    filterInfo[@"version"] = filterMetadata[@"version"];
                }
                if (filterMetadata[@"author"]) {
                    filterInfo[@"author"] = filterMetadata[@"author"];
                }
                if (filterMetadata[@"category"]) {
                    filterInfo[@"category"] = filterMetadata[@"category"];
                }
            } else {

                // ✅ Hardcoded classification based on known filter names
                NSString *lowercaseName = [filterName lowercaseString];

                // Known effect names
                NSArray *effectNames = @[@"ascii_art", @"rainbow", @"quad", @"quad_effects_grid", @"prism_light_leak"];

                BOOL isEffect = NO;
                for (NSString *effectName in effectNames) {
                    if ([lowercaseName isEqualToString:effectName]) {
                        isEffect = YES;
                        break;
                    }
                }

                if (isEffect) {
                    filterType = @"effect";
                    filterCategory = @"effect";
                } else {
                    // Everything else is a filter
                    filterType = @"filter";
                    filterCategory = @"filter";
                }
            }
            
            filterInfo[@"filterType"] = filterType;
            filterInfo[@"filterCategory"] = filterCategory;
            filterInfo[@"sourceType"] = filterCategory;
            filterInfo[@"isDownloaded"] = @YES;
            filterInfo[@"isFree"] = @YES;
            filterInfo[@"isBuiltIn"] = @YES;
            
            // Try to load preview image from assets first (following reference structure)
            NSArray *previewPaths = @[
                [NSString stringWithFormat:@"assets/Nosmai_Filters/%@/%@_preview.png", filterName, filterName],
                [NSString stringWithFormat:@"assets/filters/%@/%@_preview.png", filterName, filterName],
                [NSString stringWithFormat:@"assets/filters/%@_preview.png", filterName]
            ];
            
            NSString *previewPath = nil;
            for (NSString *pathTemplate in previewPaths) {
                NSString *previewAssetKey = [FlutterDartProject lookupKeyForAsset:pathTemplate];
                NSString *tempPath = [[NSBundle mainBundle] pathForResource:previewAssetKey ofType:nil];
                if (tempPath && [[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
                    previewPath = tempPath;
                    break;
                }
            }
            
            BOOL previewLoaded = NO;
            if (previewPath && [[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
                UIImage *previewImage = [UIImage imageWithContentsOfFile:previewPath];
                if (previewImage) {
                    NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
                    if (imageData) {
                        NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                        filterInfo[@"previewImageBase64"] = base64String;
                        filterInfo[@"previewUrl"] = base64String;
                        previewLoaded = YES;
                    }
                }
            }
            
            // If no preview image in assets, try to load from the filter file
            if (!previewLoaded) {
                NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
                if (bridge.nosmaiSDK) {
                    UIImage *previewImage = [bridge.nosmaiSDK loadPreviewImageForFilter:filePath];
                    if (previewImage) {
                        NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
                        if (imageData) {
                            NSString *base64String = [imageData base64EncodedStringWithOptions:0];
                            filterInfo[@"previewImageBase64"] = base64String;
                            filterInfo[@"previewUrl"] = base64String;
                        }
                    }
                }
            }
            
            // Remove image data from logging
            NSMutableDictionary *filterInfoForLogging = [filterInfo mutableCopy];
            [filterInfoForLogging removeObjectForKey:@"previewImageBase64"];
            [filterInfoForLogging removeObjectForKey:@"previewUrl"];
            [localFilters addObject:[filterInfo copy]];
        } else {
        }
    }
    
    // Don't log the full array as it may contain image data
    return [localFilters copy];
}

- (NSArray<NSString *> *)discoverNosmaiFiltersInAssets {
    NSMutableArray *filterNames = [NSMutableArray array];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Search paths to match reference implementation structure
    NSArray *potentialPaths = @[
        @"flutter_assets/assets/Nosmai_Filters",
        @"Frameworks/App.framework/flutter_assets/assets/Nosmai_Filters",
        @"assets/Nosmai_Filters",
        @"flutter_assets/assets/filters",
        @"Frameworks/App.framework/flutter_assets/assets/filters",
        @"assets/filters"
    ];
    
    for (NSString *relativePath in potentialPaths) {
        NSString *fullPath = [bundlePath stringByAppendingPathComponent:relativePath];
        
        if ([fileManager fileExistsAtPath:fullPath]) {
            NSError *error = nil;
            NSArray *contents = [fileManager contentsOfDirectoryAtPath:fullPath error:&error];
            
            if (!error && contents) {
                for (NSString *item in contents) {
                    NSString *itemPath = [fullPath stringByAppendingPathComponent:item];
                    BOOL isDirectory;
                    
                    if ([fileManager fileExistsAtPath:itemPath isDirectory:&isDirectory]) {
                        if (isDirectory) {
                            // Check if this directory contains a .nosmai file with matching name
                            NSString *nosmaiFile = [itemPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.nosmai", item]];
                            if ([fileManager fileExistsAtPath:nosmaiFile]) {
                                if (![filterNames containsObject:item]) {
                                    [filterNames addObject:item];
                                }
                            }
                        } else if ([item hasSuffix:@".nosmai"]) {
                            // Direct .nosmai file in the filters directory
                            NSString *filterName = [item stringByDeletingPathExtension];
                            if (![filterNames containsObject:filterName]) {
                                [filterNames addObject:filterName];
                            }
                        }
                    }
                }
            }
        }
    }
    
    [filterNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    return [filterNames copy];
}

- (NSString *)createDisplayNameFromFilterName:(NSString *)filterName {
    NSArray *components = [filterName componentsSeparatedByString:@"_"];
    NSMutableArray *titleCaseComponents = [NSMutableArray array];
    
    for (NSString *component in components) {
        if (component.length > 0) {
            NSString *titleCase = [component stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                     withString:[[component substringToIndex:1] uppercaseString]];
            [titleCaseComponents addObject:titleCase];
        }
    }
    
    return [titleCaseComponents componentsJoinedByString:@" "];
}

@end
