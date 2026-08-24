#import "BZABGuaziBlocker.h"
#import "BZABCore.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

static const void *BZABGuaziCloseAttemptGenerationKey =
    &BZABGuaziCloseAttemptGenerationKey;
static const void *BZABGuaziTimerGenerationKey =
    &BZABGuaziTimerGenerationKey;

static IMP _Nullable BZABGuaziOriginalCreateTimer;
static IMP _Nullable BZABGuaziOriginalSetTextStorage;
static BOOL BZABGuaziCreateTimerHooked;
static BOOL BZABGuaziSetTextStorageHooked;

@interface BZABGuaziBlocker (InternalScanRequest)
+ (void)requestViewScan;
@end

static BOOL BZABGuaziIsTargetApplication(void) {
    return [NSBundle.mainBundle.bundleIdentifier
        isEqualToString:@"com.Tajjwab.numberPulse"];
}

static BOOL BZABGuaziShouldBlockAds(void) {
    BZABSettings *settings = BZABSettings.sharedSettings;
    return BZABGuaziIsTargetApplication() &&
           settings.enabled &&
           settings.viewBlockingEnabled;
}

static char BZABGuaziUnqualifiedType(const char *type) {
    if (!type) {
        return '\0';
    }
    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return *type;
}

static BOOL BZABGuaziArgumentMatches(Method method,
                                     unsigned int index,
                                     const char *allowedTypes) {
    char argumentType[32] = {0};
    method_getArgumentType(method, index, argumentType, sizeof(argumentType));
    return strchr(allowedTypes,
                  BZABGuaziUnqualifiedType(argumentType)) != NULL;
}

static BOOL BZABGuaziTimerMethodMatches(Method method) {
    if (!method || method_getNumberOfArguments(method) != 6) {
        return NO;
    }
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return BZABGuaziUnqualifiedType(returnType) == 'v' &&
           BZABGuaziArgumentMatches(method, 2, "d") &&
           BZABGuaziArgumentMatches(method, 3, "d") &&
           BZABGuaziArgumentMatches(method, 4, "d") &&
           BZABGuaziArgumentMatches(method, 5, "Bc");
}

