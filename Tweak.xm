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

// ===== 安全读取联系人 NSString 字段 =====
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

// 安全读取整数字段（用 NSInvocation）
static inline NSUInteger SafeGetInt(id obj, NSString *key) {
    if (!obj || !key.length) return 0;
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return 0;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        char rt = sig.methodReturnType[0];
        if (rt == 'I' || rt == 'i' || rt == 'L' || rt == 'l' || rt == 'Q' || rt == 'q') {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj];
            [inv setSelector:sel];
            [inv invoke];
            NSUInteger val = 0;
            [inv getReturnValue:&val];
            return val;
        }
    } @catch (NSException *e) {}
    return 0;
}

// 安全读取 BOOL 字段
static inline BOOL SafeGetBool(id obj, NSString *key) {
    if (!obj || !key.length) return NO;
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return NO;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        char rt = sig.methodReturnType[0];
        if (rt == 'B' || rt == 'c') {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj];
            [inv setSelector:sel];
            [inv invoke];
            BOOL val = NO;
            [inv getReturnValue:&val];
            return val;
        }
    } @catch (NSException *e) {}
    return NO;
}

// 打印联系人关键属性
static void DumpContact(id contact) {
    if (!contact) { LogSync(@"  (nil)"); return; }
    LogSync(@"  m_nsUsrName = %@", SafeGet(contact, @"m_nsUsrName"));
    LogSync(@"  m_nsNickName = %@", SafeGet(contact, @"m_nsNickName"));
    LogSync(@"  m_nsBrandNick = %@", SafeGet(contact, @"m_nsBrandNick"));
    LogSync(@"  m_nsHeadImgUrl = %@", SafeGet(contact, @"m_nsHeadImgUrl"));
    LogSync(@"  m_nsVerifyInfo = %@", SafeGet(contact, @"m_nsVerifyInfo"));
    LogSync(@"  m_nsRemark = %@", SafeGet(contact, @"m_nsRemark"));
    LogSync(@"  m_bIsBrandContact = %d", SafeGetBool(contact, @"m_bIsBrandContact"));
    LogSync(@"  m_bIsService = %d", SafeGetBool(contact, @"m_bIsService"));
    LogSync(@"  m_uiFriendScene = %lu", (unsigned long)SafeGetInt(contact, @"m_uiFriendScene"));
    LogSync(@"  m_uiCertificationFlag = %lu", (unsigned long)SafeGetInt(contact, @"m_uiCertificationFlag"));
    LogSync(@"  m_uiBrandFlag = %lu", (unsigned long)SafeGetInt(contact, @"m_uiBrandFlag"));
    LogSync(@"  m_uiVerifyFlag = %lu", (unsigned long)SafeGetInt(contact, @"m_uiVerifyFlag"));
    LogSync(@"  m_uiContactType = %lu", (unsigned long)SafeGetInt(contact, @"m_uiContactType"));
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
    id s = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [s performSelector:@selector(doFollowWork)];
    });
}

