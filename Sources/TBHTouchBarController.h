#import <Cocoa/Cocoa.h>
#import <IOSurface/IOSurface.h>

NS_ASSUME_NONNULL_BEGIN
/// Main-thread-only adapter for undocumented DFRFoundation APIs. No polling or automatic retry loop.
@interface TBHTouchBarController : NSObject
@property(nonatomic, readonly) CGSize sourceSize;
@property(nonatomic, readonly, getter=isReady) BOOL ready;
@property(nonatomic, readonly) BOOL supportsMouseInput;
@property(nonatomic, readonly, nullable) NSString *failureReason;
/// Valid until the next frame or stop. Consumers retaining it must also increment its IOSurface use count.
@property(nonatomic, readonly, nullable) IOSurfaceRef latestSurface;
@property(nonatomic, copy, nullable) void (^frameHandler)(void);
@property(nonatomic, copy, nullable) void (^stateHandler)(void);
@property(nonatomic, readonly) NSUInteger receivedFrameCount;
@property(nonatomic, readonly) NSUInteger deliveredFrameCount;
- (BOOL)start;
- (void)stop;
- (BOOL)postMouseEvent:(NSEventType)type point:(NSPoint)point;
+ (int)checkFramework;
@end
NS_ASSUME_NONNULL_END
