#import "BZABTencentVideoBlocker.h"
#import "BZABCore.h"
#import <objc/runtime.h>
#import <string.h>

static const void *BZABTencentVideoRecordedGenerationKey =
    &BZABTencentVideoRecordedGenerationKey;

static IMP _Nullable BZABTencentVideoOriginalShouldDisplaySplash;
static IMP _Nullable BZABTencentVideoOriginalEnableHotSplashForPIP;
static IMP _Nullable BZABTencentVideoOriginalEnableHotSplashForBackgroundTime;
static IMP _Nullable BZABTencentVideoOriginalNeedBlockPauseRequest;
static IMP _Nullable BZABTencentVideoOriginalPauseShowView;
static IMP _Nullable BZABTencentVideoOriginalContainShowPauseItem;

static BOOL BZABTencentVideoShouldDisplaySplashHooked;
static BOOL BZABTencentVideoEnableHotSplashForPIPHooked;
static BOOL BZABTencentVideoEnableHotSplashForBackgroundTimeHooked;
static BOOL BZABTencentVideoNeedBlockPauseRequestHooked;
static BOOL BZABTencentVideoPauseShowViewHooked;
static BOOL BZABTencentVideoContainShowPauseItemHooked;

static BOOL BZABTencentVideoIsTargetApplication(void) {
    return [NSBundle.mainBundle.bundleIdentifier
        isEqualToString:@"com.tencent.live4iphone"];
}

static BOOL BZABTencentVideoShouldBlockAds(void) {
    BZABSettings *settings = BZABSettings.sharedSettings;
    return BZABTencentVideoIsTargetApplication() &&
           settings.enabled &&
           settings.viewBlockingEnabled;
}

static char BZABTencentVideoUnqualifiedType(const char *type) {
    if (!type) {
        return '\0';
    }
    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return *type;
}

static BOOL BZABTencentVideoMethodMatches(Method method,
                                          unsigned int argumentCount,
                                          const char *allowedReturnTypes) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) {
        return NO;
    }
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return strchr(allowedReturnTypes,
                  BZABTencentVideoUnqualifiedType(returnType)) != NULL;
}

