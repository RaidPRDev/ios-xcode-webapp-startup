//
//  ViewController.m
//  MAWV - Mobile App Web View
//
//  Created by Rafael Alvarado Emmanuelli on 3/10/18.
//  © 2018 MAWV.
//

#import "ViewController.h"
#import "Reachability.h"

@interface ViewController ()

@property (nonatomic) Reachability *hostReachability;
@property (nonatomic) Reachability *internetReachability;

@end

@implementation ViewController

@synthesize isLogger;
@synthesize isOnline;
@synthesize isAppInitialized;
@synthesize isShowProgressIndicator;
@synthesize isShowLaunchImage;
@synthesize hasMailChimpLoaded;
@synthesize config;
@synthesize statusBarHeight;
@synthesize activityIndicator;
@synthesize launchImageView;
@synthesize webView;
@synthesize webConfiguration;

#pragma mark - App Start

// update statusbar style - this first method called at startup automatically
// will only work if you add plist 'View controller-based status bar appearance' to NO
- (UIStatusBarStyle)preferredStatusBarStyle
{
    [self trace:@"preferredStatusBarStyle"];
    
    // UIStatusBarStyleDefault = BLACK
    // UIStatusBarStyleLightContent = WHITE
    
    BOOL useWhiteColor = YES;
    
    if (useWhiteColor) return UIStatusBarStyleLightContent;
    else return UIStatusBarStyleDefault;
}

// when core app is done loading
-(void)viewDidLoad
{
    [self trace:@"viewDidLoad"];
    
    isLogger = YES;
    
    [super viewDidLoad];
    
    [self loadConfig];
    
    [self updateStatusBarAppearance];
    
    [self startApplication];
    
    // add notifications
    [self addWillTerminateNotification];
    [self addOrientationChangeListener];
}

// This method will load the Config.plist settings
-(void)loadConfig
{
    [self trace:@"loadConfig"];

    // look for and get the location of the Config.plist
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Config" ofType:@"plist"];
    
    // Load the dictionary
    config = [[NSDictionary alloc] initWithContentsOfFile:path];
    
    // get progress indicator config settings
    NSDictionary* progress_indicator = [config objectForKey:@"progress_indicator"];
    isShowProgressIndicator = [[progress_indicator objectForKey:@"show_progress"] boolValue];
    
    // get show_launch_image setting
    isShowLaunchImage = [[config objectForKey:@"show_launch_image"] boolValue];
}

-(void)updateStatusBarAppearance
{
    // get status bar config settings
    NSDictionary* status_bar = [config objectForKey:@"status_bar"];
    
    // get status bar view
    UIView *statusBar = [[[UIApplication sharedApplication] valueForKey:@"statusBarWindow"] valueForKey:@"statusBar"];
    
    statusBarHeight = statusBar.frame.size.height;
    
    if ([statusBar respondsToSelector:@selector(setBackgroundColor:)])
    {
        statusBar.backgroundColor = [self uiColorFromHexString:([status_bar objectForKey:@"background_color"])];
    }
}

-(void)startApplication
{
    [self trace:@"startApplication"];
   
    isAppInitialized = false;       // tells us that the app has finished loading
    hasMailChimpLoaded = false;     // add mailchimp support
    isOnline = false;               // check for internet connection
    
    
    // clean cache and creat new web viee
    [self createWebView];
    
    // check if we show launch and/or progress indicator
    if (isShowLaunchImage) [self createLaunchImage];
    if (isShowProgressIndicator) [self createProgressIndicator];
    
    // first clean cache and then load webview url
    [self clearWKWebviewCache];
}

