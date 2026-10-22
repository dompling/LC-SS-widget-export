//
//  ProfileManagementView.swift
//  SideStore
//
//  Created by Magesh K on 14/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign
import UniformTypeIdentifiers

struct PendingProfileImport: Identifiable {
    let id = UUID()
    let profile: ALTProvisioningProfile
    let analysis: ProfileManager.CertificateAnalysisResult
}

struct ProfileManagementView: View {
    weak var presentingViewController: UIViewController?

    @StateObject private var viewModel = ProfileManagementViewModel()
    @StateObject private var certificatesViewModel = CertificatesViewModel()
    @StateObject private var devServicesViewModel = DeveloperServicesViewModel()

    @State private var searchText = ""
    @State private var showFileImporter = false
    @State private var profileToDelete: ALTProvisioningProfile? = nil
    @State private var showDeleteConfirmation = false
    @State private var showPortalDeleteConfirmation = false
    @State private var profileToShareURL: URL? = nil
    @State private var pendingImport: PendingProfileImport? = nil
    @State private var profileToEditOnPortal: ALTListedProvisioningProfile? = nil
    @State private var showAddOptions = false
    @State private var navigateToPortalProfiles = false

    private var allowedImportTypes: [UTType] {
        [UTType(filenameExtension: "mobileprovision")].compactMap { $0 }
    }

