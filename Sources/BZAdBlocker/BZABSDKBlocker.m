#import "BZABSDKBlocker.h"
#import "BZABCore.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

static const void *BZABSDKSuppressedKey = &BZABSDKSuppressedKey;
static NSMutableSet<NSString *> *BZABHookedMethodKeys;
static NSMutableDictionary<NSString *, NSValue *> *BZABOriginalImplementations;
static CFTimeInterval BZABLastHookRefresh;

static NSString *BZABMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@:%@",
            NSStringFromClass(cls),
            NSStringFromSelector(selector)];
}

static IMP _Nullable BZABOriginalImplementation(id object, SEL selector) {
    @synchronized (BZABHookedMethodKeys) {
        for (Class cls = [object class]; cls; cls = class_getSuperclass(cls)) {
            NSValue *value = BZABOriginalImplementations[BZABMethodKey(cls, selector)];
            if (value) {
                return value.pointerValue;
            }
        }
    }
    return NULL;
}

static BOOL BZABShouldSuppressSDKEntry(void) {
    BZABSettings *settings = BZABSettings.sharedSettings;
    return settings.enabled &&
           settings.viewBlockingEnabled &&
           BZABIsInsideSuppressionWindow();
}

static BOOL BZABClassNameLooksLikeStartupAd(NSString *className) {
    NSString *name = className.lowercaseString;
    if (name.length == 0) {
        return NO;
    }
    NSArray<NSString *> *needles = @[
        @"splashad", @"adsplash", @"splashview", @"splashmanager",
        @"launchad", @"adlaunch", @"launchadvert", @"startupad",
        @"startupadvert", @"openad", @"appopenad", @"openingad"
    ];
    return BZABStringContainsAnyNeedle(name, needles);
}

static BOOL BZABSelectorLooksLikeLoadOrShow(SEL selector) {
    NSString *name = NSStringFromSelector(selector).lowercaseString;
    NSArray<NSString *> *prefixes = @[
        @"loadad", @"loadandshow", @"loadsplash", @"requestad",
        @"showad", @"showsplash", @"presentsplash", @"presentad",
        @"presentfrom"
    ];
    for (NSString *prefix in prefixes) {
        if ([name hasPrefix:prefix]) {
            return YES;
        }
    }
    return NO;
}

