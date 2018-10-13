//
//  ViewController.h
//  MAWV - Mobile App Web View
//
//  Created by Rafael Alvarado Emmanuelli on 3/10/18.
//  © 2018 MAWV.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>


@interface ViewController : UIViewController <WKNavigationDelegate>

@property BOOL isLogger;
@property BOOL isOnline;
@property BOOL isAppInitialized;
@property BOOL isShowProgressIndicator;
@property BOOL isShowLaunchImage;
@property BOOL hasMailChimpLoaded;
@property int statusBarHeight;
@property (nonatomic, retain) NSDictionary *config;
@property (nonatomic, retain) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, retain) UIImageView *launchImageView;
@property (nonatomic, retain) WKWebView *webView;
@property (nonatomic, retain) WKWebViewConfiguration *webConfiguration;

@end



