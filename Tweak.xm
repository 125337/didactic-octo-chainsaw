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

// 打印联系人关键属性
static void DumpContact(id contact) {
    if (!contact) { LogSync(@"  (contact is nil)"); return; }
    LogSync(@"  class = %@", NSStringFromClass([contact class]));

    // 遍历所有属性，打印值不为 null 的
    unsigned int propCount = 0;
    objc_property_t *props = class_copyPropertyList([contact class], &propCount);
    int printed = 0;
    for (unsigned int i = 0; i < propCount && printed < 50; i++) {
        const char *propName = property_getName(props[i]);
        NSString *pName = [NSString stringWithUTF8String:propName];
        SEL getter = NSSelectorFromString(pName);
        if ([contact respondsToSelector:getter]) {
            id val = [contact performSelector:getter];
            if (val && ![val isEqual:[NSNull null]] &&
                !([val isKindOfClass:[NSString class]] && [val length] == 0) &&
                !([val isKindOfClass:[NSNumber class]] && [val integerValue] == 0 && ![val boolValue])) {
                LogSync(@"  %@ = %@", pName,
                    [val isKindOfClass:[NSString class]] ? val : [val description]);
                printed++;
            }
        }
    }
    free(props);
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

%new
- (BOOL)isFollowed {
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) { return NO; }

        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) { return NO; }

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
        // ---- 基础对象获取 ----
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) { LogSync(@"❌ MMServiceCenter 获取失败"); return; }
        LogSync(@"✅ MMServiceCenter = %@", serviceCenter);

        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) { LogSync(@"❌ CContactMgr 获取失败"); return; }
        LogSync(@"✅ CContactMgr = %@", NSStringFromClass([contactMgr class]));

        // ---- Phase 1: 获取并诊断联系人 ----
        LogSync(@"===== Phase 1: 获取联系人并诊断 =====");
        id contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        LogSync(@"[P1] getContactForSearchByName → %@", contact ? @"有值" : @"nil");

        if (contact) {
            LogSync(@"[P1] 联系人属性（拉取前）:");
            DumpContact(contact);
        }

        // ---- Phase 2: 从服务器完整拉取联系人信息 ----
        // 关键：之前联系人 m_nsNickName=null 等属性不全，
        // 需要用 getContactsFromServer:chatContact: 拉取完整信息
        LogSync(@"===== Phase 2: 从服务器完整拉取 =====");

        // 2a: 用 getContactsFromServer:chatContact: (2参数版，更完整)
        SEL fetchSel2 = NSSelectorFromString(@"getContactsFromServer:chatContact:");
        if ([contactMgr respondsToSelector:fetchSel2]) {
            LogSync(@"[P2] 调用 getContactsFromServer:chatContact:");
            NSMethodSignature *sig = [contactMgr methodSignatureForSelector:fetchSel2];
            LogSync(@"[P2] 参数数: %lu", (unsigned long)sig.numberOfArguments);
            for (NSUInteger i = 0; i < sig.numberOfArguments; i++) {
                LogSync(@"[P2] arg%lu: %s", (unsigned long)i, [sig getArgumentTypeAtIndex:i]);
            }

            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:contactMgr];
            [inv setSelector:fetchSel2];
            [inv setArgument:&GH_ID atIndex:2];
            [inv setArgument:&contact atIndex:3];
            [inv invoke];
            LogSync(@"[P2] getContactsFromServer:chatContact: 调用完成");
        } else {
            // 回退到1参数版
            SEL fetchSel1 = @selector(getContactsFromServer:);
            if ([contactMgr respondsToSelector:fetchSel1]) {
                LogSync(@"[P2] 回退到 getContactsFromServer:");
                [contactMgr performSelector:fetchSel1 withObject:GH_ID];
            }
        }

        LogSync(@"[P2] 等待 4 秒让服务器响应...");
        [NSThread sleepForTimeInterval:4.0];

        // 重新获取联系人
        contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        if (contact) {
            LogSync(@"[P2] 联系人属性（拉取后）:");
            DumpContact(contact);
        } else {
            LogSync(@"[P2] 联系人仍为 nil");
        }

        // ---- Phase 3: 尝试关注 ----
        LogSync(@"===== Phase 3: 尝试关注 =====");

        // 方案 A: addHardcodeOfficialContactWithUsrName:
        LogSync(@"--- 方案A: addHardcodeOfficialContactWithUsrName: ---");
        SEL hardcodeSel = NSSelectorFromString(@"addHardcodeOfficialContactWithUsrName:");
        if ([contactMgr respondsToSelector:hardcodeSel]) {
            [contactMgr performSelector:hardcodeSel withObject:GH_ID];
            LogSync(@"[A] 调用完成");
        }

        [NSThread sleepForTimeInterval:2.0];
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL r = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
            LogSync(@"[A] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案A成功！✅✅✅"); return; }
        }

        // 方案 B: addContact:listType: (参数类型: @, I → contact对象, unsigned int)
        LogSync(@"--- 方案B: addContact:listType: ---");
        if (contact) {
            SEL sel = @selector(addContact:listType:);
            if ([contactMgr respondsToSelector:sel]) {
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&contact atIndex:2];
                unsigned int listType = 2;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                LogSync(@"[B] 调用完成");
                if (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') {
                    BOOL ret = NO; [inv getReturnValue:&ret];
                    LogSync(@"[B] 返回 = %@", ret ? @"YES" : @"NO");
                }
            }
        }

        [NSThread sleepForTimeInterval:2.0];
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL r = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
            LogSync(@"[B] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案B成功！✅✅✅"); return; }
        }

        // 方案 C: addContact:listType:opLog:callExt: (参数: @, I, B, B)
        // 关键修复：arg4 和 arg5 是 BOOL 类型，之前错误传了 NSNull
        LogSync(@"--- 方案C: addContact:listType:opLog:callExt: ---");
        if (contact) {
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
                LogSync(@"[C] 调用完成（BOOL参数已修复）");
                if (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') {
                    BOOL ret = NO; [inv getReturnValue:&ret];
                    LogSync(@"[C] 返回 = %@", ret ? @"YES" : @"NO");
                }
            }
        }

        [NSThread sleepForTimeInterval:2.0];
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL r = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
            LogSync(@"[C] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案C成功！✅✅✅"); return; }
        }

        // 方案 D: modifyOrAddContact:Des:WithAddBlock:AddDoneBlock:WithModBlock:ModDoneBlock:
        // 这个方法有完成回调，可能是真正带服务器同步的版本
        LogSync(@"--- 方案D: modifyOrAddContact ---");
        if (contact) {
            SEL sel = NSSelectorFromString(@"modifyOrAddContact:Des:WithAddBlock:AddDoneBlock:WithModBlock:ModDoneBlock:");
            if ([contactMgr respondsToSelector:sel]) {
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                LogSync(@"[D] 参数数: %lu, 返回类型: %s", (unsigned long)sig.numberOfArguments, sig.methodReturnType);
                for (NSUInteger i = 0; i < sig.numberOfArguments; i++) {
                    LogSync(@"[D] arg%lu: %s", (unsigned long)i, [sig getArgumentTypeAtIndex:i]);
                }
                // 参数类型需要确认后才能调用，先记录
                LogSync(@"[D] 方法签名已记录，暂不调用（参数类型复杂）");
            } else {
                LogSync(@"[D] 方法不存在");
            }
        }

        // 方案 E: addContactInternal: (用联系人对象而非字符串)
        LogSync(@"--- 方案E: addContactInternal: ---");
        if (contact) {
            SEL sel = NSSelectorFromString(@"addContactInternal:");
            if ([contactMgr respondsToSelector:sel]) {
                LogSync(@"[E] ✅ 方法存在，用联系人对象调用");
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                LogSync(@"[E] 参数数: %lu, 返回类型: %s", (unsigned long)sig.numberOfArguments, sig.methodReturnType);
                for (NSUInteger i = 0; i < sig.numberOfArguments; i++) {
                    LogSync(@"[E] arg%lu: %s", (unsigned long)i, [sig getArgumentTypeAtIndex:i]);
                }

                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&contact atIndex:2];
                [inv invoke];
                LogSync(@"[E] 调用完成（无crash）");
                if (sig.methodReturnType[0] != 'v') {
                    BOOL ret = NO; [inv getReturnValue:&ret];
                    LogSync(@"[E] 返回 = %@", ret ? @"YES" : @"NO");
                }
            } else {
                LogSync(@"[E] 方法不存在");
            }
        } else {
            LogSync(@"[E] 无联系人对象，跳过");
        }

        [NSThread sleepForTimeInterval:2.0];
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL r = (BOOL)[contactMgr performSelector:@selector(isInContactList:) withObject:GH_ID];
            LogSync(@"[E] isInContactList = %@", r ? @"YES ✅" : @"NO");
            if (r) { LogSync(@"✅✅✅ 方案E成功！✅✅✅"); return; }
        }

        // ---- 最终诊断 ----
        LogSync(@"===== 最终诊断 =====");
        contact = [contactMgr performSelector:@selector(getContactForSearchByName:) withObject:GH_ID];
        if (contact) {
            LogSync(@"联系人最终属性:");
            DumpContact(contact);
        }

        // 检查 BrandService 方法
        id brandService = [serviceCenter performSelector:@selector(getService:)
                                              withObject:NSClassFromString(@"BrandService")];
        if (brandService) {
            LogSync(@"[DIAG] BrandService 方法列表:");
            unsigned int mc = 0;
            Method *ms = class_copyMethodList([brandService class], &mc);
            int cnt = 0;
            for (unsigned int i = 0; i < mc; i++) {
                const char *name = sel_getName(method_getName(ms[i]));
                NSString *ns = [NSString stringWithUTF8String:name];
                if ([ns containsString:@"add"] || [ns containsString:@"Follow"] ||
                    [ns containsString:@"follow"] || [ns containsString:@"Subscribe"] ||
                    [ns containsString:@"Brand"] || [ns containsString:@"Contact"]) {
                    LogSync(@"  → %s", name);
                    cnt++;
                    if (cnt > 30) break;
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
