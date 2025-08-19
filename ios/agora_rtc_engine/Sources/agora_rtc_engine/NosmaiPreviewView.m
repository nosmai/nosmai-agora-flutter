//
//  NosmaiPreviewView.m
//  agora_rtc_engine
//
//  Simple native view to display processed Nosmai frames
//

#import "NosmaiPreviewView.h"
#import <math.h>

// Helper function to validate CGFloat values
static BOOL isValidCGFloat(CGFloat value) {
    return !isnan(value) && !isinf(value) && isfinite(value);
}

// Helper function to validate CGRect
static BOOL isValidCGRect(CGRect rect) {
    return isValidCGFloat(rect.origin.x) && 
           isValidCGFloat(rect.origin.y) && 
           isValidCGFloat(rect.size.width) && 
           isValidCGFloat(rect.size.height) &&
           rect.size.width >= 0 && 
           rect.size.height >= 0;
}

@implementation NosmaiPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupDisplayLayer];
    }
    return self;
}

- (void)setupDisplayLayer {
    self.displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    // No transform - display frames as captured (unmirrored)
    self.displayLayer.transform = CATransform3DIdentity;
    
    [self.layer addSublayer:self.displayLayer];

}

- (void)flushDisplayLayer {
    if (self.displayLayer) {
        [self.displayLayer flush];
        NSLog(@"🔧 NosmaiPreviewView: Display layer flushed");
    }
}

- (void)recoverDisplayLayer {
    // Store current transform
    CATransform3D currentTransform = self.displayLayer.transform;
    
    // Remove old layer
    [self.displayLayer removeFromSuperlayer];
    
    // Recreate the display layer
    self.displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.displayLayer.backgroundColor = [UIColor blackColor].CGColor;
    self.displayLayer.frame = self.bounds;
    
    // Restore transform
    self.displayLayer.transform = currentTransform;
    
    // Re-add to layer hierarchy
    [self.layer addSublayer:self.displayLayer];
    
    NSLog(@"✅ NosmaiPreviewView: Display layer recovered and re-added");
}

- (void)updateMirrorMode:(BOOL)shouldMirror cameraIsFront:(BOOL)cameraIsFront {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (cameraIsFront) {
                // Front camera: Show mirrored frames as-is (same as remote viewers)
                // Capture is already mirrored, display without additional transform
                self.displayLayer.transform = CATransform3DIdentity;
                NSLog(@"📷 Front camera: Showing mirrored frames as-is (same as remote)");
            } else {
                // Back camera: Show normal view (no transform needed)
                // Capture is unmirrored, display as-is
                self.displayLayer.transform = CATransform3DIdentity;
                NSLog(@"📷 Back camera: Showing normal view (no transform)");
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception in updateMirrorMode: %@", exception.reason);
            // Fallback to identity transform
            self.displayLayer.transform = CATransform3DIdentity;
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (isValidCGRect(self.bounds)) {
        self.displayLayer.frame = self.bounds;
        
    } else {
        // Use a safe fallback frame
        self.displayLayer.frame = CGRectMake(0, 0, 100, 150);
    }
}

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer || !self.displayLayer) {
        return;
    }
    
    CVPixelBufferRetain(pixelBuffer);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // Double-check pixelBuffer validity after async dispatch
            if (!pixelBuffer) {
                CVPixelBufferRelease(pixelBuffer);
                return;
            }
            
            // Validate pixel buffer properties
            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
            
            if (width == 0 || height == 0) {
                CVPixelBufferRelease(pixelBuffer);
                return;
            }
            
            
            // Create format description with additional error checking
            CMVideoFormatDescriptionRef formatDescription = NULL;
            OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
                kCFAllocatorDefault,
                pixelBuffer,
                &formatDescription
            );
            
            if (status != noErr || !formatDescription) {
                CVPixelBufferRelease(pixelBuffer);
                return;
            }
            
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
            
            if (formatDescription) {
                CFRelease(formatDescription);
            }
            
            // Check if display layer is in failed state and recover if needed
            if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                static NSTimeInterval lastRecoveryTime = 0;
                NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                
                // Only attempt recovery once every 2 seconds
                if (currentTime - lastRecoveryTime > 2.0) {
                    lastRecoveryTime = currentTime;
                    NSLog(@"⚠️ NosmaiPreviewView: Display layer in failed state, recovering...");
                    
                    // Flush the layer to try to recover
                    [self.displayLayer flush];
                    
                    // If still failed, recreate the layer
                    if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
                        NSLog(@"🔄 NosmaiPreviewView: Recreating display layer...");
                        [self recoverDisplayLayer];
                    }
                }
                
                // Don't try to enqueue when in failed state
                if (sampleBuffer) {
                    CFRelease(sampleBuffer);
                }
            } else if (status == noErr && sampleBuffer && self.displayLayer.isReadyForMoreMediaData) {
                [self.displayLayer enqueueSampleBuffer:sampleBuffer];
                CFRelease(sampleBuffer);
            } else if (sampleBuffer) {
                CFRelease(sampleBuffer);
            }
            
            // Always release the retained pixel buffer
            CVPixelBufferRelease(pixelBuffer);
            
        } @catch (NSException *exception) {
            CVPixelBufferRelease(pixelBuffer);
        }
    });
}

@end
