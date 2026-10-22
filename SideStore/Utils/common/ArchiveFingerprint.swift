//
//  ArchiveFingerprint.swift
//  SideStore
//
//  Created by Magesh K on 28/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CryptoKit
import SideSign

public enum ArchiveFingerprint {

    public static func compute(for url: URL) -> String? {
        guard url.isFileURL else { return nil }

        guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
            return nil
        }

        if resourceValues.isDirectory == true {
            return computeDirectoryFingerprint(for: url)
        }

        if let reader = try? Archive.Reader.open(at: url),
           let entries = try? reader.entries(),
           !entries.isEmpty {
            return computeArchiveFingerprint(entries: entries)
        }

        return computeFileHash(for: url)
    }

    private static func computeArchiveFingerprint(entries: [Archive.Entry]) -> String {
        var hasher = SHA256()
        let canonicalEntries = entries
            .filter { entry in
                !entry.filename.hasPrefix("__MACOSX") &&
                !entry.filename.contains("/__MACOSX/") &&
                !entry.filename.hasSuffix(".DS_Store")
            }
            .sorted { $0.filename < $1.filename }

        for entry in canonicalEntries {
            let line = "\(entry.filename)|\(entry.uncompressedSize)|\(entry.crc)\n"
            if let data = line.data(using: .utf8) {
                hasher.update(data: data)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func computeDirectoryFingerprint(for directoryURL: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var relativePaths: [String] = []
        var fileSizes: [String: Int64] = [:]

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let relPath = fileURL.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
            if relPath.hasPrefix("__MACOSX") || relPath.hasSuffix(".DS_Store") {
                continue
            }

            relativePaths.append(relPath)
            fileSizes[relPath] = Int64(resourceValues.fileSize ?? 0)
        }

        relativePaths.sort()

        var hasher = SHA256()
        for path in relativePaths {
            let size = fileSizes[path] ?? 0
            let line = "\(path)|\(size)\n"
            if let data = line.data(using: .utf8) {
                hasher.update(data: data)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func computeFileHash(for url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let bufferSize = 65536
        while true {
            guard let chunk = try? fileHandle.read(upToCount: bufferSize), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
