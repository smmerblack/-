#import "BZABMenuController.h"
#import "BZABCore.h"
#import "BZABViewBlocker.h"
#import "BZMenuKit.h"
#import <objc/runtime.h>

static const void *BZABGestureInstalledKey = &BZABGestureInstalledKey;

@interface BZABMenuController () <BZMenuPanelDelegate>
@property (nonatomic, strong, nullable) BZMenuPanel *panel;
@end

@implementation BZABMenuController

+ (instancetype)sharedController {
    static BZABMenuController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[BZABMenuController alloc] init];
    });
    return controller;
}

- (void)installGestureEntry {
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(applicationDidBecomeActive:)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(applicationDidBecomeActive:)
                                               name:UIWindowDidBecomeVisibleNotification
                                             object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self attachGestureToAvailableWindows];
    });
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self attachGestureToAvailableWindows];
    });
}

- (NSArray<UIWindow *> *)applicationWindows {
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

- (void)attachGestureToAvailableWindows {
    for (UIWindow *window in [self applicationWindows]) {
        if (objc_getAssociatedObject(window, BZABGestureInstalledKey)) {
            continue;
        }
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(menuGestureRecognized:)];
        gesture.numberOfTouchesRequired = 3;
        gesture.numberOfTapsRequired = 2;
        gesture.cancelsTouchesInView = NO;
        [window addGestureRecognizer:gesture];
        objc_setAssociatedObject(window, BZABGestureInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)menuGestureRecognized:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        [self showMenu];
    }
}

- (nullable UIWindow *)bestWindow {
    NSArray<UIWindow *> *windows = [self applicationWindows];
    for (UIWindow *window in windows.reverseObjectEnumerator) {
        if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
            return window;
        }
    }
    return windows.lastObject;
}

- (BZMenuConfiguration *)menuConfiguration {
    BZABSettings *settings = BZABSettings.sharedSettings;
    BZABProfile *profile = BZABProfile.currentProfile;
    BZABStats *stats = BZABStats.sharedStats;

    BZMenuItem *version = [BZMenuItem valueItem:@"plugin.version" title:@"插件版本" value:BZABVersion];
    version.togglesThemeOnLongPress = YES;

    NSString *appVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    NSString *appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
        ?: [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]
        ?: @"当前 App";

    BZMenuConfiguration *configuration = [[BZMenuConfiguration alloc] init];
    configuration.title = @"启动广告屏蔽";
    configuration.versionText = BZABVersion;
    configuration.theme = BZMenuThemeStyleGlass;
    configuration.themePersistenceKey = @"BZAdBlocker.MenuTheme";
    configuration.sections = @[
        [BZMenuSection functionSectionWithItems:@[
            [BZMenuItem switchItem:@"enabled" title:@"总开关" on:settings.enabled],
            [BZMenuItem switchItem:@"network" title:@"广告请求拦截" on:settings.networkBlockingEnabled],
            [BZMenuItem switchItem:@"views" title:@"启动页清理" on:settings.viewBlockingEnabled],
            [BZMenuItem segmentItem:@"mode"
                             title:@"拦截强度"
                           options:@[@"安全", @"平衡", @"增强"]
                          selected:settings.blockingMode],
            [BZMenuItem sliderItem:@"duration"
                            title:@"启动扫描秒数"
                            value:(float)settings.suppressionDuration
                              min:3.0
                              max:30.0],
            [BZMenuItem switchItem:@"logging" title:@"调试日志" on:settings.debugLoggingEnabled],
            [BZMenuItem disclosureItem:@"rescan" title:@"立即重新扫描"]
        ]],
        [BZMenuSection infoSectionWithItems:@[
            [BZMenuItem valueItem:@"app" title:appName value:appVersion],
            [BZMenuItem valueItem:@"profile" title:@"当前规则" value:profile.name],
            [BZMenuItem valueItem:@"requests" title:@"已拦截请求" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.blockedRequests]],
            [BZMenuItem valueItem:@"views.count" title:@"已清理界面" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.blockedViews]],
            [BZMenuItem valueItem:@"skips.count" title:@"已触发跳过" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.triggeredSkips]],
            [BZMenuItem valueItem:@"sdk.count" title:@"已发现广告 SDK" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.detectedSDKClasses]],
            [BZMenuItem valueItem:@"sdk.last" title:@"最后发现 SDK" value:stats.lastDetectedSDKClass ?: @"暂无"],
            [BZMenuItem valueItem:@"last.action" title:@"最后处理" value:stats.lastBlockedClass ?: @"暂无"],
            version,
            [BZMenuItem noteItem:@"hint" text:@"三指双击打开本菜单。第二版会直接拦截常见开屏 SDK，并在启动阶段自动触发“跳过”。若页面异常，请切换到“安全”强度并重启 App。"]
        ]]
    ];
    return configuration;
}

- (void)showMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self bestWindow];
        if (!window || self.panel.superview) {
            return;
        }
        self.panel = [BZMenuPanel presentInView:window
                                  configuration:[self menuConfiguration]
                                       delegate:self];
    });
}

- (void)persistSwitchItem:(BZMenuItem *)item on:(BOOL)on {
    BZABSettings *settings = BZABSettings.sharedSettings;
    if ([item.identifier isEqualToString:@"enabled"]) {
        settings.enabled = on;
    } else if ([item.identifier isEqualToString:@"network"]) {
        settings.networkBlockingEnabled = on;
    } else if ([item.identifier isEqualToString:@"views"]) {
        settings.viewBlockingEnabled = on;
    } else if ([item.identifier isEqualToString:@"logging"]) {
        settings.debugLoggingEnabled = on;
    }
    [settings synchronize];
}

- (void)menuPanel:(BZMenuPanel *)panel didToggleItem:(BZMenuItem *)item on:(BOOL)on {
    (void)panel;
    [self persistSwitchItem:item on:on];
    [BZMenuToast show:[NSString stringWithFormat:@"%@ %@", item.title, on ? @"已开启" : @"已关闭"]];
}

- (void)menuPanel:(BZMenuPanel *)panel didChangeSlider:(BZMenuItem *)item value:(float)value {
    (void)panel;
    if ([item.identifier isEqualToString:@"duration"]) {
        BZABSettings.sharedSettings.suppressionDuration = value;
        [BZABSettings.sharedSettings synchronize];
    }
}

- (void)menuPanel:(BZMenuPanel *)panel didSelectSegment:(BZMenuItem *)item index:(NSInteger)index {
    (void)panel;
    if ([item.identifier isEqualToString:@"mode"]) {
        BZABSettings.sharedSettings.blockingMode = (BZABBlockingMode)index;
        [BZABSettings.sharedSettings synchronize];
        [BZMenuToast show:@"拦截强度已更新"];
    }
}

- (void)menuPanel:(BZMenuPanel *)panel didTapItem:(BZMenuItem *)item {
    if ([item.identifier isEqualToString:@"rescan"]) {
        [BZABViewBlocker.sharedBlocker rescanForDuration:BZABSettings.sharedSettings.suppressionDuration];
        [BZMenuToast show:@"已重新扫描启动广告"];
        [panel reloadRows];
    }
}

- (void)menuPanelDidLongPressClose:(BZMenuPanel *)panel {
    [panel dismissAnimated:YES];
    self.panel = nil;
}

- (void)menuPanelDidTapClose:(BZMenuPanel *)panel {
    [panel dismissAnimated:YES];
    self.panel = nil;
}

- (void)menuPanelDidTapLeadingButton:(BZMenuPanel *)panel {
    [panel dismissAnimated:YES];
    self.panel = nil;
}

@end
