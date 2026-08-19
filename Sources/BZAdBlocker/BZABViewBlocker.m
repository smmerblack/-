#import "BZABViewBlocker.h"
#import "BZABCore.h"
#import "BZABSDKBlocker.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const void *BZABSkipActivatedKey = &BZABSkipActivatedKey;

static void BZABExchangeInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method replacementMethod = class_getInstanceMethod(cls, replacementSelector);
    if (originalMethod && replacementMethod) {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

static NSArray<NSString *> *BZABStrongClassNameNeedles(void) {
    static NSArray<NSString *> *needles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        needles = @[
            @"splashad", @"adsplash", @"launchad", @"launchadvert",
            @"startupad", @"startupadvert", @"openadview", @"openadcontroller",
            @"adviewcontroller", @"advertviewcontroller", @"advertisementcontroller",
            @"pagsplash", @"busplash", @"gdt_splash", @"gdtsplash",
            @"mssplash", @"pangolinsplash", @"ksadsplash", @"bdadsplash",
            @"baidumobadsplash", @"sigmobsplash", @"windsplash",
            @"unifiedsplash", @"splashviewcontroller", @"splashwindow",
            @"appopenad", @"openingad", @"adlaunch"
        ];
    });
    return needles;
}

static BOOL BZABTextMeansSkip(NSString *text) {
    NSString *normalized = text.lowercaseString;
    if (normalized.length == 0) {
        return NO;
    }
    NSArray<NSString *> *needles = @[
        @"跳过", @"跳过广告", @"广告跳过", @"skip", @"skip ad",
        @"关闭广告", @"close ad"
    ];
    return BZABStringContainsAnyNeedle(normalized, needles);
}

static NSString *BZABVisibleTextForView(UIView *view) {
    NSString *text = nil;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        text = [button titleForState:UIControlStateNormal] ?: button.currentTitle;
    } else if ([view isKindOfClass:UILabel.class]) {
        text = ((UILabel *)view).text;
    } else if ([view isKindOfClass:UITextView.class]) {
        text = ((UITextView *)view).text;
    }
    if (text.length == 0) {
        text = view.accessibilityLabel;
    }
    if (text.length == 0) {
        text = view.accessibilityValue;
    }
    return text ?: @"";
}

static NSString *BZABClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"";
}

static UIWindow *BZABRootWindowForView(UIView *view) {
    if ([view isKindOfClass:UIWindow.class]) {
        return (UIWindow *)view;
    }
    return view.window;
}

@interface BZABViewBlocker ()
@property (nonatomic, strong, nullable) NSTimer *scanTimer;
@property (nonatomic, assign) CFTimeInterval scanDeadline;
- (void)evaluateView:(UIView *)view;
- (void)evaluateViewController:(UIViewController *)viewController;
- (BOOL)activateSkipControlInViewTree:(UIView *)view;
- (BOOL)activateSkipControlAtView:(UIView *)view;
@end

@interface UIView (BZAdBlocker)
- (void)bzab_didMoveToWindow;
@end

@interface UIViewController (BZAdBlocker)
- (void)bzab_viewDidAppear:(BOOL)animated;
- (void)bzab_presentViewController:(UIViewController *)viewControllerToPresent
                          animated:(BOOL)animated
                        completion:(void (^ __nullable)(void))completion;
@end

@implementation UIView (BZAdBlocker)

- (void)bzab_didMoveToWindow {
    [self bzab_didMoveToWindow];
    if (!self.window || !BZABIsInsideSuppressionWindow()) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [BZABViewBlocker.sharedBlocker activateSkipControlInViewTree:self];
        [BZABViewBlocker.sharedBlocker evaluateView:self];
    });
}

@end

@implementation UIViewController (BZAdBlocker)

- (void)bzab_viewDidAppear:(BOOL)animated {
    [self bzab_viewDidAppear:animated];
    if (!BZABIsInsideSuppressionWindow()) {
        return;
    }
    [BZABViewBlocker.sharedBlocker evaluateViewController:self];
}

- (void)bzab_presentViewController:(UIViewController *)viewControllerToPresent
                          animated:(BOOL)animated
                        completion:(void (^)(void))completion {
    BZABViewBlocker *blocker = BZABViewBlocker.sharedBlocker;
    if (BZABIsInsideSuppressionWindow() && [blocker shouldSuppressObject:viewControllerToPresent]) {
        [BZABStats.sharedStats recordBlockedClass:BZABClassName(viewControllerToPresent)];
        BZABLog(@"suppressed presentation class=%@", BZABClassName(viewControllerToPresent));
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
        return;
    }
    [self bzab_presentViewController:viewControllerToPresent animated:animated completion:completion];
}

@end

@implementation BZABViewBlocker

