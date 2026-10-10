#import <Cocoa/Cocoa.h>
#import <IOSurface/IOSurface.h>
#import <QuartzCore/QuartzCore.h>
#import "TBHGeometry.h"
#import "TBHDeviceSizing.h"
#import "TBHSurfaceView.h"
#import "TBHTouchBarController.h"
#import "TBHAppDelegate.h"
#import <math.h>
#import <stdio.h>
#import <string.h>

static unsigned checks;
#define CHECK(condition) do { checks++; if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)

@interface TBHTouchBarController (Testing)
- (void)consumeSurface:(IOSurfaceRef)surface;
@end
@interface TBHAppDelegate (Testing)
- (void)createPanel;
- (void)createStatusItem;
- (void)positionPanel;
- (void)selectDeviceProfile:(NSMenuItem *)sender;
- (void)resetAlignment:(id)sender;
- (NSUserDefaults *)preferences;
- (void)revealHUDForActivity:(BOOL)activity;
- (void)toggleHUD;
- (void)receivedFrame;
- (void)hideImmediately;
- (void)refreshAccessibilityPermissionWithPrompt:(BOOL)prompt;
- (NSScreen *)builtInScreen;
- (void)updateConnection;
- (void)workspaceSuspended:(NSNotification *)notification;
- (void)workspaceResumed:(NSNotification *)notification;
@end

@interface TBHTestSurfaceView : TBHSurfaceView
@property(nonatomic) BOOL simulatedPointerInside;
@end
@implementation TBHTestSurfaceView
- (BOOL)pointerInside { return self.simulatedPointerInside; }
@end

@interface TBHTestDelegate : TBHAppDelegate
@property(nonatomic) BOOL screenUnavailable;
@property(nonatomic, strong) NSUserDefaults *testPreferences;
@end
@implementation TBHTestDelegate
- (NSScreen *)builtInScreen { return self.screenUnavailable ? nil : NSScreen.mainScreen; }
- (NSUserDefaults *)preferences { return self.testPreferences ?: [super preferences]; }
- (void)refreshAccessibilityPermissionWithPrompt:(BOOL)prompt { (void)prompt; }
@end

static void RunLoopFor(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:until];
    }
}

static IOSurfaceRef CreateSurface(void) {
    return IOSurfaceCreate((__bridge CFDictionaryRef)@{
        (__bridge NSString *)kIOSurfaceWidth: @100,
        (__bridge NSString *)kIOSurfaceHeight: @10,
        (__bridge NSString *)kIOSurfaceBytesPerElement: @4});
}

static void TestGeometry(void) {
    CHECK(TBHClampedValue(NAN, 3, 1, 8) == 3);
    CHECK(TBHClampedValue(INFINITY, 1, 0.35, 1) == 1);
    CHECK(TBHClampedValue(-1, 3, 1, 8) == 1);
    NSPoint point = TBHTouchPoint(NSMakePoint(50, 15), NSMakeSize(100, 30), CGSizeMake(2170, 60));
    CHECK(point.x == 1085 && point.y == 30);
    point = TBHTouchPoint(NSMakePoint(-20, 99), NSMakeSize(100, 30), CGSizeMake(2170, 60));
    CHECK(point.x == 0 && point.y == 60);
    CHECK(NSEqualPoints(TBHTouchPoint(NSZeroPoint, NSZeroSize, CGSizeMake(2170, 60)), NSZeroPoint));
    for (NSNumber *width in @[@640, @1280, @1440, @1680, @1920]) {
        NSRect screen = NSMakeRect(-1920, 100, width.doubleValue, 900);
        NSRect visible = NSMakeRect(-1920, 150, width.doubleValue, 820);
        for (NSNumber *offset in @[@(-4000), @0, @4000]) {
            NSRect frame = TBHPanelFrame(screen, visible, CGSizeMake(2170, 60), 2170.0 / 2880.0, 2000, offset.doubleValue);
            CHECK(NSContainsRect(screen, frame));
            CHECK(NSMinY(frame) >= NSMinY(visible));
        }
    }
}

