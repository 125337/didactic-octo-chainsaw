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
    LogSync(@"========== 开始关注 ==========");
    id s = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [s performSelector:@selector(doFollowWork)];
    });
}

%new
- (void)doFollowWork {
    @try {
        // 获取基础对象
        id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(
            objc_getClass("MMServiceCenter"), NSSelectorFromString(@"defaultCenter"));
        if (!serviceCenter) { LogSync(@"❌ MMServiceCenter nil"); return; }

        id contactMgr = ((id (*)(id, SEL, Class))objc_msgSend)(
            serviceCenter, NSSelectorFromString(@"getService:"), objc_getClass("CContactMgr"));
        if (!contactMgr) { LogSync(@"❌ CContactMgr nil"); return; }

        // 获取联系人
        id contact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        }
        if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:) withObject:GH_ID];
        }
        if (!contact) { LogSync(@"❌ 联系人 nil"); return; }
        LogSync(@"✅ 联系人: %@", SafeGet(contact, @"m_nsUsrName"));

        // Step 1: addContactInternal: 添加到联系人列表
        @try {
            SEL sel = NSSelectorFromString(@"addContactInternal:");
            if ([contactMgr respondsToSelector:sel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(contactMgr, sel, contact);
                LogSync(@"[1] addContactInternal ✅");
            }
        } @catch (NSException *e) { LogSync(@"[1] 异常: %@", e.reason); }

        // Step 2: setLocalListTypeWithUserName:listType:addFlag: 设为公众号列表(listType=2)
        @try {
            SEL sel = NSSelectorFromString(@"setLocalListTypeWithUserName:listType:addFlag:");
            if ([contactMgr respondsToSelector:sel]) {
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&GH_ID atIndex:2];
                unsigned int listType = 2;
                [inv setArgument:&listType atIndex:3];
                BOOL addFlag = YES;
                [inv setArgument:&addFlag atIndex:4];
                [inv invoke];
                LogSync(@"[2] setLocalListType:2 ✅");
            }
        } @catch (NSException *e) { LogSync(@"[2] 异常: %@", e.reason); }

        // Step 3: addContact:listType:2 确认加入公众号列表
        @try {
            SEL sel = @selector(addContact:listType:);
            if ([contactMgr respondsToSelector:sel]) {
                BOOL ret = ((BOOL (*)(id, SEL, id, unsigned int))objc_msgSend)(
                    contactMgr, sel, contact, 2);
                LogSync(@"[3] addContact:listType:2 = %@", ret ? @"YES" : @"NO");
            }
        } @catch (NSException *e) { LogSync(@"[3] 异常: %@", e.reason); }

        // 验证
        [NSThread sleepForTimeInterval:2.0];
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            if (r) {
                LogSync(@"✅✅✅ 关注成功！✅✅✅");
            } else {
                LogSync(@"❌ 关注失败");
            }
        } @catch (NSException *e) {}

    } @catch (NSException *e) {
        LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
    }
    LogSync(@"========== 关注流程结束 ==========");
}

%end

#pragma clang diagnostic pop
