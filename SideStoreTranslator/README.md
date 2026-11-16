# SideStoreTranslator

A **standalone iOS arm64 dylib** for LC+SS built-in SideStore.
Not part of `LCFloatingMenu.dylib`; no floating-menu UI or code changes.

## Sources and coverage

- Upstream: [SideStore/SideStore](https://github.com/SideStore/SideStore), branch `develop`.
- Key inventory: [SideStore localization PR #1495](https://github.com/SideStore/SideStore/pull/1495), commit `a8bfc4945a444d4b844bc1aff2e0c2ae097a2d95`. It was **closed without merge** and contains Korean localization, but no Chinese.
- `upstream-key-inventory.json`: all extracted source keys, deduplicated, from main `Localizable.xcstrings`, widget, storyboards, and other catalogs.
- `zh-Hans.json`: **reviewed Chinese mapping**, not machine-generated guesses. Keys without a reviewed translation fall back to English.

## Activation and scope: one-shot preloading (no IPA rebuild)

The built-in SideStore intentionally has `dontInjectTweakLoader=true`: its regular
TweakLoader skips Guest tweaks. Instead of changing LC+SS or disabling that guard,
the plugin uses LC's existing **Release startup preloader** in
`LiveContainer/main.c`. The host plugin queues its own signed dylib path in
`<LC host HOME>/Library/preloadLibraries.txt` just before the ordinary
`builtinSideStore` classic launch/restart. On the next startup, `LiveContainerMainC`
loads the dylib **before** `LiveContainerShared.framework`, then removes the file
and continues into the original built-in SideStore startup flow. Other existing
preload entries are preserved.

1. Import **SideStoreTranslator.dylib** into the LC host's **private global**
   `Documents/Tweaks` folder (not only the shared App Group Tweaks folder).
2. Sign the dylib using LC's existing plugin-signing interface as appropriate.
3. Enable LC developer setting **Load Tweaks to LiveContainer Itself**
   (`LCLoadTweaksToSelf`), then fully restart LC into its **home UI**.
4. Open the built-in SideStore from LC's own list or floating-menu shortcut.
   Both launch paths call `LCSharedUtils launchToGuestAppWithClassicMode:`.
5. Check the LC host's `Documents/SideStoreTranslator/status.json`; look for
   `preloadedBeforeLC: true`, `sideStoreContext: true`, and an active
   translation dictionary. The preloader itself logs to the system console.

The constructor arms localization hooks before LC's context methods exist.
Translations only become active once `+[NSUserDefaults isSideStore]` reports
the built-in SideStore. The host hook only queues this dylib for the
`builtinSideStore` token and never modifies the bundled plist, executables,
SideStore data, or floating-menu code.

**Limitations:** The Release binary must actually use `-e _LiveContainerMainC`
(as in the current `lcss-original` Xcode project), and iOS must accept the
dylib's code signature during the early `dlopen`. Source review proves the
preload path exists, **not** that it has passed an iOS device test. A failed
early `dlopen` in `main.c` produces no error log or translation status because
the stock preloader ignores its return value. Don't override another app's
preload file or install unrelated tweaks through this mechanism.

The `NSBundle` localization hook and UIKit setters replace exact dictionary
matches. For storyboard strings decoded directly from nibs, `UILabel` and
`UITableViewCell` `awakeFromNib` hooks localize static labels, while a
`UIViewController.viewWillAppear:` fallback translates visible view trees,
navigation titles and tab bar titles (including the built-in Settings screen).
Existing attributed-label font/color styling is retained. All hooks are gated
by the built-in SideStore context; other guests and the LC home UI are not
localized. SwiftUI native literal localization is still not guaranteed.

## JSON

The built-in mapping is embedded directly into the dylib at build time. It does **not require a separate JSON file** after importing the plugin.

An optional runtime override is read from:

`<LC_HOME_PATH>/Documents/SideStoreTranslator/zh-Hans.json`

This is the **LC host container**, not SideStore's sandbox. An invalid external JSON is ignored and the embedded mapping is used.

File format:

```json
{
  "schemaVersion": 1,
  "language": "zh-Hans",
  "enabled": true,
  "translations": {
    "My Apps": "我的应用",
    "Refresh All": "全部刷新",
    "Settings": "设置"
  }
}
```

External JSON **replaces** the embedded dictionary. Set `"enabled": false` to disable translation while keeping the dylib loaded; restart built-in SideStore after changing the file. Alternatively disable the tweak in LC settings.

## Build without local Mac

Go to **Actions > Build independent SideStore Translator dylib**; run on the `feat/sidestore-translator` branch. Download the `SideStoreTranslator-dylib` artifact, unzip, import the dylib into the LC **private global Tweaks** folder, sign if needed, enable host tweaks, and restart LC before opening its built-in SideStore.

The CI intentionally does **not** create tags or Releases; builds are Actions artifacts only.

## Limitations

- No full device run has yet been performed; verify the early preload, injection logs, and My Apps / Settings screens.
- Storyboard static labels and navigation titles now have nib/appearance hooks; verify coverage on device, especially native SwiftUI text.
- Only reviewed keys are translated; the upstream inventory is preserved to support future completion.
- Never install this plugin as a replacement for `LCFloatingMenu.dylib`; both may coexist independently.
- Format specifiers (`%@, %d,` etc.) are validated in CI to prevent unsafe format strings.
