//
//  NosmaiPreviewView.m
//  agora_rtc_engine
//
//  Simple native view to display processed Nosmai frames
//

#import "NosmaiPreviewView.h"

@implementation NosmaiPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.isAppActive = YES;
        [self setupDisplayLayer];
        [self setupNotificationObservers];
    }
    return self;
}

- (void)setupDisplayLayer {
    self.displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    // Start with horizontal flip for front camera (will be updated by updateMirrorMode)
    // self.displayLayer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0);
    
    [self.layer addSublayer:self.displayLayer];

}

- (void)updateMirrorMode:(BOOL)isFrontCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isFrontCamera) {
            // Front camera: apply horizontal flip for natural selfie view
            self.displayLayer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0);
        } else {
            // Back camera: no flip needed
            self.displayLayer.transform = CATransform3DIdentity;
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.displayLayer.frame = self.bounds;
}

- (void)setupNotificationObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(appWillResignActive:) 
                                                 name:UIApplicationWillResignActiveNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(appDidBecomeActive:) 
                                                 name:UIApplicationDidBecomeActiveNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)appWillResignActive:(NSNotification *)notification {
    [self pauseDisplay];
}

- (void)appDidBecomeActive:(NSNotification *)notification {
    [self resumeDisplay];
}

- (void)appDidEnterBackground:(NSNotification *)notification {
    self.isAppActive = NO;
    [self pauseDisplay];
}

- (void)pauseDisplay {
    self.isAppActive = NO;
    if (self.displayLayer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.displayLayer flushAndRemoveImage];
        });
    }
}

- (void)resumeDisplay {
    self.isAppActive = YES;
    
    // Clear any existing content when resuming
    if (self.displayLayer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Flush old content
            [self.displayLayer flushAndRemoveImage];
            
            // Reset the display layer state
            self.displayLayer.backgroundColor = [UIColor blackColor].CGColor;
            
        });
    }
}

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer {
    // Don't process frames if app is not active
    if (!self.isAppActive) {
        return;
    }
    
    if (!pixelBuffer || !self.displayLayer) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Double-check app is still active on main thread
        if (!self.isAppActive) {
            return;
        }
        
        @try {
            // Check if window is visible before displaying
            if (!self.window) {
                return;
            }
            
            // Create format description
            CMVideoFormatDescriptionRef formatDescription;
            OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
                kCFAllocatorDefault,
                pixelBuffer,
                &formatDescription
            );
            
            if (status != noErr) return;
            
            // Create sample timing
            CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
            timingInfo.duration = CMTimeMake(1, 30);
            timingInfo.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            
            // Create sample buffer
            CMSampleBufferRef sampleBuffer;
            status = CMSampleBufferCreateReadyWithImageBuffer(
                kCFAllocatorDefault,
                pixelBuffer,
                formatDescription,
                &timingInfo,
                &sampleBuffer
            );
            
            CFRelease(formatDescription);
            
            if (status == noErr && self.displayLayer.isReadyForMoreMediaData) {
                [self.displayLayer enqueueSampleBuffer:sampleBuffer];
                CFRelease(sampleBuffer);
            }
            
        } @catch (NSException *exception) {
        }
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end