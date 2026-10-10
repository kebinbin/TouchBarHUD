#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <stdio.h>

static void FillRoundedRect(CGContextRef context, CGRect rect, CGFloat radius) {
    CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    CGContextAddPath(context, path);
    CGContextFillPath(context);
    CGPathRelease(path);
}

static void DrawMark(CGContextRef context, BOOL monochrome) {
    CGFloat shade = monochrome ? 0 : 0.96;
    CGContextSetRGBStrokeColor(context, shade, shade, monochrome ? 0 : 0.98, 1);
    CGContextSetLineWidth(context, 40);
    CGPathRef screen = CGPathCreateWithRoundedRect(CGRectMake(220, 260, 584, 408), 56, 56, NULL);
    CGContextAddPath(context, screen);
    CGContextStrokePath(context);
    CGPathRelease(screen);
    if (monochrome) { CGContextSetRGBFillColor(context, 0, 0, 0, 1); }
    else { CGContextSetRGBFillColor(context, 0.408, 0.851, 0.910, 1); }
    FillRoundedRect(context, CGRectMake(286, 550, 452, 44), 22);
    FillRoundedRect(context, CGRectMake(286, 716, 452, 44), 22);
}

static BOOL WritePNG(NSString *path, size_t size) {
    CGColorSpaceRef colors = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, size * 4, colors,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colors);
    if (!context) { return NO; }
    CGContextTranslateCTM(context, 0, size);
    CGContextScaleCTM(context, (CGFloat)size / 1024.0, -(CGFloat)size / 1024.0);
    CGContextSetRGBFillColor(context, 24.0 / 255, 34.0 / 255, 48.0 / 255, 1);
    FillRoundedRect(context, CGRectMake(96, 96, 832, 832), 180);
    DrawMark(context, NO);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
        CFSTR("public.png"), 1, NULL);
    BOOL success = NO;
    if (destination && image) {
        CGImageDestinationAddImage(destination, image, NULL);
        success = CGImageDestinationFinalize(destination);
    }
    if (destination) { CFRelease(destination); }
    if (image) { CGImageRelease(image); }
    CGContextRelease(context);
    return success;
}

static BOOL WriteStatusPDF(NSString *path) {
    CGRect page = CGRectMake(0, 0, 22, 18);
    CGContextRef context = CGPDFContextCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &page, NULL);
    if (!context) { return NO; }
    CGPDFContextBeginPage(context, NULL);
    CGContextTranslateCTM(context, 0, 18);
    CGContextScaleCTM(context, 22.0 / 644.0, -18.0 / 550.0);
    CGContextTranslateCTM(context, -190, -230);
    DrawMark(context, YES);
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr, "Usage: generate-icons RESOURCES_DIR ICONSET_DIR\n"); return 64; }
        NSString *resources = @(argv[1]), *iconset = @(argv[2]);
        for (NSNumber *points in @[@16, @32, @128, @256, @512]) {
            for (NSUInteger scale = 1; scale <= 2; scale++) {
                NSString *name = [NSString stringWithFormat:@"icon_%@x%@%@.png", points, points, scale == 2 ? @"@2x" : @""];
                if (!WritePNG([iconset stringByAppendingPathComponent:name], points.unsignedIntegerValue * scale)) { return 1; }
            }
        }
        if (!WritePNG([resources stringByAppendingPathComponent:@"Logo.png"], 1024) ||
            !WriteStatusPDF([resources stringByAppendingPathComponent:@"StatusIcon.pdf"])) { return 1; }
        NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\" role=\"img\" aria-labelledby=\"title\">\n"
            "  <title id=\"title\">TouchBar HUD — a display mirroring a Touch Bar</title>\n"
            "  <rect x=\"96\" y=\"96\" width=\"832\" height=\"832\" rx=\"180\" fill=\"#182230\"/>\n"
            "  <rect x=\"220\" y=\"260\" width=\"584\" height=\"408\" rx=\"56\" fill=\"none\" stroke=\"#f5f5fa\" stroke-width=\"40\"/>\n"
            "  <g fill=\"#68d9e8\">\n"
            "    <rect x=\"286\" y=\"550\" width=\"452\" height=\"44\" rx=\"22\"/>\n"
            "    <rect x=\"286\" y=\"716\" width=\"452\" height=\"44\" rx=\"22\"/>\n"
            "  </g>\n</svg>\n";
        NSError *error = nil;
        if (![svg writeToFile:[resources stringByAppendingPathComponent:@"Logo.svg"] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
    return 0;
}
