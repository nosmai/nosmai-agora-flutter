//
//  NosmaiNativeCameraView.m
//  Agora Flutter SDK - Nosmai Native Camera View
//
//  This provides Nosmai's own camera preview (not for streaming)
//  Copyright © 2024. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#if __has_include(<nosmai/Nosmai.h>)
#import <nosmai/Nosmai.h>
#define HAS_NOSMAI_FRAMEWORK 1
#else
#define HAS_NOSMAI_FRAMEWORK 0
#endif

@interface NosmaiNativeCameraViewFactory : NSObject <FlutterPlatformViewFactory>
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
@end

@interface NosmaiNativeCameraView : NSObject <FlutterPlatformView>
- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                    arguments:(id _Nullable)args
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger;
@end

@implementation NosmaiNativeCameraView {
    UIView *_previewView;
    NSObject<FlutterBinaryMessenger> *_messenger;
#if HAS_NOSMAI_FRAMEWORK
    NosmaiSDK *_nosmaiSDK;
#endif
    BOOL _cameraStarted;
}

- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                    arguments:(id _Nullable)args
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _messenger = messenger;
        _cameraStarted = NO;
        
        // Ensure frame has valid size
        CGRect validFrame = frame;
        if (CGRectIsEmpty(frame) || frame.size.width == 0 || frame.size.height == 0) {
            validFrame = CGRectMake(0, 0, 320, 480);
        }
        
        _previewView = [[UIView alloc] initWithFrame:validFrame];
        _previewView.backgroundColor = [UIColor blackColor];
        _previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
#if HAS_NOSMAI_FRAMEWORK
        // Get shared NosmaiSDK instance from NosmaiAgoraBridge
        @try {
            Class bridgeClass = NSClassFromString(@"NosmaiAgoraBridge");
            if (bridgeClass) {
                id bridge = [bridgeClass performSelector:@selector(sharedInstance)];
                if (bridge) {
                    _nosmaiSDK = [bridge valueForKey:@"nosmaiSDK"];
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"NosmaiNativeCameraView: Failed to get NosmaiSDK: %@", exception.reason);
        }
        
        // Start Nosmai's native camera after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startNosmaiCamera];
        });
#endif
        
        NSLog(@"NosmaiNativeCameraView: Created view with id %lld", viewId);
    }
    return self;
}

- (void)startNosmaiCamera {
#if HAS_NOSMAI_FRAMEWORK
    if (!_nosmaiSDK || _cameraStarted) {
        return;
    }
    
    @try {
        // Set the preview view
        [_nosmaiSDK setPreviewView:_previewView];
        
        // Set processing mode to Live for camera preview
        [_nosmaiSDK setProcessingMode:NosmaiProcessingModeLive];
        
        // Configure camera
        [_nosmaiSDK configureCameraWithPosition:NosmaiCameraPositionFront 
                                 sessionPreset:AVCaptureSessionPreset1280x720];
        
        // Start processing
        [_nosmaiSDK startProcessing];
        
        _cameraStarted = YES;
        NSLog(@"NosmaiNativeCameraView: Started Nosmai native camera");
        
    } @catch (NSException *exception) {
        NSLog(@"NosmaiNativeCameraView: Failed to start camera: %@", exception.reason);
    }
#endif
}

- (void)stopNosmaiCamera {
#if HAS_NOSMAI_FRAMEWORK
    if (!_nosmaiSDK || !_cameraStarted) {
        return;
    }
    
    @try {
        [_nosmaiSDK stopProcessing];
        _cameraStarted = NO;
        NSLog(@"NosmaiNativeCameraView: Stopped Nosmai native camera");
    } @catch (NSException *exception) {
        NSLog(@"NosmaiNativeCameraView: Failed to stop camera: %@", exception.reason);
    }
#endif
}

- (UIView *)view {
    return _previewView;
}

- (void)dealloc {
    [self stopNosmaiCamera];
}

@end

@implementation NosmaiNativeCameraViewFactory {
    NSObject<FlutterBinaryMessenger> *_messenger;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _messenger = messenger;
    }
    return self;
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                     viewIdentifier:(int64_t)viewId
                                          arguments:(id _Nullable)args {
    return [[NosmaiNativeCameraView alloc] initWithFrame:frame
                                                   viewId:viewId
                                               arguments:args
                                               messenger:_messenger];
}

- (NSObject<FlutterMessageCodec> *)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

@end

// Register the platform view factory
void RegisterNosmaiNativeCameraView(NSObject<FlutterPluginRegistrar> *registrar) {
    [registrar registerViewFactory:[[NosmaiNativeCameraViewFactory alloc] 
                                    initWithMessenger:[registrar messenger]]
                            withId:@"nosmai_native_camera"];
}