static void BZABGuaziRecordTimerSkipOnce(id object) {
    NSUInteger generation = BZABCurrentSuppressionGeneration();
    NSNumber *recordedGeneration = objc_getAssociatedObject(
        object,
        BZABGuaziTimerGenerationKey);
    if (recordedGeneration.unsignedIntegerValue == generation) {
        return;
    }
    objc_setAssociatedObject(object,
                             BZABGuaziTimerGenerationKey,
                             @(generation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [BZABStats.sharedStats recordTriggeredSkipWithClass:
        @"RCTTiming.guazi-five-second-fast-forward"];
}

static void BZABGuaziCreateTimer(id object,
                                 SEL selector,
                                 double callbackID,
                                 double duration,
                                 double jsSchedulingTime,
                                 BOOL repeats) {
    double forwardedDuration = duration;
    if (BZABGuaziShouldBlockAds() &&
        BZABIsInsideSuppressionWindow() &&
        !repeats &&
        duration >= 4500.0 && duration <= 6500.0) {
        forwardedDuration = 50.0;
        BZABGuaziRecordTimerSkipOnce(object);
        BZABLog(@"fast-forwarded Guazi one-shot timer duration=%.0fms",
                duration);
    }

    if (BZABGuaziOriginalCreateTimer) {
        ((void (*)(id, SEL, double, double, double, BOOL))
            BZABGuaziOriginalCreateTimer)(object,
                                          selector,
                                          callbackID,
                                          forwardedDuration,
                                          jsSchedulingTime,
                                          repeats);
    }
}

static IMP _Nullable BZABGuaziReplaceMethod(Class cls,
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

static BOOL BZABGuaziTextStorageMethodMatches(Method method) {
    if (!method || method_getNumberOfArguments(method) != 5) {
        return NO;
    }
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return BZABGuaziUnqualifiedType(returnType) == 'v' &&
           BZABGuaziArgumentMatches(method, 2, "@") &&
           BZABGuaziArgumentMatches(method, 3, "{") &&
           BZABGuaziArgumentMatches(method, 4, "@");
}

static void BZABGuaziSetTextStorage(id object,
                                    SEL selector,
                                    id textStorage,
                                    CGRect contentFrame,
                                    id descendantViews) {
    if (BZABGuaziOriginalSetTextStorage) {
        ((void (*)(id, SEL, id, CGRect, id))
            BZABGuaziOriginalSetTextStorage)(object,
                                             selector,
                                             textStorage,
                                             contentFrame,
                                             descendantViews);
    }
    if (BZABGuaziShouldBlockAds()) {
        [BZABGuaziBlocker requestViewScan];
    }
}

static NSArray<NSString *> *BZABGuaziHomeAdNeedles(void) {
    static NSArray<NSString *> *needles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        needles = @[
            @"PG官方", @"开元棋牌", @"P直播", @"全国空降",
            @"新葡京", @"同城小姐", @"免费约妞", @"更多应用",
            @"官方扶持", @"免费旋转", @"直播免费看", @"爆大奖",
            @"莞式服务", @"大放水", @"上门服务", @"送1888"
        ];
    });
    return needles;
}

static NSSet<NSString *> *BZABGuaziMatchesForText(NSString *text) {
    if (text.length == 0) {
        return [NSSet set];
    }
    NSString *normalized = text.lowercaseString;
    NSMutableSet<NSString *> *matches = [NSMutableSet set];
    for (NSString *needle in BZABGuaziHomeAdNeedles()) {
        if ([normalized containsString:needle.lowercaseString]) {
            [matches addObject:needle];
        }
    }
    return matches;
}

static BOOL BZABGuaziTextMeansCloseAd(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    NSString *normalized = [text.lowercaseString
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (normalized.length > 24) {
        return NO;
    }
    return [normalized containsString:@"关闭广告"] ||
           [normalized containsString:@"跳过广告"] ||
           [normalized isEqualToString:@"close ad"];
}

static id _Nullable BZABGuaziObjectGetter(id object, SEL selector) {
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return nil;
    }
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (BZABGuaziUnqualifiedType(returnType) != '@') {
        return nil;
    }
    IMP implementation = [object methodForSelector:selector];
    return implementation
        ? ((id (*)(id, SEL))implementation)(object, selector)
        : nil;
}

static BOOL BZABGuaziInvokeReactTextClick(UIView *view) {
    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate && depth < 5; depth++) {
        NSString *className = NSStringFromClass(candidate.class).lowercaseString;
        if ([className containsString:@"rcttextview"]) {
            SEL selector = NSSelectorFromString(@"onClick");
            Method method = class_getInstanceMethod(candidate.class, selector);
            char returnType[32] = {0};
            if (method) {
                method_getReturnType(method, returnType, sizeof(returnType));
            }
            if (returnType[0] == '@' && returnType[1] == '?') {
                id value = BZABGuaziObjectGetter(candidate, selector);
                if (value) {
                    id reactTag = BZABGuaziObjectGetter(
                        candidate,
                        NSSelectorFromString(@"reactTag"));
                    NSDictionary *payload = reactTag
                        ? @{@"target": reactTag}
                        : @{};
                    void (^clickHandler)(NSDictionary *) =
                        (void (^)(NSDictionary *))value;
                    clickHandler(payload);
                    return YES;
                }
            }
        }
        candidate = candidate.superview;
    }
    return NO;
}

static void BZABGuaziDismissModalIfAvailable(UIView *view) {
    SEL selector = NSSelectorFromString(@"dismissModalViewController");
    if (![view respondsToSelector:selector]) {
        return;
    }
    IMP implementation = [view methodForSelector:selector];
    if (implementation) {
        ((void (*)(id, SEL))implementation)(view, selector);
    }
}

