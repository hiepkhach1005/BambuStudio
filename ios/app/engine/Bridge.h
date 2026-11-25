#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface EngineBridge : NSObject
- (instancetype)initWithResources:(NSString *)res data:(NSString *)data temp:(NSString *)temp;
/// Runs on the engine thread; the completion is called on the main queue.
- (void)call:(NSString *)cmd args:(NSString *)args completion:(void (^)(NSString *result))done;
- (void)mesh:(long long)key completion:(void (^)(NSData *))done;
- (void)paintedObject:(int)o volume:(int)v kind:(int)k completion:(void (^)(NSData *))done;
- (void)previewPlate:(int)plate completion:(void (^)(NSData *))done;
- (NSString *)sliceStatus;
- (void)cancelSlice;
@end

/// LAN printer link (MQTT over TLS, FTPS, chamber camera). Blocking calls: use from a background thread.
@interface LanBridge : NSObject
- (instancetype)initWithHost:(NSString *)host serial:(NSString *)serial code:(NSString *)code ca:(NSString *)caFile;
/// nil on success, else the error text.
- (nullable NSString *)connectMqtt:(void (^)(NSString *json))onReport closed:(void (^)(NSString *reason))onClose;
- (BOOL)publish:(NSString *)json;
- (nullable NSString *)upload:(NSString *)file as:(NSString *)name progress:(void (^)(double))progress;
- (void)startCamera:(void (^)(NSData *jpeg))onFrame closed:(void (^)(NSString *reason))onClose;
- (void)stopCamera;
- (void)disconnect;
@end
NS_ASSUME_NONNULL_END
