//
//  EMSocialWebViewController.h
//  EMSocialApp
//
//  Created by Ryan Wang on 3/18/15.
//  Copyright (c) 2015 Ryan Wang. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface EMSocialWebViewController : UIViewController

@property (nonatomic, readonly, strong) WKWebView* webView;

- (instancetype)initWithURL:(NSURL *)URL;

- (void)openURL:(NSURL*)URL;
- (void)openRequest:(NSURLRequest*)request;

@end
