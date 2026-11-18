import SwiftUI

// Match Text.init<S: StringProtocol>'s consuming generic ABI. A borrowed default
// parameter has different ownership and must not be used for this replacement.
@_silgen_name("STSwiftUITextStringProtocol")
public func stTextStringProtocol<S: StringProtocol>(_ content: __owned S) -> Text {
    if let translated = STSwiftUITranslation(String(content)) {
        return Text(verbatim: translated)
    }
    // The rebinder excludes this plugin's imports. Keep Swift's own initializer
    // call so the compiler retains its native method ABI and ownership.
    return Text(content)
}

// Translate keys at creation, before SwiftUI chooses an internal localization
// resolver. Keep LocalizedStringKey's formatting/Markdown handling intact.
@_silgen_name("STSwiftUIKeyLiteral")
public func stKeyLiteral(_ content: __owned String) -> LocalizedStringKey {
    LocalizedStringKey(stringLiteral: STSwiftUITranslation(content) ?? content)
}

@_silgen_name("STSwiftUIKeyValue")
public func stKeyValue(_ content: __owned String) -> LocalizedStringKey {
    LocalizedStringKey(STSwiftUITranslation(content) ?? content)
}
