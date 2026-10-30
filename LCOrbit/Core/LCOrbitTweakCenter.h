#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// LC host-only operations. Operates on LC's existing LCTweakFolder loader mechanism.
@interface LCOrbitTweakCenter : NSObject
// Each guest includes path/title/shared/selectedFolder/managedFolder/conflict/assigned.
+ (NSArray<NSDictionary *> *)guests;
+ (NSArray<NSDictionary *> *)sourcePluginsForGuest:(NSDictionary *)guest;
+ (NSString *)assignPluginNames:(NSArray<NSString *> *)names toGuest:(NSDictionary *)guest;
+ (NSDictionary *)pluginInfo:(NSString *)name shared:(BOOL)shared;
+ (NSString *)setPlugin:(NSString *)name enabled:(BOOL)enabled shared:(BOOL)shared;
@end
NS_ASSUME_NONNULL_END
