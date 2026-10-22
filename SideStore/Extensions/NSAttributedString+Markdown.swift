//
//  NSAttributedString+Markdown.swift
//
//  Created by Magesh K on 7/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

#if canImport(UIKit)
@preconcurrency import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformFontDescriptor = UIFontDescriptor
public typealias PlatformFontDescriptorSymbolicTraits = UIFontDescriptor.SymbolicTraits
private extension PlatformFontDescriptorSymbolicTraits {
    static var boldTrait: PlatformFontDescriptorSymbolicTraits { .traitBold }
    static var italicTrait: PlatformFontDescriptorSymbolicTraits { .traitItalic }
}
#elseif canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformFontDescriptor = NSFontDescriptor
public typealias PlatformFontDescriptorSymbolicTraits = NSFontDescriptor.SymbolicTraits
private extension PlatformFontDescriptorSymbolicTraits {
    static var boldTrait: PlatformFontDescriptorSymbolicTraits { .bold }
    static var italicTrait: PlatformFontDescriptorSymbolicTraits { .italic }
}
#endif

public struct MarkdownStyleKey: RawRepresentable, Hashable, Equatable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension MarkdownStyleKey {
    static let emphasisSingle = MarkdownStyleKey("MarkdownStyleEmphasisSingle")
    static let emphasisDouble = MarkdownStyleKey("MarkdownStyleEmphasisDouble")
    static let emphasisBoth = MarkdownStyleKey("MarkdownStyleEmphasisBoth")
    static let link = MarkdownStyleKey("MarkdownStyleLink")
}

public extension CharacterSet {
    static var markdownLiteralCharacterSet: CharacterSet {
        return CharacterSet(charactersIn: "\\*_`{}[](#+-..!")
    }
}

public extension NSAttributedString {
    
    enum MarkdownSpanType {
        case emphasisSingle
        case emphasisDouble
        case linkInline
        case linkAutomatic
    }
    
    convenience init(markdownRepresentation markdownString: String, attributes: [NSAttributedString.Key: Any]) {
        self.init(markdownRepresentation: markdownString, baseAttributes: attributes, styleAttributes: nil)
    }
    
    convenience init(
        markdownRepresentation markdownString: String,
        baseAttributes: [NSAttributedString.Key: Any],
        styleAttributes: [MarkdownStyleKey: [NSAttributedString.Key: Any]]? = nil
    ) {
        assert(baseAttributes[.font] != nil, "A font attribute is required")
        
        let result = NSMutableAttributedString(string: markdownString, attributes: baseAttributes)
        
        // 1. Replaces inline and automatic links
        let linkInlineStart = "["
        let linkInlineStartDivider = "]"
        let linkInlineEndDivider = "("
        let linkInlineEnd = ")"
        let linkInlineDividerMarker = linkInlineStartDivider + linkInlineEndDivider
        
        updateAttributedString(
            result: result,
            beginMarker: linkInlineStart,
            dividerMarker: linkInlineDividerMarker,
            endMarker: linkInlineEnd,
            spanType: .linkInline,
            styleAttributes: styleAttributes
        )
        
        let linkAutomaticStart = "<"
        let linkAutomaticEnd = ">"
        updateAttributedString(
            result: result,
            beginMarker: linkAutomaticStart,
            dividerMarker: nil,
            endMarker: linkAutomaticEnd,
            spanType: .linkAutomatic,
            styleAttributes: styleAttributes
        )
        
        // 2. Replaces double emphasis (** and __)
        let emphasisDoubleStart = "**"
        let emphasisDoubleEnd = "**"
        updateAttributedString(
            result: result,
            beginMarker: emphasisDoubleStart,
            dividerMarker: nil,
            endMarker: emphasisDoubleEnd,
            spanType: .emphasisDouble,
            styleAttributes: styleAttributes
        )
        
        let emphasisDoubleAlternateStart = "__"
        let emphasisDoubleAlternateEnd = "__"
        updateAttributedString(
            result: result,
            beginMarker: emphasisDoubleAlternateStart,
            dividerMarker: nil,
            endMarker: emphasisDoubleAlternateEnd,
            spanType: .emphasisDouble,
            styleAttributes: styleAttributes
        )
        
        // 3. Replaces single emphasis (* and _)
        let emphasisSingleStart = "_"
        let emphasisSingleEnd = "_"
        updateAttributedString(
            result: result,
            beginMarker: emphasisSingleStart,
            dividerMarker: nil,
            endMarker: emphasisSingleEnd,
            spanType: .emphasisSingle,
            styleAttributes: styleAttributes
        )
        
        let emphasisSingleAlternateStart = "*"
        let emphasisSingleAlternateEnd = "*"
        updateAttributedString(
            result: result,
            beginMarker: emphasisSingleAlternateStart,
            dividerMarker: nil,
            endMarker: emphasisSingleAlternateEnd,
            spanType: .emphasisSingle,
            styleAttributes: styleAttributes
        )
        
        // 4. Remove backslashes from any escaped characters
        removeEscapedCharacterSet(in: result, characterSet: .markdownLiteralCharacterSet)
        
        self.init(attributedString: result)
    }
    
