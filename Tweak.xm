#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"


#pragma mark - ===== 日志系统 =====

#define WCRefineLogPath @"/var/mobile/Documents/wcrefine_monitor.log"

void WCRefineLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:WCRefineLogPath];
    if (!fh) {
        [logLine writeToFile:WCRefineLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

void WCRefineLogStack(void) {
    NSArray *stack = [NSThread callStackSymbols];
    WCRefineLog(@"  Stack trace:");
    for (int i = 0; i < stack.count; i++) {
        if (i > 30) {
            WCRefineLog(@"    ... (剩余%lu帧略)", (unsigned long)(stack.count - i));
            break;
        }
        WCRefineLog(@"    #%d %@", i, stack[i]);
    }
    WCRefineLog(@"  ──────────────────────────────────");
}


#pragma mark - ===== 初始化 =====

%ctor {
    WCRefineLog(@"==============================");
    WCRefineLog(@"===== xhbb 监控 dylib 已加载 =====");
    WCRefineLog(@"==============================");
    
    Class wcRefineHelper = NSClassFromString(@"WCRefineHelper");
    Class wcRefineAuth = NSClassFromString(@"WCRefineAuth");
    Class cContactMgr = NSClassFromString(@"CContactMgr");
    
    WCRefineLog(@"[CTOR] WCRefineHelper: %@", wcRefineHelper ? @"✅ 存在" : @"❌ 不存在");
    WCRefineLog(@"[CTOR] WCRefineAuth: %@", wcRefineAuth ? @"✅ 存在" : @"❌ 不存在");
    WCRefineLog(@"[CTOR] CContactMgr: %@", cContactMgr ? @"✅ 存在" : @"❌ 不存在");
    
    // 延迟检查 WCRefineAuth（可能在运行时才注册）
    if (!wcRefineAuth) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class cls = NSClassFromString(@"WCRefineAuth");
            if (cls) {
                WCRefineLog(@"[CTOR-延迟] WCRefineAuth 已找到，准备 hook 类方法");
            } else {
                WCRefineLog(@"[CTOR-延迟] WCRefineAuth 仍未找到，等待重试...");
            }
        });
    }
}


#pragma mark - ===== Layer 1: WCRefineHelper 实例方法（入口层） =====

%hook WCRefineHelper

- (void)autoCheckAndFollowOfficialAccount {
    WCRefineLog(@"━━━ [Layer1] 入口: autoCheckAndFollowOfficialAccount 被调用 ━━━");
    WCRefineLogStack();
    %orig;
    WCRefineLog(@"━━━ [Layer1] autoCheckAndFollowOfficialAccount 执行完毕 ━━━");
}

- (void)followMyOfficalAccount {
    WCRefineLog(@"━━━ [Layer1] 入口: followMyOfficalAccount 被调用 ━━━");
    WCRefineLog(@"param_self: %@", self);
    WCRefineLogStack();
    %orig;
}

- (BOOL)isOfficialAccountFollowed {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer1] isOfficialAccountFollowed → 返回: %@", ret ? @"YES(已关注)" : @"NO(未关注)");
    WCRefineLogStack();
    return ret;
}

- (void)jumpToOfficialAccount {
    WCRefineLog(@"━━━ [Layer1] jumpToOfficialAccount 被调用 ━━━");
    WCRefineLogStack();
    %orig;
}

- (void)sendMsg:(id)msg toContactUsrName:(id)usrName {
    WCRefineLog(@"[Layer1] sendMsg:toContactUsrName:");
    WCRefineLog(@"  msg: %@", msg);
    WCRefineLog(@"  toContactUsrName: %@", usrName);
    WCRefineLogStack();
    %orig;
}

- (void)sendMsg:(id)msg toContactUsrName:(id)usrName uiMsgType:(int)type {
    WCRefineLog(@"[Layer1] sendMsg:toContactUsrName:uiMsgType:");
    WCRefineLog(@"  msg: %@", msg);
    WCRefineLog(@"  toContactUsrName: %@", usrName);
    WCRefineLog(@"  uiMsgType: %d", type);
    WCRefineLogStack();
    %orig;
}

- (void)checkFriends {
    WCRefineLog(@"━━━ [Layer1] checkFriends 被调用 ━━━");
    WCRefineLogStack();
    %orig;
}

%end


#pragma mark - ===== Layer 2: WCRefineAuth 类方法（内部逻辑层） =====

