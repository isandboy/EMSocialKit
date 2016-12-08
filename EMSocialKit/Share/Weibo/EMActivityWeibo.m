//
//  EMActivityWeibo.m
//

#import "EMActivityWeibo.h"
#import "EMSocialSDK.h"
#import "UIImage+SocialBundle.h"
#import "UIImage+SK_Resize.h"
#import "EMSocialWebViewController.h"
#import "NSString+SK_URLParameters.h"

NSString *const EMActivityWeiboAccessTokenKey   = @"EMActivityWeiboAccessTokenKey";
NSString *const EMActivityWeiboRefreshTokenKey  = @"EMActivityWeiboRefreshTokenKey";
NSString *const EMActivityWeiboExpirationDateKey= @"EMActivityWeiboExpirationDateKey";

NSString *const EMActivityWeiboUserIdKey        = @"EMActivityWeiboUserIdKey";
NSString *const EMActivityWeiboUserNameKey      = @"EMActivityWeiboUserNameKey";
NSString *const EMActivityWeiboProfileImageURLKey= @"EMActivityWeiboProfileImageURLKey";// 头像

NSString *const EMActivityWeiboStatusCodeKey    = @"EMActivityWeiboStatusCodeKey";
NSString *const EMActivityWeiboStatusMessageKey = @"EMActivityWeiboStatusMessageKey";

NSString *const UIActivityTypePostToSinaWeibo   = @"UIActivityTypePostToSinaWeibo";

static NSString *const WeiboSDKVersion          = @"003013000";
static NSString *const WeiboAutorizeURL         = @"https://open.weibo.cn/oauth2/authorize";
static NSString *const WeiboAccessTokenURL      = @"https://api.weibo.com/oauth2/access_token";

static NSString *const WeiboUserInfoURL         = @"https://api.weibo.com/2/users/show.json";

@interface EMActivityWeibo () <UIWebViewDelegate>

@property (nonatomic, strong) UIImage *shareImage; // only support one image
@property (nonatomic, strong) NSString *shareString;
@property (nonatomic, strong) NSURL *shareURL; // will be converted to String
@property (nonatomic, assign) BOOL isLogin;


@end

@implementation EMActivityWeibo

+ (void)registerApp {
}

- (NSString *)redirectURI {
    return EMCONFIG(sinaWeiboCallbackUrl);
}

- (NSString *)appId {
    return EMCONFIG(sinaWeiboConsumerKey);
}

- (NSString *)appSecret {
    return EMCONFIG(sinaWeiboConsumerSecret);
}

- (NSString *)scope {
    return @"all";
}


+ (UIActivityCategory)activityCategory {
    return UIActivityCategoryShare;
}

- (NSString *)activityType {
    return UIActivityTypePostToSinaWeibo;
}

- (NSString *)activityTitle {
    return @"新浪微博";
}

- (UIImage *)activityImage {
    
    return [UIImage socialImageNamed:@"EMSocialKit.bundle/weibo"];
}

+ (BOOL)isAppInstalled {
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"weibo://"]];
}

- (BOOL)isAppInstalled {
    return [[self class] isAppInstalled];
}

// URL will be converted to string
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
    if (![self isAppInstalled]) {
        return NO;
    }
    
    for (id item in activityItems) {
        if ([item isKindOfClass:[UIImage class]]) {
            return YES;
        } else if ([item isKindOfClass:[NSData class]]) {
            return YES;
        } else if ([item isKindOfClass:[NSURL class]]) {
            return YES;
        } else if ([item isKindOfClass:[NSString class]]) {
            return YES;
        }
    }
    return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems {
    for (id item in activityItems) {
        if ([item isKindOfClass:[UIImage class]] && !self.shareImage) {
            self.shareImage = [self optimizedImageFromOriginalImage:item];
        } else if ([item isKindOfClass:[NSData class]] && !self.shareImage) {
            self.shareImage = [self optimizedImageFromOriginalImage:[UIImage imageWithData:item]];
        } else if ([item isKindOfClass:[NSString class]]) {
            self.shareString = [(self.shareString ? : @"") stringByAppendingFormat:@"%@%@", (self.shareString ? @" " : @""), item];
        } else if ([item isKindOfClass:[NSURL class]]) {
            self.shareURL = item;
        } else
            NSLog(@"NCActivityWeibo: Unknown item type: %@", item);
    }
}