static NSString *BZABGuaziVisibleText(UIView *view) {
    NSString *text = nil;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        text = [button titleForState:UIControlStateNormal] ?: button.currentTitle;
    } else if ([view isKindOfClass:UILabel.class]) {
        text = ((UILabel *)view).text;
    } else if ([view isKindOfClass:UITextView.class]) {
        text = ((UITextView *)view).text;
    } else if ([view isKindOfClass:UITextField.class]) {
        text = ((UITextField *)view).text;
    }

    if (text.length == 0) {
        text = view.accessibilityLabel;
    }
    if (text.length == 0) {
        text = view.accessibilityValue;
    }

    NSString *className = NSStringFromClass(view.class).lowercaseString;
    if (text.length == 0 &&
        ([className containsString:@"text"] ||
         [className containsString:@"paragraph"])) {
        for (NSString *selectorName in @[@"text", @"attributedText", @"textStorage"]) {
            id value = BZABGuaziObjectGetter(view,
                NSSelectorFromString(selectorName));
            if ([value isKindOfClass:NSString.class]) {
                text = value;
            } else if ([value isKindOfClass:NSAttributedString.class]) {
                text = ((NSAttributedString *)value).string;
            }
            if (text.length > 0) {
                break;
            }
        }
    }
    return text ?: @"";
}

static NSArray<UIWindow *> *BZABGuaziApplicationWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
    }
    if (windows.count == 0) {
        [windows addObjectsFromArray:application.windows];
    }
    return windows;
}

@interface BZABGuaziBlocker ()
@property (nonatomic, strong, nullable) NSTimer *scanTimer;
@property (nonatomic, assign) CFTimeInterval scanDeadline;
@property (nonatomic, assign) BOOL scanScheduled;
@property (nonatomic, assign) BOOL observedBackground;
+ (instancetype)sharedBlocker;
- (void)requestScanAfter:(NSTimeInterval)delay;
- (void)startScanForDuration:(NSTimeInterval)duration;
- (void)scanAllWindows;
- (void)applicationDidEnterBackground:(NSNotification *)notification;
- (void)applicationWillEnterForeground:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
- (void)windowDidBecomeVisible:(NSNotification *)notification;
@end

@interface UIView (BZABGuaziInsertionScan)
- (void)bzab_guazi_didMoveToWindow;
@end

@implementation UIView (BZABGuaziInsertionScan)

- (void)bzab_guazi_didMoveToWindow {
    [self bzab_guazi_didMoveToWindow];
    if (self.window && BZABGuaziShouldBlockAds()) {
        [BZABGuaziBlocker.sharedBlocker requestScanAfter:0.05];
    }
}

@end

@implementation BZABGuaziBlocker

+ (instancetype)sharedBlocker {
    static BZABGuaziBlocker *blocker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blocker = [[BZABGuaziBlocker alloc] init];
    });
    return blocker;
}

+ (BOOL)install {
    if (!BZABGuaziIsTargetApplication()) {
        return NO;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMethod = class_getInstanceMethod(
            UIView.class,
            @selector(didMoveToWindow));
        Method replacementMethod = class_getInstanceMethod(
            UIView.class,
            @selector(bzab_guazi_didMoveToWindow));
        if (originalMethod && replacementMethod) {
            method_exchangeImplementations(originalMethod, replacementMethod);
        }

        BZABGuaziBlocker *blocker = BZABGuaziBlocker.sharedBlocker;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:blocker
                   selector:@selector(applicationDidEnterBackground:)
                       name:UIApplicationDidEnterBackgroundNotification
                     object:nil];
        [center addObserver:blocker
                   selector:@selector(applicationWillEnterForeground:)
                       name:UIApplicationWillEnterForegroundNotification
                     object:nil];
        [center addObserver:blocker
                   selector:@selector(applicationDidBecomeActive:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:nil];
        [center addObserver:blocker
                   selector:@selector(windowDidBecomeVisible:)
                       name:UIWindowDidBecomeVisibleNotification
                     object:nil];
        if (@available(iOS 13.0, *)) {
            [center addObserver:blocker
                       selector:@selector(applicationDidEnterBackground:)
                           name:UISceneDidEnterBackgroundNotification
                         object:nil];
            [center addObserver:blocker
                       selector:@selector(applicationWillEnterForeground:)
                           name:UISceneWillEnterForegroundNotification
                         object:nil];
        }
    });

    [self refreshHooks];
    [self rescanAds];
    for (NSNumber *delay in @[@0.1, @0.5, @1.0, @2.0, @4.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshHooks];
        });
    }
    return [self nativeFastPathReady];
}

