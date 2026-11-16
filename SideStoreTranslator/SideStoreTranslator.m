// SideStoreTranslator - independent LC+SS guest-only localization tweak.
// Copyright (c) 2026. See repository LICENSE.
// Never loads floating-menu code or changes LC/SideStore binaries.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <stdlib.h>
#import <dlfcn.h>
#import <string.h>
#import "STEmbeddedJSON.h"

static NSDictionary<NSString *, NSString *> *STDictionary;
static BOOL STEnabled = NO;
static NSString *STOrigin = @"embedded";
static NSString *STLanguage = @"zh-Hans";
static void STInitializeDictionary(void);
static BOOL STTranslationReady(void);
static void STBootstrap(void);
static BOOL STPreloadedBeforeLC = NO;

static BOOL STIsBuiltInSideStore(void) {
    SEL selector = NSSelectorFromString(@"isSideStore");
    if (![NSUserDefaults respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id,SEL))objc_msgSend)(NSUserDefaults.class, selector);
}
static NSString *STTranslation(NSString *key) {
    if (!STTranslationReady() || ![key isKindOfClass:NSString.class] || key.length == 0) return nil;
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
    // Diagnostic available in the Files app, only after SideStore actually starts.
    const char *home = getenv("LC_HOME_PATH");
    if (home && home[0]) {
        NSString *folder = [[NSString stringWithUTF8String:home]
                            stringByAppendingPathComponent:@"Documents/SideStoreTranslator"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder
                                withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *status = @{@"status": STEnabled ? @"active" : @"disabled",
                                 @"sideStoreContext": @YES,
                                 @"source": STOrigin,
                                 @"language": STLanguage ?: @"zh-Hans",
                                 @"translationCount": @(STDictionary.count),
                                 @"externalJSONFound": @(external != nil),
                                 @"preloadedBeforeLC": @(STPreloadedBeforeLC),
                                 @"checkedAt": @([[NSDate date] timeIntervalSince1970])};
        NSData *statusData = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
        [statusData writeToFile:[folder stringByAppendingPathComponent:@"status.json"] atomically:YES];
    }
}

static BOOL STTranslationReady(void) {
    // The LC host may preload this dylib *before* it switches to SideStore.
    // Always leave hooks armed and activate them dynamically on SideStore entry.
    if (!STIsBuiltInSideStore()) return NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ STInitializeDictionary(); });
    return STEnabled;
}


// SwiftUI Text("literal") resolves a LocalizedStringKey through the app's
// localization table, typically at the CoreFoundation resource boundary.
// This is intentionally a best-effort dyld interpose. It is installed before
// SideStore startup by LC's one-shot preload mechanism. It never touches guest
// apps other than built-in SideStore and it never replaces non-matching keys.
//
// Note: Text(title), where title is a String variable, is *verbatim* in SwiftUI.
// It cannot be translated merely by changing the localization table.
// We retain UIKit hooks for storyboard content and use this bridge only for
// APIs that actually request localization.
typedef CFStringRef (*STCFBundleLocalizedFunction)(CFBundleRef, CFStringRef, CFStringRef, CFStringRef);
static CFStringRef STCFBundleCopyLocalizedString(CFBundleRef bundle,
                                                CFStringRef key,
                                                CFStringRef value,
                                                CFStringRef tableName) {
    // Avoid translating lookups belonging to unrelated system frameworks.
    BOOL appBundle = bundle && (bundle == CFBundleGetMainBundle() ||
        (CFBundleGetIdentifier(bundle) &&
         CFEqual(CFBundleGetIdentifier(bundle), CFSTR("com.SideStore.SideStore"))));
    if (STIsBuiltInSideStore() && appBundle && key &&
        CFGetTypeID(key) == CFStringGetTypeID() &&
        (!tableName || (CFGetTypeID(tableName) == CFStringGetTypeID() &&
                        CFEqual(tableName, CFSTR("Localizable")))) &&
        STTranslationReady()) {
        NSString *replacement = STDictionary[(__bridge NSString *)key];
        if (replacement.length > 0) {
            static dispatch_once_t logged;
            dispatch_once(&logged, ^{
                NSLog(@"[SideStoreTranslator] CFBundle localization bridge hit.");
            });
            // CFBundleCopyLocalizedString follows the Create Rule.
            return (__bridge_retained CFStringRef)replacement;
        }
    }
    // dyld leaves calls originating in this interposing image bound to the
    // original implementation; all other code paths remain untouched.
    return CFBundleCopyLocalizedString(bundle, key, value, tableName);
}
__attribute__((used, section("__DATA,__interpose")))
static const struct {
    STCFBundleLocalizedFunction replacement;
    STCFBundleLocalizedFunction original;
} STCFBundleInterpose = {
    STCFBundleCopyLocalizedString,
    CFBundleCopyLocalizedString
};

