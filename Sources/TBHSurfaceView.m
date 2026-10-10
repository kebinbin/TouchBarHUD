#import "TBHSurfaceView.h"
#import "TBHGeometry.h"
#import <QuartzCore/QuartzCore.h>

@implementation TBHSurfaceView {
    IOSurfaceRef _displayedSurface;
    BOOL _mouseDownForwarded;
    NSPoint _lastTouchPoint;
    NSPoint _wheelTouchPoint;
    NSTimeInterval _lastWheelTimestamp;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (BOOL)pointerInside {
    NSPoint point = [self convertPoint:[self.window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
    return self.window.isVisible && NSPointInRect(point, self.bounds);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) { [self removeTrackingArea:area]; }
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self userInfo:nil]];
}

- (void)displaySurface:(IOSurfaceRef)surface {
    if (surface == _displayedSurface) { return; }
    if (surface) {
        CFRetain(surface);
        IOSurfaceIncrementUseCount(surface);
    }
    IOSurfaceRef previous = _displayedSurface;
    _displayedSurface = surface;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // CALayer may still render the previous surface until this transaction completes.
    [CATransaction setCompletionBlock:^{
        if (previous) {
            IOSurfaceDecrementUseCount(previous);
            CFRelease(previous);
        }
    }];
    self.layer.contents = (__bridge id)surface;
    [CATransaction commit];
}

- (NSPoint)touchPointForEvent:(NSEvent *)event {
    return TBHTouchPoint([self convertPoint:event.locationInWindow fromView:nil], self.bounds.size, self.inputSize);
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.inputEnabled || !self.eventHandler) { return; }
    [self cancelInteraction];
    _lastTouchPoint = [self touchPointForEvent:event];
    _mouseDownForwarded = self.eventHandler(NSEventTypeLeftMouseDown, _lastTouchPoint);
    if (_mouseDownForwarded && self.activityHandler) { self.activityHandler(); }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_mouseDownForwarded || !self.eventHandler) { return; }
    _lastTouchPoint = [self touchPointForEvent:event];
    self.eventHandler(NSEventTypeLeftMouseDragged, _lastTouchPoint);
    if (self.activityHandler) { self.activityHandler(); }
}

- (void)mouseUp:(NSEvent *)event {
    _lastTouchPoint = [self touchPointForEvent:event];
    [self cancelInteraction];
    if (self.activityHandler) { self.activityHandler(); }
}

- (void)cancelInteraction {
    if (_mouseDownForwarded && self.eventHandler) {
        self.eventHandler(NSEventTypeLeftMouseUp, _lastTouchPoint);
    }
    _mouseDownForwarded = NO;
    _lastWheelTimestamp = 0;
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.inputEnabled || !self.eventHandler || _mouseDownForwarded ||
        event.momentumPhase != NSEventPhaseNone) { return; }
    CGFloat delta = fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)
        ? event.scrollingDeltaY : event.scrollingDeltaX;
    if (!isfinite(delta) || delta == 0) { return; }
    if (_lastWheelTimestamp == 0 || event.phase == NSEventPhaseBegan || event.timestamp - _lastWheelTimestamp > 0.45) {
        _wheelTouchPoint = [self touchPointForEvent:event];
    }
    _lastWheelTimestamp = event.timestamp;
    CGFloat sensitivity = event.hasPreciseScrollingDeltas ? 2.5 : 18.0;
    NSPoint next = NSMakePoint(MIN(MAX(_wheelTouchPoint.x + delta * sensitivity, 0), self.inputSize.width), _wheelTouchPoint.y);
    if (self.eventHandler(NSEventTypeLeftMouseDown, _wheelTouchPoint)) {
        self.eventHandler(NSEventTypeLeftMouseDragged, next);
        self.eventHandler(NSEventTypeLeftMouseUp, next);
        _wheelTouchPoint = next;
        if (self.activityHandler) { self.activityHandler(); }
    }
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    if (self.hoverHandler) { self.hoverHandler(YES); }
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    // Hover is a window event; forwarding it can collapse transient Control Strip controls.
    if (self.hoverHandler) { self.hoverHandler(NO); }
}

- (void)dealloc {
    if (_displayedSurface) {
        IOSurfaceDecrementUseCount(_displayedSurface);
        CFRelease(_displayedSurface);
    }
}
@end