+ (BOOL)isTargetApplication {
    return BZABGuaziIsTargetApplication();
}

+ (BOOL)nativeFastPathReady {
    @synchronized (self) {
        return BZABGuaziCreateTimerHooked;
    }
}

+ (void)refreshHooks {
    if (!BZABGuaziIsTargetApplication()) {
        return;
    }
    @synchronized (self) {
        if (BZABGuaziCreateTimerHooked && BZABGuaziSetTextStorageHooked) {
            return;
        }
        if (!BZABGuaziCreateTimerHooked) {
            Class timingClass = NSClassFromString(@"RCTTiming");
            SEL selector = NSSelectorFromString(
                @"createTimer:duration:jsSchedulingTime:repeats:");
            Method method = class_getInstanceMethod(timingClass, selector);
            if (timingClass && BZABGuaziTimerMethodMatches(method)) {
                BZABGuaziOriginalCreateTimer = BZABGuaziReplaceMethod(
                    timingClass,
                    selector,
                    (IMP)BZABGuaziCreateTimer);
                BZABGuaziCreateTimerHooked =
                    BZABGuaziOriginalCreateTimer != NULL;
                if (BZABGuaziCreateTimerHooked) {
                    [BZABStats.sharedStats recordDetectedSDKClass:
                        @"RCTTiming+Guazi.native-fast-path"];
                    BZABLog(@"installed Guazi RCTTiming five-second fast path");
                }
            }
        }

        if (!BZABGuaziSetTextStorageHooked) {
            Class textViewClass = NSClassFromString(@"RCTTextView");
            SEL selector = NSSelectorFromString(
                @"setTextStorage:contentFrame:descendantViews:");
            Method method = class_getInstanceMethod(textViewClass, selector);
            if (textViewClass && BZABGuaziTextStorageMethodMatches(method)) {
                BZABGuaziOriginalSetTextStorage = BZABGuaziReplaceMethod(
                    textViewClass,
                    selector,
                    (IMP)BZABGuaziSetTextStorage);
                BZABGuaziSetTextStorageHooked =
                    BZABGuaziOriginalSetTextStorage != NULL;
            }
        }
    }
}

+ (void)requestViewScan {
    if (BZABGuaziIsTargetApplication()) {
        [BZABGuaziBlocker.sharedBlocker requestScanAfter:0.05];
    }
}

+ (void)rescanAds {
    if (!BZABGuaziIsTargetApplication()) {
        return;
    }
    BZABExtendSuppressionWindow(12.0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [BZABGuaziBlocker.sharedBlocker startScanForDuration:20.0];
    });
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    (void)notification;
    self.observedBackground = YES;
    [self.scanTimer invalidate];
    self.scanTimer = nil;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    (void)notification;
    if (!self.observedBackground) {
        return;
    }
    self.observedBackground = NO;
    NSTimeInterval duration = BZABProfile.currentProfile.resumeSuppressionDuration;
    BZABExtendSuppressionWindow(duration);
    [self startScanForDuration:MAX(12.0, duration)];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    [self requestScanAfter:0.05];
}