    var markdownRepresentation: String {
        let result = NSMutableString()
        let cleanAttributedString = NSMutableAttributedString(attributedString: self)
        
        // Remove attributes that break range (like foreground color, paragraph style)
        cleanAttributedString.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: cleanAttributedString.length))
        cleanAttributedString.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: cleanAttributedString.length))
        
        let normalizedAttributedString = NSAttributedString(attributedString: cleanAttributedString)
        let normalizedString = normalizedAttributedString.string
        let normalizedLength = normalizedAttributedString.length
        
        var inBoldRun = false
        var inItalicRun = false
        
        var index = 0
        while index < normalizedLength {
            var currentRange = NSRange(location: NSNotFound, length: 0)
            let currentAttributes = normalizedAttributedString.attributes(at: index, effectiveRange: &currentRange)
            let currentString = (normalizedString as NSString).substring(with: currentRange)
            
            var nextAttributes: [NSAttributedString.Key: Any]? = nil
            let nextIndex = currentRange.location + currentRange.length
            if nextIndex < normalizedLength {
                nextAttributes = normalizedAttributedString.attributes(at: nextIndex, effectiveRange: nil)
            }
            
            let visualLineBreak = "\n\n"
            if currentString.contains(visualLineBreak) {
                let components = currentString.components(separatedBy: visualLineBreak)
                var visualLineBreakOffset = 0
                var currentComponentRange = NSRange(location: currentRange.location, length: 0)
                
                for component in components {
                    currentComponentRange.length = component.count + visualLineBreakOffset
                    emitMarkdown(
                        result: result,
                        normalizedString: normalizedString,
                        currentString: component,
                        currentRange: currentComponentRange,
                        currentAttributes: currentAttributes,
                        nextAttributes: nextAttributes,
                        inBoldRun: &inBoldRun,
                        inItalicRun: &inItalicRun
                    )
                    currentComponentRange.location = currentComponentRange.location + component.count + visualLineBreakOffset
                    visualLineBreakOffset = visualLineBreak.count
                }
            } else {
                emitMarkdown(
                    result: result,
                    normalizedString: normalizedString,
                    currentString: currentString,
                    currentRange: currentRange,
                    currentAttributes: currentAttributes,
                    nextAttributes: nextAttributes,
                    inBoldRun: &inBoldRun,
                    inItalicRun: &inItalicRun
                )
            }
            index = currentRange.location + currentRange.length
        }
        
        return result as String
    }
}

// MARK: - Private Helpers

private func addTrait(to attributedString: NSMutableAttributedString, trait: PlatformFontDescriptorSymbolicTraits, range: NSRange) {
    attributedString.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
        guard let font = value as? PlatformFont else { return }
        
        #if canImport(UIKit)
        let symbolicTraits = font.fontDescriptor.symbolicTraits.union(trait)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits) {
            let newFont = PlatformFont(descriptor: descriptor, size: font.pointSize)
            attributedString.removeAttribute(.font, range: subrange)
            attributedString.addAttribute(.font, value: newFont, range: subrange)
        }
        #else
        let symbolicTraits = font.fontDescriptor.symbolicTraits.union(trait)
        let descriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits)
        let newFont = PlatformFont(descriptor: descriptor, size: font.pointSize) ?? font
        attributedString.removeAttribute(.font, range: subrange)
        attributedString.addAttribute(.font, value: newFont, range: subrange)
        #endif
    }
}

