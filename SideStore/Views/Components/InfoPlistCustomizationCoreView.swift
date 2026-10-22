//
//  InfoPlistCustomizationCoreView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit
import SideSign

public enum InfoPlistCustomizationStyle {
    case sheet
    case dialog
}

public struct InfoPlistTarget: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isExtension: Bool
    public let initialPlist: [String: any Sendable]

    public init(
        id: String,
        name: String? = nil,
        isExtension: Bool = false,
        initialPlist: [String: any Sendable]
    ) {
        let parser = InfoPlistParser(dictionary: initialPlist)
        self.id = id
        self.name = name ?? parser.displayName ?? parser.bundleName ?? id
        self.isExtension = isExtension
        self.initialPlist = initialPlist
    }
}

public struct InfoPlistCustomizationCoreView: View {
    public let style: InfoPlistCustomizationStyle
    public let targets: [InfoPlistTarget]
    public let initialBundleID: String
    public let installedAppIdentities: [String: String]
    public let teamID: String
    public let onProceed: (([String: any Sendable], Bool) -> Void)?
    public let onProceedTargets: (([String: [String: any Sendable]], Bool) -> Void)?
    public let onCancel: () -> Void

    @State private var selectedTargetID: String
    @State private var targetStates: [String: TargetState] = [:]

    @State private var bundleID: String
    @State private var previousValidBundleID: String
    @State private var appendTeamID: Bool
    @State private var displayName: String
    @State private var versionString: String
    @State private var buildNumber: String
    @State private var minimumOSVersion: String
    @State private var fileSharingEnabled: Bool
    @State private var openingDocumentsInPlace: Bool

    @State private var rawEntries: [RawPlistEntry] = []
    @State private var rawSearchQuery: String = ""
    @State private var isShowingRawKeys: Bool = false
    @State private var isShowingAddKeySheet: Bool = false
    @State private var newKeyName: String = ""
    @State private var newKeyValue: String = ""
    @State private var newKeyType: RawPlistType = .string
    @State private var expandedKeyIDs: Set<UUID> = []

    public enum RawPlistType: String, CaseIterable, Identifiable {
        case string = "String"
        case boolean = "Boolean"
        case number = "Number"
        public var id: String { rawValue }
    }

    public struct RawPlistEntry: Identifiable {
        public let id = UUID()
        public var key: String
        public var value: String
        public var type: RawPlistType
    }

    struct TargetState {
        var bundleID: String
        var previousValidBundleID: String
        var appendTeamID: Bool
        var displayName: String
        var versionString: String
        var buildNumber: String
        var minimumOSVersion: String
        var fileSharingEnabled: Bool
        var openingDocumentsInPlace: Bool
        var rawEntries: [RawPlistEntry]

        init(
            bundleID: String,
            previousValidBundleID: String,
            appendTeamID: Bool,
            displayName: String,
            versionString: String,
            buildNumber: String,
            minimumOSVersion: String,
            fileSharingEnabled: Bool,
            openingDocumentsInPlace: Bool,
            rawEntries: [RawPlistEntry]
        ) {
            self.bundleID = bundleID
            self.previousValidBundleID = previousValidBundleID
            self.appendTeamID = appendTeamID
            self.displayName = displayName
            self.versionString = versionString
            self.buildNumber = buildNumber
            self.minimumOSVersion = minimumOSVersion
            self.fileSharingEnabled = fileSharingEnabled
            self.openingDocumentsInPlace = openingDocumentsInPlace
            self.rawEntries = rawEntries
        }