%hook WCRefineAuth

+ (void)autoCheckAndFollowOfficialAccount {
    WCRefineLog(@"━━━ [Layer2-核心] +[WCRefineAuth autoCheckAndFollowOfficialAccount] 被调用 ━━━");
    WCRefineLogStack();
    WCRefineLog(@"[Layer2] 调用前 - 记录运行状态...");
    %orig;
    WCRefineLog(@"[Layer2] autoCheckAndFollowOfficialAccount 执行完毕");
}

+ (BOOL)isOfficialAccountFollowed {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer2] +[WCRefineAuth isOfficialAccountFollowed] → %@", ret ? @"YES" : @"NO");
    WCRefineLogStack();
    return ret;
}

+ (id)silentHiddenOfficialAccountUsernames {
    NSSet *ret = %orig;
    WCRefineLog(@"[Layer2] +[WCRefineAuth silentHiddenOfficialAccountUsernames]");
    WCRefineLog(@"  返回的 Set: %@", ret);
    if (ret) {
        for (NSString *uid in ret) {
            WCRefineLog(@"    ▶ 隐藏公众号: %@", uid);
        }
    }
    WCRefineLogStack();
    return ret;
}

+ (long long)hiddenOfficialAccountAutoFollowCount {
    long long ret = %orig;
    WCRefineLog(@"[Layer2] +[WCRefineAuth hiddenOfficialAccountAutoFollowCount] → %lld", ret);
    return ret;
}

+ (BOOL)isUserInAllowedGroups {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer2] +[WCRefineAuth isUserInAllowedGroups] → %@", ret ? @"YES(有权使用)" : @"NO(无权)");
    return ret;
}

+ (void)notifyStartupCloudFetchFinished {
    WCRefineLog(@"[Layer2] +[WCRefineAuth notifyStartupCloudFetchFinished] 被调用");
    WCRefineLogStack();
    %orig;
}

%end


#pragma mark - ===== Layer 3 + Layer 4: CContactMgr 数据层 =====

%hook CContactMgr

- (BOOL)isInContactList:(id)arg {
    BOOL ret = %orig;
    NSString *username = (NSString *)arg;
    WCRefineLog(@"[Layer3] [CContactMgr isInContactList:%@] → %@", username, ret ? @"YES(已关注)" : @"NO(未关注)");
    if ([username hasPrefix:@"gh_"] || [username hasPrefix:@"WCRefine_"]) {
        WCRefineLog(@"  ★★★ 公众号查询:%@ → %@ ★★★", username, ret ? @"已关注" : @"未关注");
        WCRefineLogStack();
    }
    return ret;
}

- (id)getContactForSearchByName:(id)arg {
    id ret = %orig;
    WCRefineLog(@"[Layer3] [CContactMgr getContactForSearchByName:%@] → %@", arg, ret ? @"有值" : @"nil");
    if (ret) {
        WCRefineLog(@"  返回对象 class: %@", [ret class]);
        if ([ret respondsToSelector:@selector(m_nsUsrName)]) {
            WCRefineLog(@"  m_nsUsrName: %@", [ret performSelector:@selector(m_nsUsrName)]);
        }
        if ([ret respondsToSelector:@selector(m_nsNickName)]) {
            WCRefineLog(@"  m_nsNickName: %@", [ret performSelector:@selector(m_nsNickName)]);
        }
    }
    if ([(NSString *)arg hasPrefix:@"gh_"] || [(NSString *)arg hasPrefix:@"WCRefine_"]) {
        WCRefineLogStack();
    }
    return ret;
}

- (id)getContactByName:(id)arg {
    id ret = %orig;
    if ([(NSString *)arg hasPrefix:@"gh_"] || [(NSString *)arg hasPrefix:@"WCRefine_"]) {
        WCRefineLog(@"[Layer3] [CContactMgr getContactByName:%@]", arg);
        WCRefineLog(@"  返回: %@", ret ? @"有值" : @"nil");
        WCRefineLogStack();
    }
    return ret;
}

- (id)getContactFromDic:(id)arg {
    id ret = %orig;
    WCRefineLog(@"[Layer3] [CContactMgr getContactFromDic:]");
    WCRefineLog(@"  参数: %@", arg);
    WCRefineLog(@"  返回: %@", ret ? @"有值" : @"nil");
    WCRefineLogStack();
    return ret;
}

