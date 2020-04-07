#import "AppDelegate+FirebaseDynamicLinksPlugin.h"
#import "FirebaseDynamicLinksPlugin.h"
#import <objc/runtime.h>


@implementation AppDelegate (FirebaseDynamicLinksPlugin)
static NSString *const CUSTOM_URL_PREFIX_TO_IGNORE = @"/__/auth/callback";

+ (void)load {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        [self swizzleMethod:@selector(application:openURL:options:)];
        [self swizzleMethod:@selector(application:continueUserActivity:restorationHandler:)];
        [self swizzleMethod:@selector(application:didFinishLaunchingWithOptions:)];
    });
}

+ (void)swizzleMethod:(SEL)originalSelector {
    Class class = [self class];
    NSString *selectorString = NSStringFromSelector(originalSelector);
    SEL newSelector = NSSelectorFromString([@"swizzled_" stringByAppendingString:selectorString]);
    SEL defaultSelector = NSSelectorFromString([@"default_" stringByAppendingString:selectorString]);
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method newMethod = class_getInstanceMethod(class, newSelector);
    Method noopMethod = class_getInstanceMethod(class, defaultSelector);
    if (class_addMethod(class, originalSelector, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(class, newSelector, method_getImplementation(originalMethod ?: noopMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, newMethod);
    }
}

- (BOOL)default_application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *, id> *)options {
    return FALSE;
}

- (BOOL)swizzled_application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *, id> *)options {
    // always call original method implementation first
    BOOL handled = [self swizzled_application:app openURL:url options:options];
    FirebaseDynamicLinksPlugin* dl = [self.viewController getCommandInstance:@"FirebaseDynamicLinks"];
    // parse firebase dynamic link
    FIRDynamicLink *dynamicLink = [[FIRDynamicLinks dynamicLinks] dynamicLinkFromCustomSchemeURL:url];
    if (dynamicLink) {
        [dl postDynamicLink:dynamicLink];
        handled = TRUE;
    }
    return handled;
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<NSString *, id> *)options {
    return [self application:app
                     openURL:url
           sourceApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]
                  annotation:options[UIApplicationOpenURLOptionsAnnotationKey]];
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
  FIRDynamicLink *dynamicLink = [[FIRDynamicLinks dynamicLinks] dynamicLinkFromCustomSchemeURL:url];

    FirebaseDynamicLinksPlugin* dl = [self.viewController getCommandInstance:@"FirebaseDynamicLinks"];
    if (dynamicLink) {
        BOOL validDynamicLink = dynamicLink.url && ![dynamicLink.url.path hasPrefix:CUSTOM_URL_PREFIX_TO_IGNORE];
        if (validDynamicLink) {
            [dl postDynamicLink:dynamicLink];
            return YES;
        } else {
            // Dynamic link has empty deep link. This situation will happens if
            // Firebase Dynamic Links iOS SDK tried to retrieve pending dynamic link,
            // but pending link is not available for this device/App combination.
            // At this point you may display default onboarding view.
        }
    }
    return [super application: application
                      openURL:url
            sourceApplication:sourceApplication
                   annotation:annotation];
}

- (BOOL)default_application:(UIApplication *)app continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray *))restorationHandler {
    return FALSE;
}

- (BOOL)swizzled_application:(UIApplication *)app continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray *))restorationHandler {
    // always call original method implementation first
    BOOL handled = [self swizzled_application:app continueUserActivity:userActivity restorationHandler:restorationHandler];

    // handle firebase dynamic link
    return [[FIRDynamicLinks dynamicLinks]
        handleUniversalLink:userActivity.webpageURL
        completion:^(FIRDynamicLink * _Nullable dynamicLink, NSError * _Nullable error) {
            FirebaseDynamicLinksPlugin* dl = [self.viewController getCommandInstance:@"FirebaseDynamicLinks"];
            // Try this method as some dynamic links are not recognize by handleUniversalLink
            // ISSUE: https://github.com/firebase/firebase-ios-sdk/issues/743
            dynamicLink = dynamicLink ? dynamicLink
                : [[FIRDynamicLinks dynamicLinks]
                   dynamicLinkFromUniversalLinkURL:userActivity.webpageURL];

            if (dynamicLink) {
                [dl postDynamicLink:dynamicLink];
            }
        }] || handled;
}

// [START didfinishlaunching]
- (BOOL)default_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    return FALSE;
}
- (BOOL)swizzled_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    // always call original method implementation first
    [self swizzled_application:application didFinishLaunchingWithOptions:launchOptions];
    [FIROptions defaultOptions].deepLinkURLScheme = [[NSBundle mainBundle] bundleIdentifier];

    if (![FIRApp defaultApp]) {
        [FIRApp configure];
    }
    NSDictionary *userActivityDictionary = [launchOptions objectForKey:UIApplicationLaunchOptionsUserActivityDictionaryKey];

    if (userActivityDictionary) {
        // Continue activity here
        return YES;
    }
}
// [END didfinishlaunching]
@end
