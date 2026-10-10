#import "TBHAppDelegate.h"
#import "TBHGeometry.h"
#import "TBHDeviceSizing.h"
#import "TBHSurfaceView.h"
#import "TBHTouchBarController.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>

static NSString *const TBHAutoRevealKey = @"autoReveal";
static NSString *const TBHHideDelayKey = @"hideDelay";
static NSString *const TBHPinnedKey = @"pinned";
static NSString *const TBHOpacityKey = @"hudOpacity";
static NSString *const TBHWidthAdjustmentKey = @"widthAdjustment";
static NSString *const TBHHorizontalOffsetKey = @"horizontalOffset";
static NSString *const TBHDeviceProfileKey = @"deviceProfile";

static OSStatus TBHHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData);

@interface TBHHUDPanel : NSPanel
@end
@implementation TBHHUDPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface TBHAppDelegate ()
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) TBHHUDPanel *panel;
@property(nonatomic, strong) TBHSurfaceView *surfaceView;
@property(nonatomic, strong) TBHTouchBarController *touchBar;
@property(nonatomic, strong) NSTimer *hideTimer;
@property(nonatomic) EventHotKeyRef hotKeyRef;
@property(nonatomic) EventHandlerRef hotKeyHandlerRef;
@property(nonatomic) OSStatus shortcutStatus;
@property(nonatomic) BOOL autoReveal;
@property(nonatomic) BOOL pinned;
@property(nonatomic) BOOL accessibilityTrusted;
@property(nonatomic) BOOL suspended;
@property(nonatomic) BOOL sleeping;
@property(nonatomic) BOOL sessionInactive;
@property(nonatomic) BOOL shuttingDown;
@property(nonatomic) NSTimeInterval hideDelay;
@property(nonatomic) CGFloat hudOpacity;
@property(nonatomic) CGFloat widthAdjustment;
@property(nonatomic) CGFloat horizontalOffset;
@property(nonatomic) TBHDeviceProfile deviceProfile;
@property(nonatomic, copy) NSString *hardwareModelIdentifier;
@property(nonatomic) CFTimeInterval lastActivityTime;
@property(nonatomic) BOOL manuallyHidden;
@property(nonatomic) BOOL connectionStarted;
@property(nonatomic, strong) NSMenuItem *visibilityMenuItem;
@property(nonatomic, strong) NSMenuItem *autoRevealMenuItem;
@property(nonatomic, strong) NSMenuItem *pinnedMenuItem;
@property(nonatomic, strong) NSMenuItem *accessibilityMenuItem;
@property(nonatomic, strong) NSMenuItem *loginMenuItem;
@property(nonatomic, strong) NSMenuItem *automaticDeviceMenuItem;
- (void)toggleHUD;
@end

@implementation TBHAppDelegate

