#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>

typedef id (*DFRTouchBarSimulatorCreateFn)(NSInteger generation, id properties, NSInteger matchingGeneration);
typedef id (*DFRTouchBarSimulatorGetTouchBarFn)(id simulator);
typedef NSInteger (*DFRTouchBarGetStyleFn)(id touchBar);
typedef id (*DFRTouchBarGetMainFn)(void);
typedef CGSize (*DFRGetScreenSizeFn)(void);
typedef CGDisplayStreamRef (*DFRTouchBarCreateDisplayStreamFn)(id touchBar,
                                                               uint32_t displayID,
                                                               dispatch_queue_t queue,
                                                               CGDisplayStreamFrameAvailableHandler handler);
typedef void (*DFRTouchBarSimulatorInvalidateFn)(id simulator);
typedef BOOL (*DFRTouchBarSimulatorPostEventFn)(id simulator, NSEventType type, NSPoint point);

static NSString *const TBHAutoRevealKey = @"autoReveal";
static NSString *const TBHHideDelayKey = @"hideDelay";
static NSString *const TBHPinnedKey = @"pinned";
static NSString *const TBHOpacityKey = @"hudOpacity";
static NSString *const TBHWidthAdjustmentKey = @"widthAdjustment";
static NSString *const TBHHorizontalOffsetKey = @"horizontalOffset";

@class AppDelegate;
static OSStatus TBHHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData);

@interface HUDPanel : NSPanel
@end

@implementation HUDPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface TouchBarSurfaceView : NSView
@property(nonatomic, strong) id simulator;
@property(nonatomic) DFRTouchBarSimulatorPostEventFn postEvent;
@property(nonatomic) CGSize inputSize;
@property(nonatomic, copy) void (^activityHandler)(void);
@property(nonatomic, copy) void (^hoverHandler)(BOOL inside);
@property(nonatomic) NSPoint wheelTouchPoint;
@property(nonatomic) NSTimeInterval lastWheelTimestamp;
@end

@implementation TouchBarSurfaceView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
                                    NSTrackingMouseMoved |
                                    NSTrackingActiveAlways |
                                    NSTrackingInVisibleRect;
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:options
                                                         owner:self
                                                      userInfo:nil]];
}

- (void)forwardMouseEvent:(NSEvent *)event {
    if (!self.simulator || !self.postEvent || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
        return;
    }
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    local.x = MIN(MAX(local.x, 0.0), self.bounds.size.width);
    local.y = MIN(MAX(local.y, 0.0), self.bounds.size.height);
    NSPoint touchPoint = NSMakePoint(local.x * self.inputSize.width / self.bounds.size.width,
                                     local.y * self.inputSize.height / self.bounds.size.height);
    self.postEvent(self.simulator, event.type, touchPoint);
    if (self.activityHandler) {
        self.activityHandler();
    }
}

- (NSPoint)touchPointForEvent:(NSEvent *)event {
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    local.x = MIN(MAX(local.x, 0.0), self.bounds.size.width);
    local.y = MIN(MAX(local.y, 0.0), self.bounds.size.height);
    return NSMakePoint(local.x * self.inputSize.width / MAX(self.bounds.size.width, 1.0),
                       local.y * self.inputSize.height / MAX(self.bounds.size.height, 1.0));
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.simulator || !self.postEvent) { return; }
    NSPoint pointerPoint = [self touchPointForEvent:event];
    if (event.timestamp - self.lastWheelTimestamp > 0.45) {
        self.wheelTouchPoint = pointerPoint;
    }
    self.lastWheelTimestamp = event.timestamp;

    CGFloat delta = fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)
        ? event.scrollingDeltaY
        : event.scrollingDeltaX;
    CGFloat sensitivity = event.hasPreciseScrollingDeltas ? 2.5 : 18.0;
    NSPoint nextPoint = self.wheelTouchPoint;
    nextPoint.x = MIN(MAX(nextPoint.x + delta * sensitivity, 0.0), self.inputSize.width);

    self.postEvent(self.simulator, NSEventTypeLeftMouseDown, self.wheelTouchPoint);
    self.postEvent(self.simulator, NSEventTypeLeftMouseDragged, nextPoint);
    self.postEvent(self.simulator, NSEventTypeLeftMouseUp, nextPoint);
    self.wheelTouchPoint = nextPoint;
    if (self.activityHandler) {
        self.activityHandler();
    }
}

