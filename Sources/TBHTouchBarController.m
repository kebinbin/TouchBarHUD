#import "TBHTouchBarController.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <math.h>
#import <stdio.h>

// These signatures are reverse engineered, not an Apple compatibility contract.
typedef id (*TBHCreateSimulatorFn)(NSInteger, id, NSInteger);
typedef id (*TBHGetTouchBarFn)(id);
typedef id (*TBHGetMainFn)(void);
typedef NSInteger (*TBHGetStyleFn)(id);
typedef CGSize (*TBHScreenSizeFn)(void);
typedef CGDisplayStreamRef (*TBHCreateStreamFn)(id, uint32_t, dispatch_queue_t, CGDisplayStreamFrameAvailableHandler);
typedef void (*TBHInvalidateFn)(id);
typedef BOOL (*TBHPostEventFn)(id, NSEventType, NSPoint);
static const char *const TBHFrameworkPath = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation";
static const CFTimeInterval TBHMinimumFrameInterval = 1.0 / 30.0;

@implementation TBHTouchBarController {
    void *_framework;
    id _simulator;
    CGDisplayStreamRef _stream;
    TBHInvalidateFn _invalidate;
    TBHPostEventFn _postEvent;
    IOSurfaceRef _latestSurface;
    NSUInteger _generation;
    CFTimeInterval _lastDelivery;
    BOOL _ready;
    BOOL _deliveryScheduled;
    CGSize _sourceSize;
    NSString *_failureReason;
    NSUInteger _receivedFrameCount;
    NSUInteger _deliveredFrameCount;
}

- (instancetype)init {
    self = [super init];
    if (self) { _sourceSize = CGSizeMake(2170, 60); }
    return self;
}

- (CGSize)sourceSize { return _sourceSize; }
- (BOOL)isReady { return _ready; }
- (BOOL)supportsMouseInput { return _simulator && _postEvent; }
- (NSString *)failureReason { return _failureReason; }
- (IOSurfaceRef)latestSurface { return _latestSurface; }
- (NSUInteger)receivedFrameCount { return _receivedFrameCount; }
- (NSUInteger)deliveredFrameCount { return _deliveredFrameCount; }

- (void)clearSurface {
    if (_latestSurface) {
        IOSurfaceDecrementUseCount(_latestSurface);
        CFRelease(_latestSurface);
        _latestSurface = NULL;
    }
}

- (void)fail:(NSString *)reason {
    [self stop];
    _failureReason = [reason copy];
    if (self.stateHandler) { self.stateHandler(); }
}

- (BOOL)start {
    NSAssert(NSThread.isMainThread, @"Touch Bar lifecycle must run on the main thread");
    [self stop];
    _failureReason = nil;
    if (!_framework) { _framework = dlopen(TBHFrameworkPath, RTLD_LAZY | RTLD_LOCAL); }
    if (!_framework) {
        [self fail:@"DFRFoundation could not be loaded on this Mac."];
        return NO;
    }
    TBHCreateSimulatorFn createSimulator = (TBHCreateSimulatorFn)dlsym(_framework, "DFRTouchBarSimulatorCreate");
    TBHGetTouchBarFn getTouchBar = (TBHGetTouchBarFn)dlsym(_framework, "DFRTouchBarSimulatorGetTouchBar");
    TBHCreateStreamFn createStream = (TBHCreateStreamFn)dlsym(_framework, "DFRTouchBarCreateDisplayStream");
    TBHGetMainFn getMain = (TBHGetMainFn)dlsym(_framework, "DFRTouchBarGetMain");
    TBHGetStyleFn getStyle = (TBHGetStyleFn)dlsym(_framework, "DFRTouchBarGetStyle");
    TBHScreenSizeFn getSize = (TBHScreenSizeFn)dlsym(_framework, "DFRGetScreenSize");
    _invalidate = (TBHInvalidateFn)dlsym(_framework, "DFRTouchBarSimulatorInvalidate");
    _postEvent = (TBHPostEventFn)dlsym(_framework, "DFRTouchBarSimulatorPostEventWithMouseActivity");
    if (!createSimulator || !getTouchBar || !createStream || !_invalidate || !getMain) {
        [self fail:@"Required Touch Bar functions are unavailable on this macOS version."];
        return NO;
    }
    id physicalTouchBar = getMain();
    if (!physicalTouchBar) {
        [self fail:@"No physical Touch Bar is available on this Mac."];
        return NO;
    }
    if (getSize) {
        CGSize reported = getSize();
        if (isfinite(reported.width) && isfinite(reported.height) && reported.width > 0 &&
            reported.width <= 8192 && reported.height > 0 && reported.height <= 512) {
            _sourceSize = reported;
        }
    }
    NSInteger generation = getStyle ? getStyle(physicalTouchBar) : 3;
    if (generation != 2 && generation != 3) { generation = 3; }
    _simulator = createSimulator(generation, nil, generation);
    if (!_simulator && generation != 3) { _simulator = createSimulator(3, nil, 3); }
    if (!_simulator) {
        [self fail:@"The Touch Bar simulator could not be created. Quit other Touch Bar mirror apps and retry."];
        return NO;
    }
    id touchBar = getTouchBar(_simulator);
    if (!touchBar) {
        [self fail:@"The Touch Bar display is unavailable."];
        return NO;
    }
    NSUInteger token = _generation;
    __weak typeof(self) weakSelf = self;
    _stream = createStream(touchBar, 0, dispatch_get_main_queue(),
        ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
            (void)time;
            (void)update;
            TBHTouchBarController *controller = weakSelf;
            if (!controller || token != controller->_generation) { return; }
            if (status == kCGDisplayStreamFrameStatusStopped) {
                [controller fail:@"The Touch Bar stream stopped. Use Retry Touch Bar connection."];
                return;
            }
            if (status == kCGDisplayStreamFrameStatusFrameBlank) {
                [controller clearSurface];
                if (controller.frameHandler) { controller.frameHandler(); }
                return;
            }
            if (status != kCGDisplayStreamFrameStatusFrameComplete || !surface) { return; }
            [controller consumeSurface:surface];
        });
    if (!_stream) {
        [self fail:@"The Touch Bar display stream could not be created."];
        return NO;
    }
    CGError error = CGDisplayStreamStart(_stream);
    if (error != kCGErrorSuccess) {
        [self fail:[NSString stringWithFormat:@"Display stream error: %d", error]];
        return NO;
    }
    return YES;
}