static void TestDeviceSizing(void) {
    CHECK(TBHDeviceProfileForModel(@"MacBookPro15,1") == TBHDeviceProfileMacBookPro15);
    CHECK(TBHDeviceProfileForModel(@"MacBookPro16,2") == TBHDeviceProfileMacBookPro13);
    CHECK(TBHDeviceProfileForModel(@"MacBookPro16,4") == TBHDeviceProfileMacBookPro16);
    CHECK(TBHDeviceProfileForModel(@"MacBookPro14,1") == TBHDeviceProfileAutomatic); // No Touch Bar.
    CHECK(TBHDeviceProfileForModel(@"MacBookPro99,1") == TBHDeviceProfileAutomatic);
    CHECK(TBHDeviceProfileForModel(nil) == TBHDeviceProfileAutomatic);
    CHECK(TBHValidatedDeviceProfile(-1) == TBHDeviceProfileAutomatic);
    CHECK(TBHValidatedDeviceProfile(999) == TBHDeviceProfileAutomatic);
    CHECK(TBHResolvedDeviceProfile(TBHDeviceProfileAutomatic, @"MacBookPro16,1") == TBHDeviceProfileMacBookPro16);
    CHECK(TBHResolvedDeviceProfile(TBHDeviceProfileMacBookPro13, @"MacBookPro16,1") == TBHDeviceProfileMacBookPro13);
    CHECK(TBHResolvedDeviceProfile(TBHDeviceProfileAutomatic, nil) == TBHDeviceProfileMacBookPro15);
    CGSize logical = CGSizeMake(1085, 30), pixels = CGSizeMake(2170, 60);
    CGFloat original = 2170.0 / 2880.0;
    CHECK(fabs(TBHTouchBarWidthFraction(TBHDeviceProfileMacBookPro15, logical) - original) < 1e-9);
    for (NSNumber *value in @[@(TBHDeviceProfileMacBookPro13), @(TBHDeviceProfileMacBookPro15), @(TBHDeviceProfileMacBookPro16)]) {
        TBHDeviceProfile profile = value.integerValue;
        CGFloat fraction = TBHTouchBarWidthFraction(profile, logical);
        CHECK(fabs(fraction - TBHTouchBarWidthFraction(profile, pixels)) < 1e-9);
        CHECK(fabs(fraction - TBHTouchBarWidthFraction(profile, CGSizeMake(NAN, 30))) < 1e-9);
        CHECK(fabs(fraction - TBHTouchBarWidthFraction(profile, CGSizeMake(8192, 1))) < 1e-9);
        CGFloat shorter = TBHTouchBarWidthFraction(profile, CGSizeMake(1004, 30));
        CHECK(shorter < fraction); // Source geometry, not a hardcoded generation width, drives sizing.
        CHECK(fabs(shorter - TBHTouchBarWidthFraction(profile, CGSizeMake(2008, 60))) < 1e-9);
        for (NSNumber *screenWidth in @[@640, @1024, @1280, @1440, @1920]) {
            NSRect screen = NSMakeRect(0, 0, screenWidth.doubleValue, 900);
            NSRect frame = TBHPanelFrame(screen, screen, logical, fraction, 0, 0);
            CHECK(NSContainsRect(screen, frame));
            CHECK(fabs((frame.size.width - 12) / screen.size.width - fraction) <= 0.5 / screen.size.width);
        }
    }
    // Golden widths and unchanged input mapping across a scale/profile change.
    NSRect screen = NSMakeRect(0, 0, 1440, 900);
    NSRect legacy = TBHPanelFrame(screen, screen, logical, original, 0, 0);
    CHECK(legacy.size.width == 1097);
    NSRect thirteen = TBHPanelFrame(screen, screen, logical,
        TBHTouchBarWidthFraction(TBHDeviceProfileMacBookPro13, logical), 0, 0);
    CHECK(thirteen.size.width > legacy.size.width);
    NSPoint midpoint = TBHTouchPoint(NSMakePoint(thirteen.size.width / 2, 15), NSMakeSize(thirteen.size.width, 30), logical);
    CHECK(midpoint.x == 542.5);
}