- (void)mouseDown:(NSEvent *)event { [self forwardMouseEvent:event]; }
- (void)mouseUp:(NSEvent *)event { [self forwardMouseEvent:event]; }
- (void)mouseDragged:(NSEvent *)event { [self forwardMouseEvent:event]; }
- (void)mouseMoved:(NSEvent *)event {
    (void)event;
    // First-generation Touch Bars accept down/up/drag input. Sending hover as
    // simulated Touch Bar activity can dismiss transient Control Strip views.
}
- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    if (self.hoverHandler) {
        self.hoverHandler(YES);
    }
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    // Mouse-exit is a window event, not a Touch Bar input event. Forwarding it
    // can make transient Control Strip layouts collapse immediately.
    if (self.hoverHandler) {
        self.hoverHandler(NO);
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) HUDPanel *panel;
@property(nonatomic, strong) TouchBarSurfaceView *surfaceView;
@property(nonatomic, strong) NSTimer *hideTimer;
@property(nonatomic, strong) id simulator;
@property(nonatomic) CGDisplayStreamRef displayStream;
@property(nonatomic) void *dfrHandle;
@property(nonatomic) DFRTouchBarSimulatorInvalidateFn invalidateSimulator;
@property(nonatomic) EventHotKeyRef hotKeyRef;
@property(nonatomic) id globalEventMonitor;
@property(nonatomic) BOOL streamReady;
@property(nonatomic) BOOL receivedInitialFrame;
@property(nonatomic) BOOL autoReveal;
@property(nonatomic) BOOL pinned;
@property(nonatomic) BOOL mouseInputReady;
@property(nonatomic) BOOL mouseInsideHUD;
@property(nonatomic) BOOL accessibilityTrusted;
@property(nonatomic) NSTimeInterval hideDelay;
@property(nonatomic) CGFloat hudOpacity;
@property(nonatomic) CGSize sourceSize;
@property(nonatomic) CGFloat widthAdjustment;
@property(nonatomic) CGFloat horizontalOffset;
@property(nonatomic) NSUInteger visibilityGeneration;
@property(nonatomic, strong) NSMenuItem *visibilityMenuItem;
@property(nonatomic, strong) NSMenuItem *autoRevealMenuItem;
@property(nonatomic, strong) NSMenuItem *pinnedMenuItem;
@property(nonatomic, strong) NSMenuItem *accessibilityMenuItem;
@property(nonatomic, strong) id screenParametersObserver;
- (void)toggleHUD;
- (void)revealHUDForActivity:(BOOL)isActivity;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSDictionary *defaults = @{
        TBHAutoRevealKey: @YES,
        TBHHideDelayKey: @3.0,
        TBHPinnedKey: @NO,
        TBHOpacityKey: @1.0,
        TBHWidthAdjustmentKey: @0.0,
        TBHHorizontalOffsetKey: @0.0
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    self.autoReveal = [[NSUserDefaults standardUserDefaults] boolForKey:TBHAutoRevealKey];
    self.hideDelay = [[NSUserDefaults standardUserDefaults] doubleForKey:TBHHideDelayKey];
    if (self.hideDelay < 1.0) {
        self.hideDelay = 1.0;
        [[NSUserDefaults standardUserDefaults] setDouble:self.hideDelay forKey:TBHHideDelayKey];
    }
    self.pinned = [[NSUserDefaults standardUserDefaults] boolForKey:TBHPinnedKey];
    self.hudOpacity = [[NSUserDefaults standardUserDefaults] doubleForKey:TBHOpacityKey];
    self.widthAdjustment = [[NSUserDefaults standardUserDefaults] doubleForKey:TBHWidthAdjustmentKey];
    self.horizontalOffset = [[NSUserDefaults standardUserDefaults] doubleForKey:TBHHorizontalOffsetKey];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self createPanel];
    [self createStatusItem];
    [self refreshAccessibilityPermissionWithPrompt:YES];
    [self registerGlobalShortcut];
    [self installBestEffortEventMonitor];
    [self startTouchBarStream];

    __weak typeof(self) weakSelf = self;
    self.screenParametersObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidChangeScreenParametersNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        (void)note;
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (![strongSelf builtInScreen]) {
            [strongSelf.panel orderOut:nil];
            strongSelf.visibilityMenuItem.title = @"Show Touch Bar";
            return;
        }
        [strongSelf positionPanel];
    }];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.hideTimer invalidate];
    if (self.screenParametersObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.screenParametersObserver];
        self.screenParametersObserver = nil;
    }
    if (self.globalEventMonitor) {
        [NSEvent removeMonitor:self.globalEventMonitor];
        self.globalEventMonitor = nil;
    }
    if (self.hotKeyRef) {
        UnregisterEventHotKey(self.hotKeyRef);
        self.hotKeyRef = NULL;
    }
    if (self.displayStream) {
        CGDisplayStreamStop(self.displayStream);
        CFRelease(self.displayStream);
        self.displayStream = NULL;
    }
    if (self.invalidateSimulator && self.simulator) {
        self.invalidateSimulator(self.simulator);
    }
    self.simulator = nil;
    if (self.dfrHandle) {
        dlclose(self.dfrHandle);
        self.dfrHandle = NULL;
    }
}

