#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>


#pragma mark - ===== dylib 加载检测 =====

// 构造函数：dylib 加载时立即执行（替代 %ctor，避免 Xcode26 兼容问题）
__attribute__((constructor)) static void xhbb_init() {
    // 用 C 文件 API 确保绝对能写
    FILE *f = fopen("/tmp/xhbb_load.log", "a");
    if (f) {
        fprintf(f, "xhbb.dylib LOADED\n");
        fclose(f);
    }
    
    // 检查目标类是否存在
    Class cls = NSClassFromString(@"WCPluginsViewController");
    if (cls) {
        FILE *f2 = fopen("/tmp/xhbb_load.log", "a");
        if (f2) {
            fprintf(f2, "WCPluginsViewController class: FOUND\n");
            fclose(f2);
        }
    } else {
        FILE *f2 = fopen("/tmp/xhbb_load.log", "a");
        if (f2) {
            fprintf(f2, "WCPluginsViewController class: NOT FOUND!\n");
            fprintf(f2, "Available classes with 'Plugin' in name:\n");
            fclose(f2);
        }
        // 枚举所有已注册类，找包含 Plugin 的类名
        int classCount = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * classCount);
        objc_getClassList(classes, classCount);
        FILE *f3 = fopen("/tmp/xhbb_load.log", "a");
        if (f3) {
            for (int i = 0; i < classCount; i++) {
                const char *name = class_getName(classes[i]);
                if (strstr(name, "Plugin") || strstr(name, "Brand") || strstr(name, "WCBiz")) {
                    fprintf(f3, "  - %s\n", name);
                }
            }
            fclose(f3);
        }
        free(classes);
    }
}


#pragma mark - ===== 日志系统（多路径写入） =====

void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // 写入 /var/mobile/Documents/
    NSString *path1 = @"/var/mobile/Documents/xhbb_follow.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path1];
    if (!fh) {
        [logLine writeToFile:path1 atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    
    // 同时写入 /tmp/ 作为后备
    NSString *path2 = @"/tmp/xhbb_follow.log";
    NSFileHandle *fh2 = [NSFileHandle fileHandleForWritingAtPath:path2];
    if (!fh2) {
        [logLine writeToFile:path2 atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh2 seekToEndOfFile];
        [fh2 writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh2 closeFile];
    }
}


#pragma mark - ===== Helper 类（避免使用 Logos new 语法） =====

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
        
        // 尝试 A: addBrandContact:
        if ([contactMgr respondsToSelector:@selector(addBrandContact:)]) {
            @try {
                [contactMgr performSelector:@selector(addBrandContact:)
                                 withObject:@"gh_c6ecee578e5f"];
                Log(@"[完成] addBrandContact: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] addBrandContact: - %@", e.reason);
            }
        }
        
        // 尝试 B: addBrandContact:withScene:
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
                Log(@"[完成] addBrandContact:withScene: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] addBrandContact:withScene: - %@", e.reason);
            }
        }
        
        // 尝试 C: addContact:withOpType:
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
                Log(@"[完成] addContact:withOpType: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] addContact:withOpType: - %@", e.reason);
            }
        }
        
        // 尝试 D: followBrandContact:
        if ([contactMgr respondsToSelector:@selector(followBrandContact:)]) {
            @try {
                [contactMgr performSelector:@selector(followBrandContact:)
                                 withObject:@"gh_c6ecee578e5f"];
                Log(@"[完成] followBrandContact: 调用成功");
            } @catch (NSException *e) {
                Log(@"[异常] followBrandContact: - %@", e.reason);
            }
        }
        
        // 验证
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
    
    BOOL shown = [[NSUserDefaults standardUserDefaults] boolForKey:@"xhbb_follow_shown"];
    if (shown) {
        Log(@"弹窗已显示过，跳过");
        return;
    }
    
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