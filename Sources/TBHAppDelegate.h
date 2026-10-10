#import <Cocoa/Cocoa.h>

@interface TBHAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
/// Read-only state for support and bounded command-line runtime verification.
- (NSDictionary<NSString *, id> *)diagnosticSnapshot;
@end
