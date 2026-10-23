# LC Widget Probe (stock LC+SS Nightly)

A **separate**, metadata-only Objective-C dylib to test whether a Guest App loaded by LiveContainer can see candidate SideStore storage directories. The official LC+SS IPA is not changed. No credentials, certificates, file contents, or private keys are read or exported.

## Build
GitHub Actions: **Build independent LC Widget Probe dylib**, then download the artifact and extract `LCWidgetProbe.dylib`. The Action artifact is a ZIP wrapper.

## Test
1. Install the **official** LiveContainer+SideStore Nightly.
2. In LiveContainer > Tweaks, import `LCWidgetProbe.dylib` and sign it using LC's normal tweak signing option if necessary.
3. Associate the tweak with a **test Guest App**, or enable it as a global tweak. Launch the test Guest App once.
4. Locate the output under the Guest App-visible `Documents/LCWidgetProbe/probe.json`, if LC's sandbox mapping allows it. Alternatively check console for `[LCWidgetProbe]`.
5. Inspect `candidateDirectories` for existence / readability. Do not assume Scripting can access the generated file directly.

## Limitations
- LC's built-in SideStore is **not necessarily injectable** by the Guest App tweak loader.
- The probe is **not** a signed-date exporter: it intentionally does not parse private SideStore account data.
- A readable directory does not imply accessible or trustworthy expiration information.
- Plugin persistence across Nightly upgrades and export via Files/Shortcuts must be tested separately.
- If no candidate directory is readable, this mechanism does not meet the requested zero-modification widget-data goal.
