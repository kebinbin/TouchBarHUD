#import <Cocoa/Cocoa.h>
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import "TBHTouchBarController.h"
#import "TBHSurfaceView.h"
#import <stdio.h>

@interface TBHTouchBarController (Testing)
- (void)consumeSurface:(IOSurfaceRef)surface;
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)@{
            (__bridge NSString *)kIOSurfaceWidth: @2170,
            (__bridge NSString *)kIOSurfaceHeight: @60,
            (__bridge NSString *)kIOSurfaceBytesPerElement: @4});
        if (!surface) { return 1; }
        int32_t initialUseCount = IOSurfaceGetUseCount(surface);
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(20, 120, 1085, 30)
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        TBHSurfaceView *view = [[TBHSurfaceView alloc] initWithFrame:panel.contentView.bounds];
        view.wantsLayer = YES;
        panel.contentView = view;
        [panel orderFrontRegardless];
        TBHTouchBarController *controller = [[TBHTouchBarController alloc] init];
        __weak TBHTouchBarController *weakController = controller;
        controller.frameHandler = ^{ [view displaySurface:weakController.latestSurface]; };
        // Produce a real 60 Hz stream of new surfaces to exercise replacement and release.
        NSTimer *sourceTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            IOSurfaceRef next = IOSurfaceCreate((__bridge CFDictionaryRef)@{
                (__bridge NSString *)kIOSurfaceWidth: @2170,
                (__bridge NSString *)kIOSurfaceHeight: @60,
                (__bridge NSString *)kIOSurfaceBytesPerElement: @4});
            if (next) {
                [controller consumeSurface:next];
                CFRelease(next);
            }
        }];
        [controller consumeSurface:surface];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:45];
        while (deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
        }
        [sourceTimer invalidate];
        [panel orderOut:nil];
        [view displaySurface:NULL];
        controller.frameHandler = nil;
        [controller stop];
        [CATransaction flush];
        NSDate *settle = [NSDate dateWithTimeIntervalSinceNow:0.2];
        while (settle.timeIntervalSinceNow > 0) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:settle];
        }
        BOOL balanced = IOSurfaceGetUseCount(surface) == initialUseCount;
        printf("Synthetic rendering: %lu source frames, %lu delivered; initial surface released: %s\n",
            (unsigned long)controller.receivedFrameCount, (unsigned long)controller.deliveredFrameCount,
            balanced ? "yes" : "no");
        CFRelease(surface);
        return balanced ? 0 : 1;
    }
}