        init(target: InfoPlistTarget, teamID: String, appendTeamID: Bool) {
            let parser = InfoPlistParser(dictionary: target.initialPlist)
            self.displayName = parser.displayName ?? parser.bundleName ?? ""
            self.versionString = parser.shortVersionString ?? ""
            self.buildNumber = parser.buildVersion ?? ""
            self.minimumOSVersion = parser.minimumOSVersion ?? ""
            self.fileSharingEnabled = parser.isFileSharingEnabled
            self.openingDocumentsInPlace = parser.supportsOpeningDocumentsInPlace
            self.appendTeamID = appendTeamID

            let trimmed = target.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let base: String
            if !teamID.isEmpty && trimmed.hasSuffix(".\(teamID)") {
                base = String(trimmed.dropLast((".\(teamID)").count))
            } else {
                base = trimmed
            }
            let sanitizedBase = InfoPlistParser.sanitizeBundleID(base)
            let finalID = (appendTeamID && !teamID.isEmpty && !target.isExtension) ? "\(sanitizedBase).\(teamID)" : (target.isExtension ? trimmed : sanitizedBase)

            self.bundleID = finalID
            self.previousValidBundleID = finalID

            let standardKeys: Set<String> = [
                "CFBundleIdentifier",
                "CFBundleDisplayName",
                "CFBundleName",
                "CFBundleShortVersionString",
                "CFBundleVersion",
                "MinimumOSVersion",
                "UIFileSharingEnabled",
                "LSSupportsOpeningDocumentsInPlace"
            ]

            var entries: [RawPlistEntry] = []
            for (key, val) in target.initialPlist where !standardKeys.contains(key) {
                if let boolVal = val as? Bool {
                    entries.append(RawPlistEntry(key: key, value: boolVal ? "YES" : "NO", type: .boolean))
                } else if let numVal = val as? NSNumber {
                    entries.append(RawPlistEntry(key: key, value: numVal.stringValue, type: .number))
                } else if let strVal = val as? String {
                    entries.append(RawPlistEntry(key: key, value: strVal, type: .string))
                }
            }
            entries.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            self.rawEntries = entries
        }
    }

    var currentTarget: InfoPlistTarget {
        targets.first(where: { $0.id == selectedTargetID }) ?? targets.first ?? InfoPlistTarget(id: initialBundleID, name: initialBundleID, isExtension: false, initialPlist: [:])
    }

    public init(
        style: InfoPlistCustomizationStyle,
        targets: [InfoPlistTarget],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = "",
        onProceed: @escaping ([String: [String: any Sendable]], Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.style = style
        let resolvedTargets = targets.isEmpty
            ? [InfoPlistTarget(id: initialBundleID, name: initialBundleID, isExtension: false, initialPlist: [:])]
            : targets
        self.targets = resolvedTargets
        self.initialBundleID = initialBundleID
        self.installedAppIdentities = installedAppIdentities
        self.teamID = teamID
        self.onProceedTargets = onProceed
        self.onProceed = nil
        self.onCancel = onCancel

        let initialID = resolvedTargets.first?.id ?? initialBundleID
        var initialStates: [String: TargetState] = [:]
        for target in resolvedTargets {
            initialStates[target.id] = TargetState(target: target, teamID: teamID, appendTeamID: appendTeamID)
        }

        let firstState = initialStates[initialID] ?? TargetState(target: resolvedTargets[0], teamID: teamID, appendTeamID: appendTeamID)

        _selectedTargetID = State(initialValue: initialID)
        _targetStates = State(initialValue: initialStates)
        _bundleID = State(initialValue: firstState.bundleID)
        _previousValidBundleID = State(initialValue: firstState.previousValidBundleID)
        _appendTeamID = State(initialValue: appendTeamID)
        _displayName = State(initialValue: firstState.displayName)
        _versionString = State(initialValue: firstState.versionString)
        _buildNumber = State(initialValue: firstState.buildNumber)
        _minimumOSVersion = State(initialValue: firstState.minimumOSVersion)
        _fileSharingEnabled = State(initialValue: firstState.fileSharingEnabled)
        _openingDocumentsInPlace = State(initialValue: firstState.openingDocumentsInPlace)
        _rawEntries = State(initialValue: firstState.rawEntries)
    }

    public init(
        style: InfoPlistCustomizationStyle,
        initialPlist: [String: any Sendable],
        initialBundleID: String,
        appendTeamID: Bool = true,
        installedAppIdentities: [String: String] = [:],
        teamID: String = "",
        onProceed: @escaping ([String: any Sendable], Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let target = InfoPlistTarget(
            id: initialBundleID,
            initialPlist: initialPlist
        )
        self.style = style
        self.targets = [target]
        self.initialBundleID = initialBundleID
        self.installedAppIdentities = installedAppIdentities
        self.teamID = teamID
        self.onProceed = onProceed
        self.onProceedTargets = nil
        self.onCancel = onCancel

        let state = TargetState(target: target, teamID: teamID, appendTeamID: appendTeamID)

        _selectedTargetID = State(initialValue: initialBundleID)
        _targetStates = State(initialValue: [initialBundleID: state])
        _bundleID = State(initialValue: state.bundleID)
        _previousValidBundleID = State(initialValue: state.previousValidBundleID)
        _appendTeamID = State(initialValue: appendTeamID)
        _displayName = State(initialValue: state.displayName)
        _versionString = State(initialValue: state.versionString)
        _buildNumber = State(initialValue: state.buildNumber)
        _minimumOSVersion = State(initialValue: state.minimumOSVersion)
        _fileSharingEnabled = State(initialValue: state.fileSharingEnabled)
        _openingDocumentsInPlace = State(initialValue: state.openingDocumentsInPlace)
        _rawEntries = State(initialValue: state.rawEntries)
    }

    public var body: some View {
        switch style {
        case .sheet:
            sheetBody
        case .dialog:
            dialogBody
        }
    }

    private var sheetBody: some View {
        NavigationView {
            ScrollView {
                scrollContent
            }
            .background(Color(UIColor.systemGroupedBackground))
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    hideKeyboard()
                }
            )
            .navigationTitle("Customize Info.plist")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    onCancel()
                },
                trailing: SwiftUI.Button("Proceed") {
                    handleProceed()
                }
                .font(.system(size: 16, weight: .bold))
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    SwiftUI.Button("Done") {
                        hideKeyboard()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $isShowingAddKeySheet) {
            addKeySheet
        }
    }