-(void) clearWKWebviewCache
{
    [self trace:@"clearWKWebviewCache.Start"];
    
    NSMutableArray *dataTypes = [NSMutableArray arrayWithCapacity:0];
    
    [dataTypes addObject:(WKWebsiteDataTypeDiskCache)];
    [dataTypes addObject:(WKWebsiteDataTypeLocalStorage)];
    [dataTypes addObject:(WKWebsiteDataTypeSessionStorage)];
    [dataTypes addObject:(WKWebsiteDataTypeOfflineWebApplicationCache)];
    [dataTypes addObject:(WKWebsiteDataTypeMemoryCache)];
    
    // check if we are running on iOS 11.3
    if (@available(iOS 11.3, *))
    {
        [self trace:@"iOS 11.3+ detected, adding WKWebsiteDataTypeFetchCache"];
        [dataTypes addObject:(WKWebsiteDataTypeFetchCache)];
    }
    
    NSSet *webDataTypes = [NSSet setWithArray:dataTypes];
   
    NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:webDataTypes
        modifiedSince:dateFrom completionHandler:^{

        [self trace:@"clearWKWebviewCache.Completed"];
       
        // purge cache even more
        [self removeCache];
        [self removeAllStoredCredentials];
      
        // load web_view_url
        [self loadWebviewUrl];
   }];
}

-(void) removeAllStoredCredentials{
    // Delete any cached URLrequests!
    NSURLCache *sharedCache = [NSURLCache sharedURLCache];
    [sharedCache removeAllCachedResponses];
    
    // Also delete all stored cookies!
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [cookieStorage cookies];
    id cookie;
    for (cookie in cookies) {
        [cookieStorage deleteCookie:cookie];
    }
    
    NSDictionary *credentialsDict = [[NSURLCredentialStorage sharedCredentialStorage] allCredentials];
    if ([credentialsDict count] > 0) {
        // the credentialsDict has NSURLProtectionSpace objs as keys and dicts of userName => NSURLCredential
        NSEnumerator *protectionSpaceEnumerator = [credentialsDict keyEnumerator];
        id urlProtectionSpace;
        // iterate over all NSURLProtectionSpaces
        while (urlProtectionSpace = [protectionSpaceEnumerator nextObject]) {
            NSEnumerator *userNameEnumerator = [[credentialsDict objectForKey:urlProtectionSpace] keyEnumerator];
            id userName;
            // iterate over all usernames for this protectionspace, which are the keys for the actual NSURLCredentials
            while (userName = [userNameEnumerator nextObject]) {
                NSURLCredential *cred = [[credentialsDict objectForKey:urlProtectionSpace] objectForKey:userName];
                //NSLog(@"credentials to be removed: %@", cred);
                [[NSURLCredentialStorage sharedCredentialStorage] removeCredential:cred forProtectionSpace:urlProtectionSpace];
            }
        }
    }
}

-(void) removeCache
{
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSArray *files = [[NSFileManager defaultManager] subpathsAtPath:cachePath];
    
    NSLog(@" FILES COUNT: '%lu'", (unsigned long)[files count]);
    
    for (NSString *p in files)
    {
        NSError *error;
        NSString *path = [cachePath stringByAppendingPathComponent:p];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path] &&
            [[NSFileManager defaultManager] isDeletableFileAtPath:path])
        {
            [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
            
            NSLog(@" DELETING CACHE FILE: '%@'", path);
        }
        else
        {
            // NSLog(@" ****CANNOT DELETE FILE: '%@'", path);
        }
    }
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

-(void) removeLibraryCache
{
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSArray *files = [[NSFileManager defaultManager] subpathsAtPath:cachePath];
    
    NSLog(@" LIB FILES COUNT: '%lu'", (unsigned long)[files count]);
    
    for (NSString *p in files)
    {
        NSError *error;
        NSString *path = [cachePath stringByAppendingPathComponent:p];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path] &&
            [[NSFileManager defaultManager] isDeletableFileAtPath:path])
        {
            [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
            
            NSLog(@" LIB DELETING FILE: '%@'", path);
        }
        else
        {
            NSLog(@" **** LIB CANNOT DELETE FILE: '%@'", path);
        }
    }
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}


