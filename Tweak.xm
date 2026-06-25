#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *GH_ID = @"gh_043507dcdc38";
static NSString *_logPath;
static dispatch_queue_t _logQueue;

static NSString *GetLogPath(void) {
    if (!_logPath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _logPath = [[paths firstObject] stringByAppendingPathComponent:@"xhbb_follow.log"];
    }
    return _logPath;
}

void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    if (!_logQueue) {
        _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);
    }
    dispatch_async(_logQueue, ^{
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GetLogPath()];
        if (!fh) {
            [logLine writeToFile:GetLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    });
}

// 同步写日志（用于 crash 前的关键信息）
void LogSync(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

void LogSync(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GetLogPath()];
    if (!fh) {
        [logLine writeToFile:GetLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}


#pragma mark - ===== 初始化 =====

%ctor {
    _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);

    LogSync(@"==============================");
    LogSync(@"===== xhbb.dylib 已加载 =====");
    LogSync(@"日志: %@", GetLogPath());
    LogSync(@"==============================");

    Class cls = NSClassFromString(@"WCPluginsViewController");
    Log(@"[INIT] WCPluginsViewController: %@", cls ? @"✅ FOUND" : @"❌ NOT FOUND");
}


#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    Log(@"viewDidAppear 被调用 ✅");

    // 每次进入页面都弹窗（测试阶段）
    BOOL followed = (BOOL)[self performSelector:@selector(isFollowed)];
    if (followed) {
        Log(@"已关注，跳过弹窗");
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

    UIAlertAction *followAction = [UIAlertAction
        actionWithTitle:@"关注"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            Log(@"用户点击了「关注」");
            [self performSelector:@selector(followOfficialAccount)];
        }];

    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:@"取消"
        style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *action) {
            Log(@"用户点击了「取消」");
        }];

    [alert addAction:followAction];
    [alert addAction:cancelAction];

    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// ===== 检查是否已关注 =====
%new
- (BOOL)isFollowed {
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) {
            Log(@"[isFollowed] MMServiceCenter 获取失败");
            return NO;
        }

        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) {
            Log(@"[isFollowed] CContactMgr 获取失败");
            return NO;
        }

        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL inList = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                 withObject:GH_ID];
            Log(@"[isFollowed] isInContactList = %@", inList ? @"YES" : @"NO");
            return inList;
        }
        return NO;
    } @catch (NSException *e) {
        Log(@"[isFollowed] 异常: %@", e.reason);
        return NO;
    }
}

// ===== 核心关注逻辑 =====
%new
- (void)followOfficialAccount {
    LogSync(@"========== 开始执行关注 ==========");

    @try {
        // ---- Step 1: 获取 MMServiceCenter ----
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) {
            LogSync(@"[Step1] ❌ MMServiceCenter 获取失败");
            return;
        }
        LogSync(@"[Step1] ✅ MMServiceCenter = %@", serviceCenter);

        // ---- Step 2: 获取 CContactMgr ----
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) {
            LogSync(@"[Step2] ❌ CContactMgr 获取失败");
            return;
        }
        LogSync(@"[Step2] ✅ CContactMgr = %@", [contactMgr class]);

        // ---- Step 3: 先尝试本地获取联系人 ----
        id contact = nil;

        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                       withObject:GH_ID];
            LogSync(@"[Step3] getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }

        if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:)
                                       withObject:GH_ID];
            LogSync(@"[Step3] getContactByName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }

        // ---- Step 4: 本地没有，从服务器拉取 ----
        if (!contact) {
            LogSync(@"[Step4] 本地无联系人，尝试从服务器拉取...");

            // 4a: 用 getContactsFromServer 拉取
            if ([contactMgr respondsToSelector:@selector(getContactsFromServer:)]) {
                LogSync(@"[Step4a] 调用 getContactsFromServer:%@", GH_ID);
                [contactMgr performSelector:@selector(getContactsFromServer:)
                                  withObject:GH_ID];

                // 等待网络请求
                LogSync(@"[Step4a] 等待 3 秒让服务器响应...");
                [NSThread sleepForTimeInterval:3.0];
            }

            // 4b: 再次尝试本地获取
            if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                           withObject:GH_ID];
                LogSync(@"[Step4b] 重试 getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
            }

            if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactByName:)
                                           withObject:GH_ID];
                LogSync(@"[Step4b] 重试 getContactByName → %@", contact ? @"✅ 有值" : @"❌ nil");
            }
        }

        // ---- Step 5: 还是没有，尝试 generateOfficialContact ----
        if (!contact) {
            LogSync(@"[Step5] 服务器拉取后仍为 nil，尝试 generateOfficialContact...");

            if ([contactMgr respondsToSelector:@selector(generateOfficialContact)]) {
                contact = [contactMgr performSelector:@selector(generateOfficialContact)];
                LogSync(@"[Step5] generateOfficialContact → %@", contact ? @"✅ 有值" : @"❌ nil");

                // 如果生成了对象，设置 m_nsUsrName
                if (contact && [contact respondsToSelector:@selector(setM_nsUsrName:)]) {
                    [contact performSelector:@selector(setM_nsUsrName:) withObject:GH_ID];
                    LogSync(@"[Step5] 已设置 m_nsUsrName = %@", GH_ID);
                }
            }
        }

        // ---- Step 6: 如果有联系人对象，用 addLocalContact:listType:2 关注 ----
        if (contact) {
            LogSync(@"[Step6] 联系人对象 class: %@", [contact class]);
            if ([contact respondsToSelector:@selector(m_nsUsrName)]) {
                LogSync(@"[Step6] m_nsUsrName: %@", [contact performSelector:@selector(m_nsUsrName)]);
            }

            SEL sel = @selector(addLocalContact:listType:);
            if ([contactMgr respondsToSelector:sel]) {
                LogSync(@"[Step6] ✅ addLocalContact:listType: 可用，调用 listType=2");
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&contact atIndex:2];
                NSInteger listType = 2;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];

                LogSync(@"[Step6] addLocalContact:listType:2 调用完成");
            } else {
                LogSync(@"[Step6] ❌ addLocalContact:listType: 不可用");
            }
        } else {
            // ---- Step 7: 没有联系人对象，回退到 addBrandContact: ----
            LogSync(@"[Step7] 无联系人对象，尝试 addBrandContact:");
            if ([contactMgr respondsToSelector:@selector(addBrandContact:)]) {
                [contactMgr performSelector:@selector(addBrandContact:)
                                 withObject:GH_ID];
                LogSync(@"[Step7] addBrandContact: 调用完成");
            } else {
                LogSync(@"[Step7] ❌ addBrandContact: 不可用");
            }
        }

        // ---- Step 8: 验证关注结果 ----
        LogSync(@"[Step8] 等待 1 秒后验证...");
        [NSThread sleepForTimeInterval:1.0];

        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                   withObject:GH_ID];
            if (followed) {
                LogSync(@"[Step8] ✅✅✅ 关注成功！isInContactList = YES ✅✅✅");
            } else {
                LogSync(@"[Step8] ❌ 关注失败，isInContactList = NO");
            }
        }

    } @catch (NSException *e) {
        LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
    }

    LogSync(@"========== 关注流程结束 ==========");
}

%end

#pragma clang diagnostic pop