- (NSScreen *)builtInScreen {
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        if (screenNumber && CGDisplayIsBuiltin(screenNumber.unsignedIntValue)) {
            return screen;
        }
    }
    return nil;
}

- (void)createPanel {
    self.sourceSize = CGSizeMake(2170.0, 60.0);
    self.panel = [[HUDPanel alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 58)
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.ignoresMouseEvents = NO;
    self.panel.acceptsMouseMovedEvents = YES;
    self.panel.becomesKeyOnlyIfNeeded = YES;
    self.panel.level = NSStatusWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorStationary;

    NSView *container = [[NSView alloc] initWithFrame:self.panel.contentView.bounds];
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    container.wantsLayer = YES;
    container.layer.backgroundColor = NSColor.blackColor.CGColor;
    container.layer.cornerRadius = 9.0;
    container.layer.masksToBounds = YES;

    self.surfaceView = [[TouchBarSurfaceView alloc] initWithFrame:NSInsetRect(container.bounds, 6, 6)];
    self.surfaceView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.surfaceView.wantsLayer = YES;
    self.surfaceView.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.surfaceView.layer.contentsGravity = kCAGravityResizeAspect;
    self.surfaceView.layer.magnificationFilter = kCAFilterLinear;
    self.surfaceView.layer.minificationFilter = kCAFilterLinear;
    self.surfaceView.inputSize = self.sourceSize;
    __weak typeof(self) weakSelf = self;
    self.surfaceView.activityHandler = ^{
        [weakSelf revealHUDForActivity:NO];
    };
    self.surfaceView.hoverHandler = ^(BOOL inside) {
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        strongSelf.mouseInsideHUD = inside;
        [strongSelf.hideTimer invalidate];
        strongSelf.hideTimer = nil;
        if (!inside && strongSelf.panel.isVisible && !strongSelf.pinned) {
            [strongSelf revealHUDForActivity:NO];
        }
    };
    [container addSubview:self.surfaceView];

    self.panel.contentView = container;
    self.panel.alphaValue = 0.0;
    [self positionPanel];
}

- (void)positionPanel {
    NSScreen *screen = [self builtInScreen];
    if (!screen) { return; }
    NSRect screenFrame = screen.frame;
    NSRect visible = screen.visibleFrame;
    // A 15-inch A1990 uses a 2880-pixel-wide panel and a 2170-pixel-wide
    // first-generation Touch Bar. This keeps their physical X scales matched
    // even when macOS is using a non-default scaled display resolution.
    CGFloat visualWidth = screenFrame.size.width * (2170.0 / 2880.0) + self.widthAdjustment;
    visualWidth = MIN(visualWidth, screenFrame.size.width - 24.0);
    visualWidth = MAX(visualWidth, 700.0);
    CGFloat visualHeight = visualWidth * (self.sourceSize.height / MAX(self.sourceSize.width, 1.0));
    CGFloat width = visualWidth + 12.0;
    CGFloat height = visualHeight + 12.0;
    CGFloat x = NSMidX(screenFrame) - width / 2.0 + self.horizontalOffset;
    CGFloat y = NSMinY(visible) + 8.0;
    [self.panel setFrame:NSMakeRect(round(x), round(y), round(width), round(height)) display:YES];
}

- (void)createStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    if (@available(macOS 11.0, *)) {
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"rectangle.bottomthird.inset.filled"
                                                 accessibilityDescription:@"TouchBar HUD"];
    } else {
        self.statusItem.button.title = @"TB";
    }
    self.statusItem.button.toolTip = @"TouchBar HUD";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"TouchBar HUD"];
    self.visibilityMenuItem = [[NSMenuItem alloc] initWithTitle:@"Show Touch Bar"
                                                         action:@selector(toggleFromMenu:)
                                                  keyEquivalent:@"t"];
    self.visibilityMenuItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    self.visibilityMenuItem.target = self;
    [menu addItem:self.visibilityMenuItem];

    self.autoRevealMenuItem = [[NSMenuItem alloc] initWithTitle:@"Reveal on Touch Bar activity"
                                                         action:@selector(toggleAutoReveal:)
                                                  keyEquivalent:@""];
    self.autoRevealMenuItem.target = self;
    self.autoRevealMenuItem.state = self.autoReveal ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:self.autoRevealMenuItem];

    self.pinnedMenuItem = [[NSMenuItem alloc] initWithTitle:@"Keep visible"
                                                     action:@selector(togglePinned:)
                                              keyEquivalent:@""];
    self.pinnedMenuItem.target = self;
    self.pinnedMenuItem.state = self.pinned ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:self.pinnedMenuItem];

    self.accessibilityMenuItem = [[NSMenuItem alloc] initWithTitle:@"Enable mouse control…"
                                                            action:@selector(requestAccessibilityPermission:)
                                                     keyEquivalent:@""];
    self.accessibilityMenuItem.target = self;
    [menu addItem:self.accessibilityMenuItem];

    NSMenu *delayMenu = [[NSMenu alloc] initWithTitle:@"Hide Delay"];
    for (NSNumber *seconds in @[@1.0, @2.0, @3.0, @5.0, @8.0]) {
        NSString *title = nil;
        if (seconds.doubleValue == 1.0) {
            title = @"1 second";
        } else {
            title = [NSString stringWithFormat:@"%@ seconds", seconds];
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(selectHideDelay:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = seconds;
        item.state = fabs(seconds.doubleValue - self.hideDelay) < 0.01 ? NSControlStateValueOn : NSControlStateValueOff;
        [delayMenu addItem:item];
    }
    NSMenuItem *delayRoot = [[NSMenuItem alloc] initWithTitle:@"Hide after" action:nil keyEquivalent:@""];
    delayRoot.submenu = delayMenu;
    [menu addItem:delayRoot];

    NSMenu *opacityMenu = [[NSMenu alloc] initWithTitle:@"Opacity"];
    for (NSNumber *percent in @[@35, @50, @65, @80, @90, @100]) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:[NSString stringWithFormat:@"%@%%", percent]
                   action:@selector(selectOpacity:)
            keyEquivalent:@""];
        item.target = self;
        item.representedObject = percent;
        CGFloat opacity = percent.doubleValue / 100.0;
        item.state = fabs(opacity - self.hudOpacity) < 0.001
            ? NSControlStateValueOn
            : NSControlStateValueOff;
        [opacityMenu addItem:item];
    }
    NSMenuItem *opacityRoot = [[NSMenuItem alloc] initWithTitle:@"Opacity" action:nil keyEquivalent:@""];
    opacityRoot.submenu = opacityMenu;
    [menu addItem:opacityRoot];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *reposition = [[NSMenuItem alloc] initWithTitle:@"Move to bottom of built-in display"
                                                        action:@selector(reposition:)
                                                 keyEquivalent:@""];
    reposition.target = self;
    [menu addItem:reposition];

    NSMenu *alignmentMenu = [[NSMenu alloc] initWithTitle:@"Physical Alignment"];
    NSArray<NSDictionary *> *alignmentActions = @[
        @{@"title": @"Move left 5 pt", @"action": NSStringFromSelector(@selector(moveLeft:))},
        @{@"title": @"Move right 5 pt", @"action": NSStringFromSelector(@selector(moveRight:))},
        @{@"title": @"Make 10 pt narrower", @"action": NSStringFromSelector(@selector(makeNarrower:))},
        @{@"title": @"Make 10 pt wider", @"action": NSStringFromSelector(@selector(makeWider:))},
        @{@"title": @"Reset A1990 alignment", @"action": NSStringFromSelector(@selector(resetAlignment:))}
    ];
    for (NSDictionary *definition in alignmentActions) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:definition[@"title"]
                                                      action:NSSelectorFromString(definition[@"action"])
                                               keyEquivalent:@""];
        item.target = self;
        [alignmentMenu addItem:item];
    }
    NSMenuItem *alignmentRoot = [[NSMenuItem alloc] initWithTitle:@"Physical alignment"
                                                           action:nil
                                                    keyEquivalent:@""];
    alignmentRoot.submenu = alignmentMenu;
    [menu addItem:alignmentRoot];

    NSMenuItem *diagnostics = [[NSMenuItem alloc] initWithTitle:@"Diagnostics…"
                                                         action:@selector(showDiagnostics:)
                                                  keyEquivalent:@""];
    diagnostics.target = self;
    [menu addItem:diagnostics];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit TouchBar HUD"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)registerGlobalShortcut {
    EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&TBHHotKeyHandler, 1, &eventType, (__bridge void *)self, NULL);
    EventHotKeyID hotKeyID = { 'TBHD', 1 };
    RegisterEventHotKey(kVK_ANSI_T,
                        cmdKey | optionKey,
                        hotKeyID,
                        GetApplicationEventTarget(),
                        0,
                        &_hotKeyRef);
}

