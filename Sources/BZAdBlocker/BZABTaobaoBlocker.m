#import "BZABTaobaoBlocker.h"
#import "BZABCore.h"
#import <objc/runtime.h>
#import <string.h>

static const void *BZABTaobaoRecordedGenerationKey =
    &BZABTaobaoRecordedGenerationKey;

static IMP _Nullable BZABTaobaoOriginalClassShowCold;
static IMP _Nullable BZABTaobaoOriginalClassShowHot;
static IMP _Nullable BZABTaobaoOriginalInstanceShowCold;
static IMP _Nullable BZABTaobaoOriginalInstanceShowHot;
static IMP _Nullable BZABTaobaoOriginalClassColdWillShow;
static IMP _Nullable BZABTaobaoOriginalClassHotWillShow;
static IMP _Nullable BZABTaobaoOriginalInstanceColdWillShow;
static IMP _Nullable BZABTaobaoOriginalClassColdBootImageWillShow;
static IMP _Nullable BZABTaobaoOriginalInstanceColdBootImageWillShow;

static BOOL BZABTaobaoClassShowColdHooked;
static BOOL BZABTaobaoClassShowHotHooked;
static BOOL BZABTaobaoInstanceShowColdHooked;
static BOOL BZABTaobaoInstanceShowHotHooked;
static BOOL BZABTaobaoClassColdWillShowHooked;
static BOOL BZABTaobaoClassHotWillShowHooked;
static BOOL BZABTaobaoInstanceColdWillShowHooked;
static BOOL BZABTaobaoClassColdBootImageWillShowHooked;
static BOOL BZABTaobaoInstanceColdBootImageWillShowHooked;

static BOOL BZABTaobaoIsTargetApplication(void) {
    return [NSBundle.mainBundle.bundleIdentifier
        isEqualToString:@"com.taobao.taobao4iphone"];
}

static BOOL BZABTaobaoShouldSkipStartupAd(void) {
    BZABSettings *settings = BZABSettings.sharedSettings;
    return BZABTaobaoIsTargetApplication() &&
           settings.enabled &&
           settings.viewBlockingEnabled;
}

static char BZABTaobaoUnqualifiedType(const char *type) {
    if (!type) {
        return '\0';
    }
    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return *type;
}

static BOOL BZABTaobaoMethodMatches(Method method,
                                    unsigned int argumentCount,
                                    const char *allowedReturnTypes) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) {
        return NO;
    }
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return strchr(allowedReturnTypes,
                  BZABTaobaoUnqualifiedType(returnType)) != NULL;
}

static IMP _Nullable BZABTaobaoReplaceMethod(Class cls,
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

static void BZABTaobaoRecordSkipOnce(id object, NSString *eventName) {
    NSUInteger generation = BZABCurrentSuppressionGeneration();
    NSNumber *recordedGeneration = objc_getAssociatedObject(
        object,
        BZABTaobaoRecordedGenerationKey);
    if (recordedGeneration.unsignedIntegerValue == generation) {
        return;
    }
    objc_setAssociatedObject(object,
                             BZABTaobaoRecordedGenerationKey,
                             @(generation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [BZABStats.sharedStats recordTriggeredSkipWithClass:eventName];
}

static BOOL BZABTaobaoInvokeNativeColdSkip(id reason) {
    Class managerClass = NSClassFromString(@"TBBootImageManager");
    SEL selector = NSSelectorFromString(@"skipBootImageViewAtColdStart:");
    if (!managerClass || ![managerClass respondsToSelector:selector]) {
        return NO;
    }
    IMP implementation = [managerClass methodForSelector:selector];
    if (!implementation) {
        return NO;
    }
    ((void (*)(id, SEL, id))implementation)(managerClass, selector, reason);
    return YES;
}

static void BZABTaobaoClassShowCold(id object, SEL selector, id reason) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        BZABTaobaoRecordSkipOnce(object, @"TBBootImageManager.cold-native-skip");
        if (!BZABTaobaoInvokeNativeColdSkip(reason)) {
            BZABLog(@"Taobao cold-start skip selector was unavailable");
        }
        BZABLog(@"skipped Taobao cold-start splash before presentation");
        return;
    }

    if (BZABTaobaoOriginalClassShowCold) {
        ((void (*)(id, SEL, id))BZABTaobaoOriginalClassShowCold)(object,
                                                                 selector,
                                                                 reason);
    }
}

static BOOL BZABTaobaoClassShowHot(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        BZABTaobaoRecordSkipOnce(object, @"TBBootImageManager.hot-return-skip");
        BZABLog(@"declined Taobao hot-start splash presentation");
        return NO;
    }

    if (BZABTaobaoOriginalClassShowHot) {
        return ((BOOL (*)(id, SEL))BZABTaobaoOriginalClassShowHot)(object,
                                                                   selector);
    }
    return NO;
}

