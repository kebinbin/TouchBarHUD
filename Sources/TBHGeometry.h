#import <Cocoa/Cocoa.h>

/// Sanitizes persisted numeric preferences before they reach AppKit geometry or timers.
FOUNDATION_EXPORT double TBHClampedValue(double value, double fallback, double minimum, double maximum);
/// Fits the calibrated visual width to the built-in screen, keeping manual corrections in bounds.
FOUNDATION_EXPORT NSRect TBHPanelFrame(NSRect screen, NSRect visible, CGSize source,
                                      CGFloat widthFraction, CGFloat widthAdjustment, CGFloat horizontalOffset);
FOUNDATION_EXPORT NSPoint TBHTouchPoint(NSPoint local, NSSize viewSize, CGSize inputSize);
