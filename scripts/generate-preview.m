#import <AppKit/AppKit.h>

static NSColor *Color(CGFloat red, CGFloat green, CGFloat blue) {
    return [NSColor colorWithSRGBRed:red / 255 green:green / 255 blue:blue / 255 alpha:1];
}

static void RoundedFill(NSRect rect, CGFloat radius, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

static void Label(NSString *text, NSRect rect, CGFloat size, NSColor *color, NSFontWeight weight) {
    NSFont *font = [NSFont systemFontOfSize:size weight:weight];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *attributes = @{NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph};
    NSSize textSize = [text sizeWithAttributes:attributes];
    [text drawInRect:NSMakeRect(rect.origin.x, NSMidY(rect) - textSize.height / 2,
        rect.size.width, textSize.height) withAttributes:attributes];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) { return 64; }
        const NSInteger width = 1600, height = 300;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4
            hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];

        [Color(23, 33, 47) setFill];
        NSRectFill(NSMakeRect(0, 0, width, height));
        NSRect bar = NSMakeRect(56, 73, 1488, 154);
        RoundedFill(NSOffsetRect(bar, 0, -5), 30, Color(10, 15, 23));
        RoundedFill(bar, 30, Color(4, 6, 10));

        NSColor *primary = Color(239, 242, 247);
        NSColor *muted = Color(167, 177, 190);
        RoundedFill(NSMakeRect(89, 119, 112, 62), 12, Color(42, 47, 55));
        Label(@"esc", NSMakeRect(89, 119, 112, 62), 32, primary, NSFontWeightRegular);
        [Color(66, 73, 84) setFill];
        NSRectFill(NSMakeRect(229, 111, 2, 78));

        Label(@"◀", NSMakeRect(272, 113, 80, 74), 42, muted, NSFontWeightRegular);
        Label(@"▶", NSMakeRect(378, 113, 80, 74), 42, primary, NSFontWeightRegular);
        Label(@"the", NSMakeRect(510, 112, 160, 76), 34, primary, NSFontWeightRegular);
        Label(@"and", NSMakeRect(681, 112, 160, 76), 34, primary, NSFontWeightRegular);
        Label(@"to", NSMakeRect(852, 112, 126, 76), 34, primary, NSFontWeightRegular);

        NSRectFill(NSMakeRect(1010, 111, 2, 78));
        Label(@"☀", NSMakeRect(1041, 108, 105, 84), 51, primary, NSFontWeightRegular);
        Label(@"♪", NSMakeRect(1162, 108, 105, 84), 48, primary, NSFontWeightRegular);
        Label(@"◉", NSMakeRect(1283, 108, 105, 84), 48, Color(101, 220, 234), NSFontWeightRegular);
        RoundedFill(NSMakeRect(1413, 119, 93, 62), 12, Color(42, 47, 55));
        Label(@"×", NSMakeRect(1413, 119, 93, 62), 48, primary, NSFontWeightRegular);

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:@(argv[1]) atomically:YES] ? 0 : 1;
    }
}