+ (instancetype)sharedBlocker {
    static BZABViewBlocker *blocker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blocker = [[BZABViewBlocker alloc] init];
    });
    return blocker;
}

+ (void)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BZABExchangeInstanceMethod(UIView.class,
                                   @selector(didMoveToWindow),
                                   @selector(bzab_didMoveToWindow));
        BZABExchangeInstanceMethod(UIViewController.class,
                                   @selector(viewDidAppear:),
                                   @selector(bzab_viewDidAppear:));
        BZABExchangeInstanceMethod(UIViewController.class,
                                   @selector(presentViewController:animated:completion:),
                                   @selector(bzab_presentViewController:animated:completion:));
        BZABLog(@"view blocker installed");
    });
}

- (BOOL)shouldSuppressObject:(id)object {
    BZABSettings *settings = BZABSettings.sharedSettings;
    if (!settings.enabled || !settings.viewBlockingEnabled) {
        return NO;
    }

    NSString *className = BZABClassName(object).lowercaseString;
    if (BZABStringContainsAnyNeedle(className, BZABStrongClassNameNeedles())) {
        return YES;
    }
    if (BZABStringContainsAnyNeedle(className, BZABProfile.currentProfile.classNameNeedles)) {
        return YES;
    }

    if (settings.blockingMode == BZABBlockingModeAggressive && [object isKindOfClass:UIView.class]) {
        UIView *view = (UIView *)object;
        NSString *identifier = view.accessibilityIdentifier.lowercaseString ?: @"";
        NSArray<NSString *> *identifierNeedles = @[
            @"splash_ad", @"launch_ad", @"startup_ad", @"open_ad", @"advert_popup"
        ];
        return BZABStringContainsAnyNeedle(identifier, identifierNeedles);
    }
    return NO;
}

- (void)startSuppressionScan {
    [self rescanForDuration:BZABSettings.sharedSettings.suppressionDuration];
}

- (void)rescanForDuration:(NSTimeInterval)duration {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.scanTimer invalidate];
        self.scanDeadline = CACurrentMediaTime() + MAX(1.0, MIN(30.0, duration));
        self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                          target:self
                                                        selector:@selector(scanTick:)
                                                        userInfo:nil
                                                         repeats:YES];
        [self scanAllWindows];
    });
}

- (void)scanTick:(NSTimer *)timer {
    if (CACurrentMediaTime() >= self.scanDeadline || !BZABSettings.sharedSettings.enabled) {
        [timer invalidate];
        if (timer == self.scanTimer) {
            self.scanTimer = nil;
        }
        return;
    }
    [self scanAllWindows];
}

- (NSArray<UIWindow *> *)applicationWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (windows.count == 0) {
        [windows addObjectsFromArray:application.windows];
    }
    return windows;
}

- (void)scanAllWindows {
    if (!BZABSettings.sharedSettings.viewBlockingEnabled) {
        return;
    }
    [BZABSDKBlocker refreshHooks];
    for (UIWindow *window in [self applicationWindows]) {
        if (window.hidden || window.alpha <= 0.01) {
            continue;
        }
        [self activateSkipControlInViewTree:window];
        [self scanViewTree:window];
        UIViewController *rootViewController = window.rootViewController;
        [self scanViewControllerTree:rootViewController];
    }
}

- (void)scanViewTree:(UIView *)view {
    [self evaluateView:view];
    for (UIView *subview in [view.subviews copy]) {
        [self scanViewTree:subview];
    }
}

- (void)scanViewControllerTree:(UIViewController *)viewController {
    if (!viewController) {
        return;
    }
    [self evaluateViewController:viewController];
    if (viewController.presentedViewController) {
        [self scanViewControllerTree:viewController.presentedViewController];
    }
    for (UIViewController *child in viewController.childViewControllers) {
        [self scanViewControllerTree:child];
    }
}

- (BOOL)tapSkipButtonInView:(UIView *)view {
    return [self activateSkipControlInViewTree:view];
}

- (BOOL)hierarchyLooksLikeStartupAdForView:(UIView *)view {
    BZABProfile *profile = BZABProfile.currentProfile;
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        NSString *className = BZABClassName(candidate).lowercaseString;
        if (BZABStringContainsAnyNeedle(className, BZABStrongClassNameNeedles()) ||
            BZABStringContainsAnyNeedle(className, profile.classNameNeedles)) {
            return YES;
        }
    }
    return NO;
}

- (nullable UIControl *)controlForSkipView:(UIView *)view {
    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate && depth < 6; depth++) {
        if ([candidate isKindOfClass:UIControl.class]) {
            return (UIControl *)candidate;
        }
        candidate = candidate.superview;
    }
    return nil;
}

