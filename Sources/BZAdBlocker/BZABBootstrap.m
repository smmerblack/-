#import "BZABCMCCBlocker.h"
#import "BZABCore.h"
#import "BZABMenuController.h"
#import "BZABNetworkBlocker.h"
#import "BZABSDKBlocker.h"
#import "BZABTaobaoBlocker.h"
#import "BZABViewBlocker.h"

__attribute__((constructor))
static void BZABBootstrap(void) {
    @autoreleasepool {
        (void)BZABSettings.sharedSettings;
        BOOL chinaMobileTarget = [BZABCMCCBlocker isTargetApplication];
        BOOL taobaoTarget = [BZABTaobaoBlocker isTargetApplication];
        BOOL nativeFastPath = chinaMobileTarget
            ? [BZABCMCCBlocker install]
            : (taobaoTarget ? [BZABTaobaoBlocker install] : NO);
        BOOL dedicatedTarget = chinaMobileTarget || taobaoTarget;
        BOOL useGenericEngine = !dedicatedTarget;
        if (useGenericEngine) {
            [BZABSDKBlocker install];
            [BZABNetworkBlocker install];
            [BZABViewBlocker install];
        }

        NSTimeInterval setupDelay = dedicatedTarget ? 1.0 : 0.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(setupDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [BZABMenuController.sharedController installGestureEntry];
            if (useGenericEngine) {
                [BZABViewBlocker.sharedBlocker startSuppressionScan];
            }
            BZABProfile *profile = BZABProfile.currentProfile;
            BZABLog(@"loaded version=%@ bundle=%@ profile=%@ dedicated=%d "
                    "nativeFastPath=%d genericEngine=%d",
                    BZABVersion,
                    NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
                    profile.name,
                    dedicatedTarget,
                    nativeFastPath,
                    useGenericEngine);
        });
    }
}