-(void) loadWebviewUrl
{
    // load web_view_url
    NSURL *url = [[NSURL alloc] initWithString:[config objectForKey:@"web_view_url"]];
    NSURLRequest *nsrequest = [NSURLRequest requestWithURL:url];
    [webView loadRequest:nsrequest];
    
}

#pragma mark - Launch Splash Image Initialization

-(void)createLaunchImage
{
    // create splash image
    launchImageView = [[UIImageView alloc] initWithFrame:CGRectMake(50, 50, 20, 20)];
    launchImageView.image = [self getLaunchImage];
    launchImageView.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    [launchImageView setContentMode:UIViewContentModeScaleToFill];
    
    // show: add image view to main views
    [self.view addSubview:launchImageView];
}

#pragma mark - WKWebview Initialization

-(void)createWebView
{
    [self trace:@"createWebView"];
    
    // allow user zooming js script
    NSString *javaScript = @"var meta = document.createElement('meta'); meta.name = 'viewport'; meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'; var head = document.getElementsByTagName('head')[0]; head.appendChild(meta);";
    
    // webview inject js script
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:javaScript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                   forMainFrameOnly:YES];
    
    // webConfiguration for webView
    webConfiguration = [[WKWebViewConfiguration alloc] init];
    
    // webView
    webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, statusBarHeight, self.view.frame.size.width, self.view.frame.size.height - statusBarHeight) configuration:webConfiguration];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // check if we are allowing user zooming
    BOOL allow_user_zoom = [[config objectForKey:@"allow_user_zoom"] boolValue];
    if (!allow_user_zoom) [webView.configuration.userContentController addUserScript:userScript];
    
    webView.navigationDelegate = self;
    if ([webView respondsToSelector:@selector(setCustomUserAgent:)]) {
        webView.customUserAgent = @"Chrome/56.0.0.0 Mobile";
    }
    
    // add to main view layout
    [self.view addSubview:webView];
}

#pragma mark - Progress Indicator

-(void)createProgressIndicator
{
    // get status bar config settings
    NSDictionary* progress_indicator = [config objectForKey:@"progress_indicator"];
    
    // create progress indicator
    activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    activityIndicator.frame = CGRectMake(0, 0, 80, 80);
    activityIndicator.opaque = NO;
    activityIndicator.center = self.view.center;
    activityIndicator.backgroundColor = [self uiColorFromHexString:([progress_indicator objectForKey:@"background_color"])];
    
    UIColor* uiColor = [self uiColorFromHexString:([progress_indicator objectForKey:@"indicator_color"])];
    [activityIndicator setColor:uiColor];
    
    CGFloat cornerRadius = [[progress_indicator objectForKey:@"corner_radius"] doubleValue];
    activityIndicator.layer.cornerRadius = cornerRadius;
    
    [self.view addSubview:activityIndicator];
}

#pragma mark - Main View Methods

-(void)viewDidAppear:(BOOL)animated
{
    [self trace:@"viewDidAppear"];

    // UIAlertController does not show when running in the viewDidLoad.
    // It only shows when initializing from viewDidAppear
    [self startNetListener];
}

#pragma mark - Network Connection Methods

-(void)startNetListener
{
    [self trace:@"startNetListener"];
    
    // observe the kNetworkReachabilityChangedNotification. When that notification is posted, the method reachabilityChanged will be called.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
    
    // change the host name here to change the server you want to monitor.
    NSString *remoteHostName = @"www.apple.com";
    NSString *remoteHostLabelFormatString = NSLocalizedString(@"Remote Host: %@", @"Remote host label format string");
    [self trace:[NSString stringWithFormat:remoteHostLabelFormatString, remoteHostName]];
    
    self.hostReachability = [Reachability reachabilityWithHostName:remoteHostName];
    [self.hostReachability startNotifier];
    [self updateInterfaceWithReachability:self.hostReachability];
    
    self.internetReachability = [Reachability reachabilityForInternetConnection];
    [self.internetReachability startNotifier];
    [self updateInterfaceWithReachability:self.internetReachability];
}

