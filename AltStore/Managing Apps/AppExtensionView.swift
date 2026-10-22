//
//  AppExtensionView.swift
//  SideStore
//
//  Created by June P on 8/17/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct AppExtensionView: View {
    var extensions: Set<ALTApplication>
    @State var selection: [ALTApplication] = []
        
    var completion: (_ selection: [ALTApplication]) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(self.extensions.sorted {
                    $0.bundleIdentifier < $1.bundleIdentifier
                }, id: \.self) { item in
                    MultipleSelectionRow(title: item.bundleIdentifier, isSelected: !selection.contains(item)) {
                        if self.selection.contains(item) {
                            self.selection.removeAll(where: { $0 == item })
                        }
                        else {
                            self.selection.append(item)
                        }
                    }
                }
            }
            .navigationTitle("App Extensions")
            .onDisappear {
                completion(selection)
            }
        }
    }
}

struct MultipleSelectionRow: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        SwiftUI.Button(action: self.action) {
            HStack {
                Text(self.title)
                if self.isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

class AppExtensionViewHostingController: UIHostingController<AppExtensionView> {
    
    
    var completion: Optional<(_ selection: [ALTApplication]) -> Void>?
    
    required init(extensions: Set<ALTApplication>, completion: @escaping (_ selection: [ALTApplication]) -> Void) {
        self.completion = completion
        super.init(rootView: AppExtensionView(extensions: extensions, completion: completion))
    }
    
    @MainActor
    required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

#if !os(tvOS)
extension AppExtensionViewHostingController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
}
#endif