private func replaceAttributes(spanType: NSAttributedString.MarkdownSpanType, styleAttributes: [MarkdownStyleKey: [NSAttributedString.Key: Any]]?, result: NSMutableAttributedString, range: NSRange) {
    guard let styleAttributes = styleAttributes else { return }
    result.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
        var checkKey: MarkdownStyleKey? = nil
        var replacementKey: MarkdownStyleKey? = nil
        
        if spanType == .emphasisSingle {
            checkKey = .emphasisDouble
            replacementKey = .emphasisSingle
        } else if spanType == .emphasisDouble {
            checkKey = .emphasisSingle
            replacementKey = .emphasisDouble
        }
        
        if let check = checkKey, let replacement = replacementKey {
            let checkAttrs = styleAttributes[check] ?? [:]
            var hasExisting = true
            for (key, val) in checkAttrs {
                if let attrVal = attributes[key], String(describing: attrVal) == String(describing: val) {
                    // match
                } else {
                    hasExisting = false
                    break
                }
            }
            
            let replacementAttrs: [NSAttributedString.Key: Any]?
            if hasExisting {
                replacementAttrs = styleAttributes[.emphasisBoth]
            } else {
                replacementAttrs = styleAttributes[replacement]
            }
            
            if let replacementAttrs = replacementAttrs {
                for key in replacementAttrs.keys {
                    result.removeAttribute(key, range: subrange)
                }
                result.addAttributes(replacementAttrs, range: subrange)
            }
        }
    }
}