static void TestFrameLifecycle(void) {
    IOSurfaceRef first = CreateSurface(), last = CreateSurface();
    CHECK(first && last);
    int32_t firstCount = IOSurfaceGetUseCount(first), lastCount = IOSurfaceGetUseCount(last);
    TBHTouchBarController *controller = [[TBHTouchBarController alloc] init];
    __block NSUInteger deliveries = 0;
    controller.frameHandler = ^{ deliveries++; };
    [controller consumeSurface:first];
    CHECK(controller.isReady && deliveries == 1);
    CHECK(IOSurfaceGetUseCount(first) == firstCount + 1);
    for (NSUInteger i = 0; i < 1000; i++) { [controller consumeSurface:last]; }
    CHECK(deliveries == 1); // A burst cannot enqueue an unbounded series of UI updates.
    CHECK(IOSurfaceGetUseCount(first) == firstCount);
    CHECK(IOSurfaceGetUseCount(last) == lastCount + 1);
    RunLoopFor(0.08);
    CHECK(deliveries == 2 && controller.latestSurface == last); // Final frame must not be lost.
    [controller consumeSurface:first];
    [controller consumeSurface:last];
    [controller stop];
    NSUInteger stoppedDeliveries = deliveries;
    RunLoopFor(0.08);
    CHECK(deliveries == stoppedDeliveries && !controller.isReady && !controller.latestSurface);
    CHECK(IOSurfaceGetUseCount(first) == firstCount && IOSurfaceGetUseCount(last) == lastCount);
    CFRelease(first);
    CFRelease(last);
}

static void TestInput(void) {
    TBHSurfaceView *view = [[TBHSurfaceView alloc] initWithFrame:NSMakeRect(0, 0, 100, 10)];
    view.inputSize = CGSizeMake(100, 10);
    __block NSMutableArray<NSNumber *> *events = [NSMutableArray array];
    view.eventHandler = ^BOOL(NSEventType type, NSPoint point) {
        (void)point;
        [events addObject:@(type)];
        return YES;
    };
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(50, 5)
        modifierFlags:0 timestamp:1 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
    [view mouseDown:down];
    CHECK(events.count == 0); // No forwarding without permission.
    view.inputEnabled = YES;
    [view mouseDown:down];
    [view cancelInteraction];
    [view cancelInteraction];
    CHECK(events.count == 2 && events[0].unsignedIntegerValue == NSEventTypeLeftMouseDown &&
          events[1].unsignedIntegerValue == NSEventTypeLeftMouseUp);
}

@interface TBHLifecycleController : TBHTouchBarController
@property(nonatomic) NSUInteger startCount;
@property(nonatomic) NSUInteger stopCount;
@end
@implementation TBHLifecycleController
- (BOOL)start { self.startCount++; return NO; }
- (void)stop { self.stopCount++; [super stop]; }
@end

