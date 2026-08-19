#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BZABNetworkBlocker : NSObject

+ (void)install;
+ (BOOL)shouldBlockURL:(NSURL *)URL;

@end

NS_ASSUME_NONNULL_END
