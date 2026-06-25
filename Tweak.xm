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

// ===== Hook viewDidAppear: 进入页面时触发 =====
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
        [self performSelector:@selector(showFollowDialog)];
    });
}

// ===== 弹窗 =====
%new
- (void)showFollowDialog {
    Log(@"弹出关注对话框");
    
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"关注公众号"
        message:@"关注后获取最新功能和更新通知"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"关注"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        Log(@"用户点击了「关注」");
        [self performSelector:@selector(followOfficialAccount)];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        Log(@"用户点击了「取消」");
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
    }]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// ===== 真实关注核心逻辑（参照锤子助手方案） =====
%new
- (void)followOfficialAccount {
    Log(@"========== 开始执行关注 ==========");
    
    @try {
        // 第1步: 获取 MMServiceCenter
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) {
            Log(@"[关注失败] MMServiceCenter 获取失败");
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
            return;
        }
        Log(@"[OK] MMServiceCenter 获取成功");
        
        // 第2步: 获取 CContactMgr
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) {
            Log(@"[关注失败] CContactMgr 获取失败");
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
            return;
        }
        Log(@"[OK] CContactMgr 获取成功");
        
        // 第3步: 获取公众号联系人对象
        id contact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                       withObject:@"gh_043507dcdc38"];
            Log(@"[OK] getContactForSearchByName: 返回 %@", contact ? @"有值" : @"nil");
        } else {
            Log(@"[WARN] getContactForSearchByName: 不可用，尝试 getContactByName:");
            if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactByName:)
                                           withObject:@"gh_043507dcdc38"];
                Log(@"[OK] getContactByName: 返回 %@", contact ? @"有值" : @"nil");
            }
        }
        
        if (!contact) {
            Log(@"[关注失败] 无法获取联系人对象");
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
            return;
        }
        
        // 第4步: 真实关注 — addLocalContact:listType:2
        Log(@"[执行] addLocalContact:listType:2");
        SEL sel = @selector(addLocalContact:listType:);
        NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:contactMgr];
        [inv setSelector:sel];
        [inv setArgument:&contact atIndex:2];
        NSInteger listType = 2;
        [inv setArgument:&listType atIndex:3];
        [inv invoke];
        Log(@"[OK] addLocalContact:listType:2 调用完成");
        
        // 第5步: 验证关注结果
        [NSThread sleepForTimeInterval:0.5];
        BOOL followed = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                             withObject:@"gh_043507dcdc38"];
        }
        
        if (followed) {
            Log(@"✅ 关注成功！addLocalContact:listType:2 有效");
        } else {
            Log(@"❌ 关注失败，isInContactList 仍返回 NO");
            
            // 备选方案: addBrandContact:
            Log(@"[备选] 尝试 addBrandContact:");
            if ([contactMgr respondsToSelector:@selector(addBrandContact:)]) {
                [contactMgr performSelector:@selector(addBrandContact:)
                                 withObject:@"gh_043507dcdc38"];
                Log(@"[OK] addBrandContact: 调用完成");
                
                [NSThread sleepForTimeInterval:0.5];
                if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
                    followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                     withObject:@"gh_043507dcdc38"];
                    if (followed) {
                        Log(@"✅ 备选方案 addBrandContact: 有效");
                    } else {
                        Log(@"❌ 备选方案也失败");
                    }
                }
            } else {
                Log(@"[备选] addBrandContact: 不可用");
            }
        }
        
    } @catch (NSException *e) {
        Log(@"❌ 关注异常: %@: %@", e.name, e.reason);
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
    Log(@"========== 关注流程结束 ==========");
}

%end

#pragma clang diagnostic pop