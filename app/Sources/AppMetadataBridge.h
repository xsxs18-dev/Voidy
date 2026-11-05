#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Objective-C owns dynamic messaging and exception handling. Never let a
// LaunchServices/UIKit exception or an unretained IMP result cross into Swift.
FOUNDATION_EXPORT NSString * _Nullable VDAppDisplayName(NSString *bundleID);
FOUNDATION_EXPORT NSObject * _Nullable VDAppIcon(NSString *bundleID, double scale);

NS_ASSUME_NONNULL_END
