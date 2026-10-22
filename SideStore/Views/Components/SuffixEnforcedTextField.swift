//
//  SuffixEnforcedTextField.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit
import SideSign

public enum BundleIDSanitizer {
    public static func sanitize(_ raw: String) -> String {
        InfoPlistParser.sanitizeBundleID(raw)
    }
}

public struct SuffixEnforcedTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var suffix: String
    var isSuffixEnforced: Bool
    var autocapitalization: UITextAutocapitalizationType = .none
    var onCommit: (() -> Void)? = nil

    public init(
        text: Binding<String>,
        placeholder: String,
        suffix: String,
        isSuffixEnforced: Bool,
        autocapitalization: UITextAutocapitalizationType = .none,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.suffix = suffix
        self.isSuffixEnforced = isSuffixEnforced
        self.autocapitalization = autocapitalization
        self.onCommit = onCommit
    }

    func applyAttributedText(to textField: UITextField) {
        let current = text
        verboseLog("[SuffixEnforcedTextField] applyAttributedText: text='\(current)', suffix='\(suffix)', isSuffixEnforced=\(isSuffixEnforced)")
        let attr = NSMutableAttributedString(string: current, attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.label
        ])
        if isSuffixEnforced && !suffix.isEmpty && current.hasSuffix(suffix) {
            let baseLength = current.count - suffix.count
            let suffixRange = NSRange(location: baseLength, length: suffix.count)
            attr.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: suffixRange)
        }

        let selectedRange = textField.selectedTextRange
        textField.attributedText = attr
        if let selectedRange = selectedRange {
            textField.selectedTextRange = selectedRange
        }
    }

    public func makeUIView(context: Context) -> UITextField {
        verboseLog("[SuffixEnforcedTextField] makeUIView: initial text='\(text)', suffix='\(suffix)', isSuffixEnforced=\(isSuffixEnforced)")
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = .systemFont(ofSize: 15)
        tf.textColor = .label
        tf.autocapitalizationType = autocapitalization
        tf.autocorrectionType = .no
        tf.returnKeyType = .done
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyAttributedText(to: tf)
        return tf
    }

    public func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        verboseLog("[SuffixEnforcedTextField] updateUIView: uiView.text='\(uiView.text ?? "")', binding text='\(text)', suffix='\(suffix)'")
        applyAttributedText(to: uiView)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SuffixEnforcedTextField

        init(_ parent: SuffixEnforcedTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            verboseLog("[SuffixEnforcedTextField] textDidChange: textField.text='\(textField.text ?? "")'")
            parent.text = textField.text ?? ""
            parent.applyAttributedText(to: textField)
        }

        public func textFieldDidChangeSelection(_ textField: UITextField) {
            guard parent.isSuffixEnforced, !parent.suffix.isEmpty else { return }
            guard let currentText = textField.text as NSString? else { return }
            let suffixLength = (parent.suffix as NSString).length
            let maxLocation = currentText.length - suffixLength
            guard maxLocation >= 0 else { return }
            if let selectedRange = textField.selectedTextRange {
                let cursorOffset = textField.offset(from: textField.beginningOfDocument, to: selectedRange.start)
                if cursorOffset > maxLocation {
                    verboseLog("[SuffixEnforcedTextField] clamp cursor from \(cursorOffset) to \(maxLocation)")
                    if let newPos = textField.position(from: textField.beginningOfDocument, offset: maxLocation) {
                        textField.selectedTextRange = textField.textRange(from: newPos, to: newPos)
                    }
                }
            }
        }

        public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            verboseLog("[SuffixEnforcedTextField] shouldChange: range=\(range), string='\(string)', current='\(textField.text ?? "")'")
            let result = SuffixEnforcedTextField.shouldChangeBundleID(
                in: textField,
                range: range,
                replacementString: string,
                suffix: parent.suffix,
                isSuffixEnforced: parent.isSuffixEnforced
            ) { [weak self] updated in
                self?.parent.text = updated
            }
            verboseLog("[SuffixEnforcedTextField] shouldChange result: \(result), resulting text='\(textField.text ?? "")'")
            if !result {
                parent.applyAttributedText(to: textField)
            }
            return result
        }

        public func textFieldShouldClear(_ textField: UITextField) -> Bool {
            guard parent.isSuffixEnforced, !parent.suffix.isEmpty else { return true }
            textField.text = parent.suffix
            parent.text = parent.suffix
            parent.applyAttributedText(to: textField)
            return false
        }

        public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit?()
            return true
        }
    }
}

extension SuffixEnforcedTextField {
    @MainActor
    public static func shouldChangeBundleID(
        in textField: UITextField,
        range: NSRange,
        replacementString string: String,
        suffix: String = "",
        isSuffixEnforced: Bool = false,
        onTextUpdated: ((String) -> Void)? = nil
    ) -> Bool {
        guard let currentText = textField.text as NSString? else { return true }

        let suffixLength = (isSuffixEnforced && !suffix.isEmpty) ? (suffix as NSString).length : 0
        let suffixStartIndex = currentText.length - suffixLength
        verboseLog("[SuffixEnforcedTextField] shouldChange: current='\(currentText)', range=\(range), string='\(string)', suffix='\(suffix)', isSuffixEnforced=\(isSuffixEnforced), suffixStartIndex=\(suffixStartIndex)")
        guard suffixStartIndex >= 0 else { return true }

        // Full replacement (e.g. Select All + paste or type)
        if range.location == 0 && range.length == currentText.length {
            let cleanBase = InfoPlistParser.sanitizeBundleID(string)
            let finalString = isSuffixEnforced && !suffix.isEmpty
                ? (cleanBase.hasSuffix(suffix) ? cleanBase : cleanBase + suffix)
                : cleanBase
            textField.text = finalString
            onTextUpdated?(finalString)
            return false
        }

        // Drop any keystroke that touches or encroaches on the persistent suffix
        if isSuffixEnforced && !suffix.isEmpty && range.location + range.length > suffixStartIndex {
            return false
        }

        // Allowed characters for Apple bundle identifier: alphanumeric, hyphen, period
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        if !string.isEmpty && string.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return false
        }

        // Prevent typing or inserting consecutive dots
        if string.contains("..") {
            return false
        }
        if string.hasPrefix(".") && range.location == 0 {
            return false
        }
        if string.hasPrefix(".") && range.location > 0 {
            let prevChar = currentText.substring(with: NSRange(location: range.location - 1, length: 1))
            if prevChar == "." {
                return false
            }
        }
        if string.hasSuffix(".") && range.location + range.length < currentText.length {
            let nextChar = currentText.substring(with: NSRange(location: range.location + range.length, length: 1))
            if nextChar == "." {
                return false
            }
        }

        return true
    }
}
