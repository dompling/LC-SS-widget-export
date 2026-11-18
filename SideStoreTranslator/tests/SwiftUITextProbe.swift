import Foundation
import SwiftUI

// Inspect value storage instead of relying on screenshots or private layout APIs.
func containsString(_ value: Any, _ expected: String, depth: Int = 0) -> Bool {
    if let string = value as? String, string == expected { return true }
    guard depth < 10 else { return false }
    return Mirror(reflecting: value).children.contains {
        containsString($0.value, expected, depth: depth + 1)
    }
}

@_cdecl("STRunSwiftUIProbe")
public func runSwiftUIProbe() {
let active = ProcessInfo.processInfo.arguments.contains("--active")
let runtimeTitle = "On-Device Anisette"
let runtimeSubtitle = "Run ADI emulation directly on device instead of remote servers"
let title = Text(runtimeTitle)
let subtitle = Text(runtimeSubtitle)
let expectedTitle = active ? "本机 Anisette" : runtimeTitle
// The real embedded dictionary determines the translation in the test runner.
let expectedSubtitle = ProcessInfo.processInfo.environment["ST_EXPECTED_SUBTITLE"] ?? runtimeSubtitle
func check(_ condition: Bool, _ label: String) {
    guard condition else {
        fputs("FAIL: \(label)\n", stderr)
        exit(1)
    }
}
check(containsString(title, expectedTitle), "Text(String) settings row")
check(containsString(subtitle, active ? expectedSubtitle : runtimeSubtitle), "Text(String) settings subtitle")
let substring = runtimeTitle[...]
check(containsString(Text(substring), expectedTitle), "Text(Substring) generic ownership")
let unknown = "com.example.user-entered.identifier"
check(containsString(Text(unknown), unknown), "unknown text is preserved")
check(containsString(Text(verbatim: unknown), unknown), "verbatim value is preserved")
let key: LocalizedStringKey = "Theme Manager"
check(containsString(key, active ? "主题管理器" : "Theme Manager"), "static SwiftUI localized key")
let valueKey = LocalizedStringKey(runtimeTitle)
check(containsString(valueKey, expectedTitle), "LocalizedStringKey(String)")
check(containsString(Text("Theme Manager"), active ? "主题管理器" : "Theme Manager"), "native Text literal")
let interpolated: LocalizedStringKey = "App \(unknown)"
check(containsString(interpolated, unknown), "interpolated arguments are preserved")
for index in 0..<5000 {
    let input = index.isMultiple(of: 2) ? runtimeTitle : "Unknown-\(index)"
    let expected = active && index.isMultiple(of: 2) ? expectedTitle : input
    check(containsString(Text(input), expected), "repeated owned generic string \(index)")
}
print("SwiftUI settings text probe passed (active=\(active))")
}
