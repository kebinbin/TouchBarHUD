#import <Cocoa/Cocoa.h>
#import "Sources/TBHAppDelegate.h"
#import "Sources/TBHTouchBarController.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static int TBHUsage(void) {
    fprintf(stderr, "Usage: TouchBarHUD [--check-framework | --verify-runtime SECONDS]\n");
    return 64;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--check-framework") == 0) {
            return [TBHTouchBarController checkFramework];
        }
        long verificationSeconds = 0;
        if (argc == 3 && strcmp(argv[1], "--verify-runtime") == 0) {
            char *end;
            verificationSeconds = strtol(argv[2], &end, 10);
            if (*end || verificationSeconds < 2 || verificationSeconds > 3600) { return TBHUsage(); }
        } else if (argc > 1 && strncmp(argv[1], "-psn_", 5) != 0) {
            return TBHUsage();
        }
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        for (NSRunningApplication *running in [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier ?: @""]) {
            if (running.processIdentifier != NSProcessInfo.processInfo.processIdentifier) {
                if (verificationSeconds) { fprintf(stderr, "Quit the existing app before runtime verification.\n"); }
                return verificationSeconds ? 1 : 0;
            }
        }
        NSApplication *application = NSApplication.sharedApplication;
        // NSApplication does not retain its delegate; keep it alive for the entire run loop.
        __attribute__((objc_precise_lifetime)) TBHAppDelegate *delegate = [[TBHAppDelegate alloc] init];
        application.delegate = delegate;
        __block int result = 0;
        if (verificationSeconds) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, verificationSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSDictionary *snapshot = [delegate diagnosticSnapshot];
                NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
                fwrite(json.bytes, 1, json.length, stdout);
                putchar('\n');
                result = [snapshot[@"stream_ready"] boolValue] && [snapshot[@"received_frames"] unsignedIntegerValue] > 0 ? 0 : 1;
                if (result != 0) {
                    [delegate applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:application]];
                    exit(result);
                }
                [application terminate:nil];
            });
        }
        [application run];
        return result;
    }
}
