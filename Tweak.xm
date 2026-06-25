#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"


#pragma mark - ===== 异步日志系统 =====

static NSString *_logPath;
static dispatch_queue_t _logQueue;

static NSString *GetLogPath(void) {
    if (!_logPath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _logPath = [[paths firstObject] stringByAppendingPathComponent:@"wcrefine_monitor.log"];
    }
    return _logPath;
}

void WCRefineLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
void WCRefineLogStack(void);

void WCRefineLog(NSString *format, ...) {
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

void WCRefineLogStack(void) {
    NSArray *stack = [NSThread callStackSymbols];
    WCRefineLog(@"  Stack trace:");
    for (int i = 0; i < stack.count && i < 15; i++) {
        WCRefineLog(@"    #%d %@", i, stack[i]);
    }
    WCRefineLog(@"  ──────────────────────────────────");
}


#pragma mark - ===== 初始化 =====

%ctor {
    _logQueue = dispatch_queue_create("com.xhbb.logqueue", DISPATCH_QUEUE_SERIAL);
    
    WCRefineLog(@"==============================");
    WCRefineLog(@"===== xhbb 监控 dylib 已加载 =====");
    WCRefineLog(@"日志路径: %@", GetLogPath());
    WCRefineLog(@"==============================");
    
    Class wcRefineHelper = NSClassFromString(@"WCRefineHelper");
    Class wcRefineAuth = NSClassFromString(@"WCRefineAuth");
    Class cContactMgr = NSClassFromString(@"CContactMgr");
    
    WCRefineLog(@"[CTOR] WCRefineHelper: %@", wcRefineHelper ? @"✅ 存在" : @"❌ 不存在");
    WCRefineLog(@"[CTOR] WCRefineAuth: %@", wcRefineAuth ? @"✅ 存在" : @"❌ 不存在");
    WCRefineLog(@"[CTOR] CContactMgr: %@", cContactMgr ? @"✅ 存在" : @"❌ 不存在");
    
    // 延迟检查 WCRefineAuth
    if (!wcRefineAuth) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class cls = NSClassFromString(@"WCRefineAuth");
            WCRefineLog(@"[CTOR-延迟] WCRefineAuth: %@", cls ? @"✅ 已找到" : @"❌ 仍未找到");
        });
    }
}


#pragma mark - ===== Layer 1: WCRefineHelper 实例方法 =====

%hook WCRefineHelper

- (void)autoCheckAndFollowOfficialAccount {
    WCRefineLog(@"━━━ [Layer1] autoCheckAndFollowOfficialAccount 被调用 ━━━");
    WCRefineLogStack();
    %orig;
    WCRefineLog(@"━━━ [Layer1] autoCheckAndFollowOfficialAccount 执行完毕 ━━━");
}

- (void)followMyOfficalAccount {
    WCRefineLog(@"━━━ [Layer1] followMyOfficalAccount 被调用 ━━━");
    WCRefineLogStack();
    %orig;
}

- (BOOL)isOfficialAccountFollowed {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer1] isOfficialAccountFollowed → %@", ret ? @"YES" : @"NO");
    return ret;
}

- (void)jumpToOfficialAccount {
    WCRefineLog(@"[Layer1] jumpToOfficialAccount 被调用");
    WCRefineLogStack();
    %orig;
}

- (void)sendMsg:(id)msg toContactUsrName:(id)usrName {
    WCRefineLog(@"[Layer1] sendMsg:toContactUsrName:%@", usrName);
    WCRefineLogStack();
    %orig;
}

- (void)sendMsg:(id)msg toContactUsrName:(id)usrName uiMsgType:(int)type {
    WCRefineLog(@"[Layer1] sendMsg:toContactUsrName:%@ uiMsgType:%d", usrName, type);
    WCRefineLogStack();
    %orig;
}

- (void)checkFriends {
    WCRefineLog(@"[Layer1] checkFriends 被调用");
    %orig;
}

%end


#pragma mark - ===== Layer 2: WCRefineAuth 类方法 =====

%hook WCRefineAuth

+ (void)autoCheckAndFollowOfficialAccount {
    WCRefineLog(@"━━━ [Layer2] +autoCheckAndFollowOfficialAccount 被调用 ━━━");
    WCRefineLogStack();
    %orig;
    WCRefineLog(@"[Layer2] +autoCheckAndFollowOfficialAccount 执行完毕");
}

