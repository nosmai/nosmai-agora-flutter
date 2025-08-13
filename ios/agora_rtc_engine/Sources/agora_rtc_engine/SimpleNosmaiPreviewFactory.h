//
//  SimpleNosmaiPreviewFactory.h
//  agora_rtc_engine
//
//  Simple platform view factory for Nosmai preview
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

@class AgoraRtcNgPlugin;

NS_ASSUME_NONNULL_BEGIN

@interface SimpleNosmaiPreviewFactory : NSObject <FlutterPlatformViewFactory>

@property (nonatomic, weak) AgoraRtcNgPlugin *plugin;

@end

NS_ASSUME_NONNULL_END