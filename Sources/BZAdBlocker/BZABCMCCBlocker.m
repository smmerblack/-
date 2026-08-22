#import "BZABCMCCBlocker.h"
#import "BZABCore.h"
#import <objc/runtime.h>
#import <string.h>

static const void *BZABCMCCRecordedGenerationKey = &BZABCMCCRecordedGenerationKey;
static const void *BZABCMCCDirectEntryPendingKey = &BZABCMCCDirectEntryPendingKey;
static IMP _Nullable BZABCMCCOriginalLegacyShowAD;
static IMP _Nullable BZABCMCCOriginalCurrentShowAD;
static IMP _Nullable BZABCMCCOriginalShowADContent;
static IMP _Nullable BZABCMCCOriginalNeedSkip;
static IMP _Nullable BZABCMCCOriginalAddStartInitTimer;
static BOOL BZABCMCCLegacyShowADHooked;
static BOOL BZABCMCCCurrentShowADHooked;
static BOOL BZABCMCCShowADContentHooked;
static BOOL BZABCMCCNeedSkipHooked;
static BOOL BZABCMCCDirectEntryTimerHooked;

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

static BOOL BZABCMCCInvokeVoidSelector(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return NO;
    }
    IMP implementation = [object methodForSelector:selector];
    if (!implementation) {
        return NO;
    }
    ((void (*)(id, SEL))implementation)(object, selector);
    return YES;
}

static void BZABCMCCEnterMainPage(id object, NSString *eventName) {
    if (!BZABCMCCShouldSkipStartupAd()) {
        return;
    }

    BZABCMCCRecordSkipOnce(object, eventName);
    (void)BZABCMCCInvokeVoidSelector(object, @"cancelTimer");
    if (!BZABCMCCInvokeVoidSelector(object, @"skipStartViewAndEnterMainPage")) {
        (void)BZABCMCCInvokeVoidSelector(object, @"startViewFinished");
    }
    BZABLog(@"advanced China Mobile through its native startup completion path");
}

static void BZABCMCCScheduleDirectEntry(id object) {
    if (objc_getAssociatedObject(object, BZABCMCCDirectEntryPendingKey)) {
        return;
    }
    objc_setAssociatedObject(object,
                             BZABCMCCDirectEntryPendingKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(object,
                                 BZABCMCCDirectEntryPendingKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BZABCMCCEnterMainPage(object, @"CMStartViewController.direct-entry");
    });
}

static void BZABCMCCLegacyShowAD(id object,
                                 SEL selector,
                                 id dataDictionary,
                                 id videoURLString) {
    if (BZABCMCCShouldSkipStartupAd()) {
        BZABCMCCEnterMainPage(object, @"CMStartViewController.legacy-show-skip");
        return;
    }

    if (BZABCMCCOriginalLegacyShowAD) {
        ((void (*)(id, SEL, id, id))BZABCMCCOriginalLegacyShowAD)(object,
                                                                  selector,
                                                                  dataDictionary,
                                                                  videoURLString);
    }
}

static void BZABCMCCCurrentShowAD(id object,
                                  SEL selector,
                                  id data,
                                  id videoPath) {
    if (BZABCMCCShouldSkipStartupAd()) {
        BZABCMCCEnterMainPage(object, @"CMStartViewController.current-show-skip");
        return;
    }

    if (BZABCMCCOriginalCurrentShowAD) {
        ((void (*)(id, SEL, id, id))BZABCMCCOriginalCurrentShowAD)(object,
                                                                   selector,
                                                                   data,
                                                                   videoPath);
    }
}

static void BZABCMCCShowADContent(id object,
                                  SEL selector,
                                  id contentView,
                                  double duration) {
    if (BZABCMCCShouldSkipStartupAd()) {
        BZABCMCCEnterMainPage(object, @"CMStartViewController.content-show-skip");
        return;
    }

    if (BZABCMCCOriginalShowADContent) {
        ((void (*)(id, SEL, id, double))BZABCMCCOriginalShowADContent)(object,
                                                                       selector,
                                                                       contentView,
                                                                       duration);
    }
}

static void BZABCMCCAddStartInitTimer(id object, SEL selector) {
    if (BZABCMCCShouldSkipStartupAd()) {
        // In China Mobile 12.5.2 this method is called immediately before
        // homeViewWillStart:. Keep its lightweight state/timer initialization,
        // then cancel that timer on the next main-queue turn and use the app's
        // own startup-completion path without waiting for it to fire.
        if (BZABCMCCOriginalAddStartInitTimer) {
            ((void (*)(id, SEL))BZABCMCCOriginalAddStartInitTimer)(object,
                                                                   selector);
        }
        BZABCMCCScheduleDirectEntry(object);
        return;
    }

    if (BZABCMCCOriginalAddStartInitTimer) {
        ((void (*)(id, SEL))BZABCMCCOriginalAddStartInitTimer)(object, selector);
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

+ (BOOL)install {
    if (!BZABCMCCIsTargetApplication()) {
        return NO;
    }

    [self refreshHooks];
    if ([self nativeFastPathReady]) {
        return YES;
    }

    for (NSNumber *delay in @[@0.25, @1.0, @2.0, @4.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshHooks];
        });
    }
    return NO;
}