- (void)performActivity {
    self.isLogin = NO;

    if ([self handleAppNotInstall]) {
        return;
    }
    
    NSMutableDictionary *messageInfo = [NSMutableDictionary dictionary];
    messageInfo[@"__class"] = @"WBMessageObject";

    NSString *shareString = self.shareString;
    if (self.shareURL) {
        // 长度太长需要截取
        NSString *shareURLString = [self.shareURL absoluteString];
        if (shareURLString.length > 136) {
            shareString = [shareURLString substringToIndex:136];
        } else if (shareString.length + shareURLString.length > 136) {
            shareString = [shareString substringToIndex:136 - shareURLString.length];
            shareString = [shareString stringByAppendingFormat:@"... %@", self.shareURL];
        } else {
            shareString = [shareString stringByAppendingFormat:@" %@", self.shareURL];
        }
    }
    
    if (shareString) {
        messageInfo[@"text"] = shareString;
    }

    if (self.shareImage) {
        NSData *imageData = UIImageJPEGRepresentation(self.shareImage, 1.0);
        messageInfo[@"imageObject"] = @{@"imageData":imageData};
    }
    
    NSString *uuidString = [[NSUUID UUID] UUIDString];
    
    NSDictionary *dict = @{@"__class": @"WBSendMessageToWeiboRequest",
                           @"message": messageInfo,
                           @"requestID": uuidString
                           };
    
    NSString *appID = EMCONFIG(sinaWeiboConsumerKey);
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        bundleID = @"";
    }
    NSData *appData = [NSKeyedArchiver archivedDataWithRootObject:@{@"appKey": appID,
                                                                    @"bundleID": bundleID}];
    
    NSData *transferObjectData = [NSKeyedArchiver archivedDataWithRootObject:dict];
    NSArray *messageData = @[@{@"transferObject": transferObjectData},
                             @{@"app":appData}];

    [UIPasteboard generalPasteboard].items = messageData;

    NSString *weiboURLString = [NSString stringWithFormat:@"weibosdk://request?id=%@&sdkversion=%@", uuidString, WeiboSDKVersion];
                       
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:weiboURLString]];
    
    [self activityDidFinish:YES];
}


- (BOOL)canPerformLogin {
    return YES;
}


- (void)performLogin {
    self.isLogin = YES;

    if (![self isAppInstalled]) {
        [self performLoginInWeb];
        return;
    }
    
    NSString *appID = EMCONFIG(sinaWeiboConsumerKey);
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) {
        bundleID = @"";
    }
    NSString *bundleName = [[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"];
    if (!bundleName) {
        bundleName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    }
    NSData *appData = [NSKeyedArchiver archivedDataWithRootObject:@{@"appKey": appID,
                                                                    @"bundleID": bundleID,
                                                                    @"name":bundleName}];
    
    NSData *userInfoData = [NSKeyedArchiver archivedDataWithRootObject:@{@"mykey": @"as you like",
                                                                    @"SSO_From": @"SendMessageToWeiboViewController"}];


    NSString *uuidString = [[NSUUID UUID] UUIDString];
    
    NSDictionary *dict = @{@"__class": @"WBAuthorizeRequest",
                           @"redirectURI": [self redirectURI],
                           @"requestID": uuidString,
                           @"scope":[self scope]
                           };

    NSData *transferObjectData = [NSKeyedArchiver archivedDataWithRootObject:dict];
    NSArray *messageData = @[@{@"transferObject": transferObjectData},
                             @{@"app":appData},
                             @{@"userInfoData":userInfoData}];
    
    [UIPasteboard generalPasteboard].items = messageData;
    
    NSString *weiboURLString = [NSString stringWithFormat:@"weibosdk://request?id=%@&sdkversion=%@", uuidString, WeiboSDKVersion];
    
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:weiboURLString]];

}


- (BOOL)handleOpenURL:(NSURL *)url {
    return [self _handleOpenURL:url];
}

