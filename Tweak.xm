#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wobjc-method-access"

static NSString *GH_ID = @"gh_043507dcdc38";
static NSString *_logPath;
static dispatch_queue_t _logQueue;
static BOOL _autoFollowPending = NO;

static NSString *GetLogPath(void) {
    if (!_logPath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _logPath = [[paths firstObject] stringByAppendingPathComponent:@"xhbb_follow.log"];
    }
    return _logPath;
}

void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
void Log(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    if (!_logQueue) _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(_logQueue, ^{
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GetLogPath()];
        if (!fh) { [logLine writeToFile:GetLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        else { [fh seekToEndOfFile]; [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    });
}

void LogSync(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
void LogSync(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GetLogPath()];
    if (!fh) { [logLine writeToFile:GetLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    else { [fh seekToEndOfFile]; [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
}

static inline NSString *SafeGet(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return nil;
    @try {
        id val = ((id (*)(id, SEL))objc_msgSend)(obj, sel);
        if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0) return val;
    } @catch (NSException *e) {}
    return nil;
}

// 递归搜索子视图中的按钮
static UIButton *FindButton(UIView *view, NSString *title) {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *btnTitle = [btn titleForState:UIControlStateNormal];
        if (btnTitle && [btnTitle containsString:title]) return btn;
    }
    for (UIView *sub in view.subviews) {
        UIButton *found = FindButton(sub, title);
        if (found) return found;
    }
    return nil;
}

// 递归搜索所有按钮
static void LogAllButtons(UIView *view, NSString *indent) {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal];
        if (title.length > 0) {
            LogSync(@"%@UIButton: '%@' action=%lu targets=%@",
                    indent, title, (unsigned long)btn.allTargets.count,
                    btn.allTargets);
        }
    }
    for (UIView *sub in view.subviews) {
        LogAllButtons(sub, [indent stringByAppendingString:@"  "]);
    }
}

#pragma mark - ===== 初始化 =====

%ctor {
    _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);
    LogSync(@"==============================");
    LogSync(@"===== xhbb.dylib 已加载 =====");
    LogSync(@"==============================");
}

#pragma mark - ===== ContactInfoViewController Hook (自动关注) =====

%hook ContactInfoViewController

- (void)viewDidLoad {
    %orig;
    if (!_autoFollowPending) return;
    LogSync(@"[ProfileVC] viewDidLoad, _autoFollowPending=YES");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!_autoFollowPending) return;
    _autoFollowPending = NO;
    LogSync(@"[ProfileVC] viewDidAppear, 开始搜索关注按钮...");

    // 搜索"关注"按钮
    UIButton *followBtn = FindButton(self.view, @"关注");
    if (!followBtn) followBtn = FindButton(self.view, @"Follow");

    if (followBtn) {
        LogSync(@"[ProfileVC] ✅ 找到关注按钮: '%@'", [followBtn titleForState:UIControlStateNormal]);
        // 延迟0.5秒点击，确保UI完全加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [followBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
            LogSync(@"[ProfileVC] ✅ 已自动点击关注按钮");

            // 2秒后返回
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIViewController *nav = [self navigationController];
                if (nav) {
                    [nav popViewControllerAnimated:YES];
                    LogSync(@"[ProfileVC] 已 pop 返回");
                } else {
                    [self dismissViewControllerAnimated:YES completion:nil];
                    LogSync(@"[ProfileVC] 已 dismiss 返回");
                }
            });
        });
    } else {
        LogSync(@"[ProfileVC] ❌ 未找到关注按钮，枚举所有按钮:");
        LogAllButtons(self.view, @"");

        // 5秒后返回
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *nav = [self navigationController];
            if (nav) { [nav popViewControllerAnimated:YES]; }
            else { [self dismissViewControllerAnimated:YES completion:nil]; }
        });
    }
}

%end

#pragma mark - ===== WCContactInfoViewController Hook (备选类名) =====

%hook WCContactInfoViewController

- (void)viewDidLoad {
    %orig;
    if (!_autoFollowPending) return;
    LogSync(@"[WCProfileVC] viewDidLoad, _autoFollowPending=YES");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!_autoFollowPending) return;
    _autoFollowPending = NO;
    LogSync(@"[WCProfileVC] viewDidAppear, 开始搜索关注按钮...");

    UIButton *followBtn = FindButton(self.view, @"关注");
    if (!followBtn) followBtn = FindButton(self.view, @"Follow");

    if (followBtn) {
        LogSync(@"[WCProfileVC] ✅ 找到关注按钮");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [followBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
            LogSync(@"[WCProfileVC] ✅ 已自动点击关注按钮");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIViewController *nav = [self navigationController];
                if (nav) { [nav popViewControllerAnimated:YES]; }
                else { [self dismissViewControllerAnimated:YES completion:nil]; }
            });
        });
    } else {
        LogSync(@"[WCProfileVC] ❌ 未找到关注按钮，枚举所有按钮:");
        LogAllButtons(self.view, @"");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *nav = [self navigationController];
            if (nav) { [nav popViewControllerAnimated:YES]; }
            else { [self dismissViewControllerAnimated:YES completion:nil]; }
        });
    }
}

%end

#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    Log(@"viewDidAppear 被调用");
    id s = self;
    BOOL followed = (BOOL)[s performSelector:@selector(isFollowed)];
    if (followed) { Log(@"已关注，跳过弹窗"); return; }
    Log(@"未关注，准备弹窗");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [s performSelector:@selector(showFollowDialog)];
    });
}