- (void)installBestEffortEventMonitor {
    __weak typeof(self) weakSelf = self;
    self.globalEventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskSystemDefined | NSEventMaskDirectTouch)
                                                                    handler:^(NSEvent *event) {
        (void)event;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf revealHUDForActivity:YES];
        });
    }];
}

- (void)startTouchBarStream {
    const char *path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation";
    self.dfrHandle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (!self.dfrHandle) {
        [self setStatusFailure:@"DFRFoundation could not be loaded"];
        return;
    }

    DFRTouchBarSimulatorCreateFn createSimulator = (DFRTouchBarSimulatorCreateFn)dlsym(self.dfrHandle, "DFRTouchBarSimulatorCreate");
    DFRTouchBarSimulatorGetTouchBarFn getTouchBar = (DFRTouchBarSimulatorGetTouchBarFn)dlsym(self.dfrHandle, "DFRTouchBarSimulatorGetTouchBar");
    DFRTouchBarCreateDisplayStreamFn createStream = (DFRTouchBarCreateDisplayStreamFn)dlsym(self.dfrHandle, "DFRTouchBarCreateDisplayStream");
    DFRTouchBarSimulatorPostEventFn postEvent = (DFRTouchBarSimulatorPostEventFn)dlsym(self.dfrHandle, "DFRTouchBarSimulatorPostEventWithMouseActivity");
    DFRTouchBarGetMainFn getMain = (DFRTouchBarGetMainFn)dlsym(self.dfrHandle, "DFRTouchBarGetMain");
    DFRTouchBarGetStyleFn getStyle = (DFRTouchBarGetStyleFn)dlsym(self.dfrHandle, "DFRTouchBarGetStyle");
    DFRGetScreenSizeFn getScreenSize = (DFRGetScreenSizeFn)dlsym(self.dfrHandle, "DFRGetScreenSize");
    self.invalidateSimulator = (DFRTouchBarSimulatorInvalidateFn)dlsym(self.dfrHandle, "DFRTouchBarSimulatorInvalidate");

    if (!createSimulator || !getTouchBar || !createStream) {
        [self setStatusFailure:@"Required Touch Bar functions are unavailable"];
        return;
    }

    if (getScreenSize) {
        CGSize reported = getScreenSize();
        if (reported.width > 0 && reported.height > 0) {
            self.sourceSize = reported;
            self.surfaceView.inputSize = reported;
            [self positionPanel];
        }
    }

    NSInteger generation = 3;
    if (getMain && getStyle) {
        id mainTouchBar = getMain();
        if (mainTouchBar) {
            NSInteger reportedStyle = getStyle(mainTouchBar);
            if (reportedStyle == 2 || reportedStyle == 3) {
                generation = reportedStyle;
            }
        }
    }

    self.simulator = createSimulator(generation, nil, generation);
    if (!self.simulator && generation != 3) {
        self.simulator = createSimulator(3, nil, 3);
    }
    if (!self.simulator) {
        [self setStatusFailure:@"The Touch Bar simulator could not be created"];
        return;
    }
    self.surfaceView.simulator = self.simulator;
    self.surfaceView.postEvent = postEvent;
    self.mouseInputReady = postEvent != NULL && self.accessibilityTrusted;

    id touchBar = getTouchBar(self.simulator);
    if (!touchBar) {
        [self setStatusFailure:@"The Touch Bar display is unavailable"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.displayStream = createStream(touchBar, 0, dispatch_get_main_queue(),
        ^(CGDisplayStreamFrameStatus status,
          uint64_t displayTime,
          IOSurfaceRef frameSurface,
          CGDisplayStreamUpdateRef updateRef) {
            (void)displayTime;
            (void)updateRef;
            AppDelegate *strongSelf = weakSelf;
            if (!strongSelf || status != kCGDisplayStreamFrameStatusFrameComplete || !frameSurface) {
                return;
            }
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            strongSelf.surfaceView.layer.contents = (__bridge id)frameSurface;
            [CATransaction commit];

            BOOL wasInitial = !strongSelf.receivedInitialFrame;
            strongSelf.receivedInitialFrame = YES;
            strongSelf.streamReady = YES;
            if (strongSelf.autoReveal || wasInitial) {
                [strongSelf revealHUDForActivity:YES];
            }
        });

    if (!self.displayStream) {
        [self setStatusFailure:@"The Touch Bar display stream could not be started"];
        return;
    }

    CGError error = CGDisplayStreamStart(self.displayStream);
    if (error != kCGErrorSuccess) {
        [self setStatusFailure:[NSString stringWithFormat:@"Display stream error: %d", error]];
    }
}

- (void)setStatusFailure:(NSString *)message {
    self.streamReady = NO;
    self.statusItem.button.image = nil;
    self.statusItem.button.title = @"TB!";
    self.statusItem.button.toolTip = message;
}

- (void)refreshAccessibilityPermissionWithPrompt:(BOOL)prompt {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    self.accessibilityTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    if (self.accessibilityMenuItem) {
        self.accessibilityMenuItem.title = self.accessibilityTrusted
            ? @"Mouse control permission: enabled"
            : @"Enable mouse control…";
        self.accessibilityMenuItem.enabled = !self.accessibilityTrusted;
    }
    if (self.surfaceView.postEvent) {
        self.mouseInputReady = self.accessibilityTrusted;
    }
}

- (void)requestAccessibilityPermission:(id)sender {
    (void)sender;
    [self refreshAccessibilityPermissionWithPrompt:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self refreshAccessibilityPermissionWithPrompt:NO];
    });
}