typedef NSString *(*STLocalizedMethod)(id,SEL,NSString *,NSString *,NSString *);
static STLocalizedMethod STOriginalLocalized = NULL;
static NSString *STHookLocalized(id self, SEL command, NSString *key,
                                 NSString *value, NSString *table) {
    NSString *original = STOriginalLocalized(self, command, key, value, table);
    if (!STTranslationReady() || !STBundleIsAllowed((NSBundle *)self)) return original;
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
// Interface Builder can restore static text directly from a Storyboard archive,
// bypassing UILabel.setText:/UINavigationItem.setTitle:. Correct those values at
// the end of nib loading and again when a controller is presented.
static NSAttributedString *STTranslatedAttributed(NSAttributedString *value) {
    if (!value || value.length == 0) return value;
    NSString *translated = STTranslation(value.string);
    if (!translated || [translated isEqualToString:value.string]) return value;
    // Keep the label's font, color, paragraph style and other first-run styling.
    NSDictionary *attributes = [value attributesAtIndex:0 effectiveRange:NULL];
    return [[NSAttributedString alloc] initWithString:translated attributes:attributes];
}
static void STLocalizeLabel(UILabel *label) {
    if (!label || !STTranslationReady()) return;
    NSString *before = label.text;
    NSString *after = STTranslation(before);
    if (!after || [after isEqualToString:before]) return;
    NSAttributedString *styled = label.attributedText;
    if (styled.length > 0 && [styled.string isEqualToString:before]) {
        label.attributedText = STTranslatedAttributed(styled);
    } else {
        label.text = after;
    }
}
static void STLocalizeButton(UIButton *button) {
    if (!button || !STTranslationReady()) return;
    const UIControlState states[] = {UIControlStateNormal, UIControlStateSelected,
                                    UIControlStateHighlighted, UIControlStateDisabled};
    for (NSUInteger i = 0; i < sizeof(states) / sizeof(states[0]); ++i) {
        NSString *before = [button titleForState:states[i]];
        NSString *after = STTranslation(before);
        if (after && ![after isEqualToString:before]) {
            [button setTitle:after forState:states[i]];
        }
    }
}
static void STLocalizeViewTree(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:UILabel.class]) {
        STLocalizeLabel((UILabel *)view);
    } else if ([view isKindOfClass:UIButton.class]) {
        STLocalizeButton((UIButton *)view);
    }
    for (UIView *child in view.subviews) {
        STLocalizeViewTree(child);
    }
}
typedef void (*STAwakeMethod)(id, SEL);
static STAwakeMethod STOriginalLabelAwake = NULL;
static void STHookLabelAwake(UILabel *self, SEL command) {
    STOriginalLabelAwake(self, command);
    STLocalizeLabel(self);
}
static STAwakeMethod STOriginalCellAwake = NULL;
static void STHookCellAwake(UITableViewCell *self, SEL command) {
    STOriginalCellAwake(self, command);
    if (STTranslationReady()) STLocalizeViewTree(self.contentView);
}
typedef void (*STControllerAppearanceMethod)(id, SEL, BOOL);
static STControllerAppearanceMethod STOriginalViewWillAppear = NULL;
static void STHookViewWillAppear(UIViewController *self, SEL command, BOOL animated) {
    STOriginalViewWillAppear(self, command, animated);
    if (!STTranslationReady() || !self.isViewLoaded) return;
    STLocalizeViewTree(self.view);
    UINavigationItem *navigation = self.navigationItem;
    if (navigation.title) navigation.title = STReplace(navigation.title);
    if (self.title) self.title = STReplace(self.title);
    // Static UITabBarItem titles can also bypass the setter during nib decode.
    UITabBarItem *tab = self.tabBarItem;
    if (tab.title) tab.title = STReplace(tab.title);
}