%new
- (void)doFollowWork {
    LogSync(@"========== doFollowWork 开始 ==========");

    @try {
        // ---- 获取基础对象 ----
        id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(
            objc_getClass("MMServiceCenter"), NSSelectorFromString(@"defaultCenter"));
        if (!serviceCenter) { LogSync(@"❌ MMServiceCenter nil"); return; }
        LogSync(@"✅ MMServiceCenter");

        id contactMgr = ((id (*)(id, SEL, Class))objc_msgSend)(
            serviceCenter, NSSelectorFromString(@"getService:"), objc_getClass("CContactMgr"));
        if (!contactMgr) { LogSync(@"❌ CContactMgr nil"); return; }
        LogSync(@"✅ CContactMgr");

        // ---- 获取联系人 ----
        id contact = nil;

        // 尝试 getContactByUserName:（MioPlugin 使用的方法）
        SEL getByUserNameSel = @selector(getContactByUserName:);
        if ([contactMgr respondsToSelector:getByUserNameSel]) {
            contact = ((id (*)(id, SEL, id))objc_msgSend)(contactMgr, getByUserNameSel, GH_ID);
            LogSync(@"[P1] getContactByUserName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }

        // 尝试 getContactForSearchByName:
        if (!contact && [contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
            LogSync(@"[P1] getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }

        // 尝试 getContactByName:
        if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:) withObject:GH_ID];
            LogSync(@"[P1] getContactByName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }

        // 打印联系人属性
        if (contact) {
            LogSync(@"[P1] 联系人属性:");
            DumpContact(contact);
        } else {
            LogSync(@"[P1] 联系人为 nil，尝试从服务器拉取...");
            // 只用安全的1参数版 getContactsFromServer:
            if ([contactMgr respondsToSelector:@selector(getContactsFromServer:)]) {
                [contactMgr performSelector:@selector(getContactsFromServer:) withObject:GH_ID];
                LogSync(@"[P1] getContactsFromServer 已调用，等待4秒...");
                [NSThread sleepForTimeInterval:4.0];

                // 重试获取
                if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
                    contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
                    LogSync(@"[P1] 重试 → %@", contact ? @"✅ 有值" : @"❌ nil");
                }
                if (contact) {
                    LogSync(@"[P1] 拉取后联系人属性:");
                    DumpContact(contact);
                }
            }
        }

        // ---- 方案 A: addHardcodeOfficialContactWithUsrName: ----
        LogSync(@"===== 方案A: addHardcodeOfficialContactWithUsrName: =====");
        @try {
            SEL sel = NSSelectorFromString(@"addHardcodeOfficialContactWithUsrName:");
            if ([contactMgr respondsToSelector:sel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(contactMgr, sel, GH_ID);
                LogSync(@"[A] 调用完成");
            } else {
                LogSync(@"[A] ❌ 方法不存在");
            }
        } @catch (NSException *e) { LogSync(@"[A] 异常: %@", e.reason); }

        [NSThread sleepForTimeInterval:2.0];
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            LogSync(@"[A] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案A成功！✅✅✅"); return; }
        } @catch (NSException *e) {}

        // ---- 方案 B: addContact:listType: (用 objc_msgSend) ----
        LogSync(@"===== 方案B: addContact:listType:2 =====");
        if (contact) {
            @try {
                SEL sel = @selector(addContact:listType:);
                if ([contactMgr respondsToSelector:sel]) {
                    BOOL ret = ((BOOL (*)(id, SEL, id, unsigned int))objc_msgSend)(
                        contactMgr, sel, contact, 2);
                    LogSync(@"[B] 返回 = %@", ret ? @"YES" : @"NO");
                } else {
                    LogSync(@"[B] ❌ 方法不存在");
                }
            } @catch (NSException *e) { LogSync(@"[B] 异常: %@", e.reason); }
        }

        [NSThread sleepForTimeInterval:2.0];
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            LogSync(@"[B] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案B成功！✅✅✅"); return; }
        } @catch (NSException *e) {}

        // ---- 方案 C: addContact:listType:opLog:callExt: (BOOL参数修复) ----
        LogSync(@"===== 方案C: addContact:listType:opLog:callExt: =====");
        if (contact) {
            @try {
                SEL sel = NSSelectorFromString(@"addContact:listType:opLog:callExt:");
                if ([contactMgr respondsToSelector:sel]) {
                    NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:contactMgr];
                    [inv setSelector:sel];
                    [inv setArgument:&contact atIndex:2];
                    unsigned int listType = 2;
                    [inv setArgument:&listType atIndex:3];
                    BOOL opLog = YES;
                    [inv setArgument:&opLog atIndex:4];
                    BOOL callExt = YES;
                    [inv setArgument:&callExt atIndex:5];
                    [inv invoke];
                    LogSync(@"[C] 调用完成");
                    if (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') {
                        BOOL ret = NO; [inv getReturnValue:&ret];
                        LogSync(@"[C] 返回 = %@", ret ? @"YES" : @"NO");
                    }
                } else {
                    LogSync(@"[C] ❌ 方法不存在");
                }
            } @catch (NSException *e) { LogSync(@"[C] 异常: %@", e.reason); }
        }

        [NSThread sleepForTimeInterval:2.0];
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            LogSync(@"[C] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案C成功！✅✅✅"); return; }
        } @catch (NSException *e) {}

        // ---- 方案 D: addLocalContact:listType:2 (用 objc_msgSend) ----
        LogSync(@"===== 方案D: addLocalContact:listType:2 =====");
        if (contact) {
            @try {
                SEL sel = @selector(addLocalContact:listType:);
                if ([contactMgr respondsToSelector:sel]) {
                    BOOL ret = ((BOOL (*)(id, SEL, id, unsigned int))objc_msgSend)(
                        contactMgr, sel, contact, 2);
                    LogSync(@"[D] 返回 = %@", ret ? @"YES" : @"NO");
                }
            } @catch (NSException *e) { LogSync(@"[D] 异常: %@", e.reason); }
        }

        [NSThread sleepForTimeInterval:2.0];
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            LogSync(@"[D] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案D成功！✅✅✅"); return; }
        } @catch (NSException *e) {}

        // ---- 方案 E: addContactInternal: (用联系人对象) ----
        LogSync(@"===== 方案E: addContactInternal: =====");
        if (contact) {
            @try {
                SEL sel = NSSelectorFromString(@"addContactInternal:");
                if ([contactMgr respondsToSelector:sel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(contactMgr, sel, contact);
                    LogSync(@"[E] 调用完成");
                } else {
                    LogSync(@"[E] ❌ 方法不存在");
                }
            } @catch (NSException *e) { LogSync(@"[E] 异常: %@", e.reason); }
        }

        [NSThread sleepForTimeInterval:2.0];
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            LogSync(@"[E] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案E成功！✅✅✅"); return; }
        } @catch (NSException *e) {}

        // ---- 最终诊断 ----
        LogSync(@"===== 最终诊断 =====");
        id finalContact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            finalContact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        }
        if (finalContact) {
            LogSync(@"最终联系人属性:");
            DumpContact(finalContact);
        }

        // 检查 BrandService 方法
        id brandService = ((id (*)(id, SEL, Class))objc_msgSend)(
            serviceCenter, NSSelectorFromString(@"getService:"), objc_getClass("BrandService"));
        if (brandService) {
            LogSync(@"BrandService 方法:");
            unsigned int mc = 0;
            Method *ms = class_copyMethodList([brandService class], &mc);
            int cnt = 0;
            for (unsigned int i = 0; i < mc; i++) {
                const char *name = sel_getName(method_getName(ms[i]));
                NSString *ns = [NSString stringWithUTF8String:name];
                if ([ns containsString:@"add"] || [ns containsString:@"Follow"] ||
                    [ns containsString:@"follow"] || [ns containsString:@"Subscribe"] ||
                    [ns containsString:@"Contact"]) {
                    LogSync(@"  → %s", name);
                    cnt++;
                    if (cnt > 20) break;
                }
            }
            free(ms);
        }

        LogSync(@"❌❌❌ 所有关注方案均失败 ❌❌❌");
    } @catch (NSException *e) {
        LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
        LogSync(@"[EXCEPTION] callStack: %@", e.callStackSymbols);
    }

    LogSync(@"========== 关注流程结束 ==========");
}

%end

#pragma clang diagnostic pop
