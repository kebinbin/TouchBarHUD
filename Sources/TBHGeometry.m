#import "TBHGeometry.h"
#import <math.h>

double TBHClampedValue(double value, double fallback, double minimum, double maximum) {
    return isfinite(value) ? MIN(MAX(value, minimum), maximum) : fallback;
}

NSRect TBHPanelFrame(NSRect screen, NSRect visible, CGSize source,
                     CGFloat widthFraction, CGFloat widthAdjustment, CGFloat horizontalOffset) {
    CGFloat maximumWidth = MAX(1.0, screen.size.width - 24.0);
    CGFloat visualWidth = TBHClampedValue(screen.size.width * TBHClampedValue(widthFraction, 2170.0 / 2880.0, 0.05, 1.0) + widthAdjustment,
                                         maximumWidth, MIN(100.0, maximumWidth), maximumWidth);
    CGFloat ratio = source.width > 0 && source.height > 0 ? source.height / source.width : 60.0 / 2170.0;
    CGFloat width = round(visualWidth + 12.0);
    CGFloat height = round(MIN(visualWidth * ratio + 12.0, MAX(1.0, visible.size.height - 16.0)));
    CGFloat x = NSMidX(screen) - width / 2.0 + TBHClampedValue(horizontalOffset, 0, -screen.size.width, screen.size.width);
    x = MIN(MAX(round(x), NSMinX(screen) + 6.0), NSMaxX(screen) - width - 6.0);
    return NSMakeRect(x, round(NSMinY(visible) + 8.0), width, height);
}

NSPoint TBHTouchPoint(NSPoint local, NSSize viewSize, CGSize inputSize) {
    if (viewSize.width <= 0 || viewSize.height <= 0 || inputSize.width <= 0 || inputSize.height <= 0) {
        return NSZeroPoint;
    }
    return NSMakePoint(MIN(MAX(local.x / viewSize.width, 0), 1) * inputSize.width,
                       MIN(MAX(local.y / viewSize.height, 0), 1) * inputSize.height);
}