- (NSUserDefaults *)preferences {
    return NSUserDefaults.standardUserDefaults;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSUserDefaults *defaults = [self preferences];
    [defaults registerDefaults:@{TBHAutoRevealKey: @YES, TBHHideDelayKey: @3.0, TBHPinnedKey: @NO,
        TBHOpacityKey: @1.0, TBHWidthAdjustmentKey: @0.0, TBHHorizontalOffsetKey: @0.0,
        TBHDeviceProfileKey: @(TBHDeviceProfileAutomatic)}];
    self.autoReveal = [defaults boolForKey:TBHAutoRevealKey];
    self.pinned = [defaults boolForKey:TBHPinnedKey];
    self.hideDelay = TBHClampedValue([defaults doubleForKey:TBHHideDelayKey], 3, 1, 8);
    self.hudOpacity = TBHClampedValue([defaults doubleForKey:TBHOpacityKey], 1, 0.35, 1);
    self.widthAdjustment = TBHClampedValue([defaults doubleForKey:TBHWidthAdjustmentKey], 0, -2000, 2000);
    self.horizontalOffset = TBHClampedValue([defaults doubleForKey:TBHHorizontalOffsetKey], 0, -4000, 4000);
    self.hardwareModelIdentifier = TBHHardwareModelIdentifier();
    self.deviceProfile = TBHValidatedDeviceProfile([defaults integerForKey:TBHDeviceProfileKey]);
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.touchBar = [[TBHTouchBarController alloc] init];
    [self createPanel];
    [self createStatusItem];
    // A login launch must not interrupt the user with a permission prompt.
    [self refreshAccessibilityPermissionWithPrompt:NO];
    [self registerGlobalShortcut];
    __weak typeof(self) weakSelf = self;
    self.touchBar.frameHandler = ^{ [weakSelf receivedFrame]; };
    self.touchBar.stateHandler = ^{ [weakSelf updateStreamStatus]; };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenParametersChanged:)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(workspaceSuspended:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(workspaceResumed:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspace addObserver:self selector:@selector(workspaceSuspended:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [workspace addObserver:self selector:@selector(workspaceResumed:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    [self updateConnection];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    self.shuttingDown = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self hideImmediately];
    self.touchBar.frameHandler = nil;
    self.touchBar.stateHandler = nil;
    [self.touchBar stop];
    if (self.hotKeyRef) { UnregisterEventHotKey(self.hotKeyRef); }
    if (self.hotKeyHandlerRef) { RemoveEventHandler(self.hotKeyHandlerRef); }
    [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
}

- (NSScreen *)builtInScreen {
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
        if (number && CGDisplayIsBuiltin(number.unsignedIntValue)) { return screen; }
    }
    return nil;
}

- (void)createPanel {
    self.panel = [[TBHHUDPanel alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 58)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.becomesKeyOnlyIfNeeded = YES;
    self.panel.level = NSStatusWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
    NSView *container = [[NSView alloc] initWithFrame:self.panel.contentView.bounds];
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    container.wantsLayer = YES;
    container.layer.backgroundColor = NSColor.blackColor.CGColor;
    container.layer.cornerRadius = 9;
    container.layer.masksToBounds = YES;
    self.surfaceView = [[TBHSurfaceView alloc] initWithFrame:NSInsetRect(container.bounds, 6, 6)];
    self.surfaceView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.surfaceView.wantsLayer = YES;
    self.surfaceView.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.surfaceView.layer.contentsGravity = kCAGravityResizeAspect;
    self.surfaceView.layer.magnificationFilter = kCAFilterLinear;
    self.surfaceView.layer.minificationFilter = kCAFilterLinear;
    self.surfaceView.inputSize = self.touchBar.sourceSize;
    self.surfaceView.accessibilityLabel = @"Touch Bar mirror";
    self.surfaceView.accessibilityHelp = @"Mirrors the physical Touch Bar. Use its physical controls, or click the mirror with mouse control enabled.";
    __weak typeof(self) weakSelf = self;
    self.surfaceView.eventHandler = ^BOOL(NSEventType type, NSPoint point) {
        // Re-check on each gesture so a permission revoked while visible takes effect immediately.
        if (type == NSEventTypeLeftMouseDown && !AXIsProcessTrusted()) { return NO; }
        return [weakSelf.touchBar postMouseEvent:type point:point];
    };
    self.surfaceView.activityHandler = ^{ [weakSelf scheduleHide]; };
    self.surfaceView.hoverHandler = ^(BOOL inside) {
        if (inside) { [weakSelf cancelHideTimer]; }
        else { [weakSelf scheduleHide]; }
    };
    [container addSubview:self.surfaceView];
    self.panel.contentView = container;
    [self positionPanel];
}

- (void)positionPanel {
    NSScreen *screen = [self builtInScreen];
    if (!screen) { return; }
    CGFloat widthFraction = TBHTouchBarWidthFraction([self effectiveDeviceProfile], self.touchBar.sourceSize);
    NSRect frame = TBHPanelFrame(screen.frame, screen.visibleFrame, self.touchBar.sourceSize,
                                widthFraction, self.widthAdjustment, self.horizontalOffset);
    if (!NSEqualRects(frame, self.panel.frame)) { [self.panel setFrame:frame display:YES]; }
}

- (NSImage *)statusImage {
    NSImage *image = [NSImage imageNamed:@"StatusIcon"];
    if (image) {
        image.size = NSMakeSize(22, 18);
        image.template = YES;
        return image;
    }
    return [NSImage imageWithSystemSymbolName:@"rectangle.bottomthird.inset.filled"
        accessibilityDescription:@"TouchBar HUD"];
}

- (void)createStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [self statusImage];
    self.statusItem.button.accessibilityLabel = @"TouchBar HUD";
    self.statusItem.button.toolTip = @"TouchBar HUD";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"TouchBar HUD"];
    menu.delegate = self;
    menu.autoenablesItems = NO;
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

    NSMenu *deviceMenu = [[NSMenu alloc] initWithTitle:@"Laptop Model"];
    deviceMenu.autoenablesItems = NO;
    for (NSNumber *value in @[@(TBHDeviceProfileAutomatic), @(TBHDeviceProfileMacBookPro13),
                              @(TBHDeviceProfileMacBookPro15), @(TBHDeviceProfileMacBookPro16)]) {
        TBHDeviceProfile profile = value.integerValue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:TBHDeviceProfileName(profile)
            action:@selector(selectDeviceProfile:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = value;
        item.state = profile == self.deviceProfile ? NSControlStateValueOn : NSControlStateValueOff;
        if (profile == TBHDeviceProfileAutomatic) { self.automaticDeviceMenuItem = item; }
        [deviceMenu addItem:item];
    }
    [self updateAutomaticDeviceMenuTitle];
    NSMenuItem *deviceRoot = [[NSMenuItem alloc] initWithTitle:@"Laptop model" action:nil keyEquivalent:@""];
    deviceRoot.submenu = deviceMenu;
    [menu addItem:deviceRoot];

    NSMenu *alignmentMenu = [[NSMenu alloc] initWithTitle:@"Physical Alignment"];
    NSArray<NSDictionary *> *alignmentActions = @[
        @{@"title": @"Move left 5 pt", @"action": NSStringFromSelector(@selector(moveLeft:))},
        @{@"title": @"Move right 5 pt", @"action": NSStringFromSelector(@selector(moveRight:))},
        @{@"title": @"Make 10 pt narrower", @"action": NSStringFromSelector(@selector(makeNarrower:))},
        @{@"title": @"Make 10 pt wider", @"action": NSStringFromSelector(@selector(makeWider:))},
        @{@"title": @"Reset alignment", @"action": NSStringFromSelector(@selector(resetAlignment:))}
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

    self.loginMenuItem = [[NSMenuItem alloc] initWithTitle:@"Start at login" action:@selector(toggleLoginItem:) keyEquivalent:@""];
    self.loginMenuItem.target = self;
    [menu addItem:self.loginMenuItem];
    NSMenuItem *retry = [[NSMenuItem alloc] initWithTitle:@"Retry Touch Bar connection" action:@selector(retryConnection:) keyEquivalent:@""];
    retry.target = self;
    [menu addItem:retry];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About TouchBar HUD…"
        action:@selector(showAbout:) keyEquivalent:@""];
    about.target = self;
    [menu addItem:about];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit TouchBar HUD"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)registerGlobalShortcut {
    EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyPressed};
    self.shortcutStatus = InstallApplicationEventHandler(&TBHHotKeyHandler, 1, &type,
        (__bridge void *)self, &_hotKeyHandlerRef);
    if (self.shortcutStatus == noErr) {
        EventHotKeyID identifier = {'TBHD', 1};
        self.shortcutStatus = RegisterEventHotKey(kVK_ANSI_T, cmdKey | optionKey, identifier,
            GetApplicationEventTarget(), 0, &_hotKeyRef);
    }
}

- (void)screenParametersChanged:(NSNotification *)notification {
    (void)notification;
    [self positionPanel];
    [self updateConnection];
}

- (void)workspaceSuspended:(NSNotification *)notification {
    if ([notification.name isEqualToString:NSWorkspaceWillSleepNotification]) { self.sleeping = YES; }
    else { self.sessionInactive = YES; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateConnection) object:nil];
    [self updateConnection];
}

- (void)workspaceResumed:(NSNotification *)notification {
    if ([notification.name isEqualToString:NSWorkspaceDidWakeNotification]) { self.sleeping = NO; }
    else { self.sessionInactive = NO; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateConnection) object:nil];
    // One bounded retry lets WindowServer restore the built-in display after wake.
    [self performSelector:@selector(updateConnection) withObject:nil afterDelay:1.0];
}

