#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>


#pragma mark - ===== 日志系统 =====

void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
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