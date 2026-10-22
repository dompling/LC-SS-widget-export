//
//  CertificateStore.swift
//  SideStore
//
//  Created by Magesh K on 3/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

public enum CertificateStore {
    /// Loads an ALTCertificate from PKCS#12 data. If password is provided, decrypts with password; if nil, loads unencrypted PKCS#12.
    public static func load(_ data: Data, password: String?) throws -> ALTCertificate {
        if let password = password {
            return try ALTCertificate(p12Data: data, password: password)
        } else {
            return try ALTCertificate(p12Data: data)
        }
    }

    /// Exports an ALTCertificate to PKCS#12 data. If password is provided, encrypts PKCS#12 with password; if nil, exports unencrypted PKCS#12.
    public static func export(_ cert: ALTCertificate, password: String?) throws -> Data {
        if let password = password {
            return try cert.encryptedP12Data(password: password)
        } else {
            return try cert.unencryptedP12Data()
        }
    }
}
