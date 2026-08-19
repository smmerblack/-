#import "BZABCMCCBlocker.h"
#import "BZABCore.h"
#import "BZABMenuController.h"
#import "BZABNetworkBlocker.h"
#import "BZABSDKBlocker.h"
#import "BZABViewBlocker.h"

__attribute__((constructor))
static void BZABBootstrap(void) {
    @autoreleasepool {
        (void)BZABSettings.sharedSettings;
        [BZABCMCCBlocker install];
        [BZABSDKBlocker install];
        [BZABNetworkBlocker install];
        [BZABViewBlocker install];

        dispatch_async(dispatch_get_main_queue(), ^{
            [BZABMenuController.sharedController installGestureEntry];
            [BZABViewBlocker.sharedBlocker startSuppressionScan];
            BZABProfile *profile = BZABProfile.currentProfile;
            BZABLog(@"loaded version=%@ bundle=%@ profile=%@",
                    BZABVersion,
                    NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
                    profile.name);
        });
    }
}
