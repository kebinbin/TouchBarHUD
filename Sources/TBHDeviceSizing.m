#import "TBHDeviceSizing.h"
#import <math.h>
#import <sys/sysctl.h>

NSString *TBHHardwareModelIdentifier(void) {
    static NSString *identifier;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char model[128] = {0};
        size_t size = sizeof(model);
        if (sysctlbyname("hw.model", model, &size, NULL, 0) == 0 && size > 1 && size <= sizeof(model)) {
            model[sizeof(model) - 1] = '\0';
            identifier = [[NSString alloc] initWithUTF8String:model];
        }
    });
    return identifier;
}

TBHDeviceProfile TBHDeviceProfileForModel(NSString *model) {
    static NSDictionary<NSString *, NSNumber *> *profiles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Apple's model identifiers: https://support.apple.com/en-us/108052
        profiles = @{
            @"MacBookPro13,2": @(TBHDeviceProfileMacBookPro13),
            @"MacBookPro14,2": @(TBHDeviceProfileMacBookPro13),
            @"MacBookPro15,2": @(TBHDeviceProfileMacBookPro13),
            @"MacBookPro15,4": @(TBHDeviceProfileMacBookPro13),
            @"MacBookPro16,2": @(TBHDeviceProfileMacBookPro13),
            @"MacBookPro16,3": @(TBHDeviceProfileMacBookPro13),
            @"MacBookPro13,3": @(TBHDeviceProfileMacBookPro15),
            @"MacBookPro14,3": @(TBHDeviceProfileMacBookPro15),
            @"MacBookPro15,1": @(TBHDeviceProfileMacBookPro15),
            @"MacBookPro15,3": @(TBHDeviceProfileMacBookPro15),
            @"MacBookPro16,1": @(TBHDeviceProfileMacBookPro16),
            @"MacBookPro16,4": @(TBHDeviceProfileMacBookPro16)
        };
    });
    return model ? profiles[model].integerValue : TBHDeviceProfileAutomatic;
}

TBHDeviceProfile TBHValidatedDeviceProfile(NSInteger value) {
    return value >= TBHDeviceProfileAutomatic && value <= TBHDeviceProfileMacBookPro16
        ? (TBHDeviceProfile)value : TBHDeviceProfileAutomatic;
}

TBHDeviceProfile TBHResolvedDeviceProfile(TBHDeviceProfile selected, NSString *model) {
    TBHDeviceProfile validated = TBHValidatedDeviceProfile(selected);
    if (validated != TBHDeviceProfileAutomatic) { return validated; }
    TBHDeviceProfile detected = TBHDeviceProfileForModel(model);
    // Preserve the original calibration when detection is unavailable, rather than guessing a model.
    return detected == TBHDeviceProfileAutomatic ? TBHDeviceProfileMacBookPro15 : detected;
}

NSString *TBHDeviceProfileName(TBHDeviceProfile profile) {
    switch (profile) {
        case TBHDeviceProfileMacBookPro13: return @"13-inch MacBook Pro";
        case TBHDeviceProfileMacBookPro15: return @"15-inch MacBook Pro";
        case TBHDeviceProfileMacBookPro16: return @"16-inch MacBook Pro";
        default: return @"Automatic";
    }
}

CGFloat TBHTouchBarWidthFraction(TBHDeviceProfile profile, CGSize sourceSize) {
    CGFloat nativeWidth = 2880, displayPPI = 220;
    switch (profile) {
        case TBHDeviceProfileMacBookPro13: nativeWidth = 2560; displayPPI = 227; break;
        case TBHDeviceProfileMacBookPro16: nativeWidth = 3072; displayPPI = 226; break;
        default: break;
    }
    // Keep the original A1990 calibration (2170/2880). Display PPI converts that
    // baseline to physical scale on other models. Using source aspect ratio makes
    // logical and Retina-pixel reports equivalent and adapts to shorter Touch Bars.
    CGFloat sourceAspect = 2170.0 / 60.0;
    if (isfinite(sourceSize.width) && isfinite(sourceSize.height) && sourceSize.width > 0 && sourceSize.height > 0) {
        CGFloat reportedAspect = sourceSize.width / sourceSize.height;
        if (isfinite(reportedAspect) && reportedAspect >= 20 && reportedAspect <= 50) {
            sourceAspect = reportedAspect;
        }
    }
    return sourceAspect * 60.0 / nativeWidth * (displayPPI / 220.0);
}
