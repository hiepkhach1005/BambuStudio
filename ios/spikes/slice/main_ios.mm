#import <UIKit/UIKit.h>
#import <os/proc.h>
#include <cstdlib>
#include "slice_core.hpp"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow   *window;
@property (strong, nonatomic) UITextView *text;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts
{
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc = [UIViewController new];
    self.text            = [[UITextView alloc] initWithFrame:vc.view.bounds];
    self.text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.text.editable   = NO;
    self.text.font       = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightRegular];
    [vc.view addSubview:self.text];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    app.idleTimerDisabled = YES;
    NSThread *t = [[NSThread alloc] initWithTarget:self selector:@selector(work) object:nil];
    t.stackSize = 64 << 20; // the desktop app slices on a large stack too
    [t start];
    return YES;
}
- (void)work
{
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *res  = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"bbl_res"];
        NSString *mods = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"models"];
        FILE     *f    = fopen([docs stringByAppendingPathComponent:@"log.txt"].UTF8String, "w");
        const int r = run_slice_cases(res.UTF8String, mods.UTF8String, docs.UTF8String, [&](const std::string &s) {
            NSString *line = [NSString stringWithFormat:@"%s [free %zu MB]\n", s.c_str(), os_proc_available_memory() >> 20];
            fputs(line.UTF8String, stdout); fflush(stdout);
            if (f) { fputs(line.UTF8String, f); fflush(f); }
            dispatch_async(dispatch_get_main_queue(), ^{ self.text.text = [self.text.text stringByAppendingString:line]; });
        });
        if (f) fclose(f);
        if (getenv("SLICE_EXIT")) exit(r);
    }
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
