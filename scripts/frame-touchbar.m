#import <AppKit/AppKit.h>
#import <stdio.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "Usage: frame-touchbar INPUT.png OUTPUT.png\n");
            return 64;
        }
        NSImage *screenshot = [[NSImage alloc] initWithContentsOfFile:@(argv[1])];
        if (!screenshot) { return 1; }

        const NSInteger padding = 10;
        NSInteger width = (NSInteger)screenshot.size.width + padding * 2;
        NSInteger height = (NSInteger)screenshot.size.height + padding * 2;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4
            hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bytesPerRow:0 bitsPerPixel:0];
        if (!bitmap) { return 1; }

        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        NSRect outer = NSMakeRect(0, 0, width, height);
        NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:outer xRadius:20 yRadius:20];
        [NSColor.blackColor setFill];
        [frame fill];

        NSRect inner = NSMakeRect(padding, padding,
            screenshot.size.width, screenshot.size.height);
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithRoundedRect:inner xRadius:12 yRadius:12] addClip];
        [screenshot drawInRect:inner fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver fraction:1];
        [NSGraphicsContext restoreGraphicsState];
        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:@(argv[2]) atomically:YES] ? 0 : 1;
    }
}