    private var dialogBody: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 0) {
                headerView

                Divider()
                ScrollView {
                    scrollContent
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        hideKeyboard()
                    }
                )

                Divider()

                actionBar
            }
            .frame(maxWidth: 480, maxHeight: 640)
            .background(Color(UIColor.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    SwiftUI.Button("Done") {
                        hideKeyboard()
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddKeySheet) {
            addKeySheet
        }
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            targetPickerView

            identitySection
            versionSection
            capabilitiesSection
            advancedKeysSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var targetPickerView: some View {
        if targets.count > 1 {
            Menu {
                ForEach(targets) { target in
                    SwiftUI.Button {
                        switchTarget(to: target.id)
                    } label: {
                        HStack {
                            Text(target.name)
                            if target.id == selectedTargetID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(currentTarget.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)

                            Text(currentTarget.isExtension ? "Extension" : "Main App")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundColor(.secondary)
                        }

                        Text(selectedTargetID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func switchTarget(to newID: String) {
        guard newID != selectedTargetID else { return }
        hideKeyboard()

        // 1. Commit outgoing draft into its container
        targetStates[selectedTargetID] = TargetState(
            bundleID: bundleID,
            previousValidBundleID: previousValidBundleID,
            appendTeamID: appendTeamID,
            displayName: displayName,
            versionString: versionString,
            buildNumber: buildNumber,
            minimumOSVersion: minimumOSVersion,
            fileSharingEnabled: fileSharingEnabled,
            openingDocumentsInPlace: openingDocumentsInPlace,
            rawEntries: rawEntries
        )

        // 2. Switch selected target ID
        selectedTargetID = newID

        // 3. Load incoming target draft container
        let incoming: TargetState
        if let existing = targetStates[newID] {
            incoming = existing
        } else if let target = targets.first(where: { $0.id == newID }) {
            incoming = TargetState(target: target, teamID: teamID, appendTeamID: appendTeamID)
            targetStates[newID] = incoming
        } else {
            return
        }

        bundleID = incoming.bundleID
        previousValidBundleID = incoming.previousValidBundleID
        appendTeamID = incoming.appendTeamID
        displayName = incoming.displayName
        versionString = incoming.versionString
        buildNumber = incoming.buildNumber
        minimumOSVersion = incoming.minimumOSVersion
        fileSharingEnabled = incoming.fileSharingEnabled
        openingDocumentsInPlace = incoming.openingDocumentsInPlace
        rawEntries = incoming.rawEntries
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 36, height: 36)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Customize Info.plist")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Review and adjust app metadata before installing")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    private var resolvedEffectiveBundleID: String {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if appendTeamID && !teamID.isEmpty {
            if trimmed.hasSuffix(".\(teamID)") {
                return trimmed
            } else {
                return "\(trimmed).\(teamID)"
            }
        }
        return trimmed
    }

    private var matchingExistingAppName: String? {
        let target = resolvedEffectiveBundleID
        return installedAppIdentities[target]
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "APP IDENTITY", icon: "app.badge.checkmark")

            VStack(spacing: 0) {
                if currentTarget.isExtension {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bundle Identifier")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(bundleID)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        Text("Extension bundle identifier is managed relative to the main application.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bundle Identifier")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SuffixEnforcedTextField(
                            text: $bundleID,
                            placeholder: "com.example.app",
                            suffix: !teamID.isEmpty ? ".\(teamID)" : "",
                            isSuffixEnforced: appendTeamID,
                            autocapitalization: .none,
                            onCommit: { hideKeyboard() }
                        )
                        .frame(height: 22)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 16)

                    SwiftUI.Button(action: {
                        appendTeamID.toggle()
                        guard !teamID.isEmpty else { return }
                        let suffix = ".\(teamID)"
                        if appendTeamID {
                            let clean = InfoPlistParser.sanitizeBundleID(bundleID)
                            bundleID = clean.hasSuffix(suffix) ? clean : "\(clean)\(suffix)"
                        } else {
                            if bundleID.hasSuffix(suffix) {
                                bundleID = String(bundleID.dropLast(suffix.count))
                            }
                        }
                        previousValidBundleID = bundleID
                        debugLog("[InfoPlistCustomizationCoreView] appendTeamID toggled to \(appendTeamID) -> bundleID='\(bundleID)'")
                    }) {
                        HStack {
                            Text("Append Team ID to Bundle Identifier")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: appendTeamID ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(appendTeamID ? .blue : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider().padding(.leading, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("My App", text: $displayName)
                        .font(.system(size: 15))
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let existingName = matchingExistingAppName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                    Text("Matches installed app \"\(existingName)\" — will update existing app")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            } else {
                Text("If the bundle ID is not present in the database, it will install as a separate app.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "VERSIONING", icon: "number")

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1.0.0", text: $versionString)
                            .font(.system(size: 15))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().frame(height: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Build")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1", text: $buildNumber)
                            .font(.system(size: 15))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                    }
                    .frame(width: 90)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider().padding(.leading, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum iOS Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("15.0", text: $minimumOSVersion)
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "CAPABILITIES & SHARING", icon: "folder.badge.gearshape")

            VStack(spacing: 0) {
                Toggle(isOn: $fileSharingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable iTunes File Sharing")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Text("Exposes Documents directory via Finder/iTunes")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().padding(.leading, 16)

                Toggle(isOn: $openingDocumentsInPlace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Documents In Place")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Text("Allows Files app to edit documents directly")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var advancedKeysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader(title: "ALL RAW KEYS", icon: "ellipsis.curlybraces")
                Spacer()
                SwiftUI.Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingRawKeys.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isShowingRawKeys ? "Collapse" : "Expand (\(rawEntries.count))")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: isShowingRawKeys ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.trailing, 16)
                }
            }

            if isShowingRawKeys {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            TextField("Filter keys...", text: $rawSearchQuery)
                                .font(.system(size: 14))
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                            if !rawSearchQuery.isEmpty {
                                SwiftUI.Button(action: { rawSearchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        SwiftUI.Button(action: { isShowingAddKeySheet = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(12)

                    let filtered = rawEntries.filter {
                        rawSearchQuery.isEmpty || $0.key.localizedCaseInsensitiveContains(rawSearchQuery)
                    }

                    if filtered.isEmpty {
                        Divider().padding(.leading, 16)
                        Text("No matching keys found")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(filtered.indices, id: \.self) { index in
                            Divider().padding(.leading, 16)
                            let item = filtered[index]
                            rawKeyRow(for: item)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func rawKeyRow(for item: RawPlistEntry) -> some View {
        let isExpanded = expandedKeyIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.key)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(isExpanded ? nil : 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedKeyIDs.contains(item.id) {
                                expandedKeyIDs.remove(item.id)
                            } else {
                                expandedKeyIDs.insert(item.id)
                            }
                        }
                    }
                Spacer()
                Text(item.type.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())

                SwiftUI.Button(action: {
                    rawEntries.removeAll { $0.key == item.key }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            if let targetIdx = rawEntries.firstIndex(where: { $0.key == item.key }) {
                if item.type == .boolean {
                    Picker("", selection: Binding(
                        get: { rawEntries[targetIdx].value == "YES" },
                        set: { rawEntries[targetIdx].value = $0 ? "YES" : "NO" }
                    )) {
                        Text("YES").tag(true)
                        Text("NO").tag(false)
                    }
                    .pickerStyle(.segmented)
                } else {
                    TextField("Value", text: $rawEntries[targetIdx].value)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            SwiftUI.Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            SwiftUI.Button(action: handleProceed) {
                Text("Proceed")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    private var addKeySheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Key Name")) {
                    TextField("e.g. CFBundleURLTypes", text: $newKeyName)
                        .autocapitalization(.none)
                }

                Section(header: Text("Value Type")) {
                    Picker("Type", selection: $newKeyType) {
                        ForEach(RawPlistType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Value")) {
                    if newKeyType == .boolean {
                        Picker("Boolean Value", selection: $newKeyValue) {
                            Text("YES").tag("YES")
                            Text("NO").tag("NO")
                        }
                        .pickerStyle(.segmented)
                    } else {
                        TextField("Value", text: $newKeyValue)
                            .autocapitalization(.none)
                    }
                }
            }
            .navigationTitle("Add Plist Key")
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    newKeyName = ""
                    newKeyValue = ""
                    isShowingAddKeySheet = false
                },
                trailing: SwiftUI.Button("Add") {
                    let trimmed = newKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    rawEntries.removeAll { $0.key == trimmed }
                    let finalVal = newKeyType == .boolean && newKeyValue.isEmpty ? "YES" : newKeyValue
                    rawEntries.append(RawPlistEntry(key: trimmed, value: finalVal, type: newKeyType))
                    newKeyName = ""
                    newKeyValue = ""
                    isShowingAddKeySheet = false
                }
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.secondary)
        .padding(.leading, 4)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func serialize(state: TargetState, for target: InfoPlistTarget) -> [String: any Sendable] {
        var updated = target.initialPlist

        if !target.isExtension {
            let cleanBaseID: String = {
                let trimmed = state.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = ".\(teamID)"
                let base: String
                if state.appendTeamID && !teamID.isEmpty && trimmed.hasSuffix(suffix) {
                    base = String(trimmed.dropLast(suffix.count))
                } else {
                    base = trimmed
                }
                return InfoPlistParser.sanitizeBundleID(base)
            }()
            if !cleanBaseID.isEmpty {
                updated["CFBundleIdentifier"] = cleanBaseID
            }
        }

        let cleanDisplayName = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDisplayName.isEmpty {
            updated["CFBundleDisplayName"] = cleanDisplayName
            updated["CFBundleName"] = cleanDisplayName
        }

        let cleanVersion = state.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanVersion.isEmpty {
            updated["CFBundleShortVersionString"] = cleanVersion
        }

        let cleanBuild = state.buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanBuild.isEmpty {
            updated["CFBundleVersion"] = cleanBuild
        }

        let cleanMinOS = state.minimumOSVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanMinOS.isEmpty {
            updated["MinimumOSVersion"] = cleanMinOS
        }

        updated["UIFileSharingEnabled"] = state.fileSharingEnabled
        updated["LSSupportsOpeningDocumentsInPlace"] = state.openingDocumentsInPlace

        for entry in state.rawEntries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            switch entry.type {
            case .boolean:
                updated[key] = (entry.value.uppercased() == "YES" || entry.value == "1" || entry.value.lowercased() == "true")
            case .number:
                if let intVal = Int(entry.value) {
                    updated[key] = intVal
                } else if let doubleVal = Double(entry.value) {
                    updated[key] = doubleVal
                } else {
                    updated[key] = entry.value
                }
            case .string:
                updated[key] = entry.value
            }
        }

        return updated
    }

    private func handleProceed() {
        hideKeyboard()

        targetStates[selectedTargetID] = TargetState(
            bundleID: bundleID,
            previousValidBundleID: previousValidBundleID,
            appendTeamID: appendTeamID,
            displayName: displayName,
            versionString: versionString,
            buildNumber: buildNumber,
            minimumOSVersion: minimumOSVersion,
            fileSharingEnabled: fileSharingEnabled,
            openingDocumentsInPlace: openingDocumentsInPlace,
            rawEntries: rawEntries
        )

        var allResults: [String: [String: any Sendable]] = [:]
        for target in targets {
            let state = targetStates[target.id] ?? TargetState(target: target, teamID: teamID, appendTeamID: appendTeamID)
            allResults[target.id] = serialize(state: state, for: target)
        }

        let mainID = targets.first(where: { !$0.isExtension })?.id ?? targets.first?.id ?? initialBundleID
        let mainPlist = allResults[mainID] ?? [:]
        let mainAppendTeamID = targetStates[mainID]?.appendTeamID ?? appendTeamID

        onProceedTargets?(allResults, mainAppendTeamID)
        onProceed?(mainPlist, mainAppendTeamID)
    }
}
