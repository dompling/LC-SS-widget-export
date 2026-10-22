//
//  AppBundleFingerprint.swift
//  SideStore
//
//  Created by Magesh K on 14/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CryptoKit

public enum AppBundleFingerprint {
    public static func compute(for bundleURL: URL) -> String? {
        func merkleNode(for url: URL) -> Data? {
            autoreleasepool {
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { return nil }

                var childEntries: [(name: String, hash: Data)] = []

                for itemURL in contents {
                    let name = itemURL.lastPathComponent

                    if name == "__MACOSX" || name == ".DS_Store" ||
                       name == "_CodeSignature" || name == "embedded.mobileprovision" {
                        continue
                    }

                    let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    if isDir {
                        if let subfolderHash = merkleNode(for: itemURL) {
                            childEntries.append((name: name, hash: subfolderHash))
                        }
                    } else {
                        let size = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                        let leafHash = SHA256.hash(data: "\(name)|\(size)\n".data(using: .utf8)!)
                        childEntries.append((name: name, hash: Data(leafHash)))
                    }
                }

                childEntries.sort { $0.name < $1.name }

                var nodeHasher = SHA256()
                for child in childEntries {
                    nodeHasher.update(data: child.name.data(using: .utf8)!)
                    nodeHasher.update(data: child.hash)
                }
                return Data(nodeHasher.finalize())
            }
        }

        guard let rootDigest = merkleNode(for: bundleURL) else { return nil }
        return rootDigest.map { String(format: "%02x", $0) }.joined()
    }
}
