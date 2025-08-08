//
//  SimpleNosmaiPreviewFactory.m
//  agora_rtc_engine
//
//  Simple platform view factory for Nosmai preview
//

#import "SimpleNosmaiPreviewFactory.h"
#import "AgoraNosmaiProcessor.h"

@interface SimpleNosmaiPreview : NSObject <FlutterPlatformView>
@property (nonatomic, strong) UIView *nativeView;
@end

@implementation SimpleNosmaiPreview

- (instancetype)init {
    self = [super init];
    if (self) {
        self.nativeView = [AgoraNosmaiProcessor createGlobalPreviewView];
    }
    return self;
}

- (UIView *)view {
    return self.nativeView;
}

@end

@implementation SimpleNosmaiPreviewFactory

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args {
    return [[SimpleNosmaiPreview alloc] init];
}

- (NSObject<FlutterMessageCodec> *)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

@end