- (void)windowDidBecomeVisible:(NSNotification *)notification {
    (void)notification;
    [self requestScanAfter:0.05];
}

- (void)startScanForDuration:(NSTimeInterval)duration {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startScanForDuration:duration];
        });
        return;
    }
    [self.scanTimer invalidate];
    self.scanDeadline = CACurrentMediaTime() + MAX(1.0, MIN(30.0, duration));
    self.scanTimer = [NSTimer timerWithTimeInterval:0.25
                                             target:self
                                           selector:@selector(scanTick:)
                                           userInfo:nil
                                            repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.scanTimer
                            forMode:NSRunLoopCommonModes];
    [self scanAllWindows];
}

- (void)scanTick:(NSTimer *)timer {
    if (CACurrentMediaTime() >= self.scanDeadline ||
        !BZABGuaziShouldBlockAds()) {
        [timer invalidate];
        if (timer == self.scanTimer) {
            self.scanTimer = nil;
        }
        return;
    }
    [self scanAllWindows];
}

- (void)requestScanAfter:(NSTimeInterval)delay {
    if (self.scanScheduled || !BZABGuaziShouldBlockAds()) {
        return;
    }
    self.scanScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(MAX(0.0, delay) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.scanScheduled = NO;
        [self scanAllWindows];
    });
}

- (nullable UIControl *)controlForView:(UIView *)view {
    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate && depth < 7; depth++) {
        if ([candidate isKindOfClass:UIControl.class]) {
            return (UIControl *)candidate;
        }
        candidate = candidate.superview;
    }
    return nil;
}

- (nullable UIView *)popupOverlayForCloseView:(UIView *)view {
    UIWindow *window = view.window;
    UIView *rootView = window.rootViewController.view;
    if (!window || !rootView) {
        return nil;
    }
    CGFloat windowArea = CGRectGetWidth(window.bounds) * CGRectGetHeight(window.bounds);
    if (windowArea <= 0.0) {
        return nil;
    }

    UIView *largestOverlay = nil;
    CGFloat largestArea = 0.0;
    for (UIView *candidate = view.superview;
         candidate && candidate != window && candidate != rootView;
         candidate = candidate.superview) {
        NSString *className = NSStringFromClass(candidate.class).lowercaseString;
        if ([className containsString:@"modalhost"] ||
            [className containsString:@"modalcontainer"]) {
            return candidate;
        }
        CGRect frame = [candidate convertRect:candidate.bounds toView:window];
        CGRect visibleFrame = CGRectIntersection(frame, window.bounds);
        CGFloat area = MAX(0.0, CGRectGetWidth(visibleFrame)) *
                       MAX(0.0, CGRectGetHeight(visibleFrame));
        if (area / windowArea >= 0.35 && area > largestArea) {
            largestArea = area;
            largestOverlay = candidate;
        }
    }
    return largestOverlay;
}

