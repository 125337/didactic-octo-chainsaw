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

static void LogAllButtons(UIView *view, NSString *indent) {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal];
        if (title.length > 0) {
            LogSync(@"%@UIButton: '%@'", indent, title);
        }
    }
    for (UIView *sub in view.subviews) {
        LogAllButtons(sub, [indent stringByAppendingString:@"  "]);
    }
}

// 自动关注：在 viewDidAppear 中搜索并点击关注按钮
static void AutoFollowInVC(id vc) {
    if (!_autoFollowPending) return;
    _autoFollowPending = NO;
    LogSync(@"[AutoFollow] viewDidAppear, 搜索关注按钮...");

    UIView *view = [vc performSelector:@selector(view)];
    if (!view) { LogSync(@"[AutoFollow] ❌ view nil"); return; }

    UIButton *followBtn = FindButton(view, @"关注");
    if (!followBtn) followBtn = FindButton(view, @"Follow");

    if (followBtn) {
        LogSync(@"[AutoFollow] ✅ 找到关注按钮: '%@'", [followBtn titleForState:UIControlStateNormal]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [followBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
            LogSync(@"[AutoFollow] ✅ 已自动点击关注按钮");

            // 2秒后返回
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                id nav = [vc performSelector:@selector(navigationController)];
                if (nav) {
                    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(nav, @selector(popViewControllerAnimated:), vc, YES);
                    LogSync(@"[AutoFollow] 已 pop 返回");
                } else {
                    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(vc, @selector(dismissViewControllerAnimated:completion:), YES, nil);
                    LogSync(@"[AutoFollow] 已 dismiss 返回");
                }
            });
        });
    } else {
        LogSync(@"[AutoFollow] ❌ 未找到关注按钮，枚举所有按钮:");
        LogAllButtons(view, @"");
        // 5秒后返回
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            id nav = [vc performSelector:@selector(navigationController)];
            if (nav) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(nav, @selector(popViewControllerAnimated:), vc, YES);
            } else {
                ((void (*)(id, SEL, BOOL, id))objc_msgSend)(vc, @selector(dismissViewControllerAnimated:completion:), YES, nil);
            }
        });
    }
}

#pragma mark - ===== 初始化 =====

%ctor {
    _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);
    LogSync(@"==============================");
    LogSync(@"===== xhbb.dylib 已加载 =====");
    LogSync(@"==============================");
}

#pragma mark - ===== ContactInfoViewController Hook =====

%hook ContactInfoViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    AutoFollowInVC(self);
}

%end

#pragma mark - ===== WCContactInfoViewController Hook =====

%hook WCContactInfoViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    AutoFollowInVC(self);
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
            id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(
                objc_getClass("MMServiceCenter"), NSSelectorFromString(@"defaultCenter"));
            if (!serviceCenter) { LogSync(@"❌ MMServiceCenter nil"); return; }

            id contactMgr = ((id (*)(id, SEL, Class))objc_msgSend)(
                serviceCenter, NSSelectorFromString(@"getService:"), objc_getClass("CContactMgr"));
            if (!contactMgr) { LogSync(@"❌ CContactMgr nil"); return; }

            id contact = nil;
            SEL getByUserName = NSSelectorFromString(@"getContactByUserName:");
            if ([contactMgr respondsToSelector:getByUserName]) {
                contact = [contactMgr performSelector:getByUserName withObject:GH_ID];
                LogSync(@"getContactByUserName → %@", contact ? @"✅ 有值" : @"nil");
            }
            if (!contact && [contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
                LogSync(@"getContactForSearchByName → %@", contact ? @"✅ 有值" : @"nil");
            }
            if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactByName:) withObject:GH_ID];
                LogSync(@"getContactByName → %@", contact ? @"✅ 有值" : @"nil");
            }
            if (!contact) { LogSync(@"❌ 联系人 nil"); return; }
            LogSync(@"✅ 联系人: %@", SafeGet(contact, @"m_nsUsrName"));

            // 打开公众号资料页
            Class profileClass = NSClassFromString(@"ContactInfoViewController");
            LogSync(@"ContactInfoViewController: %@", profileClass ? @"✅ 存在" : @"❌ 不存在");

            if (!profileClass) {
                profileClass = NSClassFromString(@"WCContactInfoViewController");
                LogSync(@"WCContactInfoViewController: %@", profileClass ? @"✅ 存在" : @"❌ 不存在");
            }

            if (profileClass) {
                id profileVC = [[profileClass alloc] init];

                SEL setContactSel = NSSelectorFromString(@"setM_contact:");
                if ([(id)profileVC respondsToSelector:setContactSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)((id)profileVC, setContactSel, contact);
                    LogSync(@"✅ setM_contact: 成功");
                } else {
                    LogSync(@"❌ setM_contact: 不可用，枚举 setter:");
                    unsigned int mc = 0;
                    Method *ms = class_copyMethodList([profileVC class], &mc);
                    int cnt = 0;
                    for (unsigned int i = 0; i < mc; i++) {
                        const char *name = sel_getName(method_getName(ms[i]));
                        NSString *ns = [NSString stringWithUTF8String:name];
                        if ([ns hasPrefix:@"set"] && [ns containsString:@"ontact"]) {
                            LogSync(@"  → %s", name);
                            cnt++;
                            if (cnt > 20) break;
                        }
                    }
                    free(ms);
                }

                _autoFollowPending = YES;
                LogSync(@"✅ _autoFollowPending = YES");

                // 找导航控制器
                UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                UIViewController *topVC = rootVC;
                while (topVC.presentedViewController) topVC = topVC.presentedViewController;

                UINavigationController *nav = nil;
                if ([topVC isKindOfClass:[UINavigationController class]]) {
                    nav = (UINavigationController *)topVC;
                } else if (topVC.navigationController) {
                    nav = topVC.navigationController;
                }

                if (nav) {
                    [nav pushViewController:(UIViewController *)profileVC animated:YES];
                    LogSync(@"✅ pushViewController");
                } else {
                    [topVC presentViewController:(UIViewController *)profileVC animated:YES completion:nil];
                    LogSync(@"✅ presentViewController");
                }
            } else {
                // URL scheme 回退
                LogSync(@"❌ Profile VC 不存在，尝试 URL scheme");
                NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"weixin://contacts/profile/%@", GH_ID]];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                    LogSync(@"openURL → %@", success ? @"YES" : @"NO");
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
