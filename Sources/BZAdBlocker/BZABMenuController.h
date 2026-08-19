#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BZABMenuController : NSObject

+ (instancetype)sharedController;
- (void)installGestureEntry;
- (void)showMenu;

@end

NS_ASSUME_NONNULL_END