private func updateAttributedString(
    result: NSMutableAttributedString,
    beginMarker: String,
    dividerMarker: String?,
    endMarker: String,
    spanType: NSAttributedString.MarkdownSpanType,
    styleAttributes: [MarkdownStyleKey: [NSAttributedString.Key: Any]]?
) {
    let scanString = result.string as NSString
    var mutationOffset = 0
    
    // Find horizontal rules to ignore
    var horizontalRuleRanges: [NSRange] = []
    if let rulerChar = beginMarker.first, (rulerChar == "*" || rulerChar == "_") {
        let rulerString = String(rulerChar)
        var checkIndex = 0
        while checkIndex < scanString.length {
            let lineRange = scanString.lineRange(for: NSRange(location: checkIndex, length: 0))
            let lineString = scanString.substring(with: lineRange)
            let compressed = lineString.replacingOccurrences(of: rulerString, with: "")
            let trimmed = compressed.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCount = lineString.filter { String($0) == rulerString }.count
            if trimmed.isEmpty && rawCount >= 3 {
                horizontalRuleRanges.append(lineRange)
            }
            checkIndex = lineRange.location + lineRange.length
            if lineRange.length == 0 { break }
        }
    }
    
    var scanIndex = 0
    while scanIndex < scanString.length {
        let remainingRange = NSRange(location: scanIndex, length: scanString.length - scanIndex)
        let beginRange = scanString.range(of: beginMarker, options: [], range: remainingRange)
        if beginRange.location == NSNotFound {
            break
        }
        
        // Check escaping
        let isEscaped = beginRange.location > 0 && scanString.character(at: beginRange.location - 1) == 92 // '\\'
        var isLiteralOrList = false
        if beginMarker.count == 1 {
            let hasPrefixStartOfLine = beginRange.location == 0 || scanString.character(at: beginRange.location - 1) == 10 // '\n'
            let hasPrefixSpace = beginRange.location > 0 && scanString.character(at: beginRange.location - 1) == 32 // ' '
            let hasSuffixSpace = beginRange.location + 1 < scanString.length && scanString.character(at: beginRange.location + 1) == 32
            let hasPrefixTab = beginRange.location > 0 && scanString.character(at: beginRange.location - 1) == 9 // '\t'
            let hasSuffixTab = beginRange.location + 1 < scanString.length && scanString.character(at: beginRange.location + 1) == 9
            if (hasPrefixStartOfLine || hasPrefixSpace || hasPrefixTab) && (hasSuffixSpace || hasSuffixTab) {
                isLiteralOrList = true
            }
        }
        
        let mutatedIndex = beginRange.location - mutationOffset
        var isLinked = false
        if mutatedIndex >= 0 && mutatedIndex < result.length {
            if result.attribute(.link, at: mutatedIndex, effectiveRange: nil) != nil {
                isLinked = true
            }
        }
        
        var isHorizontalRule = false
        for ruleRange in horizontalRuleRanges {
            if NSLocationInRange(beginRange.location, ruleRange) {
                isHorizontalRule = true
                break
            }
        }
        
        if isEscaped || isLiteralOrList || isLinked || isHorizontalRule {
            scanIndex = beginRange.location + beginRange.length
            continue
        }
        
        let beginIndex = beginRange.location + beginRange.length
        var foundEndMarker = false
        var endRange = NSRange(location: NSNotFound, length: 0)
        
        var scanEndIndex = beginIndex
        while scanEndIndex < scanString.length {
            var searchRange = NSRange(location: scanEndIndex, length: scanString.length - scanEndIndex)
            let visualLineRange = scanString.range(of: "\n\n", options: [], range: searchRange)
            if visualLineRange.location != NSNotFound {
                searchRange = NSRange(location: scanEndIndex, length: visualLineRange.location - scanEndIndex)
            }
            
            var dividerMissing = false
            if let divider = dividerMarker {
                let divRange = scanString.range(of: divider, options: [], range: searchRange)
                if divRange.location == NSNotFound {
                    dividerMissing = true
                } else {
                    let divEscaped = divRange.location > 0 && scanString.character(at: divRange.location - 1) == 92
                    if divEscaped {
                        dividerMissing = true
                    } else {
                        searchRange.length = searchRange.length - (NSMaxRange(divRange) - searchRange.location)
                        searchRange.location = NSMaxRange(divRange)
                    }
                }
            }
            
            endRange = scanString.range(of: endMarker, options: [], range: searchRange)
            if endRange.location != NSNotFound {
                let endEscaped = endRange.location > 0 && scanString.character(at: endRange.location - 1) == 92
                let hasPrefixSpace = endRange.location > 0 && scanString.character(at: endRange.location - 1) == 32
                let hasSuffixSpace = endRange.location + 1 < scanString.length && scanString.character(at: endRange.location + 1) == 32
                
                if !endEscaped && !(hasPrefixSpace && hasSuffixSpace) {
                    if !dividerMissing {
                        foundEndMarker = true
                        break
                    }
                }
                scanEndIndex = endRange.location + 1
            } else {
                break
            }
        }
        
        if foundEndMarker {
            let endIndex = endRange.location
            let mutatedBeginRange = NSRange(location: beginRange.location - mutationOffset, length: beginRange.length)
            let mutatedTextRange = NSRange(location: beginIndex - mutationOffset, length: endIndex - beginIndex)
            
            var replaceMarkers = false
            var replaceStyleAttributes = false
            var replacementString: String? = nil
            var replacementAttributes: [NSAttributedString.Key: Any]? = nil
            
            let matchTextRange = NSRange(location: beginIndex - mutationOffset, length: endIndex - beginIndex)
            
            switch spanType {
            case .emphasisSingle, .emphasisDouble:
                if beginIndex != endIndex {
                    replaceStyleAttributes = true
                    replaceMarkers = true
                }
            case .linkInline:
                let matchString = (result.string as NSString).substring(with: matchTextRange)
                var linkText: String? = nil
                var inlineLink: String? = nil
                
                let linkTextMarkerRange = (matchString as NSString).range(of: "]")
                if linkTextMarkerRange.location != NSNotFound {
                    linkText = (matchString as NSString).substring(to: linkTextMarkerRange.location)
                    let inlineLinkMarkerRange = (matchString as NSString).range(of: "(", options: .backwards)
                    if inlineLinkMarkerRange.location != NSNotFound {
                        if inlineLinkMarkerRange.location == linkTextMarkerRange.location + linkTextMarkerRange.length {
                            let markerIndex = inlineLinkMarkerRange.location + 1
                            inlineLink = (matchString as NSString).substring(from: markerIndex)
                        }
                    }
                }
                
                if let text = linkText, let link = inlineLink {
                    if let url = URL(string: link) {
                        replacementString = text
                        if let styleLink = styleAttributes?[.link] {
                            replacementAttributes = styleLink
                        } else {
                            replacementAttributes = [.link: url]
                        }
                        replaceMarkers = true
                    }
                }
            case .linkAutomatic:
                let string = (result.string as NSString).substring(with: matchTextRange)
                if let url = URL(string: string) {
                    if url.scheme != nil {
                        if let styleLink = styleAttributes?[.link] {
                            replacementAttributes = styleLink
                        } else {
                            replacementAttributes = [.link: url]
                        }
                        replaceMarkers = true
                    } else {
                        var synthesizedURL: URL? = nil
                        let emailPattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
                        if string.range(of: emailPattern, options: .regularExpression) != nil {
                            synthesizedURL = URL(string: "mailto:\(string)")
                        } else {
                            let domainPattern = "^[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
                            if string.range(of: domainPattern, options: .regularExpression) != nil {
                                synthesizedURL = URL(string: "https://\(string)")
                            }
                        }
                        
                        if let url = synthesizedURL {
                            if let styleLink = styleAttributes?[.link] {
                                replacementAttributes = styleLink
                            } else {
                                replacementAttributes = [.link: url]
                            }
                            replaceMarkers = true
                        }
                    }
                }
            }
            
            if replaceMarkers {
                result.replaceCharacters(in: mutatedBeginRange, with: "")
                mutationOffset += beginRange.length
                
                let currentMutatedTextRange = NSRange(location: beginIndex - mutationOffset, length: mutatedTextRange.length)
                
                if replaceStyleAttributes {
                    if spanType == .emphasisSingle {
                        if styleAttributes?[.emphasisSingle] != nil {
                            replaceAttributes(spanType: spanType, styleAttributes: styleAttributes, result: result, range: currentMutatedTextRange)
                        } else {
                            addTrait(to: result, trait: .italicTrait, range: currentMutatedTextRange)
                        }
                    } else if spanType == .emphasisDouble {
                        if styleAttributes?[.emphasisDouble] != nil {
                            replaceAttributes(spanType: spanType, styleAttributes: styleAttributes, result: result, range: currentMutatedTextRange)
                        } else {
                            addTrait(to: result, trait: .boldTrait, range: currentMutatedTextRange)
                        }
                    }
                }
                
                if let replacementAttributes = replacementAttributes {
                    result.addAttributes(replacementAttributes, range: currentMutatedTextRange)
                }
                
                if let replacementString = replacementString {
                    result.replaceCharacters(in: currentMutatedTextRange, with: replacementString)
                    mutationOffset += currentMutatedTextRange.length - replacementString.count
                }
                
                let mutatedEndRange = NSRange(location: endRange.location - mutationOffset, length: endRange.length)
                result.replaceCharacters(in: mutatedEndRange, with: "")
                mutationOffset += endRange.length
            }
            
            scanIndex = endRange.location + endRange.length
        } else {
            scanIndex = beginRange.location + beginRange.length
        }
    }
}

