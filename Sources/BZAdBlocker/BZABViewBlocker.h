#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BZABViewBlocker : NSObject

+ (instancetype)sharedBlocker;
+ (void)install;
- (void)startSuppressionScan;
- (void)rescanForDuration:(NSTimeInterval)duration;
- (BOOL)shouldSuppressObject:(id)object;

@end

NS_ASSUME_NONNULL_END