- (void)updateConnection {
    if (self.shuttingDown) { return; }
    BOOL shouldSuspend = self.sleeping || self.sessionInactive || ![self builtInScreen];
    if (shouldSuspend) {
        [self hideImmediately];
        [self.touchBar stop];
        self.suspended = YES;
        self.connectionStarted = NO;
        [self updateStreamStatus];
        return;
    }
    self.suspended = NO;
    if (!self.connectionStarted) {
        self.connectionStarted = YES;
        [self.touchBar start];
        self.surfaceView.inputSize = self.touchBar.sourceSize;
        [self positionPanel];
        [self updateStreamStatus];
    }
}

- (void)retryConnection:(id)sender {
    (void)sender;
    [self hideImmediately];
    [self.touchBar stop];
    self.connectionStarted = NO;
    [self updateConnection];
}

- (void)updateStreamStatus {
    NSString *reason = self.suspended ? @"Waiting for the active session and built-in display."
        : self.touchBar.failureReason;
    self.statusItem.button.image = reason ? nil : [self statusImage];
    self.statusItem.button.title = reason ? @"TB!" : @"";
    self.statusItem.button.toolTip = reason ?: @"TouchBar HUD";
    self.visibilityMenuItem.enabled = self.touchBar.isReady && !self.suspended;
    if (!self.touchBar.isReady) { [self hideImmediately]; }
    [self refreshAccessibilityPermissionWithPrompt:NO];
}