static void TestWorkspaceLifecycle(void) {
    TBHTestDelegate *delegate = [[TBHTestDelegate alloc] init];
    TBHLifecycleController *controller = [[TBHLifecycleController alloc] init];
    [delegate setValue:controller forKey:@"touchBar"];
    [delegate updateConnection];
    CHECK(controller.startCount == 1);
    for (NSUInteger i = 0; i < 100; i++) { [delegate updateConnection]; }
    CHECK(controller.startCount == 1); // Failed startup cannot create a retry loop.
    [delegate workspaceSuspended:[NSNotification notificationWithName:NSWorkspaceWillSleepNotification object:nil]];
    CHECK([[delegate valueForKey:@"suspended"] boolValue]);
    [delegate workspaceSuspended:[NSNotification notificationWithName:NSWorkspaceSessionDidResignActiveNotification object:nil]];
    [delegate workspaceResumed:[NSNotification notificationWithName:NSWorkspaceDidWakeNotification object:nil]];
    [delegate updateConnection];
    CHECK(controller.startCount == 1); // Waking must not reconnect an inactive user session.
    [delegate workspaceResumed:[NSNotification notificationWithName:NSWorkspaceSessionDidBecomeActiveNotification object:nil]];
    [delegate updateConnection];
    CHECK(controller.startCount == 2 && ![[delegate valueForKey:@"suspended"] boolValue]);
    delegate.screenUnavailable = YES;
    [delegate updateConnection];
    CHECK([[delegate valueForKey:@"suspended"] boolValue]);
    delegate.screenUnavailable = NO;
    [delegate updateConnection];
    CHECK(controller.startCount == 3);
    [NSObject cancelPreviousPerformRequestsWithTarget:delegate];
}

