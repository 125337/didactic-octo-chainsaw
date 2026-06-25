#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"


#pragma mark - ===== 日志工具 =====

NSString *LogFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"xhbb_follow.log"];
}

void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], message];
    
    NSString *logPath = LogFilePath();
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [logLine writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}


#pragma mark - ===== 初始化 =====

__attribute__((constructor)) static void xhbb_init() {
    NSString *home = NSHomeDirectory();
    NSString *docPath = LogFilePath();
    NSString *info = [NSString stringWithFormat:
        @"[INIT] xhbb.dylib loaded\n"
        @"[INIT] Home: %@\n"
        @"[INIT] Log: %@\n", home, docPath];
    [info writeToFile:docPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Log(@"[INIT] 初始化完成");
}


#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    Log(@"viewDidAppear 被调用 ✅");
    
    // 检查是否已关注
    BOOL followed = NO;
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (contactMgr && [contactMgr respondsToSelector:@selector(isInContactList:)]) {
            followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                               withObject:@"gh_043507dcdc38"];
        }
    } @catch (NSException *e) {}
    
    if (followed) {
        Log(@"已关注，跳过");
        return;
    }
    
    Log(@"未关注，准备弹窗");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"关注公众号"
            message:@"点击「去关注」将跳转到公众号详情页\n请手动点击关注按钮"
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"去关注"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            Log(@"用户点击了「去关注」");
            
            // 方案1: 打开公众号详情页 URL
            NSString *url = [NSString stringWithFormat:@"weixin://contacts/profile/%@", @"gh_043507dcdc38"];
            NSURL *nsUrl = [NSURL URLWithString:url];
            if ([[UIApplication sharedApplication] canOpenURL:nsUrl]) {
                [[UIApplication sharedApplication] openURL:nsUrl options:@{} completionHandler:^(BOOL success) {
                    Log(@"openURL %@ 结果: %@", url, success ? @"成功" : @"失败");
                }];
            } else {
                Log(@"canOpenURL %@ 返回 NO", url);
                
                // 方案2: 尝试其他 URL Scheme
                NSString *url2 = @"weixin://";
                NSURL *nsUrl2 = [NSURL URLWithString:url2];
                [[UIApplication sharedApplication] openURL:nsUrl2 options:@{} completionHandler:nil];
                Log(@"尝试打开 %@", url2);
            }
            
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *action) {
            Log(@"用户点击了「取消」");
        }]];
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

%end

#pragma clang diagnostic pop