+ (BOOL)isTargetApplication {
    return BZABCMCCIsTargetApplication();
}

+ (BOOL)nativeFastPathReady {
    @synchronized (self) {
        BOOL hasPresentationHook = BZABCMCCLegacyShowADHooked ||
                                   BZABCMCCCurrentShowADHooked ||
                                   BZABCMCCShowADContentHooked;
        return BZABCMCCNeedSkipHooked &&
               (BZABCMCCDirectEntryTimerHooked || hasPresentationHook);
    }
}

+ (void)refreshHooks {
    if (!BZABCMCCIsTargetApplication()) {
        return;
    }

    @synchronized (self) {
        Class startViewController = NSClassFromString(@"CMStartViewController");
        if (!startViewController) {
            return;
        }

        BOOL installedAnyHook = NO;
        if (!BZABCMCCLegacyShowADHooked) {
            SEL selector = NSSelectorFromString(@"showADWithDataDict:videoUrlStr:");
            Method method = class_getInstanceMethod(startViewController, selector);
            if (BZABCMCCMethodMatches(method, 4, "v")) {
                BZABCMCCOriginalLegacyShowAD = BZABCMCCReplaceInstanceMethod(
                    startViewController,
                    selector,
                    (IMP)BZABCMCCLegacyShowAD);
                BZABCMCCLegacyShowADHooked = BZABCMCCOriginalLegacyShowAD != NULL;
                installedAnyHook = installedAnyHook || BZABCMCCLegacyShowADHooked;
            }
        }

        if (!BZABCMCCCurrentShowADHooked) {
            SEL selector = NSSelectorFromString(@"showADWithData:videoPath:");
            Method method = class_getInstanceMethod(startViewController, selector);
            if (BZABCMCCMethodMatches(method, 4, "v")) {
                BZABCMCCOriginalCurrentShowAD = BZABCMCCReplaceInstanceMethod(
                    startViewController,
                    selector,
                    (IMP)BZABCMCCCurrentShowAD);
                BZABCMCCCurrentShowADHooked = BZABCMCCOriginalCurrentShowAD != NULL;
                installedAnyHook = installedAnyHook || BZABCMCCCurrentShowADHooked;
            }
        }

        if (!BZABCMCCShowADContentHooked) {
            SEL selector = NSSelectorFromString(@"showADWithContentView:time:");
            Method method = class_getInstanceMethod(startViewController, selector);
            if (BZABCMCCMethodMatches(method, 4, "v")) {
                BZABCMCCOriginalShowADContent = BZABCMCCReplaceInstanceMethod(
                    startViewController,
                    selector,
                    (IMP)BZABCMCCShowADContent);
                BZABCMCCShowADContentHooked = BZABCMCCOriginalShowADContent != NULL;
                installedAnyHook = installedAnyHook || BZABCMCCShowADContentHooked;
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

        if (!BZABCMCCDirectEntryTimerHooked) {
            SEL selector = NSSelectorFromString(@"addStartInitTimer");
            Method method = class_getInstanceMethod(startViewController, selector);
            BOOL hasNativeCompletion =
                class_getInstanceMethod(startViewController,
                                        NSSelectorFromString(@"skipStartViewAndEnterMainPage")) ||
                class_getInstanceMethod(startViewController,
                                        NSSelectorFromString(@"startViewFinished"));
            if (hasNativeCompletion && BZABCMCCMethodMatches(method, 2, "v")) {
                BZABCMCCOriginalAddStartInitTimer = BZABCMCCReplaceInstanceMethod(
                    startViewController,
                    selector,
                    (IMP)BZABCMCCAddStartInitTimer);
                BZABCMCCDirectEntryTimerHooked =
                    BZABCMCCOriginalAddStartInitTimer != NULL;
                installedAnyHook = installedAnyHook || BZABCMCCDirectEntryTimerHooked;
            }
        }

        if (installedAnyHook) {
            [BZABStats.sharedStats recordDetectedSDKClass:@"CMStartViewController.direct-entry"];
            BZABLog(@"installed China Mobile hooks legacy=%d current=%d content=%d "
                    "skip=%d direct=%d",
                    BZABCMCCLegacyShowADHooked,
                    BZABCMCCCurrentShowADHooked,
                    BZABCMCCShowADContentHooked,
                    BZABCMCCNeedSkipHooked,
                    BZABCMCCDirectEntryTimerHooked);
        }
    }
}

@end
