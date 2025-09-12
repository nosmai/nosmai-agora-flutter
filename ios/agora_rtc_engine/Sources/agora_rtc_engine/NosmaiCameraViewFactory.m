//
//  NosmaiCameraViewFactory.m
//  Agora Flutter SDK - Nosmai Camera View
//
//  Created by Agora Team
//  Copyright © 2024. All rights reserved.
//

#import "NosmaiCameraViewFactory.h"
#import "NosmaiAgoraBridge.h"

@implementation NosmaiCameraView {
    UIView *_previewView;
    NSObject<FlutterBinaryMessenger> *_messenger;
}

- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                    arguments:(id _Nullable)args
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _messenger = messenger;
        
        // Ensure frame has valid size, use default if zero
        CGRect validFrame = frame;
        if (CGRectIsEmpty(frame) || frame.size.width == 0 || frame.size.height == 0) {
            validFrame = CGRectMake(0, 0, 320, 480);
            NSLog(@"NosmaiCameraView: Frame was empty, using default size");
        }
        
        _previewView = [[UIView alloc] initWithFrame:validFrame];
        _previewView.backgroundColor = [UIColor blackColor];
        _previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        NSLog(@"NosmaiCameraView: Created view with id %lld, frame: %@", viewId, NSStringFromCGRect(validFrame));
        
        // Ensure we're on the main thread when setting the preview view
        if ([NSThread isMainThread]) {
            // Set this view as the preview view for NosmaiSDK
            NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
            [bridge setLocalPreviewView:_previewView];
            NSLog(@"NosmaiCameraView: Set preview view immediately for id %lld", viewId);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_previewView) { // Check view still exists
                    // Set this view as the preview view for NosmaiSDK
                    NosmaiAgoraBridge *bridge = [NosmaiAgoraBridge sharedInstance];
                    [bridge setLocalPreviewView:_previewView];
                    NSLog(@"NosmaiCameraView: Set preview view on main thread for id %lld", viewId);
                }
            });
        }
    }
    return self;
}

- (UIView *)view {
    return _previewView;
}

@end

@implementation NosmaiCameraViewFactory {
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
    return [[NosmaiCameraView alloc] initWithFrame:frame
                                             viewId:viewId
                                          arguments:args
                                          messenger:_messenger];
}

- (NSObject<FlutterMessageCodec> *)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

@end