// Cleanup network listener
-(void)removeNetlistener
{
    [self trace:@"removeNetlistener"];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
}

// Called by Reachability whenever status changes.
- (void) reachabilityChanged:(NSNotification *)note
{
    [self trace:@"reachabilityChanged"];
    
    Reachability* curReach = [note object];
    NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
    [self updateInterfaceWithReachability:curReach];
}

// Gives us the network status info
// If there is no connection, we show an alert
- (void)updateInterfaceWithReachability:(Reachability *)reachability
{
    [self trace:@"updateInterfaceWithReachability"];
    
    if (reachability == self.hostReachability)
    {
        NetworkStatus internetStatus = [reachability currentReachabilityStatus];
        
        [self removeNetlistener];
        
        NSString *no_internet_alert_title = [config objectForKey:@"no_internet_alert_title"];
        NSString *no_internet_alert_body = [config objectForKey:@"no_internet_alert_body"];
        
        switch (internetStatus)
        {
            case NotReachable:
            {
                [self trace:@"Seems like the internet is down, there is no connection."];
                [self showAlert:no_internet_alert_title :no_internet_alert_body];
                break;
            }
            case ReachableViaWiFi:
            {
                [self trace:@"WIFI internet connection detected."];
                break;
            }
            case ReachableViaWWAN:
            {
                [self trace:@"WAN internet connection detected."];
                break;
            }
        }
    }
}


#pragma mark - Alert Methods

-(void)showAlert:(NSString *)alertTitle :(NSString *)alertMessage
{
    [self trace:@"showAlert"];
    
    NSString *web_view_url = [config objectForKey:@"web_view_url"];
    
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:alertTitle
        message:alertMessage
        preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *retryAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"RETRY", @"RETRY action")
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action)
        {
            [self trace:@"UIAlertAction retryAction"];
            
            // load web_view_url
            NSURL *url = [[NSURL alloc] initWithString:web_view_url];
            NSURLRequest *nsrequest = [NSURLRequest requestWithURL:url];
            [webView loadRequest:nsrequest];
            
            [self startNetListener];
        }];
    
    [alertController addAction:retryAction];
   
    [self presentViewController:alertController animated:YES completion:nil];
}


#pragma mark - WKWebview Delegate Methods

