// SideStoreTranslator - independent LC+SS guest-only localization tweak.
// Copyright (c) 2026. See repository LICENSE.
// Never loads floating-menu code or changes LC/SideStore binaries.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <stdlib.h>
#import <string.h>
#import "STEmbeddedJSON.h"

static NSDictionary<NSString *, NSString *> *STDictionary;
static BOOL STEnabled = NO;
static NSString *STOrigin = @"embedded";
static NSString *STLanguage = @"zh-Hans";

static BOOL STIsBuiltInSideStore(void) {
    SEL selector = NSSelectorFromString(@"isSideStore");
    if (![NSUserDefaults respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id,SEL))objc_msgSend)(NSUserDefaults.class, selector);
}
static NSString *STTranslation(NSString *key) {
    if (!STEnabled || ![key isKindOfClass:NSString.class] || key.length == 0) return nil;
    return STDictionary[key];
}
static NSString *STReplace(NSString *key) {
    NSString *translation = STTranslation(key);
    return translation ?: key;
}
static BOOL STBundleIsAllowed(NSBundle *bundle) {
    if (!bundle) return NO;
    if (bundle == NSBundle.mainBundle) return YES;
    NSString *path = bundle.bundlePath ?: @"";
    NSString *identifier = bundle.bundleIdentifier ?: @"";
    return [path hasSuffix:@"/SideStoreApp.framework"] ||
           [identifier isEqualToString:@"com.SideStore.SideStore"];
}
static NSDictionary *STParseDocument(NSData *data) {
    if (data.length == 0 || data.length > 1024 * 1024) return nil;
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![parsed isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *document = parsed;
    if (![document[@"schemaVersion"] isKindOfClass:NSNumber.class] ||
        [document[@"schemaVersion"] integerValue] != 1 ||
        ![document[@"translations"] isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary<NSString *,NSString *> *clean = [NSMutableDictionary dictionary];
    NSDictionary *translations = document[@"translations"];
    for (id key in translations) {
        id value = translations[key];
        if (![key isKindOfClass:NSString.class] ||
            ![value isKindOfClass:NSString.class] ||
            [key length] == 0 || [value length] == 0) return nil;
        clean[key] = value;
    }
    return @{@"translations": [clean copy],
             @"enabled": [document[@"enabled"] isKindOfClass:NSNumber.class] ? document[@"enabled"] : @YES,
             @"language": [document[@"language"] isKindOfClass:NSString.class] ? document[@"language"] : @"zh-Hans"};
}
static NSData *STExternalData(NSString **location) {
    const char *home = getenv("LC_HOME_PATH");
    if (!home || !home[0]) return nil;
    NSString *file = [[NSString stringWithUTF8String:home]
        stringByAppendingPathComponent:@"Documents/SideStoreTranslator/zh-Hans.json"];
    struct stat info;
    if (lstat(file.fileSystemRepresentation, &info) != 0 ||
        !S_ISREG(info.st_mode) || info.st_size <= 0 || info.st_size > 1024*1024) return nil;
    NSData *data = [NSData dataWithContentsOfFile:file options:0 error:nil];
    if (data) *location = file;
    return data;
}
static void STInitializeDictionary(void) {
    NSData *builtIn = [NSData dataWithBytes:STBuiltinJSON length:sizeof(STBuiltinJSON)-1];
    NSDictionary *parsed = STParseDocument(builtIn);
    NSString *file = nil;
    NSData *external = STExternalData(&file);
    if (external) {
        NSDictionary *override = STParseDocument(external);
        if (override) {
            parsed = override;
            STOrigin = @"external";
        } else {
            NSLog(@"[SideStoreTranslator] Invalid external JSON; using bundled translations.");
        }
    }
    if (!parsed) {
        NSLog(@"[SideStoreTranslator] No valid translation dictionary.");
        return;
    }
    STDictionary = parsed[@"translations"];
    STEnabled = [parsed[@"enabled"] boolValue] && STDictionary.count > 0;
    STLanguage = parsed[@"language"];
    NSLog(@"[SideStoreTranslator] %@ lang=%@ keys=%lu enabled=%d",
          STOrigin, STLanguage, (unsigned long)STDictionary.count, STEnabled);
}

typedef NSString *(*STLocalizedMethod)(id,SEL,NSString *,NSString *,NSString *);
static STLocalizedMethod STOriginalLocalized = NULL;
static NSString *STHookLocalized(id self, SEL command, NSString *key,
                                 NSString *value, NSString *table) {
    NSString *original = STOriginalLocalized(self, command, key, value, table);
    if (!STEnabled || !STBundleIsAllowed((NSBundle *)self)) return original;
    NSString *translated = STTranslation(key);
    if (!translated) translated = STTranslation(original);
    return translated ?: original;
}
typedef void (*STSetTextMethod)(id,SEL,NSString *);
static STSetTextMethod STOriginalLabel = NULL;
static void STHookLabel(UILabel *self, SEL command, NSString *text) {
    STOriginalLabel(self, command, STReplace(text));
}
typedef void (*STButtonMethod)(id,SEL,NSString *,UIControlState);
static STButtonMethod STOriginalButton = NULL;
static void STHookButton(UIButton *self, SEL command, NSString *title, UIControlState state) {
    STOriginalButton(self, command, STReplace(title), state);
}
static STSetTextMethod STOriginalBarItem = NULL;
static void STHookBarItem(UIBarButtonItem *self, SEL command, NSString *title) {
    STOriginalBarItem(self, command, STReplace(title));
}
static STSetTextMethod STOriginalNavigationItem = NULL;
static void STHookNavigationItem(UINavigationItem *self, SEL command, NSString *title) {
    STOriginalNavigationItem(self, command, STReplace(title));
}
typedef void (*STSegmentMethod)(id,SEL,NSString *,NSInteger);
static STSegmentMethod STOriginalSegment = NULL;
static void STHookSegment(UISegmentedControl *self, SEL command, NSString *title, NSInteger index) {
    STOriginalSegment(self, command, STReplace(title), index);
}
static BOOL STReplaceMethod(Class klass, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(klass, selector);
    if (!method) return NO;
    IMP previous = method_getImplementation(method);
    if (!previous || previous == replacement) return NO;
    *original = previous;
    method_setImplementation(method, replacement);
    return YES;
}
__attribute__((constructor))
static void STBootstrap(void) {
    // This is intentionally unavailable in LC's host UI, regular guests,
    // standalone SideStore, and LiveProcess unless LC marks them as SideStore.
    if (!STIsBuiltInSideStore()) return;
    STInitializeDictionary();
    if (!STEnabled) return;
    if (!STReplaceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:),
                         (IMP)STHookLocalized, (IMP *)&STOriginalLocalized)) {
        NSLog(@"[SideStoreTranslator] Unable to install NSBundle localization hook.");
        return;
    }
    // Storyboard labels and UI elements that do not call NSLocalizedString.
    // Match only exact keys from our controlled dictionary. No string scanning,
    // no user-input fields, no editing of installed apps or signing data.
    STReplaceMethod(UILabel.class, @selector(setText:),
                    (IMP)STHookLabel, (IMP *)&STOriginalLabel);
    STReplaceMethod(UIButton.class, @selector(setTitle:forState:),
                    (IMP)STHookButton, (IMP *)&STOriginalButton);
    STReplaceMethod(UIBarButtonItem.class, @selector(setTitle:),
                    (IMP)STHookBarItem, (IMP *)&STOriginalBarItem);
    STReplaceMethod(UINavigationItem.class, @selector(setTitle:),
                    (IMP)STHookNavigationItem, (IMP *)&STOriginalNavigationItem);
    STReplaceMethod(UISegmentedControl.class, @selector(setTitle:forSegmentAtIndex:),
                    (IMP)STHookSegment, (IMP *)&STOriginalSegment);
    NSLog(@"[SideStoreTranslator] Hooks ready (SideStore only).");
}