- (BOOL)activateOrHidePopupAtCloseView:(UIView *)view {
    NSUInteger generation = BZABCurrentSuppressionGeneration();
    NSNumber *attemptedGeneration = objc_getAssociatedObject(
        view,
        BZABGuaziCloseAttemptGenerationKey);
    if (attemptedGeneration.unsignedIntegerValue == generation) {
        UIView *overlay = [self popupOverlayForCloseView:view];
        if (overlay) {
            BZABGuaziDismissModalIfAvailable(overlay);
            overlay.userInteractionEnabled = NO;
            overlay.hidden = YES;
            [BZABStats.sharedStats recordBlockedClass:
                @"Guazi.popup-ad-overlay"];
            return YES;
        }
        return NO;
    }

    if (BZABGuaziInvokeReactTextClick(view)) {
        objc_setAssociatedObject(view,
                                 BZABGuaziCloseAttemptGenerationKey,
                                 @(generation),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [BZABStats.sharedStats recordTriggeredSkipWithClass:
            @"Guazi.popup-react-close"];
        [self requestScanAfter:0.35];
        return YES;
    }

    UIControl *control = [self controlForView:view];
    if (control && control.enabled && !control.hidden && control.alpha > 0.01) {
        objc_setAssociatedObject(view,
                                 BZABGuaziCloseAttemptGenerationKey,
                                 @(generation),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        [BZABStats.sharedStats recordTriggeredSkipWithClass:
            @"Guazi.popup-close-control"];
        [self requestScanAfter:0.35];
        return YES;
    }

    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate && depth < 7; depth++) {
        if ([candidate accessibilityActivate]) {
            objc_setAssociatedObject(view,
                                     BZABGuaziCloseAttemptGenerationKey,
                                     @(generation),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [BZABStats.sharedStats recordTriggeredSkipWithClass:
                @"Guazi.popup-accessibility-close"];
            [self requestScanAfter:0.35];
            return YES;
        }
        candidate = candidate.superview;
    }

    UIView *overlay = [self popupOverlayForCloseView:view];
    if (overlay) {
        objc_setAssociatedObject(view,
                                 BZABGuaziCloseAttemptGenerationKey,
                                 @(generation),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BZABGuaziDismissModalIfAvailable(overlay);
        overlay.userInteractionEnabled = NO;
        overlay.hidden = YES;
        [BZABStats.sharedStats recordTriggeredSkipWithClass:
            @"Guazi.popup-overlay-close"];
        [BZABStats.sharedStats recordBlockedClass:
            @"Guazi.popup-ad-overlay"];
        return YES;
    }
    return NO;
}

- (BOOL)findAndClosePopupInView:(UIView *)view
                         visited:(NSUInteger *)visited {
    if (!view || view.hidden || view.alpha <= 0.01 || *visited >= 5000) {
        return NO;
    }
    *visited += 1;
    if (BZABGuaziTextMeansCloseAd(BZABGuaziVisibleText(view)) &&
        [self activateOrHidePopupAtCloseView:view]) {
        return YES;
    }
    for (UIView *subview in [view.subviews copy]) {
        if ([self findAndClosePopupInView:subview visited:visited]) {
            return YES;
        }
    }
    return NO;
}

- (NSSet<NSString *> *)collectHomeEvidenceInView:(UIView *)view
                                   evidenceViews:(NSMutableArray<UIView *> *)evidenceViews
                                         visited:(NSUInteger *)visited {
    if (!view || view.hidden || view.alpha <= 0.01 || *visited >= 5000) {
        return [NSSet set];
    }
    *visited += 1;

    NSMutableSet<NSString *> *childMatches = [NSMutableSet set];
    for (UIView *subview in [view.subviews copy]) {
        [childMatches unionSet:[self collectHomeEvidenceInView:subview
                                                 evidenceViews:evidenceViews
                                                       visited:visited]];
    }

    NSSet<NSString *> *ownMatches = BZABGuaziMatchesForText(
        BZABGuaziVisibleText(view));
    if (ownMatches.count > 0) {
        NSMutableSet<NSString *> *newMatches = [ownMatches mutableCopy];
        [newMatches minusSet:childMatches];
        if (childMatches.count == 0 || newMatches.count > 0) {
            [evidenceViews addObject:view];
        }
    }
    [childMatches unionSet:ownMatches];
    return childMatches;
}

- (nullable UIView *)tileAncestorForEvidenceView:(UIView *)view
                                          window:(UIWindow *)window {
    CGFloat windowWidth = CGRectGetWidth(window.bounds);
    CGFloat windowHeight = CGRectGetHeight(window.bounds);
    CGFloat windowArea = windowWidth * windowHeight;
    if (windowArea <= 0.0) {
        return nil;
    }
    UIView *rootView = window.rootViewController.view;
    UIView *bestCandidate = nil;
    UIView *candidate = view;
    for (NSUInteger depth = 0;
         candidate && candidate != window && candidate != rootView && depth < 9;
         depth++, candidate = candidate.superview) {
        CGRect frame = [candidate convertRect:candidate.bounds toView:window];
        CGRect visibleFrame = CGRectIntersection(frame, window.bounds);
        CGFloat width = CGRectGetWidth(visibleFrame);
        CGFloat height = CGRectGetHeight(visibleFrame);
        CGFloat area = MAX(0.0, width) * MAX(0.0, height);
        if (width >= 28.0 && height >= 20.0 &&
            width <= windowWidth * 0.42 &&
            height <= windowHeight * 0.35 &&
            area / windowArea <= 0.14) {
            bestCandidate = candidate;
        } else if (bestCandidate &&
                   (width > windowWidth * 0.55 ||
                    height > windowHeight * 0.45)) {
            break;
        }
    }
    return bestCandidate;
}

- (nullable UIView *)commonAdContainerForEvidenceViews:(NSArray<UIView *> *)views
                                                 window:(UIWindow *)window {
    if (views.count == 0) {
        return nil;
    }
    UIView *rootView = window.rootViewController.view;
    CGFloat windowArea = CGRectGetWidth(window.bounds) * CGRectGetHeight(window.bounds);
    for (UIView *candidate = views.firstObject;
         candidate && candidate != window && candidate != rootView;
         candidate = candidate.superview) {
        BOOL containsAll = YES;
        for (UIView *view in views) {
            if (view != candidate && ![view isDescendantOfView:candidate]) {
                containsAll = NO;
                break;
            }
        }
        if (!containsAll) {
            continue;
        }
        CGRect frame = [candidate convertRect:candidate.bounds toView:window];
        CGRect visibleFrame = CGRectIntersection(frame, window.bounds);
        CGFloat area = MAX(0.0, CGRectGetWidth(visibleFrame)) *
                       MAX(0.0, CGRectGetHeight(visibleFrame));
        if (windowArea > 0.0 && area / windowArea <= 0.70) {
            return candidate;
        }
    }
    return nil;
}

- (void)hideHomeAdsInWindow:(UIWindow *)window {
    NSMutableArray<UIView *> *evidenceViews = [NSMutableArray array];
    NSUInteger visited = 0;
    NSSet<NSString *> *uniqueMatches = [self collectHomeEvidenceInView:window
                                                         evidenceViews:evidenceViews
                                                               visited:&visited];
    if (uniqueMatches.count < 2 || evidenceViews.count == 0) {
        return;
    }

    NSMutableOrderedSet<UIView *> *tileCandidates = [NSMutableOrderedSet orderedSet];
    for (UIView *evidenceView in evidenceViews) {
        UIView *candidate = [self tileAncestorForEvidenceView:evidenceView
                                                       window:window];
        if (candidate) {
            [tileCandidates addObject:candidate];
        }
    }

    if (tileCandidates.count == 0) {
        UIView *container = [self commonAdContainerForEvidenceViews:evidenceViews
                                                             window:window];
        if (container) {
            [tileCandidates addObject:container];
        }
    }

    for (UIView *candidate in tileCandidates) {
        if (candidate.hidden || !candidate.window) {
            continue;
        }
        candidate.userInteractionEnabled = NO;
        candidate.hidden = YES;
        [BZABStats.sharedStats recordBlockedClass:
            @"Guazi.home-ad-tile"];
    }
}

- (void)scanAllWindows {
    if (![NSThread isMainThread]) {
        [self requestScanAfter:0.0];
        return;
    }
    if (!BZABGuaziShouldBlockAds()) {
        return;
    }
    for (UIWindow *window in BZABGuaziApplicationWindows()) {
        if (window.hidden || window.alpha <= 0.01 || !window.rootViewController) {
            continue;
        }
        NSUInteger visited = 0;
        (void)[self findAndClosePopupInView:window visited:&visited];
        [self hideHomeAdsInWindow:window];
    }
}

@end
