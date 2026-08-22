#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BZABTaobaoBlocker : NSObject

+ (BOOL)install;
+ (void)refreshHooks;
+ (BOOL)isTargetApplication;
+ (BOOL)nativeFastPathReady;

@end

NS_ASSUME_NONNULL_END