private func removeEscapedCharacterSet(in result: NSMutableAttributedString, characterSet: CharacterSet) {
    var scanStart = 0
    var needsScan = true
    while needsScan {
        let scanString = result.string as NSString
        guard scanStart < scanString.length else { break }
        
        let range = scanString.rangeOfCharacter(from: characterSet, options: [], range: NSRange(location: scanStart, length: scanString.length - scanStart))
        if range.location != NSNotFound {
            let hasEscapeMarker = range.location > 0 && scanString.character(at: range.location - 1) == 92 // '\\'
            if hasEscapeMarker {
                result.replaceCharacters(in: NSRange(location: range.location - 1, length: 1), with: "")
                scanStart = range.location
                if scanStart > result.length {
                    needsScan = false
                }
            } else {
                scanStart = range.location + range.length
            }
        } else {
            needsScan = false
        }
    }
}

private func adjustRangeForWhitespace(range: NSRange, string: NSString, prefixRange: inout NSRange, textRange: inout NSRange, suffixRange: inout NSRange) -> Bool {
    var adjusted = false
    let length = string.length
    
    var startIndex = range.location
    while startIndex < length {
        let char = string.character(at: startIndex)
        if char == 32 || char == 9 || char == 10 { // space, tab, newline
            startIndex += 1
            adjusted = true
        } else {
            break
        }
    }
    
    var endIndex = range.location + range.length - 1
    while endIndex > 0 {
        let char = string.character(at: endIndex)
        if char == 32 || char == 9 || char == 10 {
            endIndex -= 1
            adjusted = true
        } else {
            break
        }
    }
    endIndex += 1
    
    if startIndex < endIndex {
        prefixRange = NSRange(location: range.location, length: startIndex - range.location)
        textRange = NSRange(location: startIndex, length: endIndex - startIndex)
        suffixRange = NSRange(location: endIndex, length: range.location + range.length - endIndex)
    } else {
        prefixRange = NSRange(location: NSNotFound, length: 0)
        textRange = range
        suffixRange = NSRange(location: NSNotFound, length: 0)
    }
    
    return adjusted
}

