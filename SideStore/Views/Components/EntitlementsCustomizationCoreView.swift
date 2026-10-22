//
//  EntitlementsCustomizationCoreView.swift
//  SideStore
//
//  Created by Magesh K on 13/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UIKit
import SideSign

public enum EntitlementsCustomizationStyle {
    case sheet
    case dialog
}

public struct EntitlementsCustomizationCoreView: View {
    public let style: EntitlementsCustomizationStyle
    @StateObject private var viewModel: EntitlementsCustomizationViewModel
    @State private var expandedItemIDs: Set<String> = []

    private func toggleExpanded(_ id: String) {
        if expandedItemIDs.contains(id) {
            expandedItemIDs.remove(id)
        } else {
            expandedItemIDs.insert(id)
        }
    }

    public init(
        style: EntitlementsCustomizationStyle,
        targets: [EntitlementsTarget],
        teamType: ALTTeamType,
        onProceed: @escaping ([String: [String: any Sendable]]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.style = style
        _viewModel = StateObject(wrappedValue: EntitlementsCustomizationViewModel(
            targets: targets,
            teamType: teamType,
            onProceed: onProceed,
            onCancel: onCancel
        ))
    }

    public init(
        style: EntitlementsCustomizationStyle,
        initialEntitlements: [String: any Sendable],
        bundleID: String,
        teamType: ALTTeamType,
        onProceed: @escaping ([String: any Sendable]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.style = style
        _viewModel = StateObject(wrappedValue: EntitlementsCustomizationViewModel(
            initialEntitlements: initialEntitlements,
            bundleID: bundleID,
            teamType: teamType,
            onProceed: onProceed,
            onCancel: onCancel
        ))
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
                contentView
            }
            .background(Color(UIColor.systemGroupedBackground))
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    hideKeyboard()
                }
            )
            .navigationTitle("Customize Entitlements")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    viewModel.onCancel()
                },
                trailing: SwiftUI.Button("Proceed") {
                    viewModel.handleProceed()
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
        .sheet(isPresented: $viewModel.isShowingAddCustomSheet) {
            addCustomKeySheet
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
                dialogHeaderView

                Divider()

                ScrollView {
                    contentView
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        hideKeyboard()
                    }
                )

                Divider()

                dialogActionBar
            }
            .frame(maxWidth: 500, maxHeight: 660)
            .background(Color(UIColor.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $viewModel.isShowingAddCustomSheet) {
            addCustomKeySheet
        }
    }

    private var dialogHeaderView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Customize Entitlements")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)

                if viewModel.targets.count <= 1 {
                    Text(viewModel.bundleID)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            accountBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var dialogActionBar: some View {
        HStack(spacing: 12) {
            SwiftUI.Button(action: {
                viewModel.onCancel()
            }) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            SwiftUI.Button(action: {
                viewModel.handleProceed()
            }) {
                Text("Proceed")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var accountBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.teamType == .free ? "person.crop.circle" : "star.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(viewModel.teamType == .free ? "Free Account" : "Paid Developer")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(viewModel.teamType == .free ? Color.orange : Color.green)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            (viewModel.teamType == .free ? Color.orange : Color.green).opacity(0.12)
        )
        .clipShape(Capsule())
    }

    private var contentView: some View {
        VStack(spacing: 20) {
            if style == .sheet {
                HStack {
                    if viewModel.targets.count <= 1 {
                        Text(viewModel.bundleID)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    accountBadge
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            targetPickerView

            searchBar

            activeEntitlementsSection

            availableEntitlementsSection

            addCustomKeyButton
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var targetPickerView: some View {
        if viewModel.targets.count > 1 {
            Menu {
                ForEach(viewModel.targets) { target in
                    SwiftUI.Button {
                        hideKeyboard()
                        viewModel.selectTarget(id: target.id)
                    } label: {
                        HStack {
                            Text(target.name)
                            if target.id == viewModel.selectedTargetID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(viewModel.currentTarget?.name ?? viewModel.selectedTargetID)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)

                            Text(viewModel.currentTarget?.isExtension == true ? "Extension" : "Main App")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundColor(.secondary)
                        }

                        Text(viewModel.selectedTargetID)
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
            .padding(.horizontal, 16)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("Search entitlements...", text: $viewModel.searchQuery)
                .font(.system(size: 14))
                .textFieldStyle(PlainTextFieldStyle())

            if !viewModel.searchQuery.isEmpty {
                SwiftUI.Button(action: {
                    viewModel.searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var activeEntitlementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVE ENTITLEMENTS (\(viewModel.filteredActiveEntries.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)

            if viewModel.filteredActiveEntries.isEmpty {
                VStack(spacing: 6) {
                    Text("No active entitlements")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Select additional entitlements below or tap '+' to add one.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredActiveEntries.enumerated()), id: \.element.id) { index, entry in
                        activeEntitlementRow(entry: entry)

                        if index < viewModel.filteredActiveEntries.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    private func activeEntitlementRow(entry: EntitlementEntry) -> some View {
        let isAllowed = viewModel.isEntitlementAllowed(entry.key)
        let isKeyExpanded = expandedItemIDs.contains(entry.id.uuidString)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.key)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(isKeyExpanded ? nil : 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    toggleExpanded(entry.id.uuidString)
                                }
                            }

                        if entry.isAppDefault {
                            Text("App Default")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text("Added")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if !isAllowed {
                            Text("Unsupported on \(viewModel.teamType.displayName)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    if let known = Entitlement.allKnown.first(where: { $0.id == entry.key }) {
                        Text(known.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if entry.type == .boolean {
                    Toggle("", isOn: viewModel.bindingForBool(entryID: entry.id))
                        .labelsHidden()
                        .disabled(!isAllowed)
                }

                SwiftUI.Button(action: {
                    viewModel.deleteEntry(entryID: entry.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.leading, 4)
            }

            if entry.type == .string || entry.type == .number {
                TextField("Value", text: viewModel.bindingForString(entryID: entry.id))
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(!isAllowed)
            } else if entry.type == .stringArray {
                arrayEditorView(entry: entry, isAllowed: isAllowed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func arrayEditorView(entry: EntitlementEntry, isAllowed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.arrayValue.isEmpty {
                Text("No values (empty array)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(entry.arrayValue.enumerated()), id: \.offset) { index, item in
                    let itemKey = "\(entry.id.uuidString)-arr-\(index)"
                    let isItemExpanded = expandedItemIDs.contains(itemKey)
                    HStack(spacing: 6) {
                        Text(item)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(isItemExpanded ? nil : 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    toggleExpanded(itemKey)
                                }
                            }

                        Spacer()

                        if isAllowed {
                            SwiftUI.Button(action: {
                                viewModel.removeArrayItem(entryID: entry.id, index: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            if isAllowed {
                HStack(spacing: 8) {
                    TextField("Add item (e.g. group.id)", text: $viewModel.newArrayItemText)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    SwiftUI.Button(action: {
                        viewModel.addArrayItem(entryID: entry.id)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                    }
                    .disabled(viewModel.newArrayItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var availableEntitlementsSection: some View {
        let available = viewModel.availableCatalogEntries

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AVAILABLE FOR YOUR ACCOUNT (\(available.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)

            if available.isEmpty {
                Text("All permitted account entitlements have been added.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(available.enumerated()), id: \.element.id) { index, entitlement in
                        availableEntitlementRow(entitlement: entitlement)

                        if index < available.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    private func availableEntitlementRow(entitlement: Entitlement) -> some View {
        let isEntExpanded = expandedItemIDs.contains(entitlement.id)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entitlement.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(entitlement.valueType.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }

                Text(entitlement.rawValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(isEntExpanded ? nil : 1)

                Text(entitlement.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(isEntExpanded ? nil : 2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toggleExpanded(entitlement.id)
                }
            }

            Spacer()

            SwiftUI.Button(action: {
                viewModel.addKnownEntitlement(entitlement)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var addCustomKeyButton: some View {
        SwiftUI.Button(action: {
            viewModel.resetCustomKeyFields()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add Custom Entitlement Key")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .foregroundColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
    }

    private var addCustomKeySheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Entitlement Key")) {
                    TextField("e.g. com.apple.security.application-groups", text: $viewModel.newCustomKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, design: .monospaced))
                }

                Section(header: Text("Type")) {
                    Picker("Value Type", selection: $viewModel.newCustomType) {
                        ForEach(EntitlementValueType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Value")) {
                    switch viewModel.newCustomType {
                    case .boolean:
                        Toggle("Enabled", isOn: $viewModel.newCustomBool)
                    case .string, .number:
                        TextField("Value", text: $viewModel.newCustomString)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    case .stringArray:
                        TextField("Items (comma-separated)", text: $viewModel.newCustomArrayText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
            }
            .navigationTitle("Add Entitlement")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    viewModel.isShowingAddCustomSheet = false
                },
                trailing: SwiftUI.Button("Add") {
                    viewModel.commitCustomKey()
                    viewModel.isShowingAddCustomSheet = false
                }
                .disabled(viewModel.newCustomKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.system(size: 16, weight: .bold))
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
