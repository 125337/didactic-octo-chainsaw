#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>


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


#pragma mark - ===== WCPluginsViewController Hook =====

%hook WCPluginsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    Log(@"viewDidAppear 被调用 ✅ WCPluginsViewController 页面已打开");
    
    // 获取 CContactMgr 并 dump 所有方法名
    @try {
        id serviceCenter = [NSClassFromString(@"MMServiceCenter") performSelector:@selector(defaultCenter)];
        if (!serviceCenter) { Log(@"[ERROR] MMServiceCenter 获取失败"); return; }
        
        id contactMgr = [serviceCenter performSelector:@selector(getService:)
                                            withObject:NSClassFromString(@"CContactMgr")];
        if (!contactMgr) { Log(@"[ERROR] CContactMgr 获取失败"); return; }
        
        unsigned int count = 0;
        Method *methods = class_copyMethodList([contactMgr class], &count);
        Log(@"===== CContactMgr 全部 %d 个方法 =====", count);
        
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            Log(@"  [%d] %@", i, name);
        }
        free(methods);
        
        // 检查 isInContactList: 返回类型
        Method m = NULL;
        if (count > 0) m = methods[0]; // placeholder, we freed it already
        // Re-get method for isInContactList:
        Method isInContactMethod = class_getInstanceMethod([contactMgr class], @selector(isInContactList:));
        if (isInContactMethod) {
            const char *returnType = method_copyReturnType(isInContactMethod);
            Log(@"[isInContactList:] return type: %s", returnType);
            free((void *)returnType);
        } else {
            Log(@"[INFO] isInContactList: 方法不存在");
        }
        
    } @catch (NSException *e) {
        Log(@"[EXCEPTION] %@: %@", e.name, e.reason);
    }
}

%end