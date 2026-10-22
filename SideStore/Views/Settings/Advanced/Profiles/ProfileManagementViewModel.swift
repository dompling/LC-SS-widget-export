//
//  ProfileManagementViewModel.swift
//  SideStore
//
//  Created by Magesh K on 14/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import SideSign

final class ProfileManagementViewModel: ObservableObject, @unchecked Sendable {
    @Published var profiles: [ALTProvisioningProfile] = []
    @Published var remoteProfileUUIDs: Set<UUID> = []
    @Published var remoteProfileIdMap: [UUID: String] = [:]
    @Published var remoteProfilesMap: [UUID: ALTListedProvisioningProfile] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil {
        didSet { showErrorAlert = errorMessage != nil }
    }
    @Published var showErrorAlert: Bool = false
    @Published var toastMessage: String? = nil
    @Published var team: ALTTeam? = nil
    @Published var hasFetchedRemote: Bool = false

    var readyCount: Int {
        profiles.filter { ProfileManager.shared.isProfileReadyToSign($0) }.count
    }

    var portalCount: Int {
        profiles.filter { remoteProfileUUIDs.contains($0.uuid) }.count
    }

    var localOnlyCount: Int {
        profiles.filter { !remoteProfileUUIDs.contains($0.uuid) }.count
    }

    func isRemoteProfile(_ profile: ALTProvisioningProfile) -> Bool {
        remoteProfileUUIDs.contains(profile.uuid)
    }

    func listedProfile(for uuid: UUID) -> ALTListedProvisioningProfile? {
        remoteProfilesMap[uuid]
    }

    func canEditProfileOnPortal(_ profile: ALTProvisioningProfile) -> Bool {
        guard let listed = remoteProfilesMap[profile.uuid] else { return false }
        if listed.isTeamProfile == true {
            return false
        }
        return true
    }

    func loadProfiles(isPullToRefresh: Bool = false) {
        let localProfiles = ProfileManager.shared.getAllLocalProfiles()
        self.profiles = localProfiles
        if !isPullToRefresh {
            self.isLoading = true
        }

        Task {
            guard AuthManager.shared.isAuthenticated else {
                await MainActor.run {
                    self.isLoading = false
                }
                return
            }

            do {
                let currentTeam = try? await AuthManager.shared.getAuthenticatedTeam()
                let remoteList = try await DeveloperPortalProxy.shared.listProvisioningProfiles()

                var remoteUUIDs = Set<UUID>()
                var idMap: [UUID: String] = [:]
                var listedMap: [UUID: ALTListedProvisioningProfile] = [:]

                for remoteItem in remoteList {
                    remoteUUIDs.insert(remoteItem.uuid)
                    listedMap[remoteItem.uuid] = remoteItem
                    if let profileID = remoteItem.identifier {
                        idMap[remoteItem.uuid] = profileID
                        if ProfileManager.shared.getProfile(uuid: remoteItem.uuid) == nil {
                            if let downloaded = try? await DeveloperPortalProxy.shared.downloadProvisioningProfile(profileID: profileID) {
                                try? ProfileManager.shared.importProfile(data: downloaded.data)
                            }
                        }
                    }
                }

                let updatedLocal = ProfileManager.shared.getAllLocalProfiles()

                await MainActor.run {
                    self.team = currentTeam
                    self.remoteProfileUUIDs = remoteUUIDs
                    self.remoteProfileIdMap = idMap
                    self.remoteProfilesMap = listedMap
                    self.profiles = updatedLocal
                    self.hasFetchedRemote = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    if isPullToRefresh && !(error is CancellationError) {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func deleteProfile(_ profile: ALTProvisioningProfile, alsoDeleteFromPortal: Bool = false) async {
        ProfileManager.shared.deleteProfile(uuid: profile.uuid)

        if alsoDeleteFromPortal, let profileID = remoteProfileIdMap[profile.uuid] {
            do {
                _ = try await DeveloperPortalProxy.shared.deleteProvisioningProfile(profileID: profileID)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Deleted locally, but failed to delete from Developer Portal: \(error.localizedDescription)"
                }
            }
        }

        let updatedLocal = ProfileManager.shared.getAllLocalProfiles()
        await MainActor.run {
            self.remoteProfileUUIDs.remove(profile.uuid)
            self.remoteProfileIdMap.removeValue(forKey: profile.uuid)
            self.profiles = updatedLocal
            self.showToast("Deleted profile '\(profile.name)'")
        }
    }

    func showToast(_ message: String) {
        withAnimation {
            self.toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation {
                if self?.toastMessage == message {
                    self?.toastMessage = nil
                }
            }
        }
    }
}