- (BOOL)_handleOpenURL:(NSURL *)url {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSArray *items = [UIPasteboard generalPasteboard].items;
    for (NSDictionary *item in items) {
        if (item[@"transferObject"]) {
            results[@"transferObject"] = [NSKeyedUnarchiver unarchiveObjectWithData:item[@"transferObject"]];
            break;
        }
    }
    
    NSInteger errorCode = 0;
    NSInteger generalErrorCode = 0;

    NSDictionary *responseInfo = results[@"transferObject"];
    NSString *class = responseInfo[@"__class"];
    if (!class) {
        return NO;
    }
    
    NSString *statusCode = responseInfo[@"statusCode"];
    if (statusCode) {
        errorCode = [statusCode integerValue];
    } else {
        errorCode = EMActivityWeiboStatusCodeUnknown;
    }
    
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    
    userInfo[EMActivityWeiboStatusCodeKey] = @(errorCode);
    NSString *message = [[self errorMessages] objectForKey:@(errorCode)];
    if (message) {
        userInfo[EMActivityWeiboStatusMessageKey] = message;
    }
    
    if (errorCode == EMActivityWeiboStatusCodeSuccess) {
        generalErrorCode = EMActivityGeneralStatusCodeSuccess;
    } else if (errorCode == EMActivityWeiboStatusCodeUserCancel) {
        generalErrorCode = EMActivityGeneralStatusCodeUserCancel;
    } else if (errorCode == EMActivityWeiboStatusCodeSentFail) {
        generalErrorCode = EMActivityGeneralStatusCodeCommonFail;
    } else {
        generalErrorCode = EMActivityGeneralStatusCodeUnknownFail;
    }
    
    userInfo[EMActivityGeneralStatusCodeKey] = @(generalErrorCode);
    userInfo[EMActivityGeneralMessageKey] = [[self class] errorMessageWithCode:generalErrorCode];

    
    NSString *accessToken = responseInfo[@"accessToken"];
    if (accessToken.length > 0) {
        [userInfo setObject:accessToken forKey:EMActivityWeiboAccessTokenKey];
    }
    
    NSDate *expirationDate = responseInfo[@"expirationDate"];
    if (expirationDate) {
        [userInfo setObject:expirationDate forKey:EMActivityWeiboExpirationDateKey];
    }
    
    NSString *refreshToken = responseInfo[@"refreshToken"];
    if (refreshToken.length > 0) {
        [userInfo setObject:refreshToken forKey:EMActivityWeiboRefreshTokenKey];
    }
    
    NSString *userID = responseInfo[@"userID"];
    if (userID.length > 0) {
        [userInfo setObject:userID forKey:EMActivityWeiboUserIdKey];
    }

    
    if (self.isLogin) {
        [self handledLoginResponse:userInfo error:nil];
    } else {
        [self handledShareResponse:userInfo error:nil];
    }
    
    return YES;
}

- (void)_handleWebAuthWithInfo:(NSDictionary *)info {
    
}

- (void)handledLoginResponse:(NSDictionary *)userInfo error:(NSError *)error {
    NSString *userId = userInfo[EMActivityWeiboUserIdKey];
    NSString *accessToken = userInfo[EMActivityWeiboAccessTokenKey];
    
    if (userId == nil || accessToken == nil) {
        [super handledLoginResponse:userInfo error:error];
    } else {
        __block NSMutableDictionary *newUserInfo = [userInfo mutableCopy];
        
        NSString *userInfoURL = [NSString stringWithFormat:@"%@?uid=%@&access_token=%@",
                                 WeiboUserInfoURL,
                                 newUserInfo[EMActivityWeiboUserIdKey],
                                 newUserInfo[EMActivityWeiboAccessTokenKey]];

        NSURLSession *session = [NSURLSession sharedSession];
        // 通过URL初始化task,在block内部可以直接对返回的数据进行处理
        NSURLSessionTask *task = [session dataTaskWithURL:[NSURL URLWithString:userInfoURL]
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
//                                            NSLog(@"%@", [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil]);
                                            
                                            if (!error) {
                                                NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
                                                NSString *nickname = profile[@"name"];
                                                newUserInfo[EMActivityWeiboUserNameKey] = nickname;
                                                newUserInfo[EMActivityWeiboProfileImageURLKey] = profile[@"avatar_large"];
                                            }

                                            if ([NSThread currentThread] == [NSThread mainThread]) {
                                                [super handledLoginResponse:newUserInfo error:error];
                                            } else {
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    [super handledLoginResponse:newUserInfo error:error];
                                                });
                                            }
                                        }];
        
        // 启动任务
        [task resume];
    }
}

- (NSDictionary *)errorMessages{
    return
    @{
      @(EMActivityWeiboStatusCodeSuccess):          @"分享成功",
      @(EMActivityWeiboStatusCodeUserCancel):       @"用户取消分享",
      @(EMActivityWeiboStatusCodeSentFail):         @"分享失败",
      @(EMActivityWeiboStatusCodeAuthDeny):         @"授权失败",
      @(EMActivityWeiboStatusCodeUserCancelInstall):@"用户取消安装微博客户端",
      @(EMActivityWeiboStatusCodePayFail):          @"支付失败",
      @(EMActivityWeiboStatusCodeShareInSDKFailed): @"分享失败",
      @(EMActivityWeiboStatusCodeUnsupport):        @"不支持的请求",
      @(EMActivityWeiboStatusCodeUnknown):          @"未知错误",
      @(EMActivityWeiboStatusCodeAppNotInstall):    @"您未安装微博客户端",
      };
}