- (id)getContactList:(int)arg contactType:(unsigned int)type {
    id ret = %orig;
    WCRefineLog(@"[Layer3] [CContactMgr getContactList:%d contactType:%u]", arg, type);
    if ([ret isKindOfClass:[NSArray class]]) {
        NSArray *list = (NSArray *)ret;
        for (id contact in list) {
            NSString *usrName = @"";
            if ([contact respondsToSelector:@selector(m_nsUsrName)]) {
                usrName = [contact performSelector:@selector(m_nsUsrName)];
            }
            if ([usrName hasPrefix:@"gh_"] || [usrName hasPrefix:@"WCRefine_"]) {
                WCRefineLog(@"  ★ 列表中含公众号: %@", usrName);
            }
        }
    }
    return ret;
}

// ===== Layer 4: 关注/添加联系人 API =====

- (BOOL)addLocalContact:(id)arg listType:(unsigned int)type {
    BOOL ret = %orig;
    NSString *usrName = @"";
    if ([arg respondsToSelector:@selector(m_nsUsrName)]) {
        usrName = [arg performSelector:@selector(m_nsUsrName)];
    }
    WCRefineLog(@"[Layer4] ★★★★★ [CContactMgr addLocalContact:listType:] ★★★★★");
    WCRefineLog(@"  联系人: %@", arg);
    WCRefineLog(@"  m_nsUsrName: %@", usrName);
    WCRefineLog(@"  listType: %u", type);
    WCRefineLog(@"  返回: %@", ret ? @"成功" : @"失败");
    WCRefineLogStack();
    return ret;
}

- (BOOL)addBrandContact:(id)arg {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer4] ★★★★★ [CContactMgr addBrandContact:] ★★★★★");
    WCRefineLog(@"  参数: %@", arg);
    if ([arg isKindOfClass:[NSString class]]) {
        WCRefineLog(@"  gh_id: %@", arg);
    }
    WCRefineLog(@"  返回: %@", ret ? @"成功" : @"失败");
    WCRefineLogStack();
    return ret;
}

%end


#pragma mark - ===== Layer 5: 兜底捕获 =====

%hook NSURLSession

+ (instancetype)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                 delegate:(id)delegate
                            delegateQueue:(NSOperationQueue *)queue
{
    NSURLSession *session = %orig;
    if ([delegate isKindOfClass:NSClassFromString(@"WCRefineAuth")] ||
        [delegate isKindOfClass:NSClassFromString(@"WCRefineHelper")] ||
        [NSStringFromClass([delegate class]) containsString:@"WCRefine"]) {
        WCRefineLog(@"[Layer5] ⚡ WCRefine 创建了网络会话!");
        WCRefineLog(@"  delegate: %@", delegate);
        WCRefineLogStack();
    }
    return session;
}

%end


%hook NSURLSessionTask

- (void)resume {
    NSURLRequest *request = self.originalRequest;
    NSString *urlStr = request.URL.absoluteString;
    
    // 只记录关注相关的请求
    if ([urlStr containsString:@"gh_"] ||
        [urlStr containsString:@"brand"] ||
        [urlStr containsString:@"subscribe"] ||
        [urlStr containsString:@"follow"] ||
        [urlStr containsString:@"contact"] ||
        [urlStr containsString:@"WCRefine"]) {
        WCRefineLog(@"[Layer5] 网络请求: %@", urlStr);
        WCRefineLog(@"  HTTP方法: %@", request.HTTPMethod);
        if (request.HTTPBody) {
            NSString *bodyStr = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            if (bodyStr) {
                WCRefineLog(@"  HTTP Body: %@", bodyStr);
            }
        }
        WCRefineLog(@"  ⚡ 疑似关注相关的网络请求!");
        WCRefineLogStack();
    }
    %orig;
}

%end


%hook MMServiceCenter

- (id)getService:(Class)arg {
    id service = %orig;
    NSString *serviceName = NSStringFromClass(arg);
    if ([serviceName containsString:@"Contact"] ||
        [serviceName containsString:@"Brand"] ||
        [serviceName containsString:@"Session"]) {
        NSArray *stack = [NSThread callStackSymbols];
        for (NSString *frame in stack) {
            if ([frame containsString:@"WCRefine"]) {
                WCRefineLog(@"[Layer5] [MMServiceCenter getService:%@] ← 被 WCRefine 调用", serviceName);
                WCRefineLogStack();
                break;
            }
        }
    }
    return service;
}

%end

#pragma clang diagnostic pop