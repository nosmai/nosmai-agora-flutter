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

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer;
- (void)updateMirrorMode:(BOOL)shouldMirror cameraIsFront:(BOOL)cameraIsFront;
- (void)recoverDisplayLayer;
- (void)flushDisplayLayer;

@end

NS_ASSUME_NONNULL_END
