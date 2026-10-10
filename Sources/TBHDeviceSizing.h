#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TBHDeviceProfile) {
    TBHDeviceProfileAutomatic = 0,
    TBHDeviceProfileMacBookPro13 = 1,
    TBHDeviceProfileMacBookPro15 = 2,
    TBHDeviceProfileMacBookPro16 = 3,
};

/// Cached local hw.model lookup. Returns nil if the system cannot supply it.
FOUNDATION_EXPORT NSString * _Nullable TBHHardwareModelIdentifier(void);
/// Exact identifiers only: unknown and non-Touch-Bar Macs return Automatic (unrecognized).
FOUNDATION_EXPORT TBHDeviceProfile TBHDeviceProfileForModel(NSString * _Nullable model);
FOUNDATION_EXPORT TBHDeviceProfile TBHValidatedDeviceProfile(NSInteger value);
FOUNDATION_EXPORT TBHDeviceProfile TBHResolvedDeviceProfile(TBHDeviceProfile selected, NSString * _Nullable model);
FOUNDATION_EXPORT NSString *TBHDeviceProfileName(TBHDeviceProfile profile);
/// Estimated physical width relative to the laptop display, independent of scaled resolution.
FOUNDATION_EXPORT CGFloat TBHTouchBarWidthFraction(TBHDeviceProfile profile, CGSize sourceSize);
NS_ASSUME_NONNULL_END
