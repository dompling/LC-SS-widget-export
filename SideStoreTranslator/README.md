# SideStoreTranslator

A **standalone iOS arm64 dylib** for LC+SS built-in SideStore.
Not part of `LCFloatingMenu.dylib`; no floating-menu UI or code changes.

## Sources and coverage

- Upstream: [SideStore/SideStore](https://github.com/SideStore/SideStore), branch `develop`.
- Key inventory: [SideStore localization PR #1495](https://github.com/SideStore/SideStore/pull/1495), commit `a8bfc4945a444d4b844bc1aff2e0c2ae097a2d95`. It was **closed without merge** and contains Korean localization, but no Chinese.
- `upstream-key-inventory.json`: all extracted source keys, deduplicated, from main `Localizable.xcstrings`, widget, storyboards, and other catalogs.
- `zh-Hans.json`: **reviewed Chinese mapping**, not machine-generated guesses. Keys without a reviewed translation fall back to English.

## Activation and scope

The plugin checks `+[NSUserDefaults isSideStore]` exported by LC+SS.
It installs hooks **only when the running guest is LC+SS's built-in SideStore**, and does nothing for LiveContainer host UI or other guests. Import only via LC's existing tweak import/management interface and enable its injection for SideStore.

The plugin hooks the `NSBundle` localization boundary, plus limited UIKit text setters for storyboard text that bypasses `NSLocalizedString`. It only substitutes **exact dictionary matches**.
SwiftUI literal localization isn't guaranteed. These are **runtime overrides**, not a replacement for an actual SideStore Chinese build.

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

Go to **Actions > Build independent SideStore Translator dylib**; run on the `feat/sidestore-translator` branch. Download the `SideStoreTranslator-dylib` artifact, unzip, import `SideStoreTranslator.dylib` into LC+SS, and relaunch the built-in SideStore.

The CI intentionally does **not** create tags or Releases; builds are Actions artifacts only.

## Limitations

- No full device run has yet been performed; verify injection logs and My Apps / Settings screens.
- Most Storyboard titles get localized through UIKit setters; some nib-native or SwiftUI texts require extra integration.
- Only reviewed keys are translated; the upstream inventory is preserved to support future completion.
- Never install this plugin as a replacement for `LCFloatingMenu.dylib`; both may coexist independently.
- Format specifiers (`%@, %d,` etc.) are validated in CI to prevent unsafe format strings.
