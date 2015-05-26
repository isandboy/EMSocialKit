//
//  EMSocialSDK.m
//  EMSocialApp
//
//  Created by Ryan Wang on 3/20/15.
//  Copyright (c) 2015 Ryan Wang. All rights reserved.
//

#import "EMSocialSDK.h"
#import "EMActivityViewController.h"
#import "EMActivity.h"
#import "EMActivityWeibo.h"
#import "EMActivityWeChat.h"
#import "EMActivityWeChatTimeline.h"
#import "EMActivityWeChatSession.h"

NSString *const EMSocialSDKErrorDomain = @"com.emoney.emsocialsdk";

NSString *const EMSocialOpenURLNotification = @"EMSocialOpenURLNotification";
NSString *const EMSocialOpenURLKey = @"EMSocialOpenURLKey";


static EMSocialSDK *sharedInstance = nil;

@interface EMSocialSDK ()

@property (nonatomic, strong, readwrite) EMActivity *activeActivity;
@property (nonatomic,   copy, readwrite) EMSocialLoginCompletionHandler loginCompletionHandler;
@property (nonatomic, strong, readwrite) EMSocialDefaultConfigurator *configurator;

@end

@implementation EMSocialSDK

///////////////////////////////////////////////////////////////////////////////////

+ (instancetype)sharedSDK {
    @synchronized(self)
    {
        if (sharedInstance == nil) {
            [NSException raise:@"IllegalStateException" format:@"ShareKit must be configured before use. Use your subclass of DefaultSHKConfigurator, for more info see https://github.com/ShareKit/ShareKit/wiki/Configuration. Example: ShareKitDemoConfigurator in the demo app"];
        }
    }
    return sharedInstance;
}

+ (instancetype)sharedSDKWithConfigurator:(EMSocialDefaultConfigurator *)configor {
    @synchronized(self)
    {
        if (sharedInstance != nil) {
            [NSException raise:@"IllegalStateException" format:@"SHKConfiguration has already been configured with a delegate."];
        }
        sharedInstance = [[self alloc] initWithConfigurator:configor];
    }
    return sharedInstance;
}

- (instancetype)initWithConfigurator:(EMSocialDefaultConfigurator*)config
{
    if ((self = [super init])) {
        _configurator = config;
    }
    return self;
}

- (id)configurationValue:(NSString*)selector withObject:(id)object
{
    //SHKLog(@"Looking for a configuration value for %@.", selector);
    
    SEL sel = NSSelectorFromString(selector);
    if ([self.configurator respondsToSelector:sel]) {
        id value;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if (object) {
            value = [self.configurator performSelector:sel withObject:object];
        } else {
            value = [self.configurator performSelector:sel];
        }
#pragma clang diagnostic pop
    
        if (value) {
            //SHKLog(@"Found configuration value for %@: %@", selector, [value description]);
            return value;
        }
    }
    
    //SHKLog(@"Configuration value is nil or not found for %@.", selector);
    return nil;
}

///////////////////////////////////////////////////////////////////////////////////

#pragma mark - Register
- (void)registerBuiltInSocialApps {
    [EMActivityWeibo registerApp];
    [EMActivityWeChat registerApp];
}

///////////////////////////////////////////////////////////////////////////////////

- (BOOL)handleOpenURL:(NSURL *)URL sourceApplication:(NSString *)application {
    [[NSNotificationCenter defaultCenter] postNotificationName:EMSocialOpenURLNotification object:nil userInfo:@{EMSocialOpenURLKey:URL}];
    return YES;
}

///////////////////////////////////////////////////////////////////////////////////

- (void)shareActivityItems:(NSArray *)content rootViewController:(UIViewController *)controller completionHandler:(EMActivityShareCompletionHandler)shareCompletionHandler {
    NSArray *activies = @[[[EMActivityWeibo alloc]init],
                          [[EMActivityWeChatTimeline alloc]init],
                          [[EMActivityWeChatSession alloc]init]
                         ];
    EMActivityViewController *activityViewController = [[EMActivityViewController alloc] initWithActivityItems:content applicationActivities:activies];
    
    activityViewController.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSDictionary *returnedInfo, NSError *activityError) {
        if (shareCompletionHandler) {
            shareCompletionHandler(activityType,  completed, returnedInfo, activityError);
        }
    };
    
    [controller presentViewController:activityViewController animated:YES completion:^{
        NSLog(@"DONE");
    }];
}

- (void)shareActivityItems:(NSArray *)content activity:(EMActivity *)activity completionHandler:(EMActivityShareCompletionHandler)shareCompletionHandler {
    self.activeActivity = activity;
    NSString *type = [activity activityType];
    if([activity canPerformWithActivityItems:content]) {
        [activity prepareWithActivityItems:content];
        [activity performActivity];
        activity.completionHandler = ^(BOOL completed, NSDictionary *returnedInfo, NSError *activityError) {
            if(shareCompletionHandler) {
                shareCompletionHandler(type, YES, returnedInfo, activityError);
            }
        };
    } else {
        shareCompletionHandler(type, NO, nil, [NSError errorWithDomain:EMSocialSDKErrorDomain code:100 userInfo:@{NSLocalizedDescriptionKey:@"应用未安装"}]);
    }
}


- (void)loginWithActivity:(EMActivity *)activity completionHandler:(EMSocialLoginCompletionHandler) completion {
    self.activeActivity = activity;
    if([activity canPerformLogin]) {
        self.loginCompletionHandler = completion;
        [self.activeActivity performLogin];
    } else {
        completion(NO, nil, [NSError errorWithDomain:EMSocialSDKErrorDomain code:100 userInfo:@{NSLocalizedDescriptionKey:@"应用未安装"}]);
    }
}


@end