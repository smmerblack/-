#import "BZABCMCCBlocker.h"
#import "BZABCore.h"
#import <objc/runtime.h>
#import <string.h>

static const void *BZABCMCCRecordedGenerationKey = &BZABCMCCRecordedGenerationKey;
static IMP _Nullable BZABCMCCOriginalShowAD;
static IMP _Nullable BZABCMCCOriginalNeedSkip;
static BOOL BZABCMCCShowADHooked;
static BOOL BZABCMCCNeedSkipHooked;

static BOOL BZABCMCCIsTargetApplication(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"cn.10086.app"];
}

static BOOL BZABCMCCShouldSkipStartupAd(void) {
    BZABSettings *settings = BZABSettings.sharedSettings;
    return BZABCMCCIsTargetApplication() &&
           settings.enabled &&
           settings.viewBlockingEnabled;
}

static char BZABCMCCUnqualifiedType(const char *type) {
    if (!type) {
        return '\0';
    }
    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return *type;
}

static BOOL BZABCMCCMethodMatches(Method method,
                                  unsigned int argumentCount,
                                  const char *allowedReturnTypes) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) {
        return NO;
    }
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return strchr(allowedReturnTypes, BZABCMCCUnqualifiedType(returnType)) != NULL;
}

static IMP _Nullable BZABCMCCReplaceInstanceMethod(Class cls,
                                                    SEL selector,
                                                    IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        return NULL;
    }

    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (class_addMethod(cls, selector, replacement, types)) {
        return original;
    }
    return method_setImplementation(method, replacement);
}

static void BZABCMCCRecordSkipOnce(id object, NSString *eventName) {
    NSUInteger generation = BZABCurrentSuppressionGeneration();
    NSNumber *recordedGeneration = objc_getAssociatedObject(object,
                                                             BZABCMCCRecordedGenerationKey);
    if (recordedGeneration.unsignedIntegerValue == generation) {
        return;
    }
    objc_setAssociatedObject(object,
                             BZABCMCCRecordedGenerationKey,
                             @(generation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [BZABStats.sharedStats recordTriggeredSkipWithClass:eventName];
}

static void BZABCMCCShowAD(id object,
                           SEL selector,
                           id dataDictionary,
                           id videoURLString) {
    if (BZABCMCCShouldSkipStartupAd()) {
        BZABCMCCRecordSkipOnce(object, @"CMStartViewController.native-show-blocked");
        BZABLog(@"blocked native China Mobile startup-ad presentation");
        return;
    }

    if (BZABCMCCOriginalShowAD) {
        ((void (*)(id, SEL, id, id))BZABCMCCOriginalShowAD)(object,
                                                            selector,
                                                            dataDictionary,
                                                            videoURLString);
    }
}

static BOOL BZABCMCCIsNeedSkipStartAd(id object, SEL selector) {
    if (BZABCMCCShouldSkipStartupAd()) {
        BZABCMCCRecordSkipOnce(object, @"CMStartViewController.native-skip");
        BZABLog(@"forced native China Mobile startup-ad skip");
        return YES;
    }

    if (BZABCMCCOriginalNeedSkip) {
        return ((BOOL (*)(id, SEL))BZABCMCCOriginalNeedSkip)(object, selector);
    }
    return NO;
}

@implementation BZABCMCCBlocker

+ (void)install {
    if (!BZABCMCCIsTargetApplication()) {
        return;
    }

    [self refreshHooks];
    for (NSNumber *delay in @[@0.25, @1.0, @2.0, @4.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshHooks];
        });
    }
}

+ (void)refreshHooks {
    if (!BZABCMCCIsTargetApplication() ||
        (BZABCMCCShowADHooked && BZABCMCCNeedSkipHooked)) {
        return;
    }

    @synchronized (self) {
        Class startViewController = NSClassFromString(@"CMStartViewController");
        if (!startViewController) {
            return;
        }

        BOOL installedAnyHook = NO;
        if (!BZABCMCCShowADHooked) {
            SEL selector = NSSelectorFromString(@"showADWithDataDict:videoUrlStr:");
            Method method = class_getInstanceMethod(startViewController, selector);
            if (BZABCMCCMethodMatches(method, 4, "v")) {
                BZABCMCCOriginalShowAD = BZABCMCCReplaceInstanceMethod(
                    startViewController,
                    selector,
                    (IMP)BZABCMCCShowAD);
                BZABCMCCShowADHooked = BZABCMCCOriginalShowAD != NULL;
                installedAnyHook = installedAnyHook || BZABCMCCShowADHooked;
            }
        }

        if (!BZABCMCCNeedSkipHooked) {
            SEL selector = NSSelectorFromString(@"isNeedSkipStartAd");
            Method method = class_getInstanceMethod(startViewController, selector);
            if (BZABCMCCMethodMatches(method, 2, "Bc")) {
                BZABCMCCOriginalNeedSkip = BZABCMCCReplaceInstanceMethod(
                    startViewController,
                    selector,
                    (IMP)BZABCMCCIsNeedSkipStartAd);
                BZABCMCCNeedSkipHooked = BZABCMCCOriginalNeedSkip != NULL;
                installedAnyHook = installedAnyHook || BZABCMCCNeedSkipHooked;
            }
        }

        if (installedAnyHook) {
            [BZABStats.sharedStats recordDetectedSDKClass:@"CMStartViewController.native-skip"];
            BZABLog(@"installed China Mobile native startup-ad hooks show=%d skip=%d",
                    BZABCMCCShowADHooked,
                    BZABCMCCNeedSkipHooked);
        }
    }
}

@end