static BOOL STReplaceMethod(Class klass, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(klass, selector);
    if (!method) return NO;
    IMP previous = method_getImplementation(method);
    if (!previous || previous == replacement) return NO;
    *original = previous;
    // When the selector is inherited, install a subclass override instead
    // of modifying the superclass implementation for every UIKit descendant.
    if (!class_addMethod(klass, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(method, replacement);
    }
    return YES;
}

typedef BOOL (*STClassicLaunchMethod)(id, SEL, NSUInteger);
static STClassicLaunchMethod STOriginalClassicLaunch = NULL;

// LC's Release entry point, LiveContainerMainC, reads this one-shot file
// before it loads LiveContainerShared.framework or applies Guest tweak policy.
// Never change SideStoreApp.framework, the Guest plist, or TweakLoader itself.
static BOOL STQueueSideStorePreload(void) {
    const char *homeC = getenv("LC_HOME_PATH");
    if (!homeC || !homeC[0]) return NO;
    NSString *home = [[NSString stringWithUTF8String:homeC] stringByResolvingSymlinksInPath];
    Dl_info image = {0};
    if (!dladdr((const void *)&STBootstrap, &image) || !image.dli_fname) return NO;
    NSString *library = [[[NSString stringWithUTF8String:image.dli_fname]
                          stringByStandardizingPath] stringByResolvingSymlinksInPath];
    NSString *trustedRoot = [[[home stringByAppendingPathComponent:@"Documents/Tweaks"]
                             stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
    if (!library || ![library hasPrefix:trustedRoot] ||
        ![library.pathExtension isEqualToString:@"dylib"] ||
        [library rangeOfString:@"\n"].location != NSNotFound ||
        [library rangeOfString:@"\r"].location != NSNotFound) return NO;
    struct stat st;
    if (lstat(library.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) return NO;

    NSString *file = [home stringByAppendingPathComponent:@"Library/preloadLibraries.txt"];
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:file];
    NSData *previousData = [NSData dataWithContentsOfFile:file];
    if (exists && !previousData) return NO;
    NSString *previous = previousData.length ?
        [[NSString alloc] initWithData:previousData encoding:NSUTF8StringEncoding] : @"";
    if (!previous) return NO;
    // Preserve pre-existing entries, including iOS 26+ MetalANGLE preloads.
    if ([[previous componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
         containsObject:library]) return YES;
    NSMutableString *next = [previous mutableCopy];
    if (next.length && ![next hasSuffix:@"\n"]) [next appendString:@"\n"];
    [next appendFormat:@"%@\n", library];
    NSData *data = [next dataUsingEncoding:NSUTF8StringEncoding];
    return [data writeToFile:file options:NSDataWritingAtomic error:nil];
}

static BOOL STHookClassicLaunch(id self, SEL command, NSUInteger classicMode) {
    // LC sets this token immediately before restarting into built-in SideStore.
    if ([[NSUserDefaults.standardUserDefaults stringForKey:@"selected"]
         isEqualToString:@"builtinSideStore"]) {
        BOOL queued = STQueueSideStorePreload();
        NSLog(@"[SideStoreTranslator] Built-in SideStore preload queued=%d", queued);
    }
    return STOriginalClassicLaunch(self, command, classicMode);
}

static void STInstallHostLaunchHook(void) {
    SEL infoSel = NSSelectorFromString(@"guestAppInfo");
    SEL sideSel = NSSelectorFromString(@"isSideStore");
    if (![NSUserDefaults respondsToSelector:infoSel] ||
        ![NSUserDefaults respondsToSelector:sideSel]) return;
    id guest = ((id (*)(id, SEL))objc_msgSend)(NSUserDefaults.class, infoSel);
    BOOL sideStore = ((BOOL (*)(id, SEL))objc_msgSend)(NSUserDefaults.class, sideSel);
    if (guest || sideStore) return;
    Class utils = NSClassFromString(@"LCSharedUtils");
    if (!utils) return;
    if (STReplaceMethod(object_getClass(utils),
                        @selector(launchToGuestAppWithClassicMode:),
                        (IMP)STHookClassicLaunch, (IMP *)&STOriginalClassicLaunch)) {
        NSLog(@"[SideStoreTranslator] LC classic launch hook ready.");
    }
}
__attribute__((constructor))
static void STBootstrap(void) {
    // LC may load this dylib in its own host UI before SideStore starts.
    // Install hooks once, even in LC host mode; each hook checks isSideStore
    // at call time and is a no-op for LC UI and unrelated guest applications.
    // This constructor also runs *before* LiveContainerShared is loaded when
    // main.c preloads the dylib. Do not require isSideStore to exist yet.
    STPreloadedBeforeLC = ![NSUserDefaults respondsToSelector:NSSelectorFromString(@"isSideStore")];
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
    BOOL labelNibHook = STReplaceMethod(UILabel.class, @selector(awakeFromNib),
                                      (IMP)STHookLabelAwake, (IMP *)&STOriginalLabelAwake);
    BOOL cellNibHook = STReplaceMethod(UITableViewCell.class, @selector(awakeFromNib),
                                     (IMP)STHookCellAwake, (IMP *)&STOriginalCellAwake);
    BOOL appearanceHook = STReplaceMethod(UIViewController.class, @selector(viewWillAppear:),
                                        (IMP)STHookViewWillAppear,
                                        (IMP *)&STOriginalViewWillAppear);
    STInstallHostLaunchHook();
    NSLog(@"[SideStoreTranslator] Hooks armed; earlyPreload=%d storyboard(label=%d cell=%d appearance=%d)",
          STPreloadedBeforeLC, labelNibHook, cellNibHook, appearanceHook);
}
