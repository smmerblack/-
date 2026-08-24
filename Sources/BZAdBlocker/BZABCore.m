#import "BZABCore.h"
#import <QuartzCore/QuartzCore.h>

NSString * const BZABVersion = @"0.13.0-test13";

static NSString * const BZABEnabledKey = @"BZAdBlocker.Enabled";
static NSString * const BZABNetworkKey = @"BZAdBlocker.Network";
static NSString * const BZABViewsKey = @"BZAdBlocker.Views";
static NSString * const BZABLoggingKey = @"BZAdBlocker.Logging";
static NSString * const BZABModeKey = @"BZAdBlocker.Mode";
static NSString * const BZABDurationKey = @"BZAdBlocker.Duration";
static CFTimeInterval BZABLoadTime = 0;
static CFTimeInterval BZABSuppressionDeadline = 0;
static NSUInteger BZABSuppressionGeneration = 0;

@implementation BZABProfile

+ (instancetype)genericProfile {
    BZABProfile *profile = [[BZABProfile alloc] init];
    profile.name = @"通用规则";
    profile.bundleIdentifiers = [NSSet set];
    profile.classNameNeedles = @[];
    profile.firstPartyDomains = @[];
    profile.firstPartyAdPathNeedles = @[];
    profile.defaultSuppressionDuration = 12.0;
    profile.resumeSuppressionDuration = 8.0;
    return profile;
}

+ (NSArray<BZABProfile *> *)knownProfiles {
    static NSArray<BZABProfile *> *profiles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BZABProfile *sina = [[BZABProfile alloc] init];
        sina.name = @"新浪邮箱 3.3.16";
        sina.bundleIdentifiers = [NSSet setWithArray:@[@"com.sina", @"com.sina.mail"]];
        sina.classNameNeedles = @[
            @"sinasplash", @"mailsplash", @"sinamailad", @"maillaunchad",
            @"sinaadvert", @"homepageadvert", @"startupadvert",
            @"mssplash", @"busplash", @"pagsplash", @"pangolinsplash"
        ];
        sina.firstPartyDomains = @[@"sina.com.cn", @"sina.cn", @"sina.com", @"sinaimg.cn"];
        sina.firstPartyAdPathNeedles = @[
            @"/splash", @"/startup-ad", @"/launch-ad", @"/boot-ad",
            @"/advert/", @"/advertise/", @"/popup-ad"
        ];
        sina.defaultSuppressionDuration = 20.0;
        sina.resumeSuppressionDuration = 8.0;

        BZABProfile *cmcc = [[BZABProfile alloc] init];
        cmcc.name = @"中国移动 12.x";
        cmcc.bundleIdentifiers = [NSSet setWithArray:@[@"cn.10086.app"]];
        cmcc.classNameNeedles = @[
            @"cmccsplash", @"cmccadvert", @"mobilehallad", @"homepopupad",
            @"homeadvertpopup", @"startupadvert", @"launchadvert",
            @"mssplash", @"busplash", @"pagsplash", @"gdtsplash"
        ];
        cmcc.firstPartyDomains = @[@"10086.cn", @"chinamobile.com"];
        cmcc.firstPartyAdPathNeedles = @[
            @"/splash", @"/startup-ad", @"/launch-ad", @"/boot-ad",
            @"/advert/", @"/advertise/", @"/popup-ad", @"/home-popup"
        ];
        cmcc.defaultSuppressionDuration = 20.0;
        cmcc.resumeSuppressionDuration = 8.0;

        BZABProfile *taobao = [[BZABProfile alloc] init];
        taobao.name = @"淘宝 10.59.20";
        taobao.bundleIdentifiers = [NSSet setWithArray:@[
            @"com.taobao.taobao4iphone"
        ]];
        taobao.classNameNeedles = @[
            @"tbbootimage", @"spsplash", @"taobaosplash",
            @"mmadbootimage", @"splashinteract"
        ];
        taobao.firstPartyDomains = @[
            @"taobao.com", @"tmall.com", @"alicdn.com",
            @"alibaba.com", @"alipay.com"
        ];
        taobao.firstPartyAdPathNeedles = @[
            @"/splash", @"/startup-ad", @"/launch-ad", @"/boot-ad"
        ];
        taobao.defaultSuppressionDuration = 12.0;
        taobao.resumeSuppressionDuration = 8.0;

        BZABProfile *tencentVideo = [[BZABProfile alloc] init];
        tencentVideo.name = @"腾讯视频 9.04.31";
        tencentVideo.bundleIdentifiers = [NSSet setWithArray:@[
            @"com.tencent.live4iphone"
        ]];
        tencentVideo.classNameNeedles = @[
            @"qadsplash", @"qlsplash", @"qadpause",
            @"adpause", @"splashad"
        ];
        tencentVideo.firstPartyDomains = @[
            @"v.qq.com", @"video.qq.com", @"qq.com", @"gtimg.com"
        ];
        tencentVideo.firstPartyAdPathNeedles = @[
            @"/splash", @"/launch-ad", @"/pause-ad", @"/adpause"
        ];
        tencentVideo.defaultSuppressionDuration = 12.0;
        tencentVideo.resumeSuppressionDuration = 8.0;

        BZABProfile *guazi = [[BZABProfile alloc] init];
        guazi.name = @"瓜子影视 1.1";
        guazi.bundleIdentifiers = [NSSet setWithArray:@[
            @"com.Tajjwab.numberPulse"
        ]];
        guazi.classNameNeedles = @[
            @"rctmodalhostview", @"guazisplash", @"numberpulseadvert"
        ];
        guazi.firstPartyDomains = @[];
        guazi.firstPartyAdPathNeedles = @[];
        guazi.defaultSuppressionDuration = 12.0;
        guazi.resumeSuppressionDuration = 10.0;
        profiles = @[sina, cmcc, taobao, tencentVideo, guazi];
    });
    return profiles;
}

