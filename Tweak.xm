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

#pragma mark - ===== 初始化 =====

%ctor {
    _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);
    LogSync(@"==============================");
    LogSync(@"===== xhbb.dylib 已加载 =====");
    LogSync(@"==============================");
}

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
    LogSync(@"========== 开始打开公众号资料页 ==========");
    @try {
        // 1. 获取 CContactMgr
        id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(
            objc_getClass("MMServiceCenter"), NSSelectorFromString(@"defaultCenter"));
        if (!serviceCenter) { LogSync(@"❌ MMServiceCenter nil"); return; }

        id contactMgr = ((id (*)(id, SEL, Class))objc_msgSend)(
            serviceCenter, NSSelectorFromString(@"getService:"), objc_getClass("CContactMgr"));
        if (!contactMgr) { LogSync(@"❌ CContactMgr nil"); return; }

        // 2. 获取联系人对象（参考锤子助手 addGzh 方法）
        id contact = nil;
        SEL getContactSel = NSSelectorFromString(@"getContactByName:");
        if ([contactMgr respondsToSelector:getContactSel]) {
            contact = ((id (*)(id, SEL, id))objc_msgSend)(contactMgr, getContactSel, GH_ID);
            Log(@"getContactByName: %@", contact ? @"有结果" : @"nil");
        }
        if (!contact) {
            SEL searchSel = NSSelectorFromString(@"getContactForSearchByName:");
            if ([contactMgr respondsToSelector:searchSel]) {
                contact = ((id (*)(id, SEL, id))objc_msgSend)(contactMgr, searchSel, GH_ID);
                Log(@"getContactForSearchByName: %@", contact ? @"有结果" : @"nil");
            }
        }
        if (!contact) {
            SEL byUserSel = NSSelectorFromString(@"getContactByUserName:");
            if ([contactMgr respondsToSelector:byUserSel]) {
                contact = ((id (*)(id, SEL, id))objc_msgSend)(contactMgr, byUserSel, GH_ID);
                Log(@"getContactByUserName: %@", contact ? @"有结果" : @"nil");
            }
        }
        if (!contact) { LogSync(@"❌ 无法获取公众号联系人，可能未预加载"); return; }
        LogSync(@"✅ 联系人: %@", SafeGet(contact, @"m_nsUsrName"));

        // 3. 创建 ContactInfoViewController（参考锤子助手 + MioPlugin 实现）
        Class contactInfoVCClass = objc_getClass("ContactInfoViewController");
        if (!contactInfoVCClass) { LogSync(@"❌ ContactInfoViewController 类不存在"); return; }

        id contactInfoVC = [[contactInfoVCClass alloc] init];
        if (!contactInfoVC) { LogSync(@"❌ 创建 ContactInfoViewController 失败"); return; }

        // 4. 设置联系人对象
        SEL setContactSel = NSSelectorFromString(@"setM_contact:");
        if ([contactInfoVC respondsToSelector:setContactSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(contactInfoVC, setContactSel, contact);
            LogSync(@"✅ setM_contact: 成功");
        } else {
            LogSync(@"❌ ContactInfoViewController 不响应 setM_contact:");
            return;
        }

        // 5. Push 到导航控制器（必须在主线程）
        dispatch_async(dispatch_get_main_queue(), ^{
            id nav = ((id (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"navigationController"));
            if (nav && [nav respondsToSelector:NSSelectorFromString(@"pushViewController:animated:")]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                    nav, NSSelectorFromString(@"pushViewController:animated:"), contactInfoVC, YES);
                LogSync(@"✅ 已打开公众号资料页，请手动点击关注按钮");
            } else {
                // 备用方案：从 keyWindow 获取导航控制器
                UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                UIViewController *topVC = rootVC;
                while (topVC.presentedViewController) {
                    topVC = topVC.presentedViewController;
                }
                if ([topVC isKindOfClass:[UINavigationController class]]) {
                    [(UINavigationController *)topVC pushViewController:contactInfoVC animated:YES];
                    LogSync(@"✅ 已打开公众号资料页(备用方案)");
                } else if (topVC.navigationController) {
                    [topVC.navigationController pushViewController:contactInfoVC animated:YES];
                    LogSync(@"✅ 已打开公众号资料页(备用方案2)");
                } else {
                    LogSync(@"❌ 无法获取导航控制器");
                }
            }
        });

    } @catch (NSException *e) {
        LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
    }
    LogSync(@"========== 打开资料页流程结束 ==========");
}

%end

#pragma clang diagnostic pop
