#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BZABGuaziBlocker : NSObject

+ (BOOL)install;
+ (void)refreshHooks;
+ (void)rescanAds;
+ (BOOL)isTargetApplication;
+ (BOOL)nativeFastPathReady;

@end

NS_ASSUME_NONNULL_END