// This method is where decide if we are going to allow certain links from your website go
// through webview. In certain scenerios, some links will not load via webview
// In those cases, we can capture the link before its loaded in the webview and
// decide what to do with it.
-(void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(nonnull WKNavigationAction *)navigationAction decisionHandler:(nonnull void (^)(WKNavigationActionPolicy))decisionHandler
{
    #define contains(str1, str2) ([str1 rangeOfString: str2].location != NSNotFound)
    
    WKNavigationAction *nav =navigationAction;
    NSString *requestUrl = nav.request.URL.absoluteString;
    
    [self trace:@"decidePolicyForNavigationAction"];
    NSLog(@"MAWV: request.URL: %@", nav.request.URL);
    
    // initialize url request properties
    NSURL *nsurl = [[NSURL alloc] initWithString:@""];
    NSURLRequest *nsrequest = [NSURLRequest requestWithURL:nsurl];
    
    // adding support for mail chimp posts
    // for what ever reason it does not work correctly with webviews
    // we handle the url here and invoke the post url manually
    
    if ( contains(requestUrl, [config objectForKey:@"mail_chimp_url"]) )
    {
        if (!hasMailChimpLoaded)
        {
            hasMailChimpLoaded = true;
            
            // request
            nsurl = [[NSURL alloc] initWithString:[config objectForKey:@"mail_chimp_post_url"]];
            nsrequest = [NSURLRequest requestWithURL:nsurl];
            [webView loadRequest:nsrequest];
            
            decisionHandler(WKNavigationActionPolicyCancel);
        }
        else decisionHandler(WKNavigationActionPolicyAllow);
    }
    else
    {
        // here we can handle specific urls that you don't want loaded in the webview
        // instead we want it to open in the browser
        BOOL isDisallowUrlDetected = false;
        NSArray *disallow_url_list = [config objectForKey:@"disallow_url_list"];
        
        for (NSString* urlIndex in disallow_url_list)
        {
            if ( contains(requestUrl, urlIndex) )
            {
                NSLog(@"MAWV: DISALLOWED URLINDEX DETECTED: %@", urlIndex);
                
                isDisallowUrlDetected = true;
                
                [[UIApplication sharedApplication] openURL:nav.request.URL options:@{} completionHandler:nil];
                decisionHandler(WKNavigationActionPolicyCancel);
            }
        }
        
        // process request url normally via webview
        if ( !isDisallowUrlDetected )
        {
            hasMailChimpLoaded = false;
            decisionHandler(WKNavigationActionPolicyAllow);
        }
    }
}

-(void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
    [self trace:@"didCommitNavigation"];
}

-(void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    [self trace:@"didStartProvisionalNavigation"];
    
    if (isAppInitialized)
    {
        if (isShowProgressIndicator) [activityIndicator startAnimating];
    }
}

-(void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [self trace:@"didFinishNavigation"];
    
    if (isShowProgressIndicator) [activityIndicator stopAnimating];
    
    if (!isAppInitialized)
    {
        isAppInitialized = true;
        if (isShowLaunchImage) [self fadeOutLaunchImage:launchImageView];
    }
}

-(void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self trace:@"didFailNavigation"];
    
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Error!"
                                          message:@"Cannot load request."
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", @"OK action")
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action)
                               {
                                   // call a method when the OK button is pressed
                               }];
    
    [alertController addAction:okAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}


#pragma mark - Launch ImageView Methods

// method: fades out an UIImageView
-(void)fadeOutLaunchImage:(UIImageView *)launchImageView
{
    [self trace:@"fadeOutLaunchImage"];
    
    if (launchImageView == nil) return;
    
    // add on animation completed
    [CATransaction setCompletionBlock:^
     {
         [self trace:@"AnimationFadeOut.setCompletionBlock"];
         [self removeLaunchImageView:launchImageView];
     }];
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:1.0];
    // Set alpha
    launchImageView.alpha = 0; // Alpha runs from 0.0 to 1.0
    [UIView commitAnimations];
    
}

// method: removes UIImageView from main view
- (void)removeLaunchImageView:(UIImageView*)imageView
{
    [self trace:@"removeLaunchImageView"];
    
    imageView.hidden = true;
    [imageView removeFromSuperview];
    imageView = nil;
}

// returns the correct LaunchImage based on device launch
- (UIImage *)getLaunchImage
{
    UIImage *img;
    
    // Look for the correct LaunchImage based on the device size
    NSArray *allPngImageNames = [[NSBundle mainBundle] pathsForResourcesOfType:@"png" inDirectory:nil];
    for (NSString *imgName in allPngImageNames)
    {
        // Find launch images
        if ([imgName containsString:@"LaunchImage"])
        {
            img = [UIImage imageNamed:imgName]; // -- this is a launch image
            
            // Has image same scale and dimensions as our current device's screen?
            if (img.scale == [UIScreen mainScreen].scale && CGSizeEqualToSize(img.size, [UIScreen mainScreen].bounds.size))
            {
                // NSLog(@"Found launch image for current device %@", img.description);
                break;
            }
        }
    }
    
    return img;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Device Orientation Change

-(void) removeOrientationChangeListener
{
    [self trace:@"removeOrientationChangeListener"];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"UIDeviceOrientationDidChangeNotification" object:nil];
}

