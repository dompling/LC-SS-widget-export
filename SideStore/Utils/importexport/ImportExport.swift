//
//  ImportExport.swift
//  SideStore
//
//  Created by Magesh K on 07/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


@preconcurrency import UIKit
import SideSign
import CryptoKit
import CommonCrypto
import UniformTypeIdentifiers

enum BackupEncryptionError: Error, LocalizedError {
    case invalidPassword
    case decryptionFailed
    case exportPasswordMatchesApplePassword
    case invalidDataFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid password."
        case .decryptionFailed:
            return "Incorrect password or corrupted backup file."
        case .exportPasswordMatchesApplePassword:
            return "File password cannot be the same as Apple ID password stored in secure keychain."
        case .invalidDataFormat:
            return "The backup file format is invalid."
        }
    }
}

class ImportExport {
    
    #if !os(tvOS)
    public static var documentPickerHandler: DocumentPickerHandler?
    #endif

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedKeyData = Data(count: 32)
        
        _ = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        10000,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        return SymmetricKey(data: derivedKeyData)
    }

    public static func exportAccount(password: String, includeApplePassword: Bool) throws -> Data {
        guard let email = AuthManager.shared.currentAppleID,
              let activeCert = CertificateManager.shared.activeCertificate,
              let identifier = AnisetteConfigManager.shared.anisetteIdentifier,
              let adiPB = AnisetteConfigManager.shared.anisetteAdiBlob else {
            throw OperationError.invalidParameters("Account or signing data is missing.")
        }
        
        if let applePass = AuthManager.shared.password, password == applePass {
            throw BackupEncryptionError.exportPasswordMatchesApplePassword
        }

        let applePasswordToInclude = includeApplePassword ? AuthManager.shared.password : nil
        let account: ImportedAccount
        if let certPass = activeCert.password {
            account = ImportedAccount(version: ImportedAccount.currentVersion, email: email, password: applePasswordToInclude, certificateData: activeCert.p12Data, certificatePassword: certPass, anisetteIdentifier: identifier, anisetteAdiBlob: adiPB)
        } else {
            account = ImportedAccount(version: ImportedAccount.currentVersion, email: email, password: applePasswordToInclude, certificateData: activeCert.p12Data, anisetteIdentifier: identifier, anisetteAdiBlob: adiPB)
        }

        let jsonData = try Foundation.JSONEncoder().encode(account)
        
        var salt = Data(count: 16)
        let result = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard result == errSecSuccess else {
            throw OperationError.invalidParameters("Failed to generate random salt.")
        }
        
        let key = deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combinedData = sealedBox.combined else {
            throw OperationError.invalidParameters("Encryption payload failed.")
        }
        
        var finalData = Data()
        finalData.append(salt)
        finalData.append(combinedData)
        return finalData
    }

    public static func importAccount(_ encryptedData: Data, filePassword: String) async throws -> ImportedAccount {
        guard encryptedData.count > 16 else {
            throw BackupEncryptionError.invalidDataFormat
        }
        
        let salt = encryptedData.prefix(16)
        let ciphertext = encryptedData.dropFirst(16)
        
        let key = deriveKey(password: filePassword, salt: salt)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let account = try Foundation.JSONDecoder().decode(ImportedAccount.self, from: decryptedData)
            
            await AuthManager.shared.signOut()
            AuthManager.shared.currentAppleID = account.email
            if let pass = account.password, !pass.isEmpty {
                AuthManager.shared.password = pass
            }
            AnisetteConfigManager.shared.anisetteAdiBlob = account.anisetteAdiBlob
            AnisetteConfigManager.shared.anisetteIdentifier = account.anisetteIdentifier
            
            let altCert = try CertificateManager.parse(account.certificateData, password: account.certificatePassword)
            try CertificateManager.shared.setActiveCertificate(altCert)
            
            return account
        } catch {
            throw BackupEncryptionError.decryptionFailed
        }
    }
    
    public static func getPreviousBackupURL(_ backupURL: URL) -> URL {
        let backupParentDirectory = backupURL.deletingLastPathComponent()
        let backupName = backupURL.lastPathComponent
        let backupBakURL = backupParentDirectory.appendingPathComponent("\(backupName).bak")
        return backupBakURL
    }
    
    /// Renames the existing backup contents at `backupURL` to `<foldername>.bak`.
    private static func renameBackupContents(at backupURL: URL) throws {
        
        // rename backup to backup.bak dir only if backup dir exists
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        
        let backupBakURL = getPreviousBackupURL(backupURL)
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupBakURL.path) {
            try fileManager.removeItem(at: backupBakURL) // Remove any existing .bak directory
        }
        
        try fileManager.moveItem(at: backupURL, to: backupBakURL)
    }
    
    /// Handles importing new backup data into the designated backup directory.
    private static func importBackupContents(from documentPickerURL: URL, to backupURL: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure the backup directory exists.
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        debugLog("Backup URL: \(backupURL)")
        debugLog("Document Picker URL: \(documentPickerURL)")
        
        let isDirectory = (try? documentPickerURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            // Enumerate the contents of the selected directory and copy them to the backup directory.
            let selectedContents = try fileManager.contentsOfDirectory(
                at: documentPickerURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for itemURL in selectedContents {
                let destinationURL = backupURL.appendingPathComponent(itemURL.lastPathComponent)
                
                // Remove the existing file if it exists at the destination.
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                // Copy the item.
                try fileManager.copyItem(at: itemURL, to: destinationURL)
            }
        } else if documentPickerURL.pathExtension.lowercased() == "zip" {
            try fileManager.unzipArchive(at: documentPickerURL, to: backupURL)
        } else {
            throw OperationError.invalidParameters("Unsupported backup format: \(documentPickerURL.lastPathComponent)")
        }
    }
    
    public static func importBackup(presentingViewController: UIViewController,
                                    for installedApp: InstalledApp,
                                    isZip: Bool = false,
                                    completionHandler: @escaping (Result<Void, Error>) -> Void){
        guard let backupURL = FileManager.default.backupDirectoryURL(for: installedApp) else {
            return completionHandler(.failure(OperationError.invalidParameters("Error: Backup directory URL not found.")))
        }
        
        let handleSelectedURL: (URL?) -> Void = { selectedURL in
            guard let selectedURL = selectedURL else {
                return completionHandler(.failure( OperationError.cancelled))
            }
            
            // resolve symlinks if any, so that prefix match works
            let appUserDataDir = FileManager.default.documentsDirectory.resolvingSymlinksInPath()
            let tempDir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            let isAllowedPath = selectedURL.resolvingSymlinksInPath().path.hasPrefix(appUserDataDir.path) || selectedURL.resolvingSymlinksInPath().path.hasPrefix(tempDir.path)
            guard isAllowedPath else {
                return completionHandler(.failure(
                    OperationError.forbidden(failureReason: "Selected backup data directory is not within the app's user data directory"))
                )
            }
            
            do {
                // Rename existing backup contents to `<foldername>.bak`.
                try Self.renameBackupContents(at: backupURL)
                
                // Import the contents of the selected folder into the backup directory.
                try Self.importBackupContents(from: selectedURL, to: backupURL)
                
                debugLog("Backup imported successfully to: \(backupURL.path)")
                return completionHandler(.success(()))
            } catch {
                debugLog("Backup Error: \(error)")
                return completionHandler(.failure( OperationError.invalidParameters(error.localizedDescription)))
            }
        }

        #if !os(tvOS)
        let contentTypes: [UTType] = isZip ? [.zip] : [.folder]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: isZip)
        documentPicker.allowsMultipleSelection = false
                
        // Create a handler and set it as the delegate
        Self.documentPickerHandler = DocumentPickerHandler { selectedURL in
            handleSelectedURL(selectedURL)
        }
        
        documentPicker.delegate = Self.documentPickerHandler
        // Present the picker
        presentingViewController.present(documentPicker, animated: true, completion: nil)
        #else
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: ["zip", "backup"],
            title: "Import App Backup",
            presentingVC: presentingViewController
        ) { selectedURL in
            handleSelectedURL(selectedURL)
        }
        #endif
    }
}

