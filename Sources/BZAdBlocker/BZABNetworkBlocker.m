#import "BZABNetworkBlocker.h"
#import "BZABCore.h"
#import <objc/runtime.h>

static void BZABExchangeClassMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method originalMethod = class_getClassMethod(cls, originalSelector);
    Method replacementMethod = class_getClassMethod(cls, replacementSelector);
    if (originalMethod && replacementMethod) {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

static NSArray<NSString *> *BZABDedicatedAdDomains(void) {
    static NSArray<NSString *> *domains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        domains = @[
            // Pangle / ByteDance
            @"pangolin-sdk-toutiao.com", @"pangolin-sdk-toutiao-b.com",
            @"pglstatp-toutiao.com", @"zijieapi.com", @"snssdk.com",
            @"byteoversea.com", @"bytedanceapi.com",
            // Miaozhen / Sigmob
            @"miaozhen.com", @"miaozhen.cn", @"sigmob.cn", @"adservice.sigmob.cn",
            // Meishu / MSAdSDK
            @"1rtb.com", @"adxdata.com",
            // Tencent GDT
            @"e.qq.com", @"gdt.qq.com", @"pgdt.gtimg.cn", @"qzs.gdtimg.com",
            // Kuaishou
            @"open.e.kuaishou.com", @"open.e.kuaishou.cn", @"adukwai.com",
            // Baidu ads
            @"mobads.baidu.com", @"mobads-logs.baidu.com", @"cpro.baidu.com",
            @"nsclick.baidu.com", @"duclick.baidu.com",
            // Other common mobile ad SDKs
            @"applovin.com", @"applvn.com", @"supersonicads.com", @"ironsrc.com",
            @"vungle.com", @"vungle.cn", @"unityads.unity3d.com", @"rayjump.com",
            @"inmobi.com", @"inmobi.cn", @"inmobi.net", @"adcolony.com",
            @"googlesyndication.com", @"googleadservices.com", @"doubleclick.net",
            // Sina ad delivery
            @"sax.sina.com.cn", @"saxs.sina.com.cn", @"saxn.sina.com.cn",
            @"ad.sina.com.cn", @"adbox.sina.com.cn", @"adimg.mobile.sina.cn",
            // China Mobile media ad delivery
            @"ad.cmvideo.cn", @"adxserver.ad.cmvideo.cn"
        ];
    });
    return domains;
}

static NSArray<NSString *> *BZABEssentialPathNeedles(void) {
    static NSArray<NSString *> *needles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        needles = @[
            @"/login", @"/oauth", @"/auth", @"/token", @"/passport",
            @"/account", @"/user", @"/mail", @"/message", @"/inbox",
            @"/send", @"/bill", @"/payment", @"/recharge", @"/order",
            @"/service", @"/captcha", @"/verify"
        ];
    });
    return needles;
}

static BOOL BZABHostMatchesAnyDomain(NSString *host, NSArray<NSString *> *domains) {
    for (NSString *domain in domains) {
        if (BZABHostMatchesDomain(host, domain)) {
            return YES;
        }
    }
    return NO;
}

static BOOL BZABHostLooksLikeDedicatedAdHost(NSString *host) {
    NSArray<NSString *> *labels = [host.lowercaseString componentsSeparatedByString:@"."];
    if (labels.count == 0) {
        return NO;
    }
    NSString *firstLabel = labels.firstObject;
    return [@[@"ad", @"ads", @"adx", @"advert", @"advertise", @"adserver"] containsObject:firstLabel];
}

@interface BZABURLProtocol : NSURLProtocol
@end

@interface BZABNetworkBlocker ()
+ (void)addProtocolToConfiguration:(NSURLSessionConfiguration *)configuration;
@end

@implementation BZABURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"BZAdBlocker.Handled" inRequest:request]) {
        return NO;
    }
    NSURL *URL = request.URL;
    if (!URL || ![@[@"http", @"https"] containsObject:URL.scheme.lowercaseString]) {
        return NO;
    }
    return [BZABNetworkBlocker shouldBlockURL:URL];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSURL *URL = self.request.URL;
    NSString *host = URL.host.lowercaseString ?: @"unknown";
    [BZABStats.sharedStats recordBlockedHost:host];
    BZABLog(@"blocked request host=%@", host);

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
        initWithURL:URL
        statusCode:204
        HTTPVersion:@"HTTP/1.1"
        headerFields:@{@"Cache-Control": @"no-store", @"X-BZAdBlocker": @"1"}];
    [self.client URLProtocol:self
         didReceiveResponse:response
         cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end

@interface NSURLSessionConfiguration (BZAdBlocker)
+ (NSURLSessionConfiguration *)bzab_defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)bzab_ephemeralSessionConfiguration;
@end

@implementation NSURLSessionConfiguration (BZAdBlocker)

+ (NSURLSessionConfiguration *)bzab_defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self bzab_defaultSessionConfiguration];
    [BZABNetworkBlocker addProtocolToConfiguration:configuration];
    return configuration;
}

+ (NSURLSessionConfiguration *)bzab_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self bzab_ephemeralSessionConfiguration];
    [BZABNetworkBlocker addProtocolToConfiguration:configuration];
    return configuration;
}

@end

@implementation BZABNetworkBlocker

+ (void)addProtocolToConfiguration:(NSURLSessionConfiguration *)configuration {
    NSArray<Class> *existing = configuration.protocolClasses ?: @[];
    if ([existing containsObject:BZABURLProtocol.class]) {
        return;
    }
    configuration.protocolClasses = [@[BZABURLProtocol.class] arrayByAddingObjectsFromArray:existing];
}

+ (void)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSURLProtocol registerClass:BZABURLProtocol.class];
        BZABExchangeClassMethod(NSURLSessionConfiguration.class,
                                @selector(defaultSessionConfiguration),
                                @selector(bzab_defaultSessionConfiguration));
        BZABExchangeClassMethod(NSURLSessionConfiguration.class,
                                @selector(ephemeralSessionConfiguration),
                                @selector(bzab_ephemeralSessionConfiguration));
        BZABLog(@"network blocker installed");
    });
}

+ (BOOL)shouldBlockURL:(NSURL *)URL {
    BZABSettings *settings = BZABSettings.sharedSettings;
    if (!settings.enabled || !settings.networkBlockingEnabled) {
        return NO;
    }

    NSString *host = URL.host.lowercaseString ?: @"";
    if (host.length == 0) {
        return NO;
    }

    if (BZABHostMatchesAnyDomain(host, BZABDedicatedAdDomains())) {
        return YES;
    }
    for (NSString *customDomain in BZABCustomBlockedDomains()) {
        if (BZABHostMatchesDomain(host, customDomain)) {
            return YES;
        }
    }

    if (settings.blockingMode == BZABBlockingModeSafe) {
        return NO;
    }

    BZABProfile *profile = BZABProfile.currentProfile;
    NSString *path = URL.path.lowercaseString ?: @"";
    BOOL isFirstParty = BZABHostMatchesAnyDomain(host, profile.firstPartyDomains);
    if (isFirstParty) {
        if (BZABStringContainsAnyNeedle(path, BZABEssentialPathNeedles())) {
            return NO;
        }
        if (BZABStringContainsAnyNeedle(path, profile.firstPartyAdPathNeedles)) {
            return YES;
        }
    }

    if (settings.blockingMode == BZABBlockingModeAggressive && BZABHostLooksLikeDedicatedAdHost(host)) {
        return YES;
    }
    return NO;
}

@end