private func addEscapesInMarkdownString(text: NSMutableString, marker: String) {
    if marker.count == 1 {
        var scanIndex = 0
        while scanIndex < text.length {
            let range = text.range(of: marker, options: [], range: NSRange(location: scanIndex, length: text.length - scanIndex))
            if range.location != NSNotFound {
                var isHorizontalRuler = false
                if range.location == 0 || (text as NSString).character(at: range.location - 1) == 10 {
                    var remainder = (text as NSString).substring(from: range.location)
                    let nlRange = (remainder as NSString).range(of: "\n")
                    if nlRange.location != NSNotFound {
                        remainder = (remainder as NSString).substring(to: nlRange.location)
                    }
                    let compressed = remainder.replacingOccurrences(of: " ", with: "")
                    let checked = compressed.replacingOccurrences(of: marker, with: "")
                    if checked.isEmpty && compressed.count >= 3 {
                        isHorizontalRuler = true
                        scanIndex = range.location + range.length + remainder.count - 1
                    }
                }
                
                if !isHorizontalRuler {
                    var insertEscape = false
                    var hasPrefixSpace = true
                    var hasSuffixSpace = true
                    
                    if range.location == 0 {
                        if text.length > 1 {
                            let nextChar = (text as NSString).character(at: 1)
                            hasSuffixSpace = nextChar == 32 || nextChar == 9 || nextChar == 10
                        }
                    } else if range.location == text.length - 1 {
                        let prevChar = (text as NSString).character(at: range.location - 1)
                        hasPrefixSpace = prevChar == 32 || prevChar == 9 || prevChar == 10
                    } else {
                        let prevChar = (text as NSString).character(at: range.location - 1)
                        let nextChar = (text as NSString).character(at: range.location + 1)
                        hasPrefixSpace = prevChar == 32 || prevChar == 9 || prevChar == 10
                        hasSuffixSpace = nextChar == 32 || nextChar == 9 || nextChar == 10
                    }
                    
                    if !(hasPrefixSpace && hasSuffixSpace) {
                        insertEscape = true
                    }
                    
                    if insertEscape {
                        text.insert("\\", at: range.location)
                        scanIndex = range.location + range.length + 1
                    } else {
                        scanIndex = range.location + range.length
                    }
                }
            } else {
                break
            }
        }
    }
}

private func updateMarkdownString(
    result: NSMutableString,
    string: String,
    prefixString: String?,
    prefixRange: NSRange,
    textRange: NSRange,
    suffixString: String?,
    suffixRange: NSRange,
    needsEscaping: Bool
) {
    if prefixRange.location != NSNotFound {
        let prefix = (string as NSString).substring(with: prefixRange)
        result.append(prefix)
    }
    
    if let prefixString = prefixString {
        result.append(prefixString)
    }
    
    let text = NSMutableString(string: (string as NSString).substring(with: textRange))
    if needsEscaping {
        addEscapesInMarkdownString(text: text, marker: "\\")
        addEscapesInMarkdownString(text: text, marker: "*")
        addEscapesInMarkdownString(text: text, marker: "_")
    }
    result.append(text as String)
    
    if let suffixString = suffixString {
        result.append(suffixString)
    }
    
    if suffixRange.location != NSNotFound {
        let suffix = (string as NSString).substring(with: suffixRange)
        result.append(suffix)
    }
}

