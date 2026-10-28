#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Structured, bounded plugin logs. Callers provide plugin events only.
@interface LCOrbitLog : NSObject
+ (nullable NSString *)pathForKind:(NSString *)kind;
+ (void)appendEvent:(NSString *)event details:(nullable id)details kind:(NSString *)kind;
+ (NSData *)dataForKind:(NSString *)kind;
+ (void)clearKind:(NSString *)kind;
@end
NS_ASSUME_NONNULL_END