static void TestDeviceMenu(void) {
    NSString *suiteName = [@"com.touchbarhud.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    TBHTestDelegate *delegate = [[TBHTestDelegate alloc] init];
    delegate.testPreferences = defaults;
    [delegate setValue:[[TBHTouchBarController alloc] init] forKey:@"touchBar"];
    [delegate setValue:@"MacBookPro15,1" forKey:@"hardwareModelIdentifier"];
    [delegate setValue:@10 forKey:@"widthAdjustment"];
    [delegate setValue:@5 forKey:@"horizontalOffset"];
    [delegate createPanel];
    [delegate createStatusItem];
    NSStatusItem *statusItem = [delegate valueForKey:@"statusItem"];
    NSMenu *modelMenu = nil;
    for (NSMenuItem *item in statusItem.menu.itemArray) {
        if ([item.title isEqualToString:@"Laptop model"]) { modelMenu = item.submenu; break; }
    }
    CHECK(modelMenu.numberOfItems == 4);
    NSMenuItem *automatic = [modelMenu itemAtIndex:0];
    CHECK([automatic.title containsString:@"15-inch"] && automatic.state == NSControlStateValueOn);
    NSRect initial = [[delegate valueForKey:@"panel"] frame];
    NSMenuItem *thirteen = [modelMenu itemAtIndex:1];
    [delegate selectDeviceProfile:thirteen];
    CHECK([defaults integerForKey:@"deviceProfile"] == TBHDeviceProfileMacBookPro13);
    CHECK(thirteen.state == NSControlStateValueOn && automatic.state == NSControlStateValueOff);
    CHECK([[delegate valueForKey:@"panel"] frame].size.width > initial.size.width);
    CHECK([[delegate valueForKey:@"widthAdjustment"] doubleValue] == 10 &&
          [[delegate valueForKey:@"horizontalOffset"] doubleValue] == 5);
    [delegate resetAlignment:nil];
    CHECK([defaults integerForKey:@"deviceProfile"] == TBHDeviceProfileMacBookPro13);
    CHECK([[delegate valueForKey:@"widthAdjustment"] doubleValue] == 0 &&
          [[delegate valueForKey:@"horizontalOffset"] doubleValue] == 0);
    [delegate selectDeviceProfile:automatic];
    CHECK([defaults integerForKey:@"deviceProfile"] == TBHDeviceProfileAutomatic);
    CHECK(automatic.state == NSControlStateValueOn && thirteen.state == NSControlStateValueOff);
    NSDictionary *snapshot = [delegate diagnosticSnapshot];
    CHECK([snapshot[@"hardware_model"] isEqualToString:@"MacBookPro15,1"] &&
          [snapshot[@"device_profile"] isEqualToString:@"15-inch MacBook Pro"]);
    [delegate setValue:@"Unrecognized" forKey:@"hardwareModelIdentifier"];
    CHECK([[delegate diagnosticSnapshot][@"device_profile_fallback"] boolValue]);
    [delegate hideImmediately];
    [NSStatusBar.systemStatusBar removeStatusItem:statusItem];
    [defaults removePersistentDomainForName:suiteName];
}

static void TestVisibility(void) {
    CHECK(NSScreen.mainScreen != nil);
    TBHTestDelegate *delegate = [[TBHTestDelegate alloc] init];
    TBHTouchBarController *controller = [[TBHTouchBarController alloc] init];
    [delegate setValue:controller forKey:@"touchBar"];
    [delegate setValue:@3 forKey:@"hideDelay"];
    [delegate setValue:@1 forKey:@"hudOpacity"];
    [delegate createPanel];
    NSPanel *panel = [delegate valueForKey:@"panel"];
    TBHSurfaceView *originalView = [delegate valueForKey:@"surfaceView"];
    TBHTestSurfaceView *view = [[TBHTestSurfaceView alloc] initWithFrame:originalView.frame];
    view.wantsLayer = YES;
    [originalView removeFromSuperview];
    [panel.contentView addSubview:view];
    [delegate setValue:view forKey:@"surfaceView"];
    [panel setFrameOrigin:NSMakePoint(0, 200)];
    IOSurfaceRef surface = CreateSurface();
    int32_t useCount = IOSurfaceGetUseCount(surface);
    [controller consumeSurface:surface];
    [delegate receivedFrame];
    CHECK(!panel.isVisible); // Auto reveal off also applies to the first frame.
    [delegate setValue:@YES forKey:@"pinned"];
    [delegate revealHUDForActivity:NO];
    CHECK(panel.isVisible);
    [delegate toggleHUD];
    CHECK(!panel.isVisible); // Manual hide works even while pinned.
    [delegate receivedFrame];
    CHECK(!panel.isVisible); // Stream activity cannot undo manual hide.
    [delegate toggleHUD];
    CHECK(panel.isVisible);
    [delegate setValue:@NO forKey:@"pinned"];
    [delegate setValue:@YES forKey:@"autoReveal"];
    [delegate setValue:@0 forKey:@"lastActivityTime"];
    [delegate receivedFrame];
    NSTimer *timer = [delegate valueForKey:@"hideTimer"];
    CHECK(timer != nil);
    for (NSUInteger i = 0; i < 1000; i++) { [delegate receivedFrame]; }
    CHECK([delegate valueForKey:@"hideTimer"] == timer); // Reuse one timer throughout a burst.
    view.simulatedPointerInside = YES;
    [delegate setValue:@0 forKey:@"lastActivityTime"];
    [delegate receivedFrame];
    CHECK([delegate valueForKey:@"hideTimer"] == nil);
    [delegate toggleHUD];
    CHECK(!panel.isVisible); // Hover must not block an explicit hide either.
    [delegate hideImmediately];
    CHECK(!panel.isVisible && [delegate valueForKey:@"hideTimer"] == nil);
    [controller stop];
    [CATransaction flush];
    RunLoopFor(0.1);
    CHECK(IOSurfaceGetUseCount(surface) == useCount);
    CFRelease(surface);
}

int main(int argc, const char *argv[]) {
    if (argc > 2 || (argc == 2 && strcmp(argv[1], "--headless") != 0)) { return 64; }
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestGeometry();
        TestDeviceSizing();
        TestFrameLifecycle();
        TestInput();
        if (argc == 2 && strcmp(argv[1], "--headless") == 0) {
            puts("Skipping graphical visibility checks (headless mode).");
        } else {
            TestDeviceMenu();
            TestVisibility();
            TestWorkspaceLifecycle();
        }
        printf("Passed %u checks.\n", checks);
    }
    return 0;
}
