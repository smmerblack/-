#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BZABVersion;

typedef NS_ENUM(NSInteger, BZABBlockingMode) {
    BZABBlockingModeSafe = 0,
    BZABBlockingModeBalanced = 1,
    BZABBlockingModeAggressive = 2,
};

@interface BZABProfile : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSSet<NSString *> *bundleIdentifiers;
@property (nonatomic, copy) NSArray<NSString *> *classNameNeedles;
@property (nonatomic, copy) NSArray<NSString *> *firstPartyDomains;
@property (nonatomic, copy) NSArray<NSString *> *firstPartyAdPathNeedles;
@property (nonatomic, assign) NSTimeInterval defaultSuppressionDuration;
@property (nonatomic, assign) NSTimeInterval resumeSuppressionDuration;

+ (instancetype)currentProfile;

@end

@interface BZABSettings : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL networkBlockingEnabled;
@property (nonatomic, assign) BOOL viewBlockingEnabled;
@property (nonatomic, assign) BOOL debugLoggingEnabled;
@property (nonatomic, assign) BZABBlockingMode blockingMode;
@property (nonatomic, assign) NSTimeInterval suppressionDuration;

+ (instancetype)sharedSettings;
- (void)synchronize;

@end

@interface BZABStats : NSObject

@property (atomic, assign, readonly) NSUInteger blockedRequests;
@property (atomic, assign, readonly) NSUInteger blockedViews;
@property (atomic, assign, readonly) NSUInteger triggeredSkips;
@property (atomic, assign, readonly) NSUInteger detectedSDKClasses;
@property (atomic, copy, readonly, nullable) NSString *lastBlockedHost;
@property (atomic, copy, readonly, nullable) NSString *lastBlockedClass;
@property (atomic, copy, readonly, nullable) NSString *lastDetectedSDKClass;

+ (instancetype)sharedStats;
- (void)recordBlockedHost:(NSString *)host;
- (void)recordBlockedClass:(NSString *)className;
- (void)recordTriggeredSkipWithClass:(NSString *)className;
- (void)recordDetectedSDKClass:(NSString *)className;

@end

FOUNDATION_EXPORT BOOL BZABHostMatchesDomain(NSString *host, NSString *domain);
FOUNDATION_EXPORT BOOL BZABStringContainsAnyNeedle(NSString *value, NSArray<NSString *> *needles);
FOUNDATION_EXPORT NSSet<NSString *> *BZABCustomBlockedDomains(void);
FOUNDATION_EXPORT NSTimeInterval BZABElapsedSinceLoad(void);
FOUNDATION_EXPORT BOOL BZABIsInsideSuppressionWindow(void);
FOUNDATION_EXPORT void BZABExtendSuppressionWindow(NSTimeInterval duration);
FOUNDATION_EXPORT NSUInteger BZABCurrentSuppressionGeneration(void);
FOUNDATION_EXPORT void BZABLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
