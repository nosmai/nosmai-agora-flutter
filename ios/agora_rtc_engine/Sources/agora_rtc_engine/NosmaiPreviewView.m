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
    
    // Start with horizontal flip for front camera (will be updated by updateMirrorMode)
    // self.displayLayer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0);
    
    [self.layer addSublayer:self.displayLayer];

}

- (void)updateMirrorMode:(BOOL)isFrontCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // CRITICAL: Don't apply mirroring to prevent mirror effect in streamed frames
            // Always use identity transform regardless of camera position
            self.displayLayer.transform = CATransform3DIdentity;
            NSLog(@"📷 No mirroring applied - keeping frames unmirrored for streaming");
            
            /*
            // Original mirroring code - disabled to fix mirror issue
            if (isFrontCamera) {
                // CRITICAL: Validate scale values before applying transform
                CGFloat scaleX = -1.0, scaleY = 1.0, scaleZ = 1.0;
                if (isValidCGFloat(scaleX) && isValidCGFloat(scaleY) && isValidCGFloat(scaleZ)) {
                    self.displayLayer.transform = CATransform3DMakeScale(scaleX, scaleY, scaleZ);
                    NSLog(@"🪞 Front camera mirror transform applied safely");
                } else {
                    NSLog(@"❌ Invalid scale values detected, using identity transform");
                    self.displayLayer.transform = CATransform3DIdentity;
                }
            } else {
                // Back camera: no flip needed
                self.displayLayer.transform = CATransform3DIdentity;
                NSLog(@"📷 Back camera transform applied (identity)");
            }
            */
        } @catch (NSException *exception) {
            NSLog(@"❌ Exception in updateMirrorMode: %@", exception.reason);
            // Fallback to identity transform
            self.displayLayer.transform = CATransform3DIdentity;
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // CRITICAL: Validate bounds before applying to prevent NaN CoreGraphics errors
    if (isValidCGRect(self.bounds)) {
        self.displayLayer.frame = self.bounds;
    } else {
        // Use a safe fallback frame
        self.displayLayer.frame = CGRectMake(0, 0, 100, 150);
    }
}

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer || !self.displayLayer) {
        NSLog(@"❌ displayFrame: Invalid pixelBuffer or displayLayer");
        return;
    }
    
    // Retain the pixel buffer to prevent deallocation during async operation
    CVPixelBufferRetain(pixelBuffer);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // Double-check pixelBuffer validity after async dispatch
            if (!pixelBuffer) {
                NSLog(@"❌ displayFrame: pixelBuffer became nil after dispatch");
                CVPixelBufferRelease(pixelBuffer);
                return;
            }
            
            // Validate pixel buffer properties
            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
            
            if (width == 0 || height == 0) {
                NSLog(@"❌ displayFrame: Invalid pixelBuffer dimensions: %zux%zu", width, height);
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
                NSLog(@"❌ displayFrame: Failed to create format description, status: %d", (int)status);
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
            
            if (status == noErr && sampleBuffer && self.displayLayer.isReadyForMoreMediaData) {
                [self.displayLayer enqueueSampleBuffer:sampleBuffer];
                CFRelease(sampleBuffer);
            } else if (sampleBuffer) {
                CFRelease(sampleBuffer);
                NSLog(@"❌ displayFrame: Failed to enqueue sample buffer, status: %d", (int)status);
            }
            
            // Always release the retained pixel buffer
            CVPixelBufferRelease(pixelBuffer);
            
        } @catch (NSException *exception) {
            NSLog(@"❌ displayFrame: Exception caught: %@", exception.reason);
            // Always release the retained pixel buffer in case of exception
            CVPixelBufferRelease(pixelBuffer);
        }
    });
}

@end