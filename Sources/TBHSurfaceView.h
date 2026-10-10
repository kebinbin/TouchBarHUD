#import <Cocoa/Cocoa.h>
#import <IOSurface/IOSurface.h>

NS_ASSUME_NONNULL_BEGIN
@interface TBHSurfaceView : NSView
@property(nonatomic) CGSize inputSize;
@property(nonatomic) BOOL inputEnabled;
@property(nonatomic, copy, nullable) BOOL (^eventHandler)(NSEventType type, NSPoint point);
@property(nonatomic, copy, nullable) void (^activityHandler)(void);
@property(nonatomic, copy, nullable) void (^hoverHandler)(BOOL inside);
@property(nonatomic, readonly) BOOL pointerInside;
- (void)displaySurface:(nullable IOSurfaceRef)surface;
- (void)cancelInteraction;
@end
NS_ASSUME_NONNULL_END