- (BOOL)handleAppNotInstall {
    NSMutableDictionary *userInfo = @{}.mutableCopy;
    
    userInfo[EMActivityGeneralStatusCodeKey] = @(EMActivityGeneralStatusCodeNotInstall);
    userInfo[EMActivityGeneralMessageKey] = [[self class] errorMessageWithCode:EMActivityGeneralStatusCodeNotInstall];
    userInfo[EMActivityWeiboStatusCodeKey] = @(EMActivityWeiboStatusCodeAppNotInstall);
    userInfo[EMActivityWeiboStatusMessageKey] = [self errorMessages][@(EMActivityWeiboStatusCodeAppNotInstall)];
    if (![self isAppInstalled]) {
        if (self.isLogin) {
            [self handledLoginResponse:userInfo error:nil];
        } else {
            [self handledShareResponse:userInfo error:nil];
        }
        return YES;
    }
    return NO;
}

#pragma mark - 
#pragma mark - WebApp OAuth2
- (void)performLoginInWeb {
    [self getRequestCodeInWeb];
}

- (void)getRequestCodeInWeb {
    NSString *appID = EMCONFIG(sinaWeiboConsumerKey);
    
    NSString *accessTokenAPI = [NSString stringWithFormat:@"%@?client_id=%@&response_type=code&redirect_uri=%@&scope=%@",WeiboAutorizeURL, appID, self.redirectURI, self.scope];
    
    EMSocialWebViewController *webController = [[EMSocialWebViewController alloc] initWithURL:[NSURL URLWithString:accessTokenAPI]];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:webController];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:navigationController animated:YES completion:^{
        webController.webView.delegate = self;
    }];
    
}

- (NSString *)_accessTokenInWebWithCode:(NSString *)code {
    NSString *appID = EMCONFIG(sinaWeiboConsumerKey);
    NSString *appKey = EMCONFIG(sinaWeiboConsumerSecret);

    NSString *accessTokenURL = [NSString stringWithFormat:@"%@?client_id=%@&client_secret=%@&grant_type=authorization_code&redirect_uri=%@&code=%@", WeiboAccessTokenURL, appID,appKey,self.redirectURI, code];
    
    return accessTokenURL;
}

- (void)getAccessTokenWithCode:(NSString *)code {
    NSString *url = [self _accessTokenInWebWithCode:code];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    NSURLSession *session = [NSURLSession sharedSession];
    // 通过URL初始化task,在block内部可以直接对返回的数据进行处理
    NSURLSessionTask *task = [session dataTaskWithRequest:request
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                        NSDictionary *profile = nil;
                                        if (!error) {
                                            profile = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
                                            
                                            NSString *userId = profile[@"uid"];
                                            NSString *accessToken = profile[@"access_token"];
                                            
                                            NSMutableDictionary *newUserInfo = [NSMutableDictionary dictionary];
                                            newUserInfo[EMActivityWeiboUserIdKey] = userId;
                                            newUserInfo[EMActivityWeiboAccessTokenKey] = accessToken;
                                            
                                            [self handledLoginResponse:newUserInfo error:nil];
                                        }
                                        
                                    }];
    
    // 启动任务
    [task resume];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    NSURL *URL = [request URL];
    if ([[self redirectURI] rangeOfString:[URL host]].length > 0) {

        NSDictionary *parameters = [[URL query] SK_URLParameters];
        NSString *code = parameters[@"code"];
        [self getAccessTokenWithCode:code];
        
        [[UIApplication sharedApplication].keyWindow.rootViewController dismissViewControllerAnimated:YES completion:NULL];
        return NO;
    }
    
    return YES;
}


#pragma mark -
#pragma mark Private Methods
- (UIImage *)optimizedImageFromOriginalImage:(UIImage *)oriImage {
    // Resize if needed
    UIImage *result = (oriImage.size.width > 1600 || oriImage.size.height > 1600) ? [oriImage SK_resizedImageWithMaximumSize:CGSizeMake(1600,1600)] : oriImage;
    
    return result;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