- (void)receivedFrame {
    if (self.shuttingDown || self.suspended) { return; }
    if (!self.touchBar.latestSurface) {
        [self hideImmediately];
        return;
    }
    // Display activity is best-effort evidence of touch, not proof of physical input.
    CFTimeInterval now = CACurrentMediaTime();
    if (!self.manuallyHidden && (self.autoReveal || self.pinned) && now - self.lastActivityTime >= 0.25) {
        self.lastActivityTime = now;
        [self revealHUDForActivity:YES];
    }
    if (self.panel.isVisible) { [self.surfaceView displaySurface:self.touchBar.latestSurface]; }
}

- (void)refreshAccessibilityPermissionWithPrompt:(BOOL)prompt {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    self.accessibilityTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    BOOL enabled = self.accessibilityTrusted && self.touchBar.supportsMouseInput && self.touchBar.isReady;
    if (!enabled) { [self.surfaceView cancelInteraction]; }
    self.surfaceView.inputEnabled = enabled;
    self.accessibilityMenuItem.title = !self.touchBar.supportsMouseInput ? @"Mouse control: unavailable"
        : self.accessibilityTrusted ? @"Mouse control permission: enabled" : @"Enable mouse control…";
    self.accessibilityMenuItem.enabled = self.touchBar.supportsMouseInput && !self.accessibilityTrusted;
}

- (void)requestAccessibilityPermission:(id)sender {
    (void)sender;
    [self refreshAccessibilityPermissionWithPrompt:YES];
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self refreshAccessibilityPermissionWithPrompt:NO];
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    self.loginMenuItem.state = status == SMAppServiceStatusEnabled ? NSControlStateValueOn
        : status == SMAppServiceStatusRequiresApproval ? NSControlStateValueMixed : NSControlStateValueOff;
    self.loginMenuItem.title = status == SMAppServiceStatusRequiresApproval
        ? @"Start at login (approval required)…" : @"Start at login";
}

- (void)toggleLoginItem:(id)sender {
    (void)sender;
    SMAppService *service = SMAppService.mainAppService;
    if (service.status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
        return;
    }
    NSError *error = nil;
    BOOL success = service.status == SMAppServiceStatusEnabled
        ? [service unregisterAndReturnError:&error] : [service registerAndReturnError:&error];
    if (!success) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Could not change Start at login";
        alert.informativeText = error.localizedDescription ?: @"Move the app to Applications and try again.";
        [alert runModal];
    }
    [self menuWillOpen:self.statusItem.menu];
}

- (void)cancelHideTimer {
    [self.hideTimer invalidate];
    self.hideTimer = nil;
}

