#import "Bridge.h"
#include "Engine.hpp"
#include <pthread.h>

static NSString *ns(const std::string &s) { return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"{\"error\":\"bad text\"}"; }
static NSData   *dat(const std::vector<float> &v) { return [NSData dataWithBytes:v.data() length:v.size() * sizeof(float)]; }

@implementation EngineBridge {
    std::unique_ptr<Engine> _e;
    NSThread               *_thread;
    NSMutableArray         *_queue;
    NSCondition            *_cond;
}
- (instancetype)initWithResources:(NSString *)res data:(NSString *)data temp:(NSString *)temp
{
    if ((self = [super init])) {
        _queue = [NSMutableArray new];
        _cond  = [NSCondition new];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(loop) object:nil];
        _thread.stackSize = 64 << 20;
        _thread.name      = @"engine";
        [_thread start];
        std::string r = res.UTF8String, d = data.UTF8String, t = temp.UTF8String;
        [self post:^{ self->_e = std::make_unique<Engine>(r, d, t); }];
    }
    return self;
}
- (void)loop
{
    while (true) @autoreleasepool {
        [_cond lock];
        while (_queue.count == 0) [_cond wait];
        dispatch_block_t b = _queue.firstObject;
        [_queue removeObjectAtIndex:0];
        [_cond unlock];
        try { b(); } catch (const std::exception &e) { NSLog(@"engine: %s", e.what()); }
    }
}
- (void)post:(dispatch_block_t)b
{
    [_cond lock];
    [_queue addObject:[b copy]];
    [_cond signal];
    [_cond unlock];
}
- (void)call:(NSString *)cmd args:(NSString *)args completion:(void (^)(NSString *))done
{
    std::string c = cmd.UTF8String, a = args.UTF8String;
    [self post:^{
        NSString *r = self->_e ? ns(self->_e->call(c, a)) : @"{\"error\":\"engine did not start\"}";
        dispatch_async(dispatch_get_main_queue(), ^{ done(r); });
    }];
}
- (void)mesh:(long long)key completion:(void (^)(NSData *))done
{
    [self post:^{ NSData *d = self->_e ? dat(self->_e->mesh(key)) : [NSData data]; dispatch_async(dispatch_get_main_queue(), ^{ done(d); }); }];
}
- (void)paintedObject:(int)o volume:(int)v kind:(int)k completion:(void (^)(NSData *))done
{
    [self post:^{ NSData *d = self->_e ? dat(self->_e->painted(o, v, k)) : [NSData data]; dispatch_async(dispatch_get_main_queue(), ^{ done(d); }); }];
}
- (void)previewPlate:(int)plate completion:(void (^)(NSData *))done
{
    [self post:^{ NSData *d = self->_e ? dat(self->_e->preview(plate)) : [NSData data]; dispatch_async(dispatch_get_main_queue(), ^{ done(d); }); }];
}
- (NSString *)sliceStatus { return _e ? ns(_e->slice_status()) : @"{\"state\":\"idle\"}"; }
- (void)cancelSlice { if (_e) _e->cancel(); }
@end