static id _Nullable BZABDelegateForObject(id object) {
    for (NSString *selectorName in @[@"delegate", @"splashDelegate", @"adDelegate"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([object respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
    }
    return nil;
}

static void BZABNotifySDKClosed(id splashObject, SEL blockedSelector) {
    if (!splashObject || objc_getAssociatedObject(splashObject, BZABSDKSuppressedKey)) {
        return;
    }
    objc_setAssociatedObject(splashObject,
                             BZABSDKSuppressedKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *className = NSStringFromClass([splashObject class]);
    NSString *eventName = [NSString stringWithFormat:@"%@.%@",
                           className,
                           NSStringFromSelector(blockedSelector)];
    [BZABStats.sharedStats recordTriggeredSkipWithClass:eventName];
    BZABLog(@"suppressed SDK splash entry=%@", eventName);

    dispatch_async(dispatch_get_main_queue(), ^{
        id delegate = BZABDelegateForObject(splashObject);
        NSArray<NSString *> *closeCallbacks = @[
            @"msSplashClosed:",
            @"splashAdDidClose:",
            @"splashAdClosed:",
            @"nativeExpressSplashViewDidClose:",
            @"windSplashAdDidClose:",
            @"ksad_splashAdDidClose:",
            @"adDidDismissFullScreenContent:",
            @"adDidDismiss:"
        ];
        for (NSString *callbackName in closeCallbacks) {
            SEL callback = NSSelectorFromString(callbackName);
            if ([delegate respondsToSelector:callback]) {
                ((void (*)(id, SEL, id))objc_msgSend)(delegate, callback, splashObject);
                return;
            }
        }

        NSArray<NSString *> *skipCallbacks = @[
            @"msSplashSkip:",
            @"splashAdDidClickSkip:",
            @"nativeExpressSplashViewDidClickSkip:",
            @"splashAdCountdownToZero:"
        ];
        for (NSString *callbackName in skipCallbacks) {
            SEL callback = NSSelectorFromString(callbackName);
            if ([delegate respondsToSelector:callback]) {
                ((void (*)(id, SEL, id))objc_msgSend)(delegate, callback, splashObject);
                return;
            }
        }

        for (NSString *cleanupName in @[@"removeSplashView", @"close", @"dismiss"]) {
            SEL cleanup = NSSelectorFromString(cleanupName);
            if ([splashObject respondsToSelector:cleanup]) {
                ((void (*)(id, SEL))objc_msgSend)(splashObject, cleanup);
                return;
            }
        }
    });
}

static void BZABSuppressSDK0(id object, SEL selector) {
    if (BZABShouldSuppressSDKEntry()) {
        BZABNotifySDKClosed(object, selector);
        return;
    }
    IMP original = BZABOriginalImplementation(object, selector);
    if (original) {
        ((void (*)(id, SEL))original)(object, selector);
    }
}

static void BZABSuppressSDK1(id object, SEL selector, id argument1) {
    if (BZABShouldSuppressSDKEntry()) {
        BZABNotifySDKClosed(object, selector);
        return;
    }
    IMP original = BZABOriginalImplementation(object, selector);
    if (original) {
        ((void (*)(id, SEL, id))original)(object, selector, argument1);
    }
}

static void BZABSuppressSDK2(id object,
                            SEL selector,
                            id argument1,
                            id argument2) {
    if (BZABShouldSuppressSDKEntry()) {
        BZABNotifySDKClosed(object, selector);
        return;
    }
    IMP original = BZABOriginalImplementation(object, selector);
    if (original) {
        ((void (*)(id, SEL, id, id))original)(object, selector, argument1, argument2);
    }
}

static void BZABSuppressSDK3(id object,
                            SEL selector,
                            id argument1,
                            id argument2,
                            id argument3) {
    if (BZABShouldSuppressSDKEntry()) {
        BZABNotifySDKClosed(object, selector);
        return;
    }
    IMP original = BZABOriginalImplementation(object, selector);
    if (original) {
        ((void (*)(id, SEL, id, id, id))original)(object,
                                                  selector,
                                                  argument1,
                                                  argument2,
                                                  argument3);
    }
}

static void BZABSuppressSDK4(id object,
                            SEL selector,
                            id argument1,
                            id argument2,
                            id argument3,
                            id argument4) {
    if (BZABShouldSuppressSDKEntry()) {
        BZABNotifySDKClosed(object, selector);
        return;
    }
    IMP original = BZABOriginalImplementation(object, selector);
    if (original) {
        ((void (*)(id, SEL, id, id, id, id))original)(object,
                                                      selector,
                                                      argument1,
                                                      argument2,
                                                      argument3,
                                                      argument4);
    }
}

static IMP BZABReplacementForMethod(Method method) {
    switch (method_getNumberOfArguments(method)) {
        case 2: return (IMP)BZABSuppressSDK0;
        case 3: return (IMP)BZABSuppressSDK1;
        case 4: return (IMP)BZABSuppressSDK2;
        case 5: return (IMP)BZABSuppressSDK3;
        default: return (IMP)BZABSuppressSDK4;
    }
}

static BOOL BZABMethodUsesObjectArguments(Method method) {
    unsigned int argumentCount = method_getNumberOfArguments(method);
    for (unsigned int index = 2; index < argumentCount; index++) {
        char argumentType[64] = {0};
        method_getArgumentType(method, index, argumentType, sizeof(argumentType));
        const char *type = argumentType;
        while (*type && strchr("rnNoORV", *type)) {
            type++;
        }
        if (*type != '@' && *type != '#' && *type != ':' && *type != '^') {
            return NO;
        }
    }
    return YES;
}

static void BZABHookStartupAdClass(Class cls) {
    unsigned int methodCount = 0;
    BOOL hookedAnyMethod = NO;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int index = 0; index < methodCount; index++) {
        Method method = methods[index];
        SEL selector = method_getName(method);
        if (!BZABSelectorLooksLikeLoadOrShow(selector)) {
            continue;
        }

        char returnType[16] = {0};
        method_getReturnType(method, returnType, sizeof(returnType));
        if (returnType[0] != 'v') {
            continue;
        }

        unsigned int argumentCount = method_getNumberOfArguments(method);
        if (argumentCount > 6 || !BZABMethodUsesObjectArguments(method)) {
            continue;
        }

        NSString *key = BZABMethodKey(cls, selector);
        @synchronized (BZABHookedMethodKeys) {
            if ([BZABHookedMethodKeys containsObject:key]) {
                continue;
            }
            IMP original = method_getImplementation(method);
            BZABOriginalImplementations[key] = [NSValue valueWithPointer:original];
            method_setImplementation(method, BZABReplacementForMethod(method));
            [BZABHookedMethodKeys addObject:key];
            hookedAnyMethod = YES;
        }
        BZABLog(@"hooked SDK splash method=%@", key);
    }
    free(methods);
    if (hookedAnyMethod) {
        [BZABStats.sharedStats recordDetectedSDKClass:NSStringFromClass(cls)];
    }
}

@implementation BZABSDKBlocker

+ (void)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BZABHookedMethodKeys = [NSMutableSet set];
        BZABOriginalImplementations = [NSMutableDictionary dictionary];
        [self refreshHooks];
    });
}

+ (void)refreshHooks {
    CFTimeInterval now = CACurrentMediaTime();
    if (BZABLastHookRefresh > 0 && now - BZABLastHookRefresh < 0.75) {
        return;
    }
    BZABLastHookRefresh = now;

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        return;
    }
    __unsafe_unretained Class *classes =
        (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    classCount = objc_getClassList(classes, classCount);
    for (int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        if (BZABClassNameLooksLikeStartupAd(NSStringFromClass(cls))) {
            BZABHookStartupAdClass(cls);
        }
    }
    free(classes);
}

@end