#if DEBUG
extension ImportExport {
    static func exportAccountJSON(password: String) -> ImportedAccount? {
        guard let email = AuthManager.shared.currentAppleID,
              let passwordStr = AuthManager.shared.password,
              let activeCert = CertificateManager.shared.activeCertificate,
              let identifier = AnisetteConfigManager.shared.anisetteIdentifier,
              let adiPB = AnisetteConfigManager.shared.anisetteAdiBlob else {
            return nil
        }
        if let certPass = activeCert.password {
            return ImportedAccount(version: ImportedAccount.currentVersion, email: email, password: passwordStr, certificateData: activeCert.p12Data, certificatePassword: certPass, anisetteIdentifier: identifier, anisetteAdiBlob: adiPB)
        } else {
            return ImportedAccount(version: ImportedAccount.currentVersion, email: email, password: passwordStr, certificateData: activeCert.p12Data, anisetteIdentifier: identifier, anisetteAdiBlob: adiPB)
        }
    }

    static func importAccountJSON(from file: URL) async throws {
        _ = file.startAccessingSecurityScopedResource()
        defer { file.stopAccessingSecurityScopedResource() }
        
        let accountData = try Data(contentsOf: file)
        let account = try Foundation.JSONDecoder().decode(ImportedAccount.self, from: accountData)
        
        await AuthManager.shared.signOut()
        AuthManager.shared.currentAppleID = account.email
        AuthManager.shared.password = account.password
        AnisetteConfigManager.shared.anisetteAdiBlob = account.anisetteAdiBlob
        AnisetteConfigManager.shared.anisetteIdentifier = account.anisetteIdentifier
        
        let altCert = try CertificateManager.parse(account.certificateData, password: account.certificatePassword)
        try CertificateManager.shared.setActiveCertificate(altCert)
    }
}
#endif

#if !os(tvOS)
private struct AssociatedKeys {
    static var documentPickerHandler: UInt8 = 0
}


class DocumentPickerHandler: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
#endif