- (void)consumeSurface:(IOSurfaceRef)surface {
    _receivedFrameCount++;
    CFRetain(surface);
    IOSurfaceIncrementUseCount(surface);
    [self clearSurface];
    _latestSurface = surface;
    [self scheduleDelivery];
}

- (void)deliverFrame {
    _deliveryScheduled = NO;
    _lastDelivery = CACurrentMediaTime();
    _deliveredFrameCount++;
    BOOL firstFrame = !_ready;
    _ready = YES;
    if (firstFrame && self.stateHandler) { self.stateHandler(); }
    if (self.frameHandler) { self.frameHandler(); }
}

- (void)scheduleDelivery {
    if (_deliveryScheduled) { return; }
    CFTimeInterval remaining = TBHMinimumFrameInterval - (CACurrentMediaTime() - _lastDelivery);
    if (remaining <= 0) {
        [self deliverFrame];
        return;
    }
    _deliveryScheduled = YES;
    NSUInteger token = _generation;
    __weak typeof(self) weakSelf = self;
    // Coalesce a burst into one delivery of its latest frame, including the final slider position.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TBHTouchBarController *controller = weakSelf;
        if (!controller || token != controller->_generation) { return; }
        controller->_deliveryScheduled = NO;
        if (controller->_latestSurface) { [controller deliverFrame]; }
    });
}

- (void)stop {
    _generation++; // Queued callbacks from an old stream must never touch a new session.
    if (_stream) {
        CGDisplayStreamStop(_stream);
        CFRelease(_stream);
        _stream = NULL;
    }
    if (_simulator && _invalidate) { _invalidate(_simulator); }
    _simulator = nil;
    _ready = NO;
    _lastDelivery = 0;
    _deliveryScheduled = NO;
    [self clearSurface];
}

- (BOOL)postMouseEvent:(NSEventType)type point:(NSPoint)point {
    return _simulator && _postEvent && _ready ? _postEvent(_simulator, type, point) : NO;
}

- (void)dealloc {
    [self stop];
    // Keep DFRFoundation loaded until process exit: stream teardown can finish asynchronously.
}

+ (int)checkFramework {
    void *handle = dlopen(TBHFrameworkPath, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "DFRFoundation: unavailable\n");
        return 1;
    }
    const char *required[] = {"DFRTouchBarSimulatorCreate", "DFRTouchBarSimulatorGetTouchBar",
        "DFRTouchBarCreateDisplayStream", "DFRTouchBarSimulatorInvalidate", "DFRTouchBarGetMain"};
    int missing = 0;
    for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
        BOOL found = dlsym(handle, required[i]) != NULL;
        printf("%s: %s\n", required[i], found ? "available" : "missing");
        missing += !found;
    }
    const char *optional[] = {"DFRTouchBarSimulatorPostEventWithMouseActivity", "DFRTouchBarGetStyle", "DFRGetScreenSize"};
    for (size_t i = 0; i < sizeof(optional) / sizeof(optional[0]); i++) {
        printf("%s: %s (optional)\n", optional[i], dlsym(handle, optional[i]) ? "available" : "missing");
    }
    dlclose(handle);
    return missing ? 1 : 0;
}
@end
