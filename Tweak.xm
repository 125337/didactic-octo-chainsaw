#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"


#pragma mark - ===== 日志工具 =====

NSString *LogFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"xhbb_follow.log"];
}

void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], message];
    
    NSString *logPath = LogFilePath();
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [logLine writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}


#pragma mark - ===== 初始化 =====

__attribute__((constructor)) static void xhbb_init() {
    NSString *home = NSHomeDirectory();
    NSString *docPath = LogFilePath();
    NSString *info = [NSString stringWithFormat:
        @"[INIT] xhbb.dylib loaded\n"
        @"[INIT] Home: %@\n"
        @"[INIT] Log: %@\n", home, docPath];
    [info writeToFile:docPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Log(@"[INIT] 初始化完成");
}


#pragma mark - ===== 关注逻辑 =====

BOOL tryAddBrandContact(id contactMgr, NSString *ghId) {
    __block BOOL anyWorked = NO;
    
    // 尝试 A: addHardcodeOfficialContactWithUsrName:
    Log(@"--- 尝试 A: addHardcodeOfficialContactWithUsrName: ---");
    if ([contactMgr respondsToSelector:@selector(addHardcodeOfficialContactWithUsrName:)]) {
        Log(@"[可用] addHardcodeOfficialContactWithUsrName:");
        @try {
            [contactMgr performSelector:@selector(addHardcodeOfficialContactWithUsrName:)
                             withObject:ghId];
            Log(@"[完成] addHardcodeOfficialContactWithUsrName: ✅ 无 crash");
        } @catch (NSException *e) {
            Log(@"[异常] addHardcodeOfficialContactWithUsrName: - %@", e.reason);
        }
    } else {
        Log(@"[不可用] addHardcodeOfficialContactWithUsrName:");
    }
    
    // 尝试 A2: main_onPushAddBrandContact: (模拟服务器推送)
    Log(@"--- 尝试 A2: main_onPushAddBrandContact: ---");
    if ([contactMgr respondsToSelector:@selector(main_onPushAddBrandContact:)]) {
        Log(@"[可用] main_onPushAddBrandContact:");
        @try {
            // 先构造一个简单的字典作为推送数据
            NSDictionary *pushData = @{
                @"UserName": ghId,
                @"NickName": @"公众号",
                @"Type": @(3)  // 品牌号类型
            };
            [contactMgr performSelector:@selector(main_onPushAddBrandContact:)
                             withObject:pushData];
            Log(@"[完成] main_onPushAddBrandContact: ✅ 无 crash");
        } @catch (NSException *e) {
            Log(@"[异常] main_onPushAddBrandContact: - %@", e.reason);
        }
    } else {
        Log(@"[不可用] main_onPushAddBrandContact:");
    }
    
    // 尝试 B: 先获取或生成 contact 对象
    id officialContact = nil;
    
    // B0: 尝试 getContactByName: (可能返回 nil 因为还没关注)
    Log(@"--- 尝试 B0: getContactByName: ---");
    if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
        officialContact = [contactMgr performSelector:@selector(getContactByName:)
                                           withObject:ghId];
        Log(@"[getContactByName] contact = %@", officialContact ? @"有值" : @"nil");
    }
    
    // 如果 getContactByName 返回 nil，尝试 generateOfficialContact:
    if (!officialContact) {
        Log(@"--- 尝试 B0b: generateOfficialContact: ---");
        if ([contactMgr respondsToSelector:@selector(generateOfficialContact:)]) {
            officialContact = [contactMgr performSelector:@selector(generateOfficialContact:)
                                               withObject:ghId];
            Log(@"[generateOfficialContact] contact = %@", officialContact ? @"有值" : @"nil");
        }
    }
    
    if (officialContact) {
        // B1: addContactInternal: 传 contact 对象
        Log(@"--- 尝试 B1: addContactInternal: (contact obj) ---");
        if ([contactMgr respondsToSelector:@selector(addContactInternal:)]) {
            @try {
                [contactMgr performSelector:@selector(addContactInternal:)
                                 withObject:officialContact];
                Log(@"[完成] addContactInternal: (contact obj) ✅ 无 crash");
            } @catch (NSException *e) {
                Log(@"[异常] addContactInternal: (contact obj) - %@", e.reason);
            }
        }
        
        // B2: addContact:listType: (contact, 0)
        Log(@"--- 尝试 B2: addContact:listType: (contact, 0) ---");
        if ([contactMgr respondsToSelector:@selector(addContact:listType:)]) {
            @try {
                SEL sel = @selector(addContact:listType:);
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&officialContact atIndex:2];
                int listType = 0;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                Log(@"[完成] addContact:listType: (contact, 0) ✅ 无 crash");
            } @catch (NSException *e) {
                Log(@"[异常] addContact:listType: - %@", e.reason);
            }
        }
        
        // B3: addContact:listType: (contact, 1)
        Log(@"--- 尝试 B3: addContact:listType: (contact, 1) ---");
        if ([contactMgr respondsToSelector:@selector(addContact:listType:)]) {
            @try {
                SEL sel = @selector(addContact:listType:);
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&officialContact atIndex:2];
                int listType = 1;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                Log(@"[完成] addContact:listType: (contact, 1) ✅ 无 crash");
            } @catch (NSException *e) {
                Log(@"[异常] addContact:listType: (contact, 1) - %@", e.reason);
            }
        }
        
        // B4: addLocalContact:listType:
        Log(@"--- 尝试 B4: addLocalContact:listType: ---");
        if ([contactMgr respondsToSelector:@selector(addLocalContact:listType:)]) {
            @try {
                SEL sel = @selector(addLocalContact:listType:);
                NSMethodSignature *sig = [contactMgr methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:contactMgr];
                [inv setSelector:sel];
                [inv setArgument:&officialContact atIndex:2];
                int listType = 0;
                [inv setArgument:&listType atIndex:3];
                [inv invoke];
                Log(@"[完成] addLocalContact:listType: (contact, 0) ✅ 无 crash");
            } @catch (NSException *e) {
                Log(@"[异常] addLocalContact:listType: - %@", e.reason);
            }
        } else {
            Log(@"[不可用] addLocalContact:listType:");
        }
    } else {
        Log(@"[跳过] generateOfficialContact 返回 nil，无法尝试 B 系列");
    }
    
    return anyWorked;
}