- (nullable UIView *)overlayAncestorForSkipView:(UIView *)view {
    UIWindow *window = view.window;
    if (!window) {
        return nil;
    }
    UIView *rootView = window.rootViewController.view;
    CGFloat windowArea = CGRectGetWidth(window.bounds) * CGRectGetHeight(window.bounds);
    if (windowArea <= 0) {
        return nil;
    }

    for (UIView *candidate = view.superview;
         candidate && candidate != window && candidate != rootView;
         candidate = candidate.superview) {
        CGRect frame = [candidate convertRect:candidate.bounds toView:window];
        CGRect visibleFrame = CGRectIntersection(frame, window.bounds);
        CGFloat area = MAX(0, CGRectGetWidth(visibleFrame)) * MAX(0, CGRectGetHeight(visibleFrame));
        if (area / windowArea >= 0.55) {
            return candidate;
        }
    }
    return nil;
}

- (BOOL)activateSkipControlAtView:(UIView *)view {
    BZABSettings *settings = BZABSettings.sharedSettings;
    if (!settings.enabled || !settings.viewBlockingEnabled ||
        !BZABIsInsideSuppressionWindow() || !view.window) {
        return NO;
    }

    NSString *text = BZABVisibleTextForView(view);
    if (!BZABTextMeansSkip(text)) {
        return NO;
    }
    if (objc_getAssociatedObject(view, BZABSkipActivatedKey)) {
        return NO;
    }
    if (settings.blockingMode == BZABBlockingModeSafe &&
        ![self hierarchyLooksLikeStartupAdForView:view]) {
        return NO;
    }

    UIControl *control = [self controlForSkipView:view];
    if (control && control.enabled && !control.hidden && control.alpha > 0.01) {
        objc_setAssociatedObject(view, BZABSkipActivatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(control, BZABSkipActivatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        NSString *event = [NSString stringWithFormat:@"%@.skip-control", BZABClassName(control)];
        [BZABStats.sharedStats recordTriggeredSkipWithClass:event];
        BZABLog(@"activated skip control class=%@ text=%@", BZABClassName(control), text);
        return YES;
    }

    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate && depth < 5; depth++) {
        if ([candidate accessibilityActivate]) {
            objc_setAssociatedObject(view, BZABSkipActivatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSString *event = [NSString stringWithFormat:@"%@.accessibility-skip", BZABClassName(candidate)];
            [BZABStats.sharedStats recordTriggeredSkipWithClass:event];
            BZABLog(@"activated accessibility skip class=%@ text=%@", BZABClassName(candidate), text);
            return YES;
        }
        candidate = candidate.superview;
    }

    UIView *overlay = [self overlayAncestorForSkipView:view];
    if (overlay) {
        objc_setAssociatedObject(view, BZABSkipActivatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *event = [NSString stringWithFormat:@"%@.skip-overlay", BZABClassName(overlay)];
        [BZABStats.sharedStats recordTriggeredSkipWithClass:event];
        overlay.userInteractionEnabled = NO;
        overlay.hidden = YES;
        [overlay removeFromSuperview];
        BZABLog(@"removed skip overlay class=%@ text=%@", BZABClassName(overlay), text);
        return YES;
    }
    return NO;
}

- (BOOL)activateSkipControlInViewTree:(UIView *)view {
    if ([self activateSkipControlAtView:view]) {
        return YES;
    }
    for (UIView *subview in [view.subviews copy]) {
        if ([self activateSkipControlInViewTree:subview]) {
            return YES;
        }
    }
    return NO;
}

- (void)evaluateView:(UIView *)view {
    if (!view.window || ![self shouldSuppressObject:view]) {
        return;
    }

    if ([self tapSkipButtonInView:view]) {
        return;
    }

    UIWindow *window = BZABRootWindowForView(view);
    UIView *rootView = window.rootViewController.view;
    if (view == window || view == rootView) {
        return;
    }

    NSString *className = BZABClassName(view);
    [BZABStats.sharedStats recordBlockedClass:className];
    BZABLog(@"removed overlay class=%@", className);
    view.userInteractionEnabled = NO;
    view.hidden = YES;
    [view removeFromSuperview];
}

- (void)evaluateViewController:(UIViewController *)viewController {
    if (![self shouldSuppressObject:viewController]) {
        return;
    }
    if ([self tapSkipButtonInView:viewController.view]) {
        return;
    }

    NSString *className = BZABClassName(viewController);
    if (viewController.presentingViewController) {
        [BZABStats.sharedStats recordBlockedClass:className];
        BZABLog(@"dismissed controller class=%@", className);
        [viewController dismissViewControllerAnimated:NO completion:nil];
        return;
    }

    UIWindow *window = viewController.view.window;
    if (window.rootViewController == viewController && [self applicationWindows].count > 1) {
        [BZABStats.sharedStats recordBlockedClass:className];
        BZABLog(@"hid splash window controller class=%@", className);
        window.hidden = YES;
    }
}

@end
