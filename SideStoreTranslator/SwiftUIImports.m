// Rebind only the built-in guest's imports: LC preloads tweaks with dlopen,
// which does not apply a new __interpose table to later-loaded guest images.
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>
#import "../litehook/src/litehook.h"

// Only take addresses here. All Swift values/calls remain in Swift.
extern void STSwiftUITextStringProtocol(void);
extern void STOriginalTextStringProtocol(void)
    __asm__("_$s7SwiftUI4TextVyACxcSyRzlufC");
extern void STSwiftUIKeyLiteral(void);
extern void STOriginalKeyLiteral(void)
    __asm__("_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC");
extern void STSwiftUIKeyValue(void);
extern void STOriginalKeyValue(void)
    __asm__("_$s7SwiftUI18LocalizedStringKeyVyACSScfC");

static void STBindSwiftUIImports(const struct mach_header *header, intptr_t slide) {
    (void)slide;
    Dl_info image;
    if (!dladdr(header, &image) || !image.dli_fname ||
        !strstr(image.dli_fname, "/SideStoreApp.framework/")) return;
    // In particular, never rewrite this plugin's imports: its native Swift
    // fallback initializer calls must keep pointing at Apple's implementations.
    litehook_rebind_symbol((const mach_header_u *)header,
        STOriginalTextStringProtocol, STSwiftUITextStringProtocol, NULL);
    litehook_rebind_symbol((const mach_header_u *)header,
        STOriginalKeyLiteral, STSwiftUIKeyLiteral, NULL);
    litehook_rebind_symbol((const mach_header_u *)header,
        STOriginalKeyValue, STSwiftUIKeyValue, NULL);
}

__attribute__((constructor))
static void STRegisterSwiftUIImports(void) {
    // Also visits images loaded before us, then handles future dlopen guests.
    _dyld_register_func_for_add_image(STBindSwiftUIImports);
}
