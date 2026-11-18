#import "STSwiftUIBridge.h"
#import "STEmbeddedJSON.h"
#import <stdlib.h>

// Test only: model the existing context gate and use the production dictionary.
// The production lookup lives in SideStoreTranslator.m and calls STTranslation.
NSString *STSwiftUITranslation(NSString *source) {
    const char *active = getenv("ST_TEST_SIDESTORE");
    if (!active || strcmp(active, "1") != 0) return nil;
    static NSDictionary *translations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithBytes:STBuiltinJSON length:sizeof(STBuiltinJSON) - 1];
        translations = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil][@"translations"];
    });
    return translations[source];
}