- (void)scheduleHide {
    if (!self.panel.isVisible || self.pinned || self.surfaceView.pointerInside) {
        [self cancelHideTimer];
        return;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:self.hideDelay];
    if (self.hideTimer) {
        self.hideTimer.fireDate = deadline;
    } else {
        __weak typeof(self) weakSelf = self;
        self.hideTimer = [NSTimer timerWithTimeInterval:self.hideDelay repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            weakSelf.hideTimer = nil;
            if (!weakSelf.pinned && !weakSelf.surfaceView.pointerInside) { [weakSelf hideImmediately]; }
        }];
        self.hideTimer.tolerance = 0.1;
        [NSRunLoop.mainRunLoop addTimer:self.hideTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)hideImmediately {
    [self cancelHideTimer];
    [self.surfaceView cancelInteraction];
    [self.panel orderOut:nil];
    [self.surfaceView displaySurface:NULL];
    self.visibilityMenuItem.title = @"Show Touch Bar";
}

- (void)revealHUDForActivity:(BOOL)isActivity {
    if (isActivity && ((!self.autoReveal && !self.pinned) || self.manuallyHidden)) { return; }
    if (!self.touchBar.isReady || !self.touchBar.latestSurface || self.suspended || ![self builtInScreen]) { return; }
    if (!isActivity) { self.manuallyHidden = NO; }
    if (!self.panel.isVisible) {
        [self refreshAccessibilityPermissionWithPrompt:NO];
        [self.surfaceView displaySurface:self.touchBar.latestSurface];
        self.panel.alphaValue = self.hudOpacity;
        [self.panel orderFrontRegardless];
    }
    self.visibilityMenuItem.title = @"Hide Touch Bar";
    [self scheduleHide];
}

- (void)toggleHUD {
    if (self.panel.isVisible) {
        self.manuallyHidden = YES;
        [self hideImmediately];
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
    if (self.autoReveal) { self.manuallyHidden = NO; }
    sender.state = self.autoReveal ? NSControlStateValueOn : NSControlStateValueOff;
    [[self preferences] setBool:self.autoReveal forKey:TBHAutoRevealKey];
}

- (void)togglePinned:(NSMenuItem *)sender {
    self.pinned = !self.pinned;
    sender.state = self.pinned ? NSControlStateValueOn : NSControlStateValueOff;
    [[self preferences] setBool:self.pinned forKey:TBHPinnedKey];
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
    [[self preferences] setDouble:self.hideDelay forKey:TBHHideDelayKey];
    for (NSMenuItem *item in sender.menu.itemArray) {
        item.state = (item == sender) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (self.panel.isVisible && !self.pinned) {
        [self revealHUDForActivity:NO];
    }
}

- (void)selectOpacity:(NSMenuItem *)sender {
    self.hudOpacity = [sender.representedObject doubleValue] / 100.0;
    [[self preferences] setDouble:self.hudOpacity forKey:TBHOpacityKey];
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

- (TBHDeviceProfile)effectiveDeviceProfile {
    return TBHResolvedDeviceProfile(self.deviceProfile, self.hardwareModelIdentifier);
}

- (void)updateAutomaticDeviceMenuTitle {
    TBHDeviceProfile detected = TBHDeviceProfileForModel(self.hardwareModelIdentifier);
    self.automaticDeviceMenuItem.title = detected == TBHDeviceProfileAutomatic
        ? @"Automatic (unrecognized — 15-inch fallback)"
        : [NSString stringWithFormat:@"Automatic — %@", TBHDeviceProfileName(detected)];
}

- (void)selectDeviceProfile:(NSMenuItem *)sender {
    self.deviceProfile = TBHValidatedDeviceProfile([sender.representedObject integerValue]);
    [[self preferences] setInteger:self.deviceProfile forKey:TBHDeviceProfileKey];
    for (NSMenuItem *item in sender.menu.itemArray) {
        item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self positionPanel];
    [self revealHUDForActivity:NO];
}

- (void)saveAlignmentAndReposition {
    [[self preferences] setDouble:self.widthAdjustment forKey:TBHWidthAdjustmentKey];
    [[self preferences] setDouble:self.horizontalOffset forKey:TBHHorizontalOffsetKey];
    [self positionPanel];
    [self revealHUDForActivity:NO];
}

- (void)moveLeft:(id)sender {
    (void)sender;
    self.horizontalOffset = MAX(self.horizontalOffset - 5.0, -4000);
    [self saveAlignmentAndReposition];
}

- (void)moveRight:(id)sender {
    (void)sender;
    self.horizontalOffset = MIN(self.horizontalOffset + 5.0, 4000);
    [self saveAlignmentAndReposition];
}

- (void)makeNarrower:(id)sender {
    (void)sender;
    self.widthAdjustment = MAX(self.widthAdjustment - 10.0, -2000);
    [self saveAlignmentAndReposition];
}

- (void)makeWider:(id)sender {
    (void)sender;
    self.widthAdjustment = MIN(self.widthAdjustment + 10.0, 2000);
    [self saveAlignmentAndReposition];
}

- (void)resetAlignment:(id)sender {
    (void)sender;
    self.widthAdjustment = 0.0;
    self.horizontalOffset = 0.0;
    [self saveAlignmentAndReposition];
}

- (NSDictionary<NSString *, id> *)diagnosticSnapshot {
    return @{ @"stream_ready": @(self.touchBar.isReady),
        @"failure_reason": self.touchBar.failureReason ?: @"",
        @"source_width": @(self.touchBar.sourceSize.width), @"source_height": @(self.touchBar.sourceSize.height),
        @"built_in_display": @([self builtInScreen] != nil), @"suspended": @(self.suspended),
        @"mouse_input_enabled": @(self.surfaceView.inputEnabled), @"shortcut_status": @(self.shortcutStatus),
        @"received_frames": @(self.touchBar.receivedFrameCount), @"delivered_frames": @(self.touchBar.deliveredFrameCount),
        @"hud_visible": @(self.panel.isVisible),
        @"hardware_model": self.hardwareModelIdentifier ?: @"unknown",
        @"device_profile_automatic": @(self.deviceProfile == TBHDeviceProfileAutomatic),
        @"device_profile": TBHDeviceProfileName([self effectiveDeviceProfile]),
        @"device_profile_fallback": @(self.deviceProfile == TBHDeviceProfileAutomatic &&
            TBHDeviceProfileForModel(self.hardwareModelIdentifier) == TBHDeviceProfileAutomatic),
        @"touch_bar_width_fraction": @(TBHTouchBarWidthFraction([self effectiveDeviceProfile], self.touchBar.sourceSize)) };
}

- (void)showAbout:(id)sender {
    (void)sender;
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSAttributedString *description = [[NSAttributedString alloc]
        initWithString:@"Mirrors your MacBook’s Touch Bar."
        attributes:@{NSParagraphStyleAttributeName: paragraph,
            NSFontAttributeName: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
    // AppKit reads the icon, version, build, and copyright directly from the bundle.
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: description}];
    if (@available(macOS 14.0, *)) { [NSApp activate]; }
    else { [NSApp activateIgnoringOtherApps:YES]; }
}

- (void)showDiagnostics:(id)sender {
    (void)sender;
    [self refreshAccessibilityPermissionWithPrompt:NO];
    NSString *details = [NSString stringWithFormat:
        @"Touch Bar stream: %@\n%@\nMouse control: %@\nBuilt-in display: %@\n"
        "Shortcut ⌥⌘T: %@\nAuto reveal: %@\nHide delay: %.0f seconds\nOpacity: %.0f%%\n"
        "Laptop model: %@\nSizing: %@ (%@)\n"
        "Alignment: width %+.0f pt, horizontal %+.0f pt\nFrames received / delivered: %lu / %lu\n\n"
        "Automatic reveal uses display activity, so app layout changes may also reveal the mirror. "
        "Private macOS APIs can change after an OS update.",
        self.touchBar.isReady ? @"active" : @"unavailable",
        self.suspended ? @"Waiting for the active session and built-in display." : self.touchBar.failureReason ?: @"",
        self.surfaceView.inputEnabled ? @"enabled" : @"unavailable (check Accessibility permission)",
        [self builtInScreen] ? @"available" : @"unavailable",
        self.shortcutStatus == noErr ? @"registered" : [NSString stringWithFormat:@"unavailable (error %d)", (int)self.shortcutStatus],
        self.autoReveal ? @"On" : @"Off", self.hideDelay, self.hudOpacity * 100,
        self.hardwareModelIdentifier ?: @"unknown", TBHDeviceProfileName([self effectiveDeviceProfile]),
        self.deviceProfile != TBHDeviceProfileAutomatic ? @"manual"
            : TBHDeviceProfileForModel(self.hardwareModelIdentifier) == TBHDeviceProfileAutomatic ? @"fallback" : @"automatic",
        self.widthAdjustment, self.horizontalOffset,
        (unsigned long)self.touchBar.receivedFrameCount, (unsigned long)self.touchBar.deliveredFrameCount];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"TouchBar HUD Diagnostics";
    alert.informativeText = details;
    [alert runModal];
}
@end

static OSStatus TBHHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    (void)nextHandler;
    EventHotKeyID identifier = {0};
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
        sizeof(identifier), NULL, &identifier);
    if (status != noErr || identifier.signature != 'TBHD' || identifier.id != 1) { return eventNotHandledErr; }
    [(__bridge TBHAppDelegate *)userData toggleHUD];
    return noErr;
}