+ (instancetype)currentProfile {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    for (BZABProfile *profile in [self knownProfiles]) {
        if ([profile.bundleIdentifiers containsObject:bundleIdentifier]) {
            return profile;
        }
    }
    return [self genericProfile];
}

@end

@implementation BZABSettings

+ (instancetype)sharedSettings {
    static BZABSettings *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BZABProfile *profile = [BZABProfile currentProfile];
        CFTimeInterval now = CACurrentMediaTime();
        @synchronized (BZABSettings.class) {
            BZABLoadTime = now;
            BZABSuppressionDeadline = now + profile.defaultSuppressionDuration;
            BZABSuppressionGeneration = 1;
        }
        [NSUserDefaults.standardUserDefaults registerDefaults:@{
            BZABEnabledKey: @YES,
            BZABNetworkKey: @YES,
            BZABViewsKey: @YES,
            BZABLoggingKey: @NO,
            BZABModeKey: @(BZABBlockingModeBalanced),
            BZABDurationKey: @(profile.defaultSuppressionDuration),
        }];
        settings = [[BZABSettings alloc] init];
    });
    return settings;
}

- (BOOL)enabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:BZABEnabledKey];
}

- (void)setEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:BZABEnabledKey];
}

- (BOOL)networkBlockingEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:BZABNetworkKey];
}

- (void)setNetworkBlockingEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:BZABNetworkKey];
}

- (BOOL)viewBlockingEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:BZABViewsKey];
}

- (void)setViewBlockingEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:BZABViewsKey];
}

- (BOOL)debugLoggingEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:BZABLoggingKey];
}

- (void)setDebugLoggingEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:BZABLoggingKey];
}

- (BZABBlockingMode)blockingMode {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:BZABModeKey];
    return (BZABBlockingMode)MAX(BZABBlockingModeSafe, MIN(BZABBlockingModeAggressive, value));
}

- (void)setBlockingMode:(BZABBlockingMode)mode {
    NSInteger clamped = MAX(BZABBlockingModeSafe, MIN(BZABBlockingModeAggressive, mode));
    [NSUserDefaults.standardUserDefaults setInteger:clamped forKey:BZABModeKey];
}

- (NSTimeInterval)suppressionDuration {
    NSTimeInterval duration = [NSUserDefaults.standardUserDefaults doubleForKey:BZABDurationKey];
    return MAX(3.0, MIN(30.0, duration));
}

- (void)setSuppressionDuration:(NSTimeInterval)duration {
    [NSUserDefaults.standardUserDefaults setDouble:MAX(3.0, MIN(30.0, duration))
                                            forKey:BZABDurationKey];
}

- (void)synchronize {
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end

@interface BZABStats ()
@property (atomic, assign, readwrite) NSUInteger blockedRequests;
@property (atomic, assign, readwrite) NSUInteger blockedViews;
@property (atomic, assign, readwrite) NSUInteger triggeredSkips;
@property (atomic, assign, readwrite) NSUInteger detectedSDKClasses;
@property (atomic, copy, readwrite, nullable) NSString *lastBlockedHost;
@property (atomic, copy, readwrite, nullable) NSString *lastBlockedClass;
@property (atomic, copy, readwrite, nullable) NSString *lastDetectedSDKClass;
@end

@implementation BZABStats

+ (instancetype)sharedStats {
    static BZABStats *stats;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stats = [[BZABStats alloc] init];
    });
    return stats;
}

