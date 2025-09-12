//
//  NosmaiCameraViewFactory.h
//  Agora Flutter SDK - Nosmai Camera View
//
//  Created by Agora Team
//  Copyright © 2024. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface NosmaiCameraViewFactory : NSObject <FlutterPlatformViewFactory>

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;

@end

@interface NosmaiCameraView : NSObject <FlutterPlatformView>

- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                    arguments:(id _Nullable)args
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger;

@end

NS_ASSUME_NONNULL_END