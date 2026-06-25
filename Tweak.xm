#pragma mark - ===== 日志系统 =====

// 日志文件路径：/var/mobile/Documents/xhbb_follow.log
// 越狱设备用 Filza 直接查看
// 非越狱设备用 iFunBox/爱思助手 → 应用 → 微信 → 文件共享
void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // 时间戳
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    
    // 日志行
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // 写入文件（追加模式）
    NSString *logPath = @"/var/mobile/Documents/xhbb_follow.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [logLine writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}


#pragma mark - ===== dylib 加载入口 =====

%ctor {
    Log(@"==============================");
    Log(@"===== xhbb.dylib 已加载 =====");
    Log(@"==============================");
    
    // 确认目标类存在
    Class cls = NSClassFromString(@"WCPluginsViewController");
    if (cls) {
        Log(@"[OK] 找到 WCPluginsViewController 类");
    } else {
        Log(@"[ERROR] WCPluginsViewController 类不存在！检查 Filter 是否正确");
    }
}


#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

// ===== Hook viewDidAppear: 进入页面时触发 =====
- (void)viewDidAppear:(BOOL)animated {
    %orig; // 必须先调原实现
    
    Log(@"viewDidAppear 被调用, self=%@", [self class]);
    
    // 1. 检查是否已弹过窗
    BOOL shown = [[NSUserDefaults standardUserDefaults] boolForKey:@"xhbb_follow_shown"];
    if (shown) {
        Log(@"弹窗已显示过，跳过");
        return;
    }
    
    // 2. 检查是否已关注
    if ([self isFollowed]) {
        Log(@"已关注，标记弹窗已显示并跳过");
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
        return;
    }
    
    Log(@"未关注，准备弹窗");
    
    // 3. 延迟弹窗（等页面加载完）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        Log(@"执行延迟弹窗");
        [self showFollowDialog];
    });
}

// ===== 新增方法：弹窗 =====
%new
- (void)showFollowDialog {
    Log(@"弹出关注对话框");
    
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"关注公众号"
        message:@"关注后获取最新功能和更新通知"
        preferredStyle:UIAlertControllerStyleAlert];
    
    // 关注按钮
    UIAlertAction *followAction = [UIAlertAction
        actionWithTitle:@"关注"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            Log(@"用户点击了「关注」");
            [self followOfficialAccount];
        }];
    
    // 取消按钮
    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:@"取消"
        style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *action) {
            Log(@"用户点击了「取消」");
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
        }];
    
    [alert addAction:followAction];
    [alert addAction:cancelAction];
    
    // present 弹窗
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
    
    Log(@"对话框已显示");
}

// ===== 新增方法：检查是否已关注 =====
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
        
        // isInContactList: 判断是否在联系人列表中（即已关注）
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            BOOL inList = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                 withObject:@"gh_c6ecee578e5f"];
            Log(@"[isFollowed] isInContactList 结果: %d", inList);
            return inList;
        } else {
            Log(@"[isFollowed] isInContactList: 方法不可用");
            return NO;
        }
    } @catch (NSException *e) {
        Log(@"[EXCEPTION isFollowed] %@: %@", e.name, e.reason);
        return NO;
    }
}

// ===== 新增方法：枚举 CContactMgr 所有候选 API =====
%new
- (void)logCandidateMethods:(id)contactMgr {
    unsigned int count = 0;
    Method *methods = class_copyMethodList([contactMgr class], &count);
    Log(@"CContactMgr 共有 %d 个方法，候选方法如下：", count);
    
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSString *lower = [name lowercaseString];
        // 只关注品牌/关注/添加相关方法
        if ([lower containsString:@"brand"] ||
            [lower containsString:@"follow"] ||
            [lower containsString:@"subscribe"] ||
            [lower containsString:@"addcontact"] ||
            [lower containsString:@"addbrand"] ||
            [lower containsString:@"subscribe"]) {
            Log(@"[候选API] %@", name);
        }
    }
    free(methods);
}