- (void)recordBlockedHost:(NSString *)host {
    @synchronized (self) {
        self.blockedRequests += 1;
        self.lastBlockedHost = host;
    }
}

- (void)recordBlockedClass:(NSString *)className {
    @synchronized (self) {
        self.blockedViews += 1;
        self.lastBlockedClass = className;
    }
}

- (void)recordTriggeredSkipWithClass:(NSString *)className {
    @synchronized (self) {
        self.triggeredSkips += 1;
        self.lastBlockedClass = className;
    }
}

- (void)recordDetectedSDKClass:(NSString *)className {
    @synchronized (self) {
        self.detectedSDKClasses += 1;
        self.lastDetectedSDKClass = className;
    }
}

@end

BOOL BZABHostMatchesDomain(NSString *host, NSString *domain) {
    NSString *normalizedHost = host.lowercaseString;
    NSString *normalizedDomain = domain.lowercaseString;
    if ([normalizedHost isEqualToString:normalizedDomain]) {
        return YES;
    }
    return [normalizedHost hasSuffix:[@"." stringByAppendingString:normalizedDomain]];
}

BOOL BZABStringContainsAnyNeedle(NSString *value, NSArray<NSString *> *needles) {
    NSString *lowercaseValue = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lowercaseValue containsString:needle.lowercaseString]) {
            return YES;
        }
    }
    return NO;
}

NSSet<NSString *> *BZABCustomBlockedDomains(void) {
    static NSSet<NSString *> *domains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString *> *loadedDomains = [NSMutableSet set];
        NSMutableArray<NSString *> *candidatePaths = [NSMutableArray array];
        NSString *resourcePath = [NSBundle.mainBundle pathForResource:@"BZAdBlockerRules" ofType:@"txt"];
        if (resourcePath.length > 0) {
            [candidatePaths addObject:resourcePath];
        }
        NSString *bundleRootPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"BZAdBlockerRules.txt"];
        [candidatePaths addObject:bundleRootPath];

        for (NSString *path in candidatePaths) {
            NSString *contents = [NSString stringWithContentsOfFile:path
                                                            encoding:NSUTF8StringEncoding
                                                               error:nil];
            if (contents.length == 0) {
                continue;
            }
            NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",\n\r\t "];
            for (NSString *candidate in [contents componentsSeparatedByCharactersInSet:separators]) {
                NSString *domain = [candidate.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (domain.length > 2 && ![domain hasPrefix:@"#"]) {
                    [loadedDomains addObject:domain];
                }
            }
        }
        domains = [loadedDomains copy];
    });
    return domains;
}

NSTimeInterval BZABElapsedSinceLoad(void) {
    (void)BZABSettings.sharedSettings;
    CFTimeInterval loadTime;
    @synchronized (BZABSettings.class) {
        loadTime = BZABLoadTime;
    }
    return MAX(0.0, CACurrentMediaTime() - loadTime);
}

BOOL BZABIsInsideSuppressionWindow(void) {
    (void)BZABSettings.sharedSettings;
    CFTimeInterval deadline;
    @synchronized (BZABSettings.class) {
        deadline = BZABSuppressionDeadline;
    }
    return CACurrentMediaTime() <= deadline;
}

void BZABExtendSuppressionWindow(NSTimeInterval duration) {
    (void)BZABSettings.sharedSettings;
    NSTimeInterval boundedDuration = MAX(1.0, MIN(30.0, duration));
    CFTimeInterval requestedDeadline = CACurrentMediaTime() + boundedDuration;
    @synchronized (BZABSettings.class) {
        BZABSuppressionDeadline = MAX(BZABSuppressionDeadline, requestedDeadline);
        BZABSuppressionGeneration += 1;
    }
}

NSUInteger BZABCurrentSuppressionGeneration(void) {
    (void)BZABSettings.sharedSettings;
    NSUInteger generation;
    @synchronized (BZABSettings.class) {
        generation = BZABSuppressionGeneration;
    }
    return generation;
}

void BZABLog(NSString *format, ...) {
    if (!BZABSettings.sharedSettings.debugLoggingEnabled) {
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[BZAdBlocker] %@", message);
}