private func emitMarkdown(
    result: NSMutableString,
    normalizedString: String,
    currentString: String,
    currentRange: NSRange,
    currentAttributes: [NSAttributedString.Key: Any],
    nextAttributes: [NSAttributedString.Key: Any]?,
    inBoldRun: inout Bool,
    inItalicRun: inout Bool
) {
    let trimmed = currentString.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
        var prefixRange = NSRange(location: NSNotFound, length: 0)
        var textRange = NSRange(location: NSNotFound, length: 0)
        var suffixRange = NSRange(location: NSNotFound, length: 0)
        _ = adjustRangeForWhitespace(range: currentRange, string: normalizedString as NSString, prefixRange: &prefixRange, textRange: &textRange, suffixRange: &suffixRange)
        updateMarkdownString(result: result, string: normalizedString, prefixString: nil, prefixRange: prefixRange, textRange: textRange, suffixString: nil, suffixRange: suffixRange, needsEscaping: false)
    } else {
        var currentRangeHasLink = false
        var currentRangeURL: URL? = nil
        
        if let linkVal = currentAttributes[.link] {
            var url: URL? = nil
            if let u = linkVal as? URL {
                url = u
            } else if let s = linkVal as? String {
                url = URL(string: s)
            }
            
            if let u = url {
                currentRangeHasLink = true
                if u.scheme != "mailto" && u.absoluteString != currentString {
                    currentRangeURL = u
                }
            }
        }
        
        var prefixString = ""
        var suffixString = ""
        
        var currentSymbolicTraits: PlatformFontDescriptorSymbolicTraits = []
        if let font = currentAttributes[.font] as? PlatformFont {
            currentSymbolicTraits = font.fontDescriptor.symbolicTraits
        }
        
        var nextSymbolicTraits: PlatformFontDescriptorSymbolicTraits = []
        if let nextAttrs = nextAttributes {
            if let font = nextAttrs[.font] as? PlatformFont {
                nextSymbolicTraits = font.fontDescriptor.symbolicTraits
            }
        }
        
        let currentRangeHasBold = currentSymbolicTraits.contains(.boldTrait)
        let currentRangeHasItalic = currentSymbolicTraits.contains(.italicTrait)
        let nextRangeHasBold = nextSymbolicTraits.contains(.boldTrait)
        let nextRangeHasItalic = nextSymbolicTraits.contains(.italicTrait)
        
        var needsEscaping = true
        
        if currentRangeHasBold {
            if !inBoldRun {
                prefixString += "**"
                inBoldRun = true
            }
        }
        if currentRangeHasItalic {
            if !inItalicRun {
                prefixString += "_"
                inItalicRun = true
            }
        }
        
        if currentRangeHasLink {
            if let url = currentRangeURL {
                prefixString += "["
                suffixString += "](\(url.absoluteString))"
            } else {
                needsEscaping = false
                prefixString += "<"
                suffixString += ">"
            }
        }
        
        if !nextRangeHasItalic {
            if inItalicRun {
                suffixString += "_"
                inItalicRun = false
            }
        }
        
        if !nextRangeHasBold {
            if inBoldRun {
                suffixString += "**"
                inBoldRun = false
            }
        }
        
        var prefixRange = NSRange(location: NSNotFound, length: 0)
        var textRange = NSRange(location: NSNotFound, length: 0)
        var suffixRange = NSRange(location: NSNotFound, length: 0)
        _ = adjustRangeForWhitespace(range: currentRange, string: normalizedString as NSString, prefixRange: &prefixRange, textRange: &textRange, suffixRange: &suffixRange)
        updateMarkdownString(result: result, string: normalizedString, prefixString: prefixString, prefixRange: prefixRange, textRange: textRange, suffixString: suffixString, suffixRange: suffixRange, needsEscaping: needsEscaping)
    }
}
