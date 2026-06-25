#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>


#pragma mark - ===== 日志工具（使用 App 真实沙盒路径） =====

/// 获取 App 沙盒内的 Documents 路径（真正的可写目录）
NSString *LogFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    return [docDir stringByAppendingPathComponent:@"xhbb_follow.log"];
}

void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // 写入 App 真正的 Documents/xhbb_follow.log
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


#pragma mark - ===== dylib 加载检测（替代 %ctor） =====

__attribute__((constructor)) static void xhbb_init() {
    // 获取可写目录路径作为检测证据
    NSString *docPath = LogFilePath();
    NSString *home = NSHomeDirectory();
    NSString *info = [NSString stringWithFormat:
        @"[INIT] xhbb.dylib loaded\n"
        @"[INIT] Home: %@\n"
        @"[INIT] Log: %@\n",
        home, docPath];
    
    [info writeToFile:docPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // 检查目标类是否存在
    Class cls = NSClassFromString(@"WCPluginsViewController");
    if (cls) {
        Log(@"[INIT] WCPluginsViewController FOUND  ✅");
    } else {
        Log(@"[INIT] WCPluginsViewController NOT FOUND  ❌");
        
        // 枚举含 Plugin/Brand/WCBiz 的类
        int count = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * count);
        objc_getClassList(classes, count);
        for (int i = 0; i < count; i++) {
            const char *name = class_getName(classes[i]);
            if (strstr(name, "Plugin") || strstr(name, "Brand") || strstr(name, "WCBiz")) {
                Log(@"[INIT]   similar class: %s", name);
            }
        }
        free(classes);
    }
}


#pragma mark - ===== Helper 类 =====

@interface XHBBHelper : NSObject
@end

@implementation XHBBHelper

+ (BOOL)isFollowed {
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) return NO;
        
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) return NO;
        
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            return (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                         withObject:@"gh_c6ecee578e5f"];
        }
    } @catch (NSException *e) {
        Log(@"[EXCEPTION isFollowed] %@: %@", e.name, e.reason);
    }
    return NO;
}

+ (void)logCandidateMethods:(id)contactMgr {
    unsigned int count = 0;
    Method *methods = class_copyMethodList([contactMgr class], &count);
    Log(@"CContactMgr 共有 %d 个方法", count);
    
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSString *lower = [name lowercaseString];
        if ([lower containsString:@"brand"] ||
            [lower containsString:@"follow"] ||
            [lower containsString:@"subscribe"] ||
            [lower containsString:@"addcontact"] ||
            [lower containsString:@"addbrand"]) {
            Log(@"[候选API] %@", name);
        }
    }
    free(methods);
}

+ (void)followOfficialAccount {
    Log(@"========== 开始执行关注 ==========");
    
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) { Log(@"[关注失败] MMServiceCenter 获取失败"); return; }
        
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) { Log(@"[关注失败] CContactMgr 获取失败"); return; }
        
        [self logCandidateMethods:contactMgr];
        
        if ([contactMgr respondsToSelector:@selector(addBrandContact:)]) {
            @try {
                [contactMgr performSelector:@selector(addBrandContact:)
                                 withObject:@"gh_c6ecee578e5f"];
                Log(@"[完成] addBrandContact:");
            } @catch (NSException *e) {
                Log(@"[异常] addBrandContact: - %@", e.reason);
            }
        }
        
        if ([contactMgr respondsToSelector:@selector(addBrandContact:withScene:)]) {
            @try {
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
                Log(@"[完成] addBrandContact:withScene:");
            } @catch (NSException *e) {
                Log(@"[异常] addBrandContact:withScene: - %@", e.reason);
            }
        }
        
        id contact = nil;
        if ([contactMgr respondsToSelector:@selector(getContactByName:)]) {
            contact = [contactMgr performSelector:@selector(getContactByName:)
                                       withObject:@"gh_c6ecee578e5f"];
        }
        if (contact && [contactMgr respondsToSelector:@selector(addContact:withOpType:)]) {
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
                Log(@"[完成] addContact:withOpType:");
            } @catch (NSException *e) {
                Log(@"[异常] addContact:withOpType: - %@", e.reason);
            }
        }
        
        if ([contactMgr respondsToSelector:@selector(followBrandContact:)]) {
            @try {
                [contactMgr performSelector:@selector(followBrandContact:)
                                 withObject:@"gh_c6ecee578e5f"];
                Log(@"[完成] followBrandContact:");
            } @catch (NSException *e) {
                Log(@"[异常] followBrandContact: - %@", e.reason);
            }
        }
        
        [NSThread sleepForTimeInterval:2.0];
        BOOL followed = NO;
        if ([contactMgr respondsToSelector:@selector(isInContactList:)]) {
            followed = (BOOL)[contactMgr performSelector:@selector(isInContactList:)
                                               withObject:@"gh_c6ecee578e5f"];
        }
        Log(@"[结果] isInContactList = %d", followed);
        
    } @catch (NSException *e) {
        Log(@"[EXCEPTION] %@: %@", e.name, e.reason);
    }
}

+ (void)showFollowDialogForVC:(UIViewController *)viewController {
    Log(@"弹出关注对话框");
    
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"关注公众号"
        message:@"关注后获取最新功能和更新通知"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"关注"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        Log(@"用户点击了「关注」");
        [XHBBHelper followOfficialAccount];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        Log(@"用户点击了「取消」");
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
    }]];
    
    [viewController presentViewController:alert animated:YES completion:nil];
}

@end


#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    Log(@"viewDidAppear 被调用");
    
    if ([XHBBHelper isFollowed]) {
        Log(@"已关注，标记跳过");
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"xhbb_follow_shown"];
        return;
    }
    
    Log(@"未关注，准备弹窗");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [XHBBHelper showFollowDialogForVC:(UIViewController *)self];
    });
}

%end