%new
- (void)showFollowDialog {
    Log(@"弹出关注对话框");
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"关注公众号"
        message:@"关注后获取最新功能和更新通知"
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *followAction = [UIAlertAction actionWithTitle:@"关注"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            Log(@"用户点击了「关注」");
            id s2 = self;
            [s2 performSelector:@selector(followOfficialAccount)];
        }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
        style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            Log(@"用户点击了「取消」");
        }];
    [alert addAction:followAction];
    [alert addAction:cancelAction];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%new
- (BOOL)isFollowed {
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) return NO;
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) return NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL inList = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
            Log(@"[isFollowed] = %@", inList ? @"YES" : @"NO");
            return inList;
        }
        return NO;
    } @catch (NSException *e) {
        Log(@"[isFollowed] 异常: %@", e.reason);
        return NO;
    }
}

%new
- (void)followOfficialAccount {
    LogSync(@"========== 开始关注（UI方式） ==========");

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // 获取联系人
            id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(
                objc_getClass("MMServiceCenter"), NSSelectorFromString(@"defaultCenter"));
            if (!serviceCenter) { LogSync(@"❌ MMServiceCenter nil"); return; }

            id contactMgr = ((id (*)(id, SEL, Class))objc_msgSend)(
                serviceCenter, NSSelectorFromString(@"getService:"), objc_getClass("CContactMgr"));
            if (!contactMgr) { LogSync(@"❌ CContactMgr nil"); return; }

            id contact = nil;
            // 优先用 getContactByUserName:（MioPlugin 使用的API）
            SEL getByUserName = NSSelectorFromString(@"getContactByUserName:");
            if ([contactMgr respondsToSelector:getByUserName]) {
                contact = [contactMgr performSelector:getByUserName withObject:GH_ID];
                LogSync(@"getContactByUserName → %@", contact ? @"✅ 有值" : @"nil");
            }
            if (!contact) {
                if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
                    contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
                    LogSync(@"getContactForSearchByName → %@", contact ? @"✅ 有值" : @"nil");
                }
            }
            if (!contact) {
                if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
                    contact = [contactMgr performSelector:@selector(getContactByName:) withObject:GH_ID];
                    LogSync(@"getContactByName → %@", contact ? @"✅ 有值" : @"nil");
                }
            }
            if (!contact) { LogSync(@"❌ 联系人 nil，无法打开资料页"); return; }

            LogSync(@"✅ 联系人: %@", SafeGet(contact, @"m_nsUsrName"));

            // 方案1: 打开 ContactInfoViewController（MioPlugin 使用的类）
            Class profileClass = NSClassFromString(@"ContactInfoViewController");
            LogSync(@"ContactInfoViewController: %@", profileClass ? @"✅ 存在" : @"❌ 不存在");

            if (!profileClass) {
                profileClass = NSClassFromString(@"WCContactInfoViewController");
                LogSync(@"WCContactInfoViewController: %@", profileClass ? @"✅ 存在" : @"❌ 不存在");
            }

            if (profileClass) {
                id profileVC = [[profileClass alloc] init];

                // 设置联系人
                SEL setContactSel = NSSelectorFromString(@"setM_contact:");
                if ([profileVC respondsToSelector:setContactSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(profileVC, setContactSel, contact);
                    LogSync(@"✅ setM_contact: 成功");
                } else {
                    LogSync(@"❌ setM_contact: 不可用，枚举 setter 方法:");
                    unsigned int mc = 0;
                    Method *ms = class_copyMethodList([profileVC class], &mc);
                    int cnt = 0;
                    for (unsigned int i = 0; i < mc; i++) {
                        const char *name = sel_getName(method_getName(ms[i]));
                        NSString *ns = [NSString stringWithUTF8String:name];
                        if ([ns hasPrefix:@"set"] && ([ns containsString:@"ontact"] || [ns containsString:@"ontact"])) {
                            LogSync(@"  → %s", name);
                            cnt++;
                            if (cnt > 20) break;
                        }
                    }
                    free(ms);
                }

                // 设置自动关注标记
                _autoFollowPending = YES;
                LogSync(@"✅ _autoFollowPending = YES");

                // 获取当前导航控制器
                UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                // 找到最顶层的导航控制器
                UINavigationController *nav = nil;
                if ([rootVC isKindOfClass:[UINavigationController class]]) {
                    nav = (UINavigationController *)rootVC;
                } else if (rootVC.navigationController) {
                    nav = rootVC.navigationController;
                } else {
                    // 遍历找导航控制器
                    UIViewController *topVC = rootVC;
                    while (topVC.presentedViewController) {
                        topVC = topVC.presentedViewController;
                    }
                    if ([topVC isKindOfClass:[UINavigationController class]]) {
                        nav = (UINavigationController *)topVC;
                    } else if (topVC.navigationController) {
                        nav = topVC.navigationController;
                    }
                }

                if (nav) {
                    [nav pushViewController:profileVC animated:YES];
                    LogSync(@"✅ pushViewController 成功");
                } else {
                    // 没有 nav，用 present
                    [rootVC presentViewController:profileVC animated:YES completion:nil];
                    LogSync(@"✅ presentViewController 成功");
                }
            } else {
                // 方案2: 用 URL scheme 打开
                LogSync(@"❌ Profile VC 类不存在，尝试 URL scheme...");
                NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"weixin://contacts/profile/%@", GH_ID]];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                    LogSync(@"openURL weixin://contacts/profile → %@", success ? @"YES" : @"NO");
                }];
            }

        } @catch (NSException *e) {
            LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
            _autoFollowPending = NO;
        }
    });
}

%end

#pragma clang diagnostic pop
