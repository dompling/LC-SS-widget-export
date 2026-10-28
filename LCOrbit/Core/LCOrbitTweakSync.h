#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Host-only shared-global tweak management. Never touches TweakLoader or Guest folders.
@interface LCOrbitTweakSync : NSObject
// Inventory item: name, private, shared, loaded, matches, canShare, canUnshare.
+ (NSArray<NSDictionary *> *)pluginInventory;
// Backwards-compatible one-tap sync of all loaded private global dylibs.
+ (NSArray<NSString *> *)eligibleNames;
+ (NSString *)copyLoadedTweaksToShared;
// Opt-in automatic sharing of eligible loaded private plugins. Defaults off.
+ (BOOL)automaticSyncEnabled;
+ (void)setAutomaticSyncEnabled:(BOOL)enabled;
+ (BOOL)setAutomaticSyncEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
// Synchronous, serialized with manual sharing. Empty report means no work.
+ (NSString *)syncAutomaticallyIfNeeded;
// Batch manage explicitly selected, validated names. share=NO revokes only shared copies.
+ (NSString *)applyShare:(BOOL)share names:(NSArray<NSString *> *)names;
@end
NS_ASSUME_NONNULL_END