static IMP _Nullable BZABTencentVideoReplaceMethod(Class cls,
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

static void BZABTencentVideoRecordSkipOnce(id object, NSString *eventName) {
    NSUInteger generation = BZABCurrentSuppressionGeneration();
    NSNumber *recordedGeneration = objc_getAssociatedObject(
        object,
        BZABTencentVideoRecordedGenerationKey);
    if (recordedGeneration.unsignedIntegerValue == generation) {
        return;
    }
    objc_setAssociatedObject(object,
                             BZABTencentVideoRecordedGenerationKey,
                             @(generation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [BZABStats.sharedStats recordTriggeredSkipWithClass:eventName];
}

static BOOL BZABTencentVideoInvokeVoidSelector(id object,
                                               NSString *selectorName) {
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

static BOOL BZABTencentVideoShouldDisplaySplash(id object, SEL selector) {
    if (BZABTencentVideoShouldBlockAds()) {
        BZABTencentVideoRecordSkipOnce(
            object,
            @"QADSplashSDK.cold-native-decision-skip");
        BZABLog(@"disabled Tencent Video cold-start splash at native decision");
        return NO;
    }

    if (BZABTencentVideoOriginalShouldDisplaySplash) {
        return ((BOOL (*)(id, SEL))
            BZABTencentVideoOriginalShouldDisplaySplash)(object, selector);
    }
    return NO;
}

static BOOL BZABTencentVideoEnableHotSplashForPIP(id object, SEL selector) {
    if (BZABTencentVideoShouldBlockAds()) {
        BZABTencentVideoRecordSkipOnce(
            object,
            @"QADSplashSDK.hot-native-decision-skip");
        return NO;
    }

    if (BZABTencentVideoOriginalEnableHotSplashForPIP) {
        return ((BOOL (*)(id, SEL))
            BZABTencentVideoOriginalEnableHotSplashForPIP)(object, selector);
    }
    return NO;
}

static BOOL BZABTencentVideoEnableHotSplashForBackgroundTime(id object,
                                                              SEL selector) {
    if (BZABTencentVideoShouldBlockAds()) {
        BZABTencentVideoRecordSkipOnce(
            object,
            @"QADSplashSDK.hot-native-decision-skip");
        return NO;
    }

    if (BZABTencentVideoOriginalEnableHotSplashForBackgroundTime) {
        return ((BOOL (*)(id, SEL))
            BZABTencentVideoOriginalEnableHotSplashForBackgroundTime)(object,
                                                                      selector);
    }
    return NO;
}

static BOOL BZABTencentVideoNeedBlockPauseRequest(id object, SEL selector) {
    if (BZABTencentVideoShouldBlockAds()) {
        BZABTencentVideoRecordSkipOnce(
            object,
            @"QADPauseViewController.native-request-block");
        BZABLog(@"blocked Tencent Video pause-ad request at native gate");
        return YES;
    }

    if (BZABTencentVideoOriginalNeedBlockPauseRequest) {
        return ((BOOL (*)(id, SEL))
            BZABTencentVideoOriginalNeedBlockPauseRequest)(object, selector);
    }
    return NO;
}

static void BZABTencentVideoPauseShowView(id object, SEL selector) {
    if (BZABTencentVideoShouldBlockAds()) {
        BZABTencentVideoRecordSkipOnce(
            object,
            @"QADPauseViewController.presentation-skip");
        (void)BZABTencentVideoInvokeVoidSelector(object, @"cancelPauseModel");
        (void)BZABTencentVideoInvokeVoidSelector(object, @"hiddenView");
        return;
    }

    if (BZABTencentVideoOriginalPauseShowView) {
        ((void (*)(id, SEL))BZABTencentVideoOriginalPauseShowView)(object,
                                                                   selector);
    }
}

static void BZABTencentVideoContainShowPauseItem(id object,
                                                 SEL selector,
                                                 id pauseItem,
                                                 id reportHandler) {
    if (BZABTencentVideoShouldBlockAds()) {
        BZABTencentVideoRecordSkipOnce(
            object,
            @"QADPauseContainView.presentation-skip");
        (void)BZABTencentVideoInvokeVoidSelector(object, @"hiddenPauseView");
        return;
    }

    if (BZABTencentVideoOriginalContainShowPauseItem) {
        ((void (*)(id, SEL, id, id))
            BZABTencentVideoOriginalContainShowPauseItem)(object,
                                                          selector,
                                                          pauseItem,
                                                          reportHandler);
    }
}

@implementation BZABTencentVideoBlocker

+ (BOOL)install {
    if (!BZABTencentVideoIsTargetApplication()) {
        return NO;
    }

    [self refreshHooks];
    if ([self nativeFastPathReady]) {
        return YES;
    }

    for (NSNumber *delay in @[@0.1, @0.5, @1.0, @2.0, @4.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshHooks];
        });
    }
    return NO;
}

+ (BOOL)isTargetApplication {
    return BZABTencentVideoIsTargetApplication();
}

+ (BOOL)nativeFastPathReady {
    @synchronized (self) {
        BOOL hotReady = BZABTencentVideoEnableHotSplashForPIPHooked ||
                        BZABTencentVideoEnableHotSplashForBackgroundTimeHooked;
        BOOL pauseReady = BZABTencentVideoNeedBlockPauseRequestHooked &&
                          (BZABTencentVideoPauseShowViewHooked ||
                           BZABTencentVideoContainShowPauseItemHooked);
        return BZABTencentVideoShouldDisplaySplashHooked &&
               hotReady &&
               pauseReady;
    }
}

+ (void)refreshHooks {
    if (!BZABTencentVideoIsTargetApplication()) {
        return;
    }

    @synchronized (self) {
        BOOL installedAnyHook = NO;
        Class splashClass = NSClassFromString(@"QADSplashSDK");
        Class splashMetaClass = splashClass ? object_getClass(splashClass) : Nil;

        if (splashMetaClass && !BZABTencentVideoShouldDisplaySplashHooked) {
            SEL selector = NSSelectorFromString(@"shouldDisplaySplash");
            Method method = class_getInstanceMethod(splashMetaClass, selector);
            if (BZABTencentVideoMethodMatches(method, 2, "Bc")) {
                BZABTencentVideoOriginalShouldDisplaySplash =
                    BZABTencentVideoReplaceMethod(
                        splashMetaClass,
                        selector,
                        (IMP)BZABTencentVideoShouldDisplaySplash);
                BZABTencentVideoShouldDisplaySplashHooked =
                    BZABTencentVideoOriginalShouldDisplaySplash != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTencentVideoShouldDisplaySplashHooked;
            }
        }

        if (splashMetaClass && !BZABTencentVideoEnableHotSplashForPIPHooked) {
            SEL selector = NSSelectorFromString(
                @"enableHotLaunchSplashWithPIPState");
            Method method = class_getInstanceMethod(splashMetaClass, selector);
            if (BZABTencentVideoMethodMatches(method, 2, "Bc")) {
                BZABTencentVideoOriginalEnableHotSplashForPIP =
                    BZABTencentVideoReplaceMethod(
                        splashMetaClass,
                        selector,
                        (IMP)BZABTencentVideoEnableHotSplashForPIP);
                BZABTencentVideoEnableHotSplashForPIPHooked =
                    BZABTencentVideoOriginalEnableHotSplashForPIP != NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTencentVideoEnableHotSplashForPIPHooked;
            }
        }

        if (splashMetaClass &&
            !BZABTencentVideoEnableHotSplashForBackgroundTimeHooked) {
            SEL selector = NSSelectorFromString(
                @"enableHotLaunchSplashWithBackgroundStayTime");
            Method method = class_getInstanceMethod(splashMetaClass, selector);
            if (BZABTencentVideoMethodMatches(method, 2, "Bc")) {
                BZABTencentVideoOriginalEnableHotSplashForBackgroundTime =
                    BZABTencentVideoReplaceMethod(
                        splashMetaClass,
                        selector,
                        (IMP)BZABTencentVideoEnableHotSplashForBackgroundTime);
                BZABTencentVideoEnableHotSplashForBackgroundTimeHooked =
                    BZABTencentVideoOriginalEnableHotSplashForBackgroundTime !=
                    NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTencentVideoEnableHotSplashForBackgroundTimeHooked;
            }
        }

        Class pauseController = NSClassFromString(@"QADPauseViewController");
        if (pauseController &&
            !BZABTencentVideoNeedBlockPauseRequestHooked) {
            SEL selector = NSSelectorFromString(@"needBlockPauseRequest");
            Method method = class_getInstanceMethod(pauseController, selector);
            if (BZABTencentVideoMethodMatches(method, 2, "Bc")) {
                BZABTencentVideoOriginalNeedBlockPauseRequest =
                    BZABTencentVideoReplaceMethod(
                        pauseController,
                        selector,
                        (IMP)BZABTencentVideoNeedBlockPauseRequest);
                BZABTencentVideoNeedBlockPauseRequestHooked =
                    BZABTencentVideoOriginalNeedBlockPauseRequest != NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTencentVideoNeedBlockPauseRequestHooked;
            }
        }

        if (pauseController && !BZABTencentVideoPauseShowViewHooked) {
            SEL selector = NSSelectorFromString(@"showView");
            Method method = class_getInstanceMethod(pauseController, selector);
            if (BZABTencentVideoMethodMatches(method, 2, "v")) {
                BZABTencentVideoOriginalPauseShowView =
                    BZABTencentVideoReplaceMethod(
                        pauseController,
                        selector,
                        (IMP)BZABTencentVideoPauseShowView);
                BZABTencentVideoPauseShowViewHooked =
                    BZABTencentVideoOriginalPauseShowView != NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTencentVideoPauseShowViewHooked;
            }
        }

        Class pauseContainView = NSClassFromString(@"QADPauseContainView");
        if (pauseContainView &&
            !BZABTencentVideoContainShowPauseItemHooked) {
            SEL selector = NSSelectorFromString(@"showPauseItem:reportHandler:");
            Method method = class_getInstanceMethod(pauseContainView, selector);
            if (BZABTencentVideoMethodMatches(method, 4, "v")) {
                BZABTencentVideoOriginalContainShowPauseItem =
                    BZABTencentVideoReplaceMethod(
                        pauseContainView,
                        selector,
                        (IMP)BZABTencentVideoContainShowPauseItem);
                BZABTencentVideoContainShowPauseItemHooked =
                    BZABTencentVideoOriginalContainShowPauseItem != NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTencentVideoContainShowPauseItemHooked;
            }
        }

        if (installedAnyHook) {
            [BZABStats.sharedStats recordDetectedSDKClass:
                @"QADSplashSDK+QADPauseViewController.native-skip"];
            BZABLog(@"installed Tencent Video hooks cold=%d hotPIP=%d "
                    "hotTime=%d pauseGate=%d pauseShow=%d pauseView=%d",
                    BZABTencentVideoShouldDisplaySplashHooked,
                    BZABTencentVideoEnableHotSplashForPIPHooked,
                    BZABTencentVideoEnableHotSplashForBackgroundTimeHooked,
                    BZABTencentVideoNeedBlockPauseRequestHooked,
                    BZABTencentVideoPauseShowViewHooked,
                    BZABTencentVideoContainShowPauseItemHooked);
        }
    }
}

@end
