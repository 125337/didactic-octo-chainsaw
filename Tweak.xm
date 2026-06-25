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

// 安全读取
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

static inline NSUInteger SafeGetInt(id obj, NSString *key) {
    if (!obj || !key.length) return 0;
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return 0;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        char rt = sig.methodReturnType[0];
        if (rt == 'I' || rt == 'i' || rt == 'L' || rt == 'l' || rt == 'Q' || rt == 'q') {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj]; [inv setSelector:sel]; [inv invoke];
            NSUInteger val = 0; [inv getReturnValue:&val]; return val;
        }
    } @catch (NSException *e) {}
    return 0;
}

static inline BOOL SafeGetBool(id obj, NSString *key) {
    if (!obj || !key.length) return NO;
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return NO;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        char rt = sig.methodReturnType[0];
        if (rt == 'B' || rt == 'c') {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj]; [inv setSelector:sel]; [inv invoke];
            BOOL val = NO; [inv getReturnValue:&val]; return val;
        }
    } @catch (NSException *e) {}
    return NO;
}

// 安全设置 BOOL
static inline void SafeSetBool(id obj, NSString *key, BOOL val) {
    if (!obj || !key.length) return;
    NSString *setterName = [NSString stringWithFormat:@"set%@:", [key stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[key substringToIndex:1] uppercaseString]]];
    SEL sel = NSSelectorFromString(setterName);
    if (![obj respondsToSelector:sel]) return;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        if (sig.numberOfArguments == 3 && (sig.methodReturnType[0] == 'v')) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj]; [inv setSelector:sel];
            // 检查参数类型
            const char *argType = [sig getArgumentTypeAtIndex:2];
            if (argType[0] == 'B' || argType[0] == 'c') {
                BOOL bval = val;
                [inv setArgument:&bval atIndex:2];
            } else {
                return; // 类型不匹配，跳过
            }
            [inv invoke];
        }
    } @catch (NSException *e) {}
}

// 安全设置 NSUInteger
static inline void SafeSetInt(id obj, NSString *key, NSUInteger val) {
    if (!obj || !key.length) return;
    NSString *setterName = [NSString stringWithFormat:@"set%@:", [key stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[key substringToIndex:1] uppercaseString]]];
    SEL sel = NSSelectorFromString(setterName);
    if (![obj respondsToSelector:sel]) return;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        if (sig.numberOfArguments == 3 && (sig.methodReturnType[0] == 'v')) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj]; [inv setSelector:sel];
            const char *argType = [sig getArgumentTypeAtIndex:2];
            if (argType[0] == 'I') { unsigned int v = (unsigned int)val; [inv setArgument:&v atIndex:2]; }
            else if (argType[0] == 'i') { int v = (int)val; [inv setArgument:&v atIndex:2]; }
            else if (argType[0] == 'L') { unsigned long v = (unsigned long)val; [inv setArgument:&v atIndex:2]; }
            else if (argType[0] == 'l') { long v = (long)val; [inv setArgument:&v atIndex:2]; }
            else if (argType[0] == 'Q') { unsigned long long v = (unsigned long long)val; [inv setArgument:&v atIndex:2]; }
            else if (argType[0] == 'q') { long long v = (long long)val; [inv setArgument:&v atIndex:2]; }
            else { return; }
            [inv invoke];
        }
    } @catch (NSException *e) {}
}

// 安全设置 NSString
static inline void SafeSetString(id obj, NSString *key, NSString *val) {
    if (!obj || !key.length || !val) return;
    NSString *setterName = [NSString stringWithFormat:@"set%@:", [key stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[key substringToIndex:1] uppercaseString]]];
    SEL sel = NSSelectorFromString(setterName);
    if (![obj respondsToSelector:sel]) return;
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, val);
    } @catch (NSException *e) {}
}

