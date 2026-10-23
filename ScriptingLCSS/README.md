# LiveContainer+SideStore → Scripting (two independent tracks)

This is an **experimental Scripting project**, separate from the LCWidgetProbe dylib, without modifying the official LC+SS IPA.

## Track A: one-tap app refresh

Scripting's TestFlight documentation for **3.2.2+ on iOS 27** adds \`<Button shortcutIndex={0} />\` widgets.

1. Create a Shortcut on your iPhone, e.g. **Refresh LC+SS**, containing the official **LiveContainer → Refresh All Apps** action. If required, connect **LocalDevVPN** before the refresh and disconnect it when done.
2. **Test this Shortcut directly first**. LC+SS can need a valid Apple login, VPN, LiveProcess extension and occasionally the built-in SideStore open in foreground. Some Nightly builds have known cold-start issues.
3. Install a Scripting TestFlight version with \`shortcutIndex\` support. Create a Scripting project and copy \`widget.tsx\`.
4. Put it on the Home Screen. Long-press **Edit Widget → Shortcuts → Add New Item** and assign your Shortcut as the **first** action.
5. Tap **刷新签名**. It invokes the shortcut; it does not directly call private SideStore methods.

**Older Scripting builds:** a whole-widget action with **When Interacting → Open URL** to \`shortcuts://run-shortcut?name=Refresh%20LC%2BSS\` may work, but this is less ergonomic and must be tested. The exact Shortcut name must match. No per-button \`shortcutIndex\` on unsupported versions.

## Track B: accurate widget snapshot

The official SideStore keeps:
- Original app data in \`SideStore App Group / Database / SideStore.sqlite\` (\`InstalledApp\` records).
- A widget snapshot at \`SideStore App Group / widget_data.json\`.
- The SideStore widget snapshot may be stale: the dates are **not** necessarily live reads of the current embedded mobileprovision.

The **independent v4 probe dylib** copies the original SideStore widget JSON *unchanged* into **LiveContainer host Documents/LCWidgetExport/widget_data.json**. It runs ONLY when a Guest App loads the tweak. Opening the LC main app or calling Refresh All Apps alone does NOT run it.

Scripting app sandboxes have different permissions. Its widget code reads ONLY its own \`FileManager.appGroupDocumentsDirectory\`, not LC's private folders.

Setup after the v4 output exists:
1. In the iOS **Files** app, check **On My iPhone → LiveContainer → LCWidgetExport**. The official LC main \`Info.plist\` has both \`UIFileSharingEnabled\` and \`LSSupportsOpeningDocumentsInPlace\` enabled, but whether Files exposes this installed build must be verified.
2. In the **Scripting main app**, run \`index.tsx\`; in the folder picker choose \`LCWidgetExport\`. This saves the directory's user-authorized bookmark as \`LCWidgetExport\`.
3. In iOS Shortcuts, select **Scripting → Run Script** and choose this project's \`intent.tsx\` script. This should load the LC v4 export via the bookmark and copy it to **Scripting's own App Group**.
4. The Scripting widget (\`widget.tsx\`) now reads the snapshot and shows the **single** actual \`com.kdt.livecontainer\` entry.
5. For testing, launch a Guest App to run the v4 dylib **after** official SideStore has refreshed its widget snapshot; then run \`intent.tsx\`. A future automatic trigger is a separate research task.

The Scripting script and Apple Shortcuts calls **have not been tested on your phone yet**. In particular, background \`Run Script\` may be unable to resolve a security-scoped bookmark; if so, test **Run Script in App** or manual foreground sync.

## Important caveats

- A Scripting widget does not acquire LC's App Group entitlements through a bookmark.
- Do not promise a real-time snapshot until timestamp, original profile dates, and refresh event have been compared.
- The Shortcut refresh and JSON reading tracks are decoupled. A successful refresh does not guarantee the dylib has run.
- \`Widget.reloadAll()\` refreshes Scripting's **visual widget**, not SideStore's **app signing**.
- The Date fields in an **original** SideStore \`JSONEncoder\` snapshot are encoded relative to 2001-01-01. \`widget.tsx\` converts them to displayed calendar days.
- No Apple ID tokens, authentication information, certificate contents, or passwords are read.

## Upstream references
- https://scriptingapp.github.io/TestFlight/zh/guide/Changelog/3.2.2/Breaking%20Change%3A%20Widget%20Shortcut%20Lists
- https://scriptingapp.github.io/zh/guide/Device%20Capabilities/DocumentPicker
- https://scriptingapp.github.io/guide/Utilities/FileManager
- https://scriptingapp.github.io/guide/Intent/Quick%20Start
- https://livecontainer.github.io/docs/installation/lc_sidestore
- https://github.com/SideStore/SideStore/blob/develop/SideStore/Widget/WidgetData/WidgetDataManager.swift
- https://github.com/LiveContainer/LiveContainer/blob/main/SideStoreSupport/SideStore.swift