- (void)revealHUDForActivity:(BOOL)isActivity {
    if (isActivity && !self.autoReveal && !self.panel.isVisible) {
        return;
    }
    if (![self builtInScreen]) {
        [self.panel orderOut:nil];
        self.visibilityMenuItem.title = @"Show Touch Bar";
        return;
    }
    [self positionPanel];
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    self.visibilityGeneration++;

    if (!self.panel.isVisible) {
        self.panel.alphaValue = 0.0;
        [self.panel orderFrontRegardless];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.12;
            self.panel.animator.alphaValue = self.hudOpacity;
        } completionHandler:nil];
    } else {
        self.panel.alphaValue = self.hudOpacity;
    }
    self.visibilityMenuItem.title = @"Hide Touch Bar";

    BOOL pointerInside = self.panel.isVisible && NSPointInRect(NSEvent.mouseLocation, self.panel.frame);
    if (!self.pinned && !self.mouseInsideHUD && !pointerInside) {
        self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:self.hideDelay
                                                          target:self
                                                        selector:@selector(hideHUD:)
                                                        userInfo:nil
                                                         repeats:NO];
    }
}

- (void)hideHUD:(id)sender {
    (void)sender;
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    if (!self.panel.isVisible) { return; }
    BOOL pointerInside = NSPointInRect(NSEvent.mouseLocation, self.panel.frame);
    if (self.pinned || self.mouseInsideHUD || pointerInside) {
        return;
    }
    NSUInteger hideGeneration = ++self.visibilityGeneration;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.16;
        self.panel.animator.alphaValue = 0.0;
    } completionHandler:^{
        if (hideGeneration != self.visibilityGeneration || self.pinned || self.mouseInsideHUD ||
            NSPointInRect(NSEvent.mouseLocation, self.panel.frame)) {
            self.panel.alphaValue = self.hudOpacity;
            return;
        }
        [self.panel orderOut:nil];
        self.visibilityMenuItem.title = @"Show Touch Bar";
    }];
}

