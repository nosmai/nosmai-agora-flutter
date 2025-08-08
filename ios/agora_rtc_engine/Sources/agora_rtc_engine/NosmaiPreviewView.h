//
//  NosmaiPreviewView.h
//  agora_rtc_engine
//
//  Simple native view to display processed Nosmai frames
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NosmaiPreviewView : UIView

@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;
@property (nonatomic, assign) BOOL isAppActive;

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer;
- (void)updateMirrorMode:(BOOL)shouldMirror;
- (void)pauseDisplay;
- (void)resumeDisplay;

@end

NS_ASSUME_NONNULL_END