    private var filteredProfiles: [ALTProvisioningProfile] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.profiles
        }
        return viewModel.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText) ||
            $0.teamName.localizedCaseInsensitiveContains(searchText) ||
            $0.uuid.uuidString.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            List {
                Section(header: Text("Overview")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(viewModel.profiles.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(viewModel.readyCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Portal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(viewModel.portalCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Missing Cert")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(viewModel.profiles.count - viewModel.readyCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(viewModel.profiles.count - viewModel.readyCount > 0 ? .orange : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(
                    header: Text("Provisioning Profiles (\(filteredProfiles.count))"),
                    footer: Text("Provisioning profiles dictate entitlements, device permissions, and expiration dates. Profiles sync automatically with your developer account.")
                ) {
                    if filteredProfiles.isEmpty {
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            Text(searchText.isEmpty ? "No provisioning profiles installed. Tap '+' to import or pull to refresh." : "No matching provisioning profiles found.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    } else {
                        ForEach(filteredProfiles, id: \.uuid) { profile in
                            NavigationLink(destination: ProvisioningProfileDetailView(profile: profile, profileURL: ProfileManager.shared.profileURL(for: profile.uuid), certificatesViewModel: certificatesViewModel)) {
                                ProfileManagementRowView(profile: profile, isRemote: viewModel.isRemoteProfile(profile), formatDate: formatDate)
                            }
                            #if !os(tvOS)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                SwiftUI.Button(role: .destructive) {
                                    promptDelete(profile)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                if viewModel.canEditProfileOnPortal(profile) {
                                    SwiftUI.Button {
                                        if let listed = viewModel.listedProfile(for: profile.uuid) {
                                            profileToEditOnPortal = listed
                                        }
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.purple)
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                SwiftUI.Button {
                                    shareProfile(profile)
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                            #endif
                            .contextMenu {
                                if viewModel.canEditProfileOnPortal(profile) {
                                    SwiftUI.Button {
                                        if let listed = viewModel.listedProfile(for: profile.uuid) {
                                            profileToEditOnPortal = listed
                                        }
                                    } label: {
                                        Label("Edit on Developer Portal", systemImage: "pencil")
                                    }
                                }
                                SwiftUI.Button {
                                    shareProfile(profile)
                                } label: {
                                    Label("Share Profile", systemImage: "square.and.arrow.up")
                                }
                                SwiftUI.Button(role: .destructive) {
                                    promptDelete(profile)
                                } label: {
                                    Label("Delete Profile", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            #if !os(tvOS)
            .listStyle(InsetGroupedListStyle())
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Profiles")
            #else
            .listStyle(GroupedListStyle())
            #endif

            if let message = viewModel.toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                        .shadow(radius: 6)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: viewModel.toastMessage)
            }
        }
        .navigationTitle("Profile Management")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    showAddOptions = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Provisioning Profile")
            }
        }
        .onAppear {
            viewModel.loadProfiles(isPullToRefresh: false)
        }
        .refreshable {
            viewModel.loadProfiles(isPullToRefresh: true)
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                handleFileSelected(at: url)
            case .failure(let error):
                viewModel.showToast("Import canceled: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: Binding<Bool>(
            get: { profileToShareURL != nil },
            set: { if !$0 { profileToShareURL = nil } }
        )) {
            if let url = profileToShareURL {
                ActivityViewController(activityItems: [url])
            }
        }
        #endif
        .sheet(item: $profileToEditOnPortal) { listed in
            NavigationView {
                ProfilePortalDetailView(profile: listed, viewModel: devServicesViewModel, presentingViewController: presentingViewController)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            SwiftUI.Button("Done") {
                                profileToEditOnPortal = nil
                                viewModel.loadProfiles(isPullToRefresh: true)
                            }
                        }
                    }
            }
        }
        .alert(item: $pendingImport) { pending in
            switch pending.analysis {
            case .signable(let certName, _):
                return Alert(
                    title: Text("Link Signing Certificate?"),
                    message: Text("Found matching signing certificate '\(certName)' with private key in SideStore.\n\nWould you like to link and save this profile?"),
                    primaryButton: .default(Text("Link & Save")) {
                        commitImport(pending.profile)
                    },
                    secondaryButton: .cancel()
                )
            case .publicOnly(let certName, _):
                return Alert(
                    title: Text("Missing Private Key"),
                    message: Text("Found certificate '\(certName)' in this profile, but no matching private key (.p12) was found in SideStore.\n\nContinuing means this profile will not be usable for signing apps until a matching signing certificate with private key is imported."),
                    primaryButton: .destructive(Text("Import Anyway")) {
                        commitImport(pending.profile)
                    },
                    secondaryButton: .cancel()
                )
            case .noMatch(let count):
                return Alert(
                    title: Text("No Matching Signing Certificate"),
                    message: Text("This provisioning profile contains \(count) developer certificate(s), but none match any signing certificates in SideStore.\n\nContinuing means this profile will not be usable for signing apps until a matching signing certificate with private key is imported."),
                    primaryButton: .destructive(Text("Import Anyway")) {
                        commitImport(pending.profile)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Local Profile?"),
                message: Text("Are you sure you want to delete '\(profileToDelete?.name ?? "this profile")' from local storage? Any apps assigned to this profile will revert to default."),
                primaryButton: .destructive(Text("Delete")) {
                    if let target = profileToDelete {
                        Task {
                            await viewModel.deleteProfile(target, alsoDeleteFromPortal: false)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Delete Portal Profile?", isPresented: $showPortalDeleteConfirmation) {
            SwiftUI.Button("Delete from Portal & Locally", role: .destructive) {
                if let target = profileToDelete {
                    Task {
                        await viewModel.deleteProfile(target, alsoDeleteFromPortal: true)
                    }
                }
            }
            SwiftUI.Button("Delete Locally Only") {
                if let target = profileToDelete {
                    Task {
                        await viewModel.deleteProfile(target, alsoDeleteFromPortal: false)
                    }
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("'\((profileToDelete?.name ?? "This profile"))' exists on the Apple Developer Portal. Do you want to delete it from Apple's servers as well, or only delete the local cache?")
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            SwiftUI.Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog("Add Provisioning Profile", isPresented: $showAddOptions, titleVisibility: .visible) {
            SwiftUI.Button("Import from Files") {
                importProfileAction()
            }
            SwiftUI.Button("Create on Developer Portal") {
                Task {
                    await devServicesViewModel.loadAll(presentingViewController: presentingViewController)
                }
                navigateToPortalProfiles = true
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        }
        .onChange(of: navigateToPortalProfiles) { isActive in
            if !isActive {
                viewModel.loadProfiles(isPullToRefresh: true)
            }
        }
        .background(
            NavigationLink(
                destination: ProfilesListView(viewModel: devServicesViewModel, presentingViewController: presentingViewController),
                isActive: $navigateToPortalProfiles
            ) {
                EmptyView()
            }
            .hidden()
        )
    }

    private func handleFileSelected(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let profile = try ALTProvisioningProfile(data: data)
            let analysis = ProfileManager.shared.analyzeCertificates(for: profile)
            self.pendingImport = PendingProfileImport(profile: profile, analysis: analysis)
        } catch {
            viewModel.showToast("Invalid provisioning profile: \(error.localizedDescription)")
        }
    }

    private func commitImport(_ profile: ALTProvisioningProfile) {
        do {
            _ = try ProfileManager.shared.importProfile(data: profile.data)
            viewModel.loadProfiles(isPullToRefresh: false)
            viewModel.showToast("Imported '\(profile.name)' successfully")
        } catch {
            viewModel.showToast("Failed to import profile: \(error.localizedDescription)")
        }
    }

    private func promptDelete(_ profile: ALTProvisioningProfile) {
        profileToDelete = profile
        if viewModel.isRemoteProfile(profile) {
            showPortalDeleteConfirmation = true
        } else {
            showDeleteConfirmation = true
        }
    }

    private func importProfileAction() {
        #if !os(tvOS)
        showFileImporter = true
        #else
        guard let topVC = presentingViewController ?? UIApplication.shared.topViewController() else { return }
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: ["mobileprovision"],
            title: "Import Provisioning Profile",
            presentingVC: topVC
        ) { fileURL in
            guard let fileURL = fileURL else { return }
            handleFileSelected(at: fileURL)
        }
        #endif
    }

    private func shareProfile(_ profile: ALTProvisioningProfile) {
        let fileURL = ProfileManager.shared.profileURL(for: profile.uuid)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        #if !os(tvOS)
        profileToShareURL = fileURL
        #else
        guard let topVC = presentingViewController ?? UIApplication.shared.topViewController() else { return }
        TVWebFileTransferManager.shared.startExport(
            fileURL: fileURL,
            title: "Export Provisioning Profile",
            presentingVC: topVC,
            completion: nil
        )
        #endif
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct ProfileManagementRowView: View {
    let profile: ALTProvisioningProfile
    let isRemote: Bool
    let formatDate: (Date) -> String

    private var isExpired: Bool {
        profile.expirationDate < Date()
    }

    private var matchingCert: ALTCertificate? {
        ProfileManager.shared.getMatchingCertificate(for: profile)
    }

    private var assignedApps: [String] {
        ProfileManager.shared.getAppsUsingProfile(uuid: profile.uuid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                if isRemote {
                    HStack(spacing: 3) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 8))
                        Text("Portal")
                            .fontWeight(.medium)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 8))
                        Text("Local")
                            .fontWeight(.medium)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundColor(.secondary)
                    .cornerRadius(6)
                }

                if isExpired {
                    Text("Expired")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                } else if matchingCert != nil {
                    Text("Ready")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                } else {
                    Text("No Key")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                }
                Text("Expires: \(formatDate(profile.expirationDate))")
                    .font(.caption)
                    .foregroundColor(isExpired ? .red : .secondary)
            }

            HStack {
                Text(profile.bundleIdentifier)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(profile.teamName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let cert = matchingCert {
                HStack(spacing: 4) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("Signer: \(cert.name)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if !assignedApps.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                    Text("Assigned: \(assignedApps.joined(separator: ", "))")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