- (void)toggleHUD {
    if (self.panel.isVisible && self.panel.alphaValue > 0.05) {
        [self hideHUD:nil];
    } else {
        [self revealHUDForActivity:NO];
    }
}

- (void)toggleFromMenu:(id)sender {
    (void)sender;
    [self toggleHUD];
}

- (void)toggleAutoReveal:(NSMenuItem *)sender {
    self.autoReveal = !self.autoReveal;
    sender.state = self.autoReveal ? NSControlStateValueOn : NSControlStateValueOff;
    [[NSUserDefaults standardUserDefaults] setBool:self.autoReveal forKey:TBHAutoRevealKey];
}

- (void)togglePinned:(NSMenuItem *)sender {
    self.pinned = !self.pinned;
    sender.state = self.pinned ? NSControlStateValueOn : NSControlStateValueOff;
    [[NSUserDefaults standardUserDefaults] setBool:self.pinned forKey:TBHPinnedKey];
    if (self.pinned) {
        [self.hideTimer invalidate];
        self.hideTimer = nil;
        [self revealHUDForActivity:NO];
    } else if (self.panel.isVisible) {
        [self revealHUDForActivity:NO];
    }
}

- (void)selectHideDelay:(NSMenuItem *)sender {
    self.hideDelay = [sender.representedObject doubleValue];
    [[NSUserDefaults standardUserDefaults] setDouble:self.hideDelay forKey:TBHHideDelayKey];
    for (NSMenuItem *item in sender.menu.itemArray) {
        item.state = (item == sender) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (self.panel.isVisible && !self.pinned) {
        [self revealHUDForActivity:NO];
    }
}

- (void)selectOpacity:(NSMenuItem *)sender {
    self.hudOpacity = [sender.representedObject doubleValue] / 100.0;
    [[NSUserDefaults standardUserDefaults] setDouble:self.hudOpacity forKey:TBHOpacityKey];
    for (NSMenuItem *item in sender.menu.itemArray) {
        item.state = (item == sender) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (self.panel.isVisible) {
        self.panel.alphaValue = self.hudOpacity;
    }
}

- (void)reposition:(id)sender {
    (void)sender;
    [self positionPanel];
    [self revealHUDForActivity:NO];
}

- (void)saveAlignmentAndReposition {
    [[NSUserDefaults standardUserDefaults] setDouble:self.widthAdjustment forKey:TBHWidthAdjustmentKey];
    [[NSUserDefaults standardUserDefaults] setDouble:self.horizontalOffset forKey:TBHHorizontalOffsetKey];
    [self positionPanel];
    [self revealHUDForActivity:NO];
}

- (void)moveLeft:(id)sender {
    (void)sender;
    self.horizontalOffset -= 5.0;
    [self saveAlignmentAndReposition];
}

- (void)moveRight:(id)sender {
    (void)sender;
    self.horizontalOffset += 5.0;
    [self saveAlignmentAndReposition];
}

- (void)makeNarrower:(id)sender {
    (void)sender;
    self.widthAdjustment -= 10.0;
    [self saveAlignmentAndReposition];
}

- (void)makeWider:(id)sender {
    (void)sender;
    self.widthAdjustment += 10.0;
    [self saveAlignmentAndReposition];
}

- (void)resetAlignment:(id)sender {
    (void)sender;
    self.widthAdjustment = 0.0;
    self.horizontalOffset = 0.0;
    [self saveAlignmentAndReposition];
}

- (void)showDiagnostics:(id)sender {
    (void)sender;
    NSString *status = self.streamReady ? @"Touch Bar stream: active" : @"Touch Bar stream: unavailable";
    NSString *details = [NSString stringWithFormat:
        @"%@\nMouse input: %@\nAccessibility permission: %@\n\nShortcut: ⌥⌘T\nAuto reveal: %@\nHide delay: %.0f seconds\nOpacity: %.0f%%\n"
         "Alignment: width %+.0f pt, horizontal %+.0f pt\n\n"
         "Automatic reveal responds to Touch Bar display activity and supported system touch events. "
         "Because Apple does not publish these APIs, an occasional app-driven layout change may also reveal the HUD.",
        status,
        self.mouseInputReady ? @"active" : @"unavailable",
        self.accessibilityTrusted ? @"enabled" : @"required",
        self.autoReveal ? @"On" : @"Off",
        self.hideDelay,
        self.hudOpacity * 100.0,
        self.widthAdjustment,
        self.horizontalOffset];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"TouchBar HUD Diagnostics";
    alert.informativeText = details;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

static OSStatus TBHHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    (void)nextHandler;
    (void)event;
    AppDelegate *delegate = (__bridge AppDelegate *)userData;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate toggleHUD];
    });
    return noErr;
}

