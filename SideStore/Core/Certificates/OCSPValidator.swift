//
//  OCSPValidator.swift
//  SideStore
//
//  Created by Magesh K on 10/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CommonCrypto
import SideSign

public enum OCSPValidationError: Error, LocalizedError {
    case expired
    case revoked
    case invalidCertificate
    case missingIntermediateCertificate
    case ocspServerError(String)
    
    public var errorDescription: String? {
        switch self {
        case .expired:
            return "The certificate has expired."
        case .revoked:
            return "The certificate was revoked by Apple."
        case .invalidCertificate:
            return "Failed to parse the certificate data."
        case .missingIntermediateCertificate:
            return "Failed to fetch Apple WWDR intermediate certificate."
        case .ocspServerError(let message):
            return "OCSP server error: \(message)"
        }
    }
}

public enum OCSPLiveStatus: Equatable {
    case valid
    case revoked
    case unknown
    case error(String)
}

public struct OCSPValidator {
    
    private static let wwdrFetchTask = Task<SecCertificate?, Never> {
        let wwdrURL = URL(string: "http://certs.apple.com/wwdrg3.der")!
        var request = URLRequest(url: wwdrURL)
        request.cachePolicy = .returnCacheDataElseLoad
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let cert = SecCertificateCreateWithData(nil, data as CFData) {
                return cert
            }
        } catch {
            debugLog("[OCSPValidator] Failed to fetch WWDR G3 intermediate certificate: \(error)")
        }
        return nil
    }
    
    private static func getWWDRIntermediateCertificate() async -> SecCertificate? {
        return await wwdrFetchTask.value
    }
    
    // Validates an ALTCertificate against expiration and direct live un-cached Apple OCSP queries over HTTP.
    // NOTE: Newly submitted revocation requests on Apple Developer Portal may take time to propagate to Apple's public OCSP servers, 
    //       but are typically synchronized within 10 to 30 minutes from revocation time so this is a warning for anyone relying on this api 
    //       to confirm the revocation status, to expect waiting for a period of time before assuming anything about the result.
    //
    // NOTE: SecTrust reports might be delayed coz that is exactly what OS sees before AMFI flags the cert as revoked and doesn't let app opens
    //       so we still check that first just in case our live reporting wasn't good.
    public static func validate(_ certificate: ALTX509Certificate) async throws {
        // 1. Expiration check
        if certificate.expiryDate <= Date() {
            debugLog("[OCSPValidator] Certificate \(certificate.serialNumber) is expired (\(certificate.expiryDate)).")
            throw OCSPValidationError.expired
        }
        
        guard let data = certificate.data,
              let derData = getDERData(from: data) ?? certificate.data as Data?,
              let secCert = SecCertificateCreateWithData(nil, derData as CFData) else {
            debugLog("[OCSPValidator] Failed to parse SecCertificate for serial \(certificate.serialNumber).")
            throw OCSPValidationError.invalidCertificate
        }
        
        guard let wwdrCert = await getWWDRIntermediateCertificate() else {
            debugLog("[OCSPValidator] Failed to obtain WWDR G3 intermediate certificate.")
            throw OCSPValidationError.missingIntermediateCertificate
        }
        
        // 2. Apple SecTrust Evaluation (Fast local OS check)
        let isSecTrustRevoked = checkRevocationWithSecTrust(secCert: secCert, wwdrCert: wwdrCert)
        if isSecTrustRevoked {
            debugLog("[OCSPValidator] Certificate \(certificate.serialNumber) confirmed REVOKED by SecTrust evaluation!")
            throw OCSPValidationError.revoked
        }
        
        // 3. Direct un-cached HTTP OCSP Live Query
        let liveStatus = await fetchDirectLiveOCSPStatus(cert: secCert, issuerCert: wwdrCert)
        debugLog("[OCSPValidator] Direct Live HTTP OCSP status for \(certificate.serialNumber): \(liveStatus)")
        
        switch liveStatus {
        case .revoked:
            debugLog("[OCSPValidator] Certificate \(certificate.serialNumber) confirmed REVOKED by direct live OCSP query!")
            throw OCSPValidationError.revoked
        case .error(let message):
            debugLog("[OCSPValidator] Direct Live HTTP OCSP query error for \(certificate.serialNumber): \(message)")
            throw OCSPValidationError.ocspServerError(message)
        case .valid, .unknown:
            break
        }
    }
    
    public static func checkRevocationWithSecTrust(secCert: SecCertificate, wwdrCert: SecCertificate? = nil) -> Bool {
        let policy = SecPolicyCreateBasicX509()
        var optionalTrust: SecTrust?
        
        var certsToVerify: [SecCertificate] = [secCert]
        if let wwdrCert = wwdrCert {
            certsToVerify.append(wwdrCert)
        }
        
        let status = SecTrustCreateWithCertificates(certsToVerify as CFArray, policy, &optionalTrust)
        guard status == errSecSuccess, let trust = optionalTrust else {
            return false
        }
        
        SecTrustSetNetworkFetchAllowed(trust, true)
        
        if let revocationPolicy = SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationOCSPMethod | kSecRevocationCRLMethod | kSecRevocationRequirePositiveResponse)) {
            SecTrustSetPolicies(trust, revocationPolicy)
        }
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)
        
        if isValid {
            return false
        }
        
        if let err = error as Error? as NSError? {
            if let underlyingErr = err.userInfo[NSUnderlyingErrorKey] as? NSError {
                if underlyingErr.code == Int(errSecCertificateRevoked) || underlyingErr.code == -67820 || underlyingErr.localizedDescription.lowercased().contains("revoked") {
                    return true
                }
            }
            if err.code == Int(errSecCertificateRevoked) || err.code == -67820 || err.localizedDescription.lowercased().contains("revoked") {
                return true
            }
        }
        return false
    }
    
    public static func fetchDirectLiveOCSPStatus(cert: SecCertificate, issuerCert: SecCertificate) async -> OCSPLiveStatus {
        guard let certData = SecCertificateCopyData(cert) as Data?,
              let issuerCertData = SecCertificateCopyData(issuerCert) as Data? else {
            return .error("Failed to copy cert data")
        }
        
        guard let serialData = SecCertificateCopySerialNumberData(cert, nil) as Data? else {
            return .error("Failed to copy serial number")
        }
        
        guard let issuerSubjectDER = extractSubjectNameDER(from: issuerCertData),
              let issuerPublicKeyDER = extractPublicKeyDER(from: issuerCertData) else {
            return .error("Failed to extract Subject or Public Key DER")
        }
        
        let issuerNameHash = sha1(issuerSubjectDER)
        let issuerKeyHash = sha1(issuerPublicKeyDER)
        
        let sha1AlgID = Data([0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05, 0x00])
        
        var certIDContent = Data()
        certIDContent.append(sha1AlgID)
        certIDContent.append(derEncode(tag: 0x04, content: issuerNameHash))
        certIDContent.append(derEncode(tag: 0x04, content: issuerKeyHash))
        certIDContent.append(derInteger(serialData))
        let certID = derEncode(tag: 0x30, content: certIDContent)
        
        let request = derEncode(tag: 0x30, content: certID)
        let requestList = derEncode(tag: 0x30, content: request)
        let tbsRequest = derEncode(tag: 0x30, content: requestList)
        let ocspRequestDER = derEncode(tag: 0x30, content: tbsRequest)
        
        let ocspURLString = extractOCSPURL(from: certData) ?? "http://ocsp.apple.com/ocsp03-wwdrg303"
        guard let ocspURL = URL(string: ocspURLString) else {
            return .error("Invalid OCSP URL: \(ocspURLString)")
        }
        
        var httpRequest = URLRequest(url: ocspURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("application/ocsp-response", forHTTPHeaderField: "Accept")
        httpRequest.setValue(ocspURL.host ?? "ocsp.apple.com", forHTTPHeaderField: "Host")
        httpRequest.httpBody = ocspRequestDER
        httpRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: httpRequest)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return .error("HTTP Status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            
            return parseOCSPResponse(data)
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }
    
    private static func sha1(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    private static func derEncode(tag: UInt8, content: Data) -> Data {
        var result = Data([tag])
        let len = content.count
        if len < 128 {
            result.append(UInt8(len))
        } else if len < 256 {
            result.append(contentsOf: [0x81, UInt8(len)])
        } else if len < 65536 {
            result.append(contentsOf: [0x82, UInt8(len >> 8), UInt8(len & 0xFF)])
        } else {
            result.append(contentsOf: [0x83, UInt8(len >> 16), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)])
        }
        result.append(content)
        return result
    }
    
    private static func derInteger(_ data: Data) -> Data {
        var d = data
        while d.count > 1 && d[0] == 0 && (d[1] & 0x80) == 0 {
            d.removeFirst()
        }
        if d.count > 0 && (d[0] & 0x80) != 0 {
            d.insert(0x00, at: 0)
        }
        return derEncode(tag: 0x02, content: d)
    }
    
    private static func extractSubjectNameDER(from certDER: Data) -> Data? {
        let bytes = Array(certDER)
        guard bytes.count > 10 && bytes[0] == 0x30 else { return nil }
        
        var offset = getDERHeaderLength(bytes, start: 0)
        guard bytes[offset] == 0x30 else { return nil }
        offset += getDERHeaderLength(bytes, start: offset)
        
        if bytes[offset] == 0xA0 {
            let len = getDERElementLength(bytes, start: offset)
            offset += len
        }
        offset += getDERElementLength(bytes, start: offset) // serial
        offset += getDERElementLength(bytes, start: offset) // sig alg
        offset += getDERElementLength(bytes, start: offset) // issuer
        offset += getDERElementLength(bytes, start: offset) // validity
        
        if bytes[offset] == 0x30 {
            let len = getDERElementLength(bytes, start: offset)
            return Data(bytes[offset..<offset+len])
        }
        return nil
    }
    
    private static func extractPublicKeyDER(from certDER: Data) -> Data? {
        let bytes = Array(certDER)
        guard bytes.count > 10 && bytes[0] == 0x30 else { return nil }
        
        var offset = getDERHeaderLength(bytes, start: 0)
        guard bytes[offset] == 0x30 else { return nil }
        offset += getDERHeaderLength(bytes, start: offset)
        
        if bytes[offset] == 0xA0 { offset += getDERElementLength(bytes, start: offset) }
        offset += getDERElementLength(bytes, start: offset) // serial
        offset += getDERElementLength(bytes, start: offset) // sig alg
        offset += getDERElementLength(bytes, start: offset) // issuer
        offset += getDERElementLength(bytes, start: offset) // validity
        offset += getDERElementLength(bytes, start: offset) // subject
        
        if bytes[offset] == 0x30 {
            let spkiOffset = offset
            let spkiHeaderLen = getDERHeaderLength(bytes, start: spkiOffset)
            var pOffset = spkiOffset + spkiHeaderLen
            pOffset += getDERElementLength(bytes, start: pOffset) // alg ID
            if bytes[pOffset] == 0x03 {
                let bitStringHeaderLen = getDERHeaderLength(bytes, start: pOffset)
                let bitStringDataOffset = pOffset + bitStringHeaderLen + 1
                let bitStringLen = getDERElementLength(bytes, start: pOffset) - bitStringHeaderLen - 1
                return Data(bytes[bitStringDataOffset..<bitStringDataOffset+bitStringLen])
            }
        }
        return nil
    }
    
    private static func getDERHeaderLength(_ bytes: [UInt8], start: Int) -> Int {
        if start + 1 >= bytes.count { return 2 }
        let lenByte = bytes[start + 1]
        if lenByte < 128 { return 2 }
        return 2 + Int(lenByte & 0x7F)
    }
    
    private static func getDERElementLength(_ bytes: [UInt8], start: Int) -> Int {
        if start + 1 >= bytes.count { return 0 }
        let lenByte = bytes[start + 1]
        if lenByte < 128 { return 2 + Int(lenByte) }
        let numLenBytes = Int(lenByte & 0x7F)
        var contentLen = 0
        for i in 0..<numLenBytes {
            if start + 2 + i < bytes.count {
                contentLen = (contentLen << 8) | Int(bytes[start + 2 + i])
            }
        }
        return 2 + numLenBytes + contentLen
    }
    
    private static func extractOCSPURL(from certDER: Data) -> String? {
        guard let text = String(data: certDER, encoding: .ascii) else { return nil }
        if let range = text.range(of: "http://ocsp.apple.com/") {
            let urlPart = text[range.lowerBound...]
            let clean = urlPart.prefix(while: { $0.isASCII && !$0.isWhitespace && $0 != "\0" && $0 != "\n" && $0 != "\r" && $0 != "\"" })
            return String(clean)
        }
        return nil
    }
    
    private static func parseOCSPResponse(_ data: Data) -> OCSPLiveStatus {
        let bytes = Array(data)
        guard bytes.count > 5 && bytes[0] == 0x30 else {
            return .error("Invalid OCSP response DER")
        }
        
        let offset = getDERHeaderLength(bytes, start: 0)
        guard bytes[offset] == 0x0A && bytes[offset+1] == 0x01 else {
            return .error("Invalid OCSP responseStatus tag")
        }
        let responseStatus = bytes[offset+2]
        if responseStatus != 0 {
            return .error("OCSP Response Status code: \(responseStatus)")
        }
        
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == 0x80 && bytes[i+1] == 0x00 && bytes[i+2] == 0x18 {
                return .valid
            }
        }
        
        for i in 0..<(bytes.count - 20) {
            if (bytes[i] == 0xA1 || bytes[i] == 0x81) && (bytes[i+2] == 0x18 || bytes[i+3] == 0x18 || bytes[i+4] == 0x18 || bytes[i+18] == 0x18 || bytes[i+19] == 0x18) {
                return .revoked
            }
        }
        
        return .unknown
    }
}
