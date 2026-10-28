#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface LCOrbitPreferences : NSObject
- (nullable id)objectForKey:(NSString *)key;
- (void)setObject:(nullable id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (nullable NSString *)stringForKey:(NSString *)key;
- (nullable NSArray *)arrayForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)synchronize;
@end
/// Existing LCFloatingMenu.* preference keys remain intact across migration.
@interface LCOrbitStorage : NSObject
+ (NSString *)key:(NSString *)key forModule:(NSString *)identifier;
+ (nullable id)objectForKey:(NSString *)key module:(NSString *)identifier;
+ (void)setObject:(nullable id)object forKey:(NSString *)key module:(NSString *)identifier;
+ (nullable NSString *)rootPath;
+ (LCOrbitPreferences *)preferences;
+ (BOOL)reloadWithError:(NSError * _Nullable * _Nullable)error;
+ (nullable NSError *)lastError;
@end
NS_ASSUME_NONNULL_END