-(void) addOrientationChangeListener
{
    [self trace:@"addOrientationChangeListener"];
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(orientationChanged:)
     name:UIDeviceOrientationDidChangeNotification
     object:[UIDevice currentDevice]];
}

-(void) orientationChanged:(NSNotification *)note
{
    [self trace:@"orientationChanged"];
    
    UIDevice * device = note.object;
    NSLog(@"MAWV: orientation: '%ld'", device.orientation);
    switch (device.orientation)
    {
        case UIDeviceOrientationPortrait:
        case UIDeviceOrientationPortraitUpsideDown:
            webView.frame = CGRectMake(0, statusBarHeight, self.view.frame.size.width, self.view.frame.size.height - statusBarHeight);
            break;
            
        case UIDeviceOrientationLandscapeLeft:
        case UIDeviceOrientationLandscapeRight:
            webView.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
            break;
            
        default:
            break;
            
    }
}


#pragma mark - Application Termination

-(void) addWillTerminateNotification
{
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(applicationWillTerminate:)
     name:UIApplicationWillTerminateNotification
     object:[UIApplication sharedApplication]];
}

-(void) removeWillTerminateNotification
{
    // remove applicationWillTerminate notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"UIApplicationWillTerminateNotification" object:nil];
}

-(void) applicationWillTerminate:(NSNotification *)note
{
    [self trace:@"ViewController.applicationWillTerminate"];
    
    [self removeWillTerminateNotification];
    [self removeOrientationChangeListener];
}


#pragma mark - Tools

-(void)trace:(NSString *)msg, ...
{
    if (isLogger == NO) return;
    
    NSLog( @"MAWV: '%@'", msg );
}

NSObject* getDictionaryValueByKey(NSDictionary *dict, NSString *searchKey)
{
    NSLog(@"getDictionaryValueByKey.searchKey: '%@'", searchKey);
    
    if ( [searchKey isKindOfClass:[NSString class]] )
    {
        
    }
    
    __block NSObject* searchedValue;
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        
        // NSLog(@"MAWV: %@ => %@", key, value);
        
        if ([searchKey isEqualToString:key])
        {
            searchedValue = value;
            *stop = YES;
        }
    }];
    
    return searchedValue;
}

// convert hex string to UIColor
- (UIColor *)uiColorFromHexString:(NSString *)hexString
{
    unsigned rgbValue = 0;
    
    // convert hex string to unsigned value
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    if ( [hexString rangeOfString:@"#"].location == 0 ) [scanner setScanLocation:1];
    [scanner scanHexInt:&rgbValue];
    
    // convert unsigned hex to rgb values
    float redColor = ((rgbValue & 0xFF0000) >> 16) / 255.0;
    float greenColor = ((rgbValue & 0xFF00) >> 8) / 255.0;
    float blueColor = (rgbValue & 0xFF) / 255.0;
    
    return [UIColor colorWithRed:redColor green:greenColor blue:blueColor alpha:1.0];
}

-(void) checkForVersion
{
    // check iOS version 11.3+ for WKWebsiteDataTypeFetchCache
    NSString *verStr = [[UIDevice currentDevice] systemVersion];
    float ver = [verStr floatValue];
    // NSLog(@"iOS Version: '%@'", verStr);
    
    if (ver >= 11.3)
    {
        NSLog(@"iOS Version 11.3 Detected '%@'", verStr);
    }
    
    NSOperatingSystemVersion ios11_3_0 = (NSOperatingSystemVersion){11, 3, 0};
    
    if ([NSProcessInfo instanceMethodForSelector:@selector(isOperatingSystemAtLeastVersion:)])
    {
        // check any version >= iOS 8
        if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios11_3_0])
        {
            // iOS 11.3.0 and above
        }
        else
        {
            // iOS 11.2.9 and below
        }
    }
    else
    {
        // we are on iOS 7 or below
    }
}

@end
