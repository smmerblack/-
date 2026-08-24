#import "BZABMenuController.h"
#import "BZABCMCCBlocker.h"
#import "BZABCore.h"
#import "BZABGuaziBlocker.h"
#import "BZABTaobaoBlocker.h"
#import "BZABTencentVideoBlocker.h"
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
    BOOL chinaMobileTarget = BZABCMCCBlocker.isTargetApplication;
    BOOL taobaoTarget = BZABTaobaoBlocker.isTargetApplication;
    BOOL tencentVideoTarget = BZABTencentVideoBlocker.isTargetApplication;
    BOOL guaziTarget = BZABGuaziBlocker.isTargetApplication;
    BOOL nativeFastPath = NO;
    if (chinaMobileTarget) {
        nativeFastPath = BZABCMCCBlocker.nativeFastPathReady;
    } else if (taobaoTarget) {
        nativeFastPath = BZABTaobaoBlocker.nativeFastPathReady;
    } else if (tencentVideoTarget) {
        nativeFastPath = BZABTencentVideoBlocker.nativeFastPathReady;
    } else if (guaziTarget) {
        nativeFastPath = BZABGuaziBlocker.nativeFastPathReady;
    }
    NSString *ruleName = profile.name;
    NSString *hint = @"三指双击打开本菜单。通用模式会在冷启动及从后台返回后的保护窗口内拦截开屏 SDK，并自动触发“跳过”。若页面异常，请切换到“安全”强度并重启 App。";
    if (chinaMobileTarget) {
        ruleName = nativeFastPath
            ? @"中国移动 12.5.2 直接进入"
            : @"中国移动专用规则加载中";
        hint = @"三指双击打开本菜单。中国移动使用版本专用直接进入流程：保留首页初始化，在下一次主线程循环调用 App 自身的启动完成方法，并禁止通用网络和界面扫描制造超时等待。";
    } else if (taobaoTarget) {
        ruleName = nativeFastPath
            ? @"淘宝 10.59.20 冷/热启动直跳"
            : @"淘宝专用规则加载中";
        hint = @"三指双击打开本菜单。淘宝使用 TBBootImage 原生路径：冷启动调用 App 自身的跳过方法，后台返回直接拒绝热启动广告展示；首页初始化保持不变，也不启用通用网络拦截。";
    } else if (tencentVideoTarget) {
        ruleName = nativeFastPath
            ? @"腾讯视频 9.04.31 开屏/返回/暂停广告直跳"
            : @"腾讯视频专用规则加载中";
        hint = @"三指双击打开本菜单。腾讯视频使用 QAD 原生决策路径：冷启动和后台返回走 SDK 自身的无广告完成分支，不创建五秒广告计时；播放器暂停广告在请求闸门阻止，并保留播放、暂停和控制栏功能。";
    } else if (guaziTarget) {
        ruleName = nativeFastPath
            ? @"瓜子影视 1.1 开屏/返回直跳 + 弹窗/首页清理"
            : @"瓜子影视专用规则加载中";
        hint = @"三指双击打开本菜单。瓜子影视使用 React Native 原始完成流程：只把启动及后台返回时的一次性五秒广告计时缩短为 0.05 秒，随后仍由 App 自己进入首页；弹窗关闭和首页推广格仅按瓜子影视的多项专用特征组合清理，不启用通用网络拦截。";
    }

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
            [BZMenuItem valueItem:@"profile"
                            title:@"当前规则"
                            value:ruleName],
            [BZMenuItem valueItem:@"requests" title:@"已拦截请求" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.blockedRequests]],
            [BZMenuItem valueItem:@"views.count" title:@"已清理界面" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.blockedViews]],
            [BZMenuItem valueItem:@"skips.count" title:@"已触发跳过" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.triggeredSkips]],
            [BZMenuItem valueItem:@"sdk.count" title:@"已发现广告 SDK" value:[NSString stringWithFormat:@"%lu", (unsigned long)stats.detectedSDKClasses]],
            [BZMenuItem valueItem:@"sdk.last" title:@"最后发现 SDK" value:stats.lastDetectedSDKClass ?: @"暂无"],
            [BZMenuItem valueItem:@"last.action" title:@"最后处理" value:stats.lastBlockedClass ?: @"暂无"],
            version,
            [BZMenuItem noteItem:@"hint" text:hint]
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
        if (BZABCMCCBlocker.isTargetApplication) {
            [BZABCMCCBlocker refreshHooks];
            [BZMenuToast show:BZABCMCCBlocker.nativeFastPathReady
                ? @"中国移动直接进入规则已启用"
                : @"正在重新加载中国移动专用规则"];
        } else if (BZABTaobaoBlocker.isTargetApplication) {
            [BZABTaobaoBlocker refreshHooks];
            [BZMenuToast show:BZABTaobaoBlocker.nativeFastPathReady
                ? @"淘宝冷/热启动直跳规则已启用"
                : @"正在重新加载淘宝专用规则"];
        } else if (BZABTencentVideoBlocker.isTargetApplication) {
            [BZABTencentVideoBlocker refreshHooks];
            [BZMenuToast show:BZABTencentVideoBlocker.nativeFastPathReady
                ? @"腾讯视频开屏/返回/暂停广告规则已启用"
                : @"正在重新加载腾讯视频专用规则"];
        } else if (BZABGuaziBlocker.isTargetApplication) {
            [BZABGuaziBlocker refreshHooks];
            [BZABGuaziBlocker rescanAds];
            [BZMenuToast show:BZABGuaziBlocker.nativeFastPathReady
                ? @"瓜子影视开屏/返回直跳及页面清理已启用"
                : @"正在重新加载瓜子影视专用规则"];
        } else {
            [BZABViewBlocker.sharedBlocker rescanForDuration:BZABSettings.sharedSettings.suppressionDuration];
            [BZMenuToast show:@"已重新扫描广告界面"];
        }
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
