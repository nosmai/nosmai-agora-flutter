#import <Flutter/Flutter.h>

#import <AgoraRtcWrapper/AgoraPIPController.h>

@interface AgoraRtcNgPlugin
    : NSObject <FlutterPlugin, AgoraPIPStateChangedDelegate>

+ (void)resetFactoryRegistration;
+ (void)performSafeCleanup;

// Method to restart NosmaiSDK processing if needed
- (void)restartNosmaiProcessingIfNeeded;

@end
