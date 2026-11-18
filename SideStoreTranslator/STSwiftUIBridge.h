#import <Foundation/Foundation.h>

// Called by Swift using the imported C/Objective-C ABI, never a Swift symbol cast.
// nil means disabled, outside SideStore, or no exact dictionary entry.
FOUNDATION_EXPORT NSString * _Nullable STSwiftUITranslation(NSString * _Nonnull source);