static int TBHRunFrameworkCheck(void) {
    const char *path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation";
    void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "DFRFoundation: unavailable\n");
        return 1;
    }

    const char *symbols[] = {
        "DFRTouchBarSimulatorCreate",
        "DFRTouchBarSimulatorGetTouchBar",
        "DFRTouchBarCreateDisplayStream",
        "DFRTouchBarSimulatorPostEventWithMouseActivity",
        "DFRTouchBarSimulatorInvalidate",
        "DFRTouchBarGetMain",
        "DFRTouchBarGetStyle",
        "DFRGetScreenSize"
    };
    int missing = 0;
    for (size_t index = 0; index < sizeof(symbols) / sizeof(symbols[0]); index++) {
        BOOL found = dlsym(handle, symbols[index]) != NULL;
        printf("%s: %s\n", symbols[index], found ? "available" : "missing");
        if (!found && index < 4) {
            missing++;
        }
    }
    DFRGetScreenSizeFn getScreenSize = (DFRGetScreenSizeFn)dlsym(handle, "DFRGetScreenSize");
    if (getScreenSize) {
        CGSize size = getScreenSize();
        printf("Touch Bar screen size: %.0f x %.0f\n", size.width, size.height);
    }
    dlclose(handle);
    return missing == 0 ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    if (argc == 2 && strcmp(argv[1], "--check-framework") == 0) {
        return TBHRunFrameworkCheck();
    }
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