static void DumpContact(id contact) {
    if (!contact) { LogSync(@"  (nil)"); return; }
    LogSync(@"  m_nsUsrName = %@", SafeGet(contact, @"m_nsUsrName"));
    LogSync(@"  m_nsNickName = %@", SafeGet(contact, @"m_nsNickName"));
    LogSync(@"  m_nsBrandNick = %@", SafeGet(contact, @"m_nsBrandNick"));
    LogSync(@"  m_nsHeadImgUrl = %@", SafeGet(contact, @"m_nsHeadImgUrl"));
    LogSync(@"  m_bIsBrandContact = %d", SafeGetBool(contact, @"m_bIsBrandContact"));
    LogSync(@"  m_bIsService = %d", SafeGetBool(contact, @"m_bIsService"));
    LogSync(@"  m_uiFriendScene = %lu", (unsigned long)SafeGetInt(contact, @"m_uiFriendScene"));
    LogSync(@"  m_uiBrandFlag = %lu", (unsigned long)SafeGetInt(contact, @"m_uiBrandFlag"));
    LogSync(@"  m_uiVerifyFlag = %lu", (unsigned long)SafeGetInt(contact, @"m_uiVerifyFlag"));
    LogSync(@"  m_uiContactType = %lu", (unsigned long)SafeGetInt(contact, @"m_uiContactType"));
    LogSync(@"  m_uiCertificationFlag = %lu", (unsigned long)SafeGetInt(contact, @"m_uiCertificationFlag"));
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
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        }
        if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:) withObject:GH_ID];
        }
        if (!contact) { LogSync(@"❌ 无法获取联系人对象"); return; }

        LogSync(@"[P1] 联系人属性（修改前）:");
        DumpContact(contact);

        // ==== 核心策略：先修改联系人属性为公众号，再用 addContactInternal: 添加 ====
        LogSync(@"===== 修改联系人属性为公众号 =====");

        // 设置 m_bIsBrandContact = YES
        SafeSetBool(contact, @"m_bIsBrandContact", YES);
        LogSync(@"[MOD] m_bIsBrandContact → %d", SafeGetBool(contact, @"m_bIsBrandContact"));

        // 设置 m_bIsService = YES (服务号)
        SafeSetBool(contact, @"m_bIsService", YES);
        LogSync(@"[MOD] m_bIsService → %d", SafeGetBool(contact, @"m_bIsService"));

        // 设置 m_uiBrandFlag = 8 (公众号标志，参考微信内部常量)
        SafeSetInt(contact, @"m_uiBrandFlag", 8);
        LogSync(@"[MOD] m_uiBrandFlag → %lu", (unsigned long)SafeGetInt(contact, @"m_uiBrandFlag"));

        // 设置 m_uiVerifyFlag = 8 (认证标志)
        SafeSetInt(contact, @"m_uiVerifyFlag", 8);
        LogSync(@"[MOD] m_uiVerifyFlag → %lu", (unsigned long)SafeGetInt(contact, @"m_uiVerifyFlag"));

        // 设置 m_uiContactType = 3 (公众号类型)
        SafeSetInt(contact, @"m_uiContactType", 3);
        LogSync(@"[MOD] m_uiContactType → %lu", (unsigned long)SafeGetInt(contact, @"m_uiContactType"));

        // 设置 m_uiCertificationFlag = 1 (已认证)
        SafeSetInt(contact, @"m_uiCertificationFlag", 1);
        LogSync(@"[MOD] m_uiCertificationFlag → %lu", (unsigned long)SafeGetInt(contact, @"m_uiCertificationFlag"));

        // 设置 m_uiFriendScene = 14 (公众号添加场景)
        SafeSetInt(contact, @"m_uiFriendScene", 14);
        LogSync(@"[MOD] m_uiFriendScene → %lu", (unsigned long)SafeGetInt(contact, @"m_uiFriendScene"));

        // 设置昵称（虽然我们不知道真实昵称，但设置一个标记便于识别）
        SafeSetString(contact, @"m_nsNickName", @"iOS逆向助手");
        LogSync(@"[MOD] m_nsNickName → %@", SafeGet(contact, @"m_nsNickName"));

        LogSync(@"[P2] 联系人属性（修改后）:");
        DumpContact(contact);

        // ==== 方案1: addContactInternal: (已验证有效) ====
        LogSync(@"===== 方案1: addContactInternal:（已验证可添加到联系人列表）=====");
        @try {
            SEL sel = NSSelectorFromString(@"addContactInternal:");
            if ([contactMgr respondsToSelector:sel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(contactMgr, sel, contact);
                LogSync(@"[1] addContactInternal 调用完成");
            }
        } @catch (NSException *e) { LogSync(@"[1] 异常: %@", e.reason); }

        // ==== 方案2: setLocalListTypeWithUserName:listType:addFlag: 设置为公众号列表 ====
        LogSync(@"===== 方案2: setLocalListTypeWithUserName:listType:addFlag: =====");
        @try {
            SEL sel = NSSelectorFromString(@"setLocalListTypeWithUserName:listType:addFlag:");
            if ([contactMgr respondsToSelector:sel]) {
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&GH_ID atIndex:2];
                unsigned int listType = 2; // 2 = 品牌号/公众号
                [inv setArgument:&listType atIndex:3];
                BOOL addFlag = YES;
                [inv setArgument:&addFlag atIndex:4];
                [inv invoke];
                LogSync(@"[2] setLocalListType 调用完成（listType=2, addFlag=YES）");
            } else {
                LogSync(@"[2] ❌ 方法不存在");
            }
        } @catch (NSException *e) { LogSync(@"[2] 异常: %@", e.reason); }

        // ==== 方案3: addContact:listType:2 再试一次（联系人已修改为公众号属性）====
        LogSync(@"===== 方案3: addContact:listType:2（联系人已设公众号属性）=====");
        @try {
            SEL sel = @selector(addContact:listType:);
            if ([contactMgr respondsToSelector:sel]) {
                BOOL ret = ((BOOL (*)(id, SEL, id, unsigned int))objc_msgSend)(
                    contactMgr, sel, contact, 2);
                LogSync(@"[3] 返回 = %@", ret ? @"YES" : @"NO");
            }
        } @catch (NSException *e) { LogSync(@"[3] 异常: %@", e.reason); }

        // ==== 等待验证 ====
        LogSync(@"===== 验证结果 =====");
        [NSThread sleepForTimeInterval:3.0];

        // 验证 isInContactList
        @try {
            BOOL r = (BOOL)((BOOL (*)(id, SEL, id))objc_msgSend)(
                contactMgr, @selector(isInContactList:), GH_ID);
            LogSync(@"isInContactList = %@", r ? @"YES ✅" : @"NO");
        } @catch (NSException *e) {}

        // 验证联系人最终属性
        id finalContact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            finalContact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        }
        if (finalContact) {
            LogSync(@"最终联系人属性:");
            DumpContact(finalContact);
        }

        // 检查 getAllBrandContacts 看公众号列表
        @try {
            SEL sel = NSSelectorFromString(@"getAllBrandContacts");
            if ([contactMgr respondsToSelector:sel]) {
                id brandList = ((id (*)(id, SEL))objc_msgSend)(contactMgr, sel);
                if ([brandList isKindOfClass:[NSArray class]]) {
                    NSArray *brands = (NSArray *)brandList;
                    LogSync(@"getAllBrandContacts: %lu 个", (unsigned long)[brands count]);
                    for (NSUInteger i = 0; i < [brands count] && i < 5; i++) {
                        id b = brands[i];
                        LogSync(@"  [%lu] %@", (unsigned long)i, SafeGet(b, @"m_nsUsrName"));
                    }
                    // 检查我们的公众号是否在列表中
                    for (id b in brands) {
                        if ([SafeGet(b, @"m_nsUsrName") isEqualToString:GH_ID]) {
                            LogSync(@"✅ 找到 %@ 在 brandContacts 列表中！", GH_ID);
                            break;
                        }
                    }
                } else {
                    LogSync(@"getAllBrandContacts 返回非数组类型: %@", [brandList class]);
                }
            }
        } @catch (NSException *e) { LogSync(@"getAllBrandContacts 异常: %@", e.reason); }

        LogSync(@"========== 关注流程结束 ==========");
    } @catch (NSException *e) {
        LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
        LogSync(@"[EXCEPTION] callStack: %@", e.callStackSymbols);
    }
}

%end

#pragma clang diagnostic pop