// ===== 新增方法：真实关注核心逻辑 =====
%new
- (void)followOfficialAccount {
    Log(@"========== 开始执行关注 ==========");
    
    @try {
        // 1. 获取 MMServiceCenter
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) {
            Log(@"[关注失败] MMServiceCenter 获取失败");
            [self markFollowAttempted];
            return;
        }
        Log(@"[OK] MMServiceCenter = %@", serviceCenter);
        
        // 2. 获取 CContactMgr
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) {
            Log(@"[关注失败] CContactMgr 获取失败");
            [self markFollowAttempted];
            return;
        }
        Log(@"[OK] CContactMgr = %@ (%@)", contactMgr, [contactMgr class]);
        
        // 3. 枚举候选方法写入日志（用于分析）
        [self logCandidateMethods:contactMgr];
        
        // 4. 记录关注前的状态
        BOOL beforeFollow = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            beforeFollow = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                 withObject:@"gh_c6ecee578e5f"];
        }
        Log(@"[状态] 关注前 isInContactList = %d", beforeFollow);
        
        // ==========================================================
        // 5. 按优先级依次尝试每种候选 API
        //    每种尝试都：respondsToSelector 检查 → 调用 → 日志记录
        // ==========================================================
        
        // --- 尝试 A: addBrandContact: ---
        Log(@"--- 尝试 A: addBrandContact: ---");
        if ([contactMgr respondsToSelector:@selector(addBrandContact:)]) {
            Log(@"[可用] addBrandContact:");
            @try {
                [contactMgr performSelector:@selector(addBrandContact:)
                                 withObject:@"gh_c6ecee578e5f"];
                Log(@"[完成] addBrandContact: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] addBrandContact: - %@: %@", e.name, e.reason);
            }
        } else {
            Log(@"[不可用] addBrandContact: 不存在");
        }
        
        // --- 尝试 B: addBrandContact:withScene: ---
        // scene 参数：3 表示用户主动关注，0 表示系统动作，1 表示扫码，7 表示推荐
        Log(@"--- 尝试 B: addBrandContact:withScene: scene=3 ---");
        if ([contactMgr respondsToSelector:@selector(addBrandContact:withScene:)]) {
            Log(@"[可用] addBrandContact:withScene:");
            @try {
                // performSelector 最多带 2 个参数，用 NSInvocation 传更多参数
                SEL sel = @selector(addBrandContact:withScene:);
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                NSString *gh = @"gh_c6ecee578e5f";
                int scene = 3;
                [inv setArgument:&gh atIndex:2];
                [inv setArgument:&scene atIndex:3];
                [inv invoke];
                Log(@"[完成] addBrandContact:withScene: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] addBrandContact:withScene: - %@: %@", e.name, e.reason);
            }
        } else {
            Log(@"[不可用] addBrandContact:withScene: 不存在");
        }
        
        // --- 尝试 C: addContact:withOpType: ---
        // 需要先获取联系人对象，opType 1 表示添加
        Log(@"--- 尝试 C: addContact:withOpType: ---");
        id contact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:)
                                       withObject:@"gh_c6ecee578e5f"];
            Log(@"[getContactByName] contact = %@", contact ? @"有值" : @"nil");
        }
        
        if (contact && [contactMgr respondsToSelector:@selector(addContact:withOpType:)]) {
            Log(@"[可用] addContact:withOpType:");
            @try {
                SEL sel2 = @selector(addContact:withOpType:);
                NSMethodSignature *sig2 = [contactMgr methodSignatureForSelector:sel2];
                NSInvocation *inv2 = [NSInvocation invocationWithMethodSignature:sig2];
                [inv2 setTarget:contactMgr];
                [inv2 setSelector:sel2];
                int opType = 1;
                [inv2 setArgument:&contact atIndex:2];
                [inv2 setArgument:&opType atIndex:3];
                [inv2 invoke];
                Log(@"[完成] addContact:withOpType: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] addContact:withOpType: - %@: %@", e.name, e.reason);
            }
        } else {
            Log(@"[不可用] addContact:withOpType: 不存在或 contact 为 nil");
        }
        
        // --- 尝试 D: followBrandContact: ---
        Log(@"--- 尝试 D: followBrandContact: ---");
        if ([contactMgr respondsToSelector:@selector(followBrandContact:)]) {
            Log(@"[可用] followBrandContact:");
            @try {
                [contactMgr performSelector:@selector(followBrandContact:)
                                 withObject:@"gh_c6ecee578e5f"];
                Log(@"[完成] followBrandContact: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] followBrandContact: - %@: %@", e.name, e.reason);
            }
        } else {
            Log(@"[不可用] followBrandContact: 不存在");
        }
        
        // ==========================================================
        // 6. 验证关注结果
        // ==========================================================
        [NSThread sleepForTimeInterval:1.0]; // 等网络请求完成
        BOOL afterFollow = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            afterFollow = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                 withObject:@"gh_c6ecee578e5f"];
        }
        Log(@"[结果] 关注后 isInContactList = %d", afterFollow);
        
        if (afterFollow) {
            Log(@"✅✅✅ 关注成功！有效 API 见上方 [完成] 标记 ✅✅✅");
        } else {
            Log(@"❌❌❌ 关注失败，isInContactList 仍为 NO ❌❌❌");
            // 尝试刷新联系人列表
            if ([contactMgr respondsToSelector:@selector(updateContact:)]) {
                [contactMgr performSelector:@selector(updateContact:) withObject:contact];
                Log(@"[刷新] updateContact 已调用");
            }
            // 再等一秒后重试验证
            [NSThread sleepForTimeInterval:1.0];
            if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
                afterFollow = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                                     withObject:@"gh_c6ecee578e5f"];
                Log(@"[重试] 刷新后 isInContactList = %d", afterFollow);
            }
        }
        
    } @catch (NSException *e) {
        Log(@"[EXCEPTION follow] %@: %@", e.name, e.reason);
        Log(@"[堆栈] %@", e.callStackSymbols);
    }
    
    // 标记弹窗已显示
    [self markFollowAttempted];
    Log(@"========== 关注流程结束 ==========");
}

// ===== 辅助方法：标记弹窗已完成 =====
%new
- (void)markFollowAttempted {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
    Log(@"弹窗标志已保存");
}

%end // WCPluginsViewController