+ (BOOL)isOfficialAccountFollowed {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer2] +isOfficialAccountFollowed → %@", ret ? @"YES" : @"NO");
    return ret;
}

+ (id)silentHiddenOfficialAccountUsernames {
    NSSet *ret = %orig;
    WCRefineLog(@"[Layer2] +silentHiddenOfficialAccountUsernames: %@", ret);
    return ret;
}

+ (long long)hiddenOfficialAccountAutoFollowCount {
    long long ret = %orig;
    WCRefineLog(@"[Layer2] +hiddenOfficialAccountAutoFollowCount → %lld", ret);
    return ret;
}

+ (BOOL)isUserInAllowedGroups {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer2] +isUserInAllowedGroups → %@", ret ? @"YES" : @"NO");
    return ret;
}

+ (void)notifyStartupCloudFetchFinished {
    WCRefineLog(@"[Layer2] +notifyStartupCloudFetchFinished");
    %orig;
}

%end


#pragma mark - ===== Layer 3 + Layer 4: CContactMgr =====

%hook CContactMgr

// 只记录公众号相关的查询，避免高频日志卡死
- (BOOL)isInContactList:(id)arg {
    BOOL ret = %orig;
    NSString *username = (NSString *)arg;
    if ([username hasPrefix:@"gh_"] || [username hasPrefix:@"WCRefine_"]) {
        WCRefineLog(@"[Layer3] ★ isInContactList:%@ → %@", username, ret ? @"YES" : @"NO");
        WCRefineLogStack();
    }
    return ret;
}

- (id)getContactForSearchByName:(id)arg {
    id ret = %orig;
    NSString *name = (NSString *)arg;
    if ([name hasPrefix:@"gh_"] || [name hasPrefix:@"WCRefine_"]) {
        WCRefineLog(@"[Layer3] ★ getContactForSearchByName:%@ → %@", name, ret ? @"有值" : @"nil");
        if (ret) {
            if ([ret respondsToSelector:@selector(m_nsUsrName)]) {
                WCRefineLog(@"  m_nsUsrName: %@", [ret performSelector:@selector(m_nsUsrName)]);
            }
        }
        WCRefineLogStack();
    }
    return ret;
}

- (id)getContactByName:(id)arg {
    id ret = %orig;
    NSString *name = (NSString *)arg;
    if ([name hasPrefix:@"gh_"] || [name hasPrefix:@"WCRefine_"]) {
        WCRefineLog(@"[Layer3] ★ getContactByName:%@ → %@", name, ret ? @"有值" : @"nil");
        WCRefineLogStack();
    }
    return ret;
}

// Layer 4: 关注 API — 无论如何都记录
- (BOOL)addLocalContact:(id)arg listType:(unsigned int)type {
    BOOL ret = %orig;
    NSString *usrName = @"";
    if ([arg respondsToSelector:@selector(m_nsUsrName)]) {
        usrName = [arg performSelector:@selector(m_nsUsrName)];
    }
    WCRefineLog(@"[Layer4] ★★★★★ addLocalContact:listType:%u ★★★★★", type);
    WCRefineLog(@"  m_nsUsrName: %@  返回: %@", usrName, ret ? @"成功" : @"失败");
    WCRefineLogStack();
    return ret;
}

- (BOOL)addBrandContact:(id)arg {
    BOOL ret = %orig;
    WCRefineLog(@"[Layer4] ★★★★★ addBrandContact:%@ → %@", arg, ret ? @"成功" : @"失败");
    WCRefineLogStack();
    return ret;
}

%end


#pragma mark - ===== Layer 5: 兜底捕获 =====

%hook MMServiceCenter

- (id)getService:(Class)arg {
    id service = %orig;
    NSString *serviceName = NSStringFromClass(arg);
    if ([serviceName containsString:@"Contact"] || [serviceName containsString:@"Brand"]) {
        NSArray *stack = [NSThread callStackSymbols];
        for (NSString *frame in stack) {
            if ([frame containsString:@"WCRefine"]) {
                WCRefineLog(@"[Layer5] getService:%@ ← WCRefine 调用", serviceName);
                WCRefineLogStack();
                break;
            }
        }
    }
    return service;
}

%end

#pragma clang diagnostic pop