static void BZABTaobaoInstanceShowCold(id object, SEL selector, id reason) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        BZABTaobaoRecordSkipOnce(object,
                                 @"TBBootImageManager.cold-instance-skip");
        (void)BZABTaobaoInvokeNativeColdSkip(reason);
        return;
    }

    if (BZABTaobaoOriginalInstanceShowCold) {
        ((void (*)(id, SEL, id))BZABTaobaoOriginalInstanceShowCold)(object,
                                                                    selector,
                                                                    reason);
    }
}

static BOOL BZABTaobaoInstanceShowHot(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        BZABTaobaoRecordSkipOnce(object,
                                 @"TBBootImageManager.hot-instance-skip");
        return NO;
    }

    if (BZABTaobaoOriginalInstanceShowHot) {
        return ((BOOL (*)(id, SEL))BZABTaobaoOriginalInstanceShowHot)(object,
                                                                      selector);
    }
    return NO;
}

static BOOL BZABTaobaoClassColdWillShow(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        return NO;
    }
    if (BZABTaobaoOriginalClassColdWillShow) {
        return ((BOOL (*)(id, SEL))BZABTaobaoOriginalClassColdWillShow)(object,
                                                                        selector);
    }
    return NO;
}

static BOOL BZABTaobaoClassHotWillShow(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        return NO;
    }
    if (BZABTaobaoOriginalClassHotWillShow) {
        return ((BOOL (*)(id, SEL))BZABTaobaoOriginalClassHotWillShow)(object,
                                                                       selector);
    }
    return NO;
}

static BOOL BZABTaobaoInstanceColdWillShow(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        return NO;
    }
    if (BZABTaobaoOriginalInstanceColdWillShow) {
        return ((BOOL (*)(id, SEL))BZABTaobaoOriginalInstanceColdWillShow)(
            object,
            selector);
    }
    return NO;
}

static BOOL BZABTaobaoClassColdBootImageWillShow(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        BZABTaobaoRecordSkipOnce(object,
                                 @"TBBootImageManager.cold-decision-skip");
        (void)BZABTaobaoInvokeNativeColdSkip(nil);
        return NO;
    }
    if (BZABTaobaoOriginalClassColdBootImageWillShow) {
        return ((BOOL (*)(id, SEL))
            BZABTaobaoOriginalClassColdBootImageWillShow)(object, selector);
    }
    return NO;
}

static BOOL BZABTaobaoInstanceColdBootImageWillShow(id object, SEL selector) {
    if (BZABTaobaoShouldSkipStartupAd()) {
        BZABTaobaoRecordSkipOnce(object,
                                 @"TBBootImageManager.cold-decision-skip");
        (void)BZABTaobaoInvokeNativeColdSkip(nil);
        return NO;
    }
    if (BZABTaobaoOriginalInstanceColdBootImageWillShow) {
        return ((BOOL (*)(id, SEL))
            BZABTaobaoOriginalInstanceColdBootImageWillShow)(object, selector);
    }
    return NO;
}

@implementation BZABTaobaoBlocker

