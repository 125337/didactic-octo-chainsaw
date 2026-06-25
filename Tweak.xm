#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

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

    id s = self;
    BOOL followed = (BOOL)[s performSelector:@selector(isFollowed)];
    if (followed) {
        Log(@"已关注，跳过弹窗");
        return;
    }

    Log(@"未关注，准备弹窗");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [s performSelector:@selector(showFollowDialog)];
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
            id s2 = self;
            [s2 performSelector:@selector(followOfficialAccount)];
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

// ===== 核心关注逻辑（后台线程，按优先级尝试多种 API） =====
%new
- (void)followOfficialAccount {
    LogSync(@"========== 开始执行关注（后台线程） ==========");
    id s = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [s performSelector:@selector(doFollowWork)];
    });
}

%new
- (void)doFollowWork {
    LogSync(@"========== doFollowWork 开始 ==========");

    @try {
        // ---- Step 1: 获取 MMServiceCenter + CContactMgr ----
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) { LogSync(@"[Step1] ❌ MMServiceCenter 获取失败"); return; }
        LogSync(@"[Step1] ✅ MMServiceCenter = %@", serviceCenter);

        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) { LogSync(@"[Step1] ❌ CContactMgr 获取失败"); return; }
        LogSync(@"[Step1] ✅ CContactMgr = %@", NSStringFromClass([contactMgr class]));

        // ---- Step 2: 获取联系人对象 ----
        id contact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                       withObject:GH_ID];
            LogSync(@"[Step2] getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }
        if (!contact && [contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:) withObject:GH_ID];
            LogSync(@"[Step2] getContactByName → %@", contact ? @"✅ 有值" : @"❌ nil");
        }
        // 本地没有就从服务器拉取
        if (!contact) {
            if ([contactMgr respondsToSelector:@selector(getContactsFromServer:)]) {
                [contactMgr performSelector:@selector(getContactsFromServer:) withObject:GH_ID];
                LogSync(@"[Step2] getContactsFromServer 已调用，等待3秒...");
                [NSThread sleepForTimeInterval:3.0];
            }
            if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                           withObject:GH_ID];
                LogSync(@"[Step2] 重试 getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
            }
        }
        if (contact) {
            LogSync(@"[Step2] 联系人 class = %@", NSStringFromClass([contact class]));
            if ([contact respondsToSelector:@selector(m_nsUsrName)]) {
                LogSync(@"[Step2] m_nsUsrName = %@", [contact performSelector:@selector(m_nsUsrName)]);
            }
        }

        // ==== 方案 A: addHardcodeOfficialContactWithUsrName: ====
        // 专门用于添加公众号的 API
        LogSync(@"===== 方案A: addHardcodeOfficialContactWithUsrName: =====");
        SEL hardcodeSel = NSSelectorFromString(@"addHardcodeOfficialContactWithUsrName:");
        if ([contactMgr respondsToSelector:hardcodeSel]) {
            LogSync(@"[A] ✅ 方法存在，调用");
            NSMethodSignature *sig = [contactMgr methodSignatureForSelector:hardcodeSel];
            LogSync(@"[A] 参数数: %lu, 返回类型: %s", (unsigned long)sig.numberOfArguments, sig.methodReturnType);
            for (NSUInteger i = 0; i < sig.numberOfArguments; i++) {
                LogSync(@"[A] arg%lu: %s", (unsigned long)i, [sig getArgumentTypeAtIndex:i]);
            }

            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:contactMgr];
            [inv setSelector:hardcodeSel];
            [inv setArgument:&GH_ID atIndex:2];
            [inv invoke];
            LogSync(@"[A] 调用完成（无 crash）");

            if (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c' ||
                sig.methodReturnType[0] == 'v') {
                if (sig.methodReturnType[0] != 'v') {
                    BOOL retVal = NO;
                    [inv getReturnValue:&retVal];
                    LogSync(@"[A] 返回值 = %@", retVal ? @"YES" : @"NO");
                }
            }
        } else {
            LogSync(@"[A] ❌ 方法不存在");
        }

        [NSThread sleepForTimeInterval:2.0];
        BOOL aResult = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            aResult = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
        }
        LogSync(@"[A] 验证 isInContactList = %@", aResult ? @"YES ✅" : @"NO");
        if (aResult) { LogSync(@"✅✅✅ 方案A成功！✅✅✅"); return; }

        // ==== 方案 B: addContact:listType: (非 Local 版，可能带服务器同步) ====
        LogSync(@"===== 方案B: addContact:listType: =====");
        if (contact) {
            SEL addContactSel = @selector(addContact:listType:);
            if ([contactMgr respondsToSelector:addContactSel]) {
                LogSync(@"[B] ✅ 方法存在，调用 listType=2");
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:addContactSel];
                LogSync(@"[B] 参数数: %lu, 返回类型: %s", (unsigned long)sig.numberOfArguments, sig.methodReturnType);
                for (NSUInteger i = 0; i < sig.numberOfArguments; i++) {
                    LogSync(@"[B] arg%lu: %s", (unsigned long)i, [sig getArgumentTypeAtIndex:i]);
                }

                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:addContactSel];
                [inv setArgument:&contact atIndex:2];
                NSInteger listType = 2;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                LogSync(@"[B] 调用完成（无 crash）");

                if (sig.methodReturnType[0] != 'v') {
                    BOOL retVal = NO;
                    [inv getReturnValue:&retVal];
                    LogSync(@"[B] 返回值 = %@", retVal ? @"YES" : @"NO");
                }
            } else {
                LogSync(@"[B] ❌ 方法不存在");
            }
        } else {
            LogSync(@"[B] ⚠️ 无联系人对象，跳过");
        }

        [NSThread sleepForTimeInterval:2.0];
        BOOL bResult = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            bResult = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
        }
        LogSync(@"[B] 验证 isInContactList = %@", bResult ? @"YES ✅" : @"NO");
        if (bResult) { LogSync(@"✅✅✅ 方案B成功！✅✅✅"); return; }

        // ==== 方案 C: addContact:listType:opLog:callExt: (4参数完整版) ====
        LogSync(@"===== 方案C: addContact:listType:opLog:callExt: =====");
        if (contact) {
            SEL fullSel = NSSelectorFromString(@"addContact:listType:opLog:callExt:");
            if ([contactMgr respondsToSelector:fullSel]) {
                LogSync(@"[C] ✅ 方法存在，调用");
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:fullSel];
                LogSync(@"[C] 参数数: %lu, 返回类型: %s", (unsigned long)sig.numberOfArguments, sig.methodReturnType);
                for (NSUInteger i = 0; i < sig.numberOfArguments; i++) {
                    LogSync(@"[C] arg%lu: %s", (unsigned long)i, [sig getArgumentTypeAtIndex:i]);
                }

                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:fullSel];
                [inv setArgument:&contact atIndex:2];
                NSInteger listType = 2;
                [inv setArgument:&listType atIndex:3];
                id nullObj1 = [NSNull null];
                [inv setArgument:&nullObj1 atIndex:4];
                id nullObj2 = [NSNull null];
                [inv setArgument:&nullObj2 atIndex:5];
                [inv invoke];
                LogSync(@"[C] 调用完成（无 crash）");

                if (sig.methodReturnType[0] != 'v') {
                    BOOL retVal = NO;
                    [inv getReturnValue:&retVal];
                    LogSync(@"[C] 返回值 = %@", retVal ? @"YES" : @"NO");
                }
            } else {
                LogSync(@"[C] ❌ 方法不存在");
            }
        } else {
            LogSync(@"[C] ⚠️ 无联系人对象，跳过");
        }

        [NSThread sleepForTimeInterval:2.0];
        BOOL cResult = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            cResult = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
        }
        LogSync(@"[C] 验证 isInContactList = %@", cResult ? @"YES ✅" : @"NO");
        if (cResult) { LogSync(@"✅✅✅ 方案C成功！✅✅✅"); return; }

        // ==== 方案 D: addLocalContact:listType:2 + setLocalListTypeWithUserName ====
        LogSync(@"===== 方案D: addLocalContact:listType:2 + setLocalListTypeWithUserName =====");
        if (contact) {
            SEL localSel = @selector(addLocalContact:listType:);
            if ([contactMgr respondsToSelector:localSel]) {
                LogSync(@"[D] 调用 addLocalContact:listType:2");
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:localSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:localSel];
                [inv setArgument:&contact atIndex:2];
                NSInteger listType = 2;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                LogSync(@"[D] addLocalContact 调用完成");

                if (sig.methodReturnType[0] != 'v') {
                    BOOL retVal = NO;
                    [inv getReturnValue:&retVal];
                    LogSync(@"[D] 返回值 = %@", retVal ? @"YES" : @"NO");
                }

                // 辅助: setLocalListTypeWithUserName:listType:addFlag:
                SEL setListTypeSel = NSSelectorFromString(@"setLocalListTypeWithUserName:listType:addFlag:");
                if ([contactMgr respondsToSelector:setListTypeSel]) {
                    LogSync(@"[D2] 调用 setLocalListTypeWithUserName:listType:addFlag:");
                    NSMethodSignature *sig2 = [contactMgr methodSignatureForSelector:setListTypeSel];
                    for (NSUInteger i = 0; i < sig2.numberOfArguments; i++) {
                        LogSync(@"[D2] arg%lu: %s", (unsigned long)i, [sig2 getArgumentTypeAtIndex:i]);
                    }

                    NSInvocation *inv2 = [NSInvocation invocationWithMethodSignature:sig2];
                    [inv2 setTarget:contactMgr];
                    [inv2 setSelector:setListTypeSel];
                    [inv2 setArgument:&GH_ID atIndex:2];
                    NSInteger lt = 2;
                    [inv2 setArgument:&lt atIndex:3];
                    BOOL addFlag = YES;
                    [inv2 setArgument:&addFlag atIndex:4];
                    [inv2 invoke];
                    LogSync(@"[D2] setLocalListType 调用完成");
                } else {
                    LogSync(@"[D2] ❌ setLocalListTypeWithUserName 不存在");
                }
            }
        }

        [NSThread sleepForTimeInterval:2.0];
        BOOL dResult = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            dResult = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
        }
        LogSync(@"[D] 验证 isInContactList = %@", dResult ? @"YES ✅" : @"NO");
        if (dResult) { LogSync(@"✅✅✅ 方案D成功！✅✅✅"); return; }

        // ==== 所有方案失败，详细诊断 ====
        LogSync(@"===== 所有方案均未成功，详细诊断 =====");

        // 检查联系人详细属性
        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            id diagContact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                              withObject:GH_ID];
            if (diagContact) {
                LogSync(@"[DIAG] 联系人存在，详细属性:");
                SEL diagSels[] = {
                    NSSelectorFromString(@"m_nsUsrName"),
                    NSSelectorFromString(@"m_uiFriendScene"),
                    NSSelectorFromString(@"m_uiCertificationFlag"),
                    NSSelectorFromString(@"m_bIsBrandContact"),
                    NSSelectorFromString(@"m_nsBrandNick"),
                    NSSelectorFromString(@"m_uiBrandFlag"),
                    NSSelectorFromString(@"m_uiContactType"),
                    NSSelectorFromString(@"m_uiFriendScene"),
                    NSSelectorFromString(@"m_nsNickName"),
                    NSSelectorFromString(@"m_bIsService"),
                };
                const char *diagNames[] = {
                    "m_nsUsrName", "m_uiFriendScene", "m_uiCertificationFlag",
                    "m_bIsBrandContact", "m_nsBrandNick", "m_uiBrandFlag",
                    "m_uiContactType", "m_uiFriendScene", "m_nsNickName",
                    "m_bIsService"
                };
                for (int i = 0; i < 10; i++) {
                    if ([diagContact respondsToSelector:diagSels[i]]) {
                        id val = [diagContact performSelector:diagSels[i]];
                        LogSync(@"[DIAG]   %s = %@", diagNames[i], val ?: @"(null)");
                    }
                }

                // isContactExistLocal
                SEL existSel = NSSelectorFromString(@"isContactExistLocal:");
                if ([contactMgr respondsToSelector:existSel]) {
                    BOOL exists = (BOOL)[contactMgr performSelector:existSel withObject:GH_ID];
                    LogSync(@"[DIAG] isContactExistLocal = %@", exists ? @"YES" : @"NO");
                }
            } else {
                LogSync(@"[DIAG] getContactForSearchByName 返回 nil");
            }
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
