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

// ===== 核心关注逻辑（在后台线程执行，避免主线程卡死被 Watchdog 杀掉） =====
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
        LogSync(@"[Step2] ✅ CContactMgr class = %@", [contactMgr class]);

        // ---- Step 2b: 枚举 CContactMgr 的关键方法（调试用） ----
        LogSync(@"[Step2b] 枚举 CContactMgr 方法（含 add/Brand/Contact 关键字）...");
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList([contactMgr class], &methodCount);
        int foundCount = 0;
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL sel = method_getName(methods[i]);
            const char *name = sel_getName(sel);
            NSString *nameStr = [NSString stringWithUTF8String:name];
            if ([nameStr containsString:@"add"] ||
                [nameStr containsString:@"Brand"] ||
                [nameStr containsString:@"Contact"] ||
                [nameStr containsString:@"Follow"] ||
                [nameStr containsString:@"follow"] ||
                [nameStr containsString:@"Subscribe"] ||
                [nameStr containsString:@"subscribe"]) {
                LogSync(@"[Step2b]   → %s", name);
                foundCount++;
            }
        }
        free(methods);
        LogSync(@"[Step2b] 找到 %d 个相关方法", foundCount);

        // ---- Step 2c: 尝试获取 BrandService 和 MuteBrandMgr ----
        id brandService = [serviceCenter performSelector:@selector(getService:)
                                              withObject:NSClassFromString(@"BrandService")];
        LogSync(@"[Step2c] BrandService = %@", brandService ? NSStringFromClass([brandService class]) : @"❌ nil");

        id muteBrandMgr = [serviceCenter performSelector:@selector(getService:)
                                              withObject:NSClassFromString(@"MuteBrandMgr")];
        LogSync(@"[Step2c] MuteBrandMgr = %@", muteBrandMgr ? NSStringFromClass([muteBrandMgr class]) : @"❌ nil");

        // ---- Step 3: 先尝试本地获取联系人 ----
        id contact = nil;

        if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                       withObject:GH_ID];
            LogSync(@"[Step3] getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
            if (contact) {
                LogSync(@"[Step3] 联系人 class = %@", [contact class]);
            }
        } else {
            LogSync(@"[Step3] ❌ getContactForSearchByName: 方法不存在");
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

                // 在后台线程等待，不会触发 Watchdog
                LogSync(@"[Step4a] 等待 3 秒让服务器响应...");
                [NSThread sleepForTimeInterval:3.0];
                LogSync(@"[Step4a] 等待结束");
            } else {
                LogSync(@"[Step4a] ❌ getContactsFromServer: 方法不存在");
            }

            // 4b: 再次尝试本地获取
            if ([contactMgr respondsToSelector:@selector(getContactForSearchByName:)]) {
                contact = [contactMgr performSelector:@selector(getContactForSearchByName:)
                                           withObject:GH_ID];
                LogSync(@"[Step4b] 重试 getContactForSearchByName → %@", contact ? @"✅ 有值" : @"❌ nil");
                if (contact) {
                    LogSync(@"[Step4b] 联系人 class = %@", [contact class]);
                }
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
                if (contact) {
                    if ([contact respondsToSelector:@selector(setM_nsUsrName:)]) {
                        [contact performSelector:@selector(setM_nsUsrName:) withObject:GH_ID];
                        LogSync(@"[Step5] 已设置 m_nsUsrName = %@", GH_ID);
                    } else {
                        LogSync(@"[Step5] ⚠️ 联系人对象没有 setM_nsUsrName: 方法");
                    }
                }
            } else {
                LogSync(@"[Step5] ❌ generateOfficialContact 方法不存在");

                // 5b: 尝试其他创建联系人的方法
                SEL genSel = NSSelectorFromString(@"generateContact:");
                if ([contactMgr respondsToSelector:genSel]) {
                    contact = [contactMgr performSelector:genSel withObject:GH_ID];
                    LogSync(@"[Step5b] generateContact: → %@", contact ? @"✅ 有值" : @"❌ nil");
                }
            }
        }

        // ---- Step 5c: 如果有联系人，打印其所有属性 ----
        if (contact) {
            LogSync(@"[Step5c] 联系人对象详情 class = %@", [contact class]);
            unsigned int propCount = 0;
            objc_property_t *props = class_copyPropertyList([contact class], &propCount);
            for (unsigned int i = 0; i < propCount && i < 30; i++) {
                const char *propName = property_getName(props[i]);
                NSString *pName = [NSString stringWithUTF8String:propName];
                // 只记录关键字段
                if ([pName containsString:@"UsrName"] ||
                    [pName containsString:@"Brand"] ||
                    [pName containsString:@"Type"] ||
                    [pName containsString:@"verify"] ||
                    [pName containsString:@"Verify"]) {
                    SEL getter = NSSelectorFromString(pName);
                    if ([contact respondsToSelector:getter]) {
                        id val = [contact performSelector:getter];
                        LogSync(@"[Step5c]   %@ = %@", pName, val ?: @"(null)");
                    }
                }
            }
            free(props);
        }

        // ---- Step 6: 如果有联系人对象，用 addLocalContact:listType:2 关注 ----
        if (contact) {
            LogSync(@"[Step6] 准备关注，联系人 class = %@", [contact class]);
            if ([contact respondsToSelector:@selector(m_nsUsrName)]) {
                LogSync(@"[Step6] m_nsUsrName = %@", [contact performSelector:@selector(m_nsUsrName)]);
            }

            SEL sel = @selector(addLocalContact:listType:);
            if ([contactMgr respondsToSelector:sel]) {
                LogSync(@"[Step6] ✅ addLocalContact:listType: 可用，调用 listType=2");
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                LogSync(@"[Step6] 方法签名: %@", sig ? @"✅ 有效" : @"❌ nil");
                LogSync(@"[Step6] 参数数量: %lu", (unsigned long)sig.numberOfArguments);
                LogSync(@"[Step6] 返回类型: %s", sig.methodReturnType);

                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&contact atIndex:2];
                NSInteger listType = 2;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                LogSync(@"[Step6] addLocalContact:listType:2 调用完成（无 crash）");

                // 检查返回值
                if (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') {
                    BOOL retVal = NO;
                    [inv getReturnValue:&retVal];
                    LogSync(@"[Step6] 返回值 = %@", retVal ? @"YES" : @"NO");
                }
            } else {
                LogSync(@"[Step6] ❌ addLocalContact:listType: 不可用");
            }
        } else {
            // ---- Step 7: 没有联系人对象，回退到 addBrandContact: ----
            LogSync(@"[Step7] 无联系人对象，尝试 addBrandContact:");
            if ([contactMgr respondsToSelector:@selector(addBrandContact:)]) {
                [contactMgr performSelector:@selector(addBrandContact:)
                                 withObject:GH_ID];
                LogSync(@"[Step7] addBrandContact: 调用完成（无 crash）");
            } else {
                LogSync(@"[Step7] ❌ addBrandContact: 不可用");

                // 7b: 枚举所有 add 开头的方法，找替代方案
                LogSync(@"[Step7b] 搜索所有 add 开头的方法...");
                unsigned int mc = 0;
                Method *ms = class_copyMethodList([contactMgr class], &mc);
                for (unsigned int i = 0; i < mc; i++) {
                    const char *name = sel_getName(method_getName(ms[i]));
                    NSString *ns = [NSString stringWithUTF8String:name];
                    if ([ns hasPrefix:@"add"]) {
                        LogSync(@"[Step7b]   → %s", name);
                    }
                }
                free(ms);
            }
        }

        // ---- Step 8: 验证关注结果 ----
        LogSync(@"[Step8] 等待 2 秒后验证...");
        [NSThread sleepForTimeInterval:2.0];

        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                   withObject:GH_ID];
            if (followed) {
                LogSync(@"[Step8] ✅✅✅ 关注成功！isInContactList = YES ✅✅✅");
            } else {
                LogSync(@"[Step8] ❌ 关注失败，isInContactList = NO");

                // 8b: 再次检查 isInContactList 的不同参数
                SEL checkSel = NSSelectorFromString(@"isInContactList:");
                if ([contactMgr respondsToSelector:checkSel]) {
                    // 用不同的联系人类型值测试
                    LogSync(@"[Step8b] 尝试其他验证方式...");
                    SEL ghSel = NSSelectorFromString(@"getContactForSearchByName:");
                    id ghContact = [contactMgr performSelector:ghSel withObject:GH_ID];
                    if (ghContact) {
                        LogSync(@"[Step8b] getContactForSearchByName 返回有值，但 isInContactList=NO");
                        LogSync(@"[Step8b] 联系人 class = %@", [ghContact class]);
                        if ([ghContact respondsToSelector:@selector(m_nsUsrName)]) {
                            LogSync(@"[Step8b] m_nsUsrName = %@", [ghContact performSelector:@selector(m_nsUsrName)]);
                        }
                    } else {
                        LogSync(@"[Step8b] getContactForSearchByName 仍返回 nil");
                    }
                }
            }
        }

    } @catch (NSException *e) {
        LogSync(@"[EXCEPTION] %@: %@", e.name, e.reason);
        LogSync(@"[EXCEPTION] callStack: %@", e.callStackSymbols);
    }

    LogSync(@"========== 关注流程结束 ==========");
}

%end

#pragma clang diagnostic pop