//
//  SimpleNosmaiPreviewFactory.m
//  agora_rtc_engine
//
//  Simple platform view factory for Nosmai preview
//

#import "SimpleNosmaiPreviewFactory.h"
#import "AgoraNosmaiProcessor.h"
#import "AgoraRtcNgPlugin.h"

// Forward declaration
@class SimpleNosmaiPreview;

// Global view reuse pool to prevent rapid creation/destruction
static NSMutableDictionary<NSNumber *, SimpleNosmaiPreview *> *viewPool = nil;
static dispatch_once_t viewPoolOnceToken;

@interface SimpleNosmaiPreview : NSObject <FlutterPlatformView>
@property (nonatomic, strong) UIView *nativeView;
@property (nonatomic, assign) int64_t viewId;
@end

@implementation SimpleNosmaiPreview

- (instancetype)initWithViewId:(int64_t)viewId {
    self = [super init];
    if (self) {
        self.viewId = viewId;
        
        // CRITICAL: Ensure UI operations are on main thread
        if ([NSThread isMainThread]) {
            self.nativeView = [AgoraNosmaiProcessor createGlobalPreviewView];
            NSLog(@"✅ SimpleNosmaiPreview created with unique view ID: %lld, view: %@", viewId, self.nativeView);
        } else {
            // Force main thread execution for UI operations
            dispatch_sync(dispatch_get_main_queue(), ^{
                self.nativeView = [AgoraNosmaiProcessor createGlobalPreviewView];
                NSLog(@"✅ SimpleNosmaiPreview created with unique view ID: %lld, view: %@ (main thread)", viewId, self.nativeView);
            });
        }
    }
    return self;
}

- (UIView *)view {
    return self.nativeView;
}

- (void)dealloc {
    NSLog(@"🗑️ SimpleNosmaiPreview deallocated for view ID: %lld", self.viewId);
    
    // CRITICAL: Ensure UI cleanup is on main thread
    if ([NSThread isMainThread]) {
        self.nativeView = nil;
    } else {
        // Force main thread for UI cleanup
        dispatch_sync(dispatch_get_main_queue(), ^{
            self.nativeView = nil;
        });
    }
    
    NSLog(@"✅ SimpleNosmaiPreview cleanup completed for view ID: %lld", self.viewId);
}

@end

@implementation SimpleNosmaiPreviewFactory

+ (void)initializeViewPool {
    dispatch_once(&viewPoolOnceToken, ^{
        viewPool = [[NSMutableDictionary alloc] init];
        NSLog(@"🎱 Platform view reuse pool initialized");
    });
}

+ (SimpleNosmaiPreview *)getReusableViewForId:(int64_t)viewId {
    [self initializeViewPool];
    NSNumber *key = @(viewId);
    SimpleNosmaiPreview *reusableView = viewPool[key];
    if (reusableView) {
        NSLog(@"♾️ Reusing existing platform view for ID: %lld", viewId);
        return reusableView;
    }
    return nil;
}

+ (void)storeViewInPool:(SimpleNosmaiPreview *)view forId:(int64_t)viewId {
    [self initializeViewPool];
    NSNumber *key = @(viewId);
    viewPool[key] = view;
    NSLog(@"💾 Platform view stored in pool for ID: %lld", viewId);
}

+ (void)removeViewFromPool:(int64_t)viewId {
    [self initializeViewPool];
    NSNumber *key = @(viewId);
    [viewPool removeObjectForKey:key];
    NSLog(@"🗑️ Platform view removed from pool for ID: %lld", viewId);
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args {
    NSLog(@"🔧 [SimpleNosmaiPreviewFactory] Requesting platform view for ID: %lld", viewId);
    
    // CRITICAL: Try to reuse existing view first to prevent rapid creation/destruction
    SimpleNosmaiPreview *reusableView = [SimpleNosmaiPreviewFactory getReusableViewForId:viewId];
    if (reusableView) {
        NSLog(@"♾️ [SimpleNosmaiPreviewFactory] Reusing existing view for ID: %lld", viewId);
        return reusableView;
    }
    
    NSLog(@"🆕 [SimpleNosmaiPreviewFactory] Creating new platform view instance with ID: %lld", viewId);
    
    // Ensure main thread creation for UI safety
    __block SimpleNosmaiPreview *preview;
    if ([NSThread isMainThread]) {
        preview = [[SimpleNosmaiPreview alloc] initWithViewId:viewId];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            preview = [[SimpleNosmaiPreview alloc] initWithViewId:viewId];
        });
    }
    
    // Store in reuse pool for future use
    [SimpleNosmaiPreviewFactory storeViewInPool:preview forId:viewId];
    
    // Trigger processing restart if needed (when camera is turned back on)
    [self triggerProcessingRestartIfNeeded];
    
    NSLog(@"✅ [SimpleNosmaiPreviewFactory] Platform view instance created and pooled: %@", preview);
    return preview;
}

- (NSObject<FlutterMessageCodec> *)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

- (void)triggerProcessingRestartIfNeeded {
    if (self.plugin) {
        [self.plugin restartNosmaiProcessingIfNeeded];
    }
}

@end