+ (BOOL)install {
    if (!BZABTaobaoIsTargetApplication()) {
        return NO;
    }

    [self refreshHooks];
    if ([self nativeFastPathReady]) {
        return YES;
    }

    for (NSNumber *delay in @[@0.1, @0.5, @1.0, @2.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshHooks];
        });
    }
    return NO;
}

+ (BOOL)isTargetApplication {
    return BZABTaobaoIsTargetApplication();
}

+ (BOOL)nativeFastPathReady {
    @synchronized (self) {
        BOOL coldReady = BZABTaobaoClassShowColdHooked ||
                         BZABTaobaoInstanceShowColdHooked;
        BOOL hotReady = BZABTaobaoClassShowHotHooked ||
                        BZABTaobaoInstanceShowHotHooked;
        return coldReady && hotReady;
    }
}

+ (void)refreshHooks {
    if (!BZABTaobaoIsTargetApplication()) {
        return;
    }

    @synchronized (self) {
        Class managerClass = NSClassFromString(@"TBBootImageManager");
        if (!managerClass) {
            return;
        }
        Class managerMetaClass = object_getClass(managerClass);
        BOOL installedAnyHook = NO;

        if (!BZABTaobaoClassShowColdHooked) {
            SEL selector = NSSelectorFromString(@"showBootImageViewAtColdStart:");
            Method method = class_getInstanceMethod(managerMetaClass, selector);
            BOOL hasNativeSkip = [managerClass respondsToSelector:
                NSSelectorFromString(@"skipBootImageViewAtColdStart:")];
            if (hasNativeSkip && BZABTaobaoMethodMatches(method, 3, "v")) {
                BZABTaobaoOriginalClassShowCold = BZABTaobaoReplaceMethod(
                    managerMetaClass,
                    selector,
                    (IMP)BZABTaobaoClassShowCold);
                BZABTaobaoClassShowColdHooked =
                    BZABTaobaoOriginalClassShowCold != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoClassShowColdHooked;
            }
        }

        if (!BZABTaobaoClassShowHotHooked) {
            SEL selector = NSSelectorFromString(@"showBootImageViewAtHotStart");
            Method method = class_getInstanceMethod(managerMetaClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalClassShowHot = BZABTaobaoReplaceMethod(
                    managerMetaClass,
                    selector,
                    (IMP)BZABTaobaoClassShowHot);
                BZABTaobaoClassShowHotHooked =
                    BZABTaobaoOriginalClassShowHot != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoClassShowHotHooked;
            }
        }

        if (!BZABTaobaoInstanceShowColdHooked) {
            SEL selector = NSSelectorFromString(@"showBootImageAtColdStart:");
            Method method = class_getInstanceMethod(managerClass, selector);
            if (BZABTaobaoMethodMatches(method, 3, "v")) {
                BZABTaobaoOriginalInstanceShowCold = BZABTaobaoReplaceMethod(
                    managerClass,
                    selector,
                    (IMP)BZABTaobaoInstanceShowCold);
                BZABTaobaoInstanceShowColdHooked =
                    BZABTaobaoOriginalInstanceShowCold != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoInstanceShowColdHooked;
            }
        }

        if (!BZABTaobaoInstanceShowHotHooked) {
            SEL selector = NSSelectorFromString(@"showBootImageAtHotStart");
            Method method = class_getInstanceMethod(managerClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalInstanceShowHot = BZABTaobaoReplaceMethod(
                    managerClass,
                    selector,
                    (IMP)BZABTaobaoInstanceShowHot);
                BZABTaobaoInstanceShowHotHooked =
                    BZABTaobaoOriginalInstanceShowHot != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoInstanceShowHotHooked;
            }
        }

        if (!BZABTaobaoClassColdWillShowHooked) {
            SEL selector = NSSelectorFromString(@"isColdTaobaoSplashAdvWillShow");
            Method method = class_getInstanceMethod(managerMetaClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalClassColdWillShow = BZABTaobaoReplaceMethod(
                    managerMetaClass,
                    selector,
                    (IMP)BZABTaobaoClassColdWillShow);
                BZABTaobaoClassColdWillShowHooked =
                    BZABTaobaoOriginalClassColdWillShow != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoClassColdWillShowHooked;
            }
        }

        if (!BZABTaobaoClassHotWillShowHooked) {
            SEL selector = NSSelectorFromString(@"isHotStartTaobaoSplashAdvWillShow");
            Method method = class_getInstanceMethod(managerMetaClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalClassHotWillShow = BZABTaobaoReplaceMethod(
                    managerMetaClass,
                    selector,
                    (IMP)BZABTaobaoClassHotWillShow);
                BZABTaobaoClassHotWillShowHooked =
                    BZABTaobaoOriginalClassHotWillShow != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoClassHotWillShowHooked;
            }
        }

        if (!BZABTaobaoInstanceColdWillShowHooked) {
            SEL selector = NSSelectorFromString(@"isColdTaobaoSplashAdvWillShow");
            Method method = class_getInstanceMethod(managerClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalInstanceColdWillShow =
                    BZABTaobaoReplaceMethod(
                        managerClass,
                        selector,
                        (IMP)BZABTaobaoInstanceColdWillShow);
                BZABTaobaoInstanceColdWillShowHooked =
                    BZABTaobaoOriginalInstanceColdWillShow != NULL;
                installedAnyHook = installedAnyHook ||
                                   BZABTaobaoInstanceColdWillShowHooked;
            }
        }

        if (!BZABTaobaoClassColdBootImageWillShowHooked) {
            SEL selector = NSSelectorFromString(@"isColdStartBootImageWillShow");
            Method method = class_getInstanceMethod(managerMetaClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalClassColdBootImageWillShow =
                    BZABTaobaoReplaceMethod(
                        managerMetaClass,
                        selector,
                        (IMP)BZABTaobaoClassColdBootImageWillShow);
                BZABTaobaoClassColdBootImageWillShowHooked =
                    BZABTaobaoOriginalClassColdBootImageWillShow != NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTaobaoClassColdBootImageWillShowHooked;
            }
        }

        if (!BZABTaobaoInstanceColdBootImageWillShowHooked) {
            SEL selector = NSSelectorFromString(@"isColdStartBootImageWillShow");
            Method method = class_getInstanceMethod(managerClass, selector);
            if (BZABTaobaoMethodMatches(method, 2, "Bc")) {
                BZABTaobaoOriginalInstanceColdBootImageWillShow =
                    BZABTaobaoReplaceMethod(
                        managerClass,
                        selector,
                        (IMP)BZABTaobaoInstanceColdBootImageWillShow);
                BZABTaobaoInstanceColdBootImageWillShowHooked =
                    BZABTaobaoOriginalInstanceColdBootImageWillShow != NULL;
                installedAnyHook = installedAnyHook ||
                    BZABTaobaoInstanceColdBootImageWillShowHooked;
            }
        }

        if (installedAnyHook) {
            [BZABStats.sharedStats recordDetectedSDKClass:
                @"TBBootImageManager.cold-hot-native-skip"];
            BZABLog(@"installed Taobao hooks classCold=%d classHot=%d "
                    "instanceCold=%d instanceHot=%d coldFlag=%d "
                    "coldBootFlag=%d hotFlag=%d",
                    BZABTaobaoClassShowColdHooked,
                    BZABTaobaoClassShowHotHooked,
                    BZABTaobaoInstanceShowColdHooked,
                    BZABTaobaoInstanceShowHotHooked,
                    BZABTaobaoClassColdWillShowHooked ||
                        BZABTaobaoInstanceColdWillShowHooked,
                    BZABTaobaoClassColdBootImageWillShowHooked ||
                        BZABTaobaoInstanceColdBootImageWillShowHooked,
                    BZABTaobaoClassHotWillShowHooked);
        }
    }
}

@end