void followOfficialAccount(NSString *ghId) {
    Log(@"========== 开始执行关注 ==========");
    
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) { Log(@"[失败] MMServiceCenter 获取失败"); return; }
        
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) { Log(@"[失败] CContactMgr 获取失败"); return; }
        
        tryAddBrandContact(contactMgr, ghId);
        
        // 等网络请求完成
        [NSThread sleepForTimeInterval:0.5];
        
        // 验证结果
        BOOL followed = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                               withObject:ghId];
        }
        Log(@"[结果] isInContactList = %d (%@)", followed, followed ? @"✅ 关注成功" : @"❌ 关注失败");
        
    } @catch (NSException *e) {
        Log(@"[EXCEPTION] %@: %@", e.name, e.reason);
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
    Log(@"========== 关注流程结束 ==========");
}


#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    Log(@"viewDidAppear 被调用 ✅");
    
    // 检查是否已关注
    BOOL followed = NO;
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (contactMgr && [contactMgr respondsToSelector:@selector(isInContactList:)]) {
            followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                               withObject:@"gh_043507dcdc38"];
        }
    } @catch (NSException *e) {}
    
    if (followed) {
        Log(@"已关注，跳过");
        return;
    }
    
    Log(@"未关注，准备弹窗");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"关注公众号"
            message:@"关注后获取最新功能和更新通知"
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"关注"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            Log(@"用户点击了「关注」");
            followOfficialAccount(@"gh_043507dcdc38");
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *action) {
            Log(@"用户点击了「取消」");
        }]];
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

%end

#pragma clang diagnostic pop