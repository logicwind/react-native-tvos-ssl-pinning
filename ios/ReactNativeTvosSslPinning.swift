import Foundation
import React
import CommonCrypto

@objc(ReactNativeTvosSslPinning)
class ReactNativeTvosSslPinning: NSObject {
    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }
        
    @objc
    func fetchDataWithPinning(_ url: String,
                                options: NSDictionary,
                                resolver: @escaping RCTPromiseResolveBlock,
                                rejecter: @escaping RCTPromiseRejectBlock) {
        
        guard let url = URL(string: url) else {
            rejecter("INVALID_URL", "Invalid URL provided", nil)
            return
        }
        
        var request = URLRequest(url: url)
        
        // Set method
        let method = options["method"] as? String ?? "GET"
        request.httpMethod = method
        
        // Set headers
        if let headers = options["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Set body
        if let body = options["body"] as? String, method != "GET" {
            request.httpBody = body.data(using: .utf8)
        }
        
        // Set timeout
        let timeout = options["timeoutInterval"] as? TimeInterval ?? 10.0
        request.timeoutInterval = timeout / 1000.0 // Convert ms to seconds
        
        // Create session with SSL pinning
        let session = createURLSessionWithPinning(options: options)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                // Check if it's SSL pinning related error
                if (error as NSError).code == NSURLErrorServerCertificateUntrusted ||
                    (error as NSError).code == NSURLErrorSecureConnectionFailed {
                    rejecter("SSL_PINNING_FAILED", "SSL Certificate pinning failed: \(error.localizedDescription)", error)
                } else {
                    rejecter("NETWORK_ERROR", error.localizedDescription, error)
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                rejecter("INVALID_RESPONSE", "Invalid response type", nil)
                return
            }
            
            let responseDict: [String: Any] = [
                "status": httpResponse.statusCode,
                "url": httpResponse.url?.absoluteString ?? url.absoluteString,
                "headers": httpResponse.allHeaderFields,
                "data": String(data: data ?? Data(), encoding: .utf8) ?? ""
            ]
            
            resolver(responseDict)
        }.resume()
    }
    
    @objc
    func getCertificateFingerprint(_ hostname: String,
                                    resolver: @escaping RCTPromiseResolveBlock,
                                    rejecter: @escaping RCTPromiseRejectBlock) {
        
        guard let url = URL(string: "https://\(hostname)") else {
            rejecter("INVALID_URL", "Invalid hostname", nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        let session = URLSession(configuration: .default, delegate: CertificateExtractor(), delegateQueue: nil)
        
        session.dataTask(with: request) { _, _, error in
            // The delegate will handle the certificate extraction
            if let extractor = session.delegate as? CertificateExtractor {
                if let fingerprint = extractor.certificateFingerprint {
                    resolver(fingerprint)
                } else {
                    rejecter("NO_CERTIFICATE", "Could not extract certificate", error)
                }
            } else {
                rejecter("EXTRACTION_ERROR", "Certificate extraction failed", error)
            }
        }.resume()
    }

    @objc
    func getAvailableCertificates(_ resolver: @escaping RCTPromiseResolveBlock,
                                rejecter: @escaping RCTPromiseRejectBlock) {
        do {
            // Get the main bundle
            let bundle = Bundle.main
            
            // Get all files in the bundle
            let files = try FileManager.default.contentsOfDirectory(atPath: bundle.bundlePath)
            
            // Filter for certificate files
            let certFiles = files.filter { file in
                file.hasSuffix(".cer") || file.hasSuffix(".crt") || file.hasSuffix(".pem")
            }
            
            resolver(certFiles)
        } catch {
            rejecter("CERT_LIST_ERROR", "Failed to list certificates: \(error.localizedDescription)", error)
        }
    }

    @objc
    func validateCertificate(_ hostname: String,
                            expectedCert: String,
                            resolver: @escaping RCTPromiseResolveBlock,
                            rejecter: @escaping RCTPromiseRejectBlock) {
        
        getCertificateFingerprint(hostname) { fingerprint in
            if let actualFingerprint = fingerprint as? String {
                resolver(actualFingerprint == expectedCert)
            } else {
                resolver(false)
            }
        } rejecter: { _, _, _ in
            resolver(false)
        }
    }
  
    private func createURLSessionWithPinning(options: NSDictionary) -> URLSession {
        let config = URLSessionConfiguration.default
        
        if let timeout = options["timeoutInterval"] as? TimeInterval {
            config.timeoutIntervalForRequest = timeout / 1000.0
            config.timeoutIntervalForResource = timeout / 1000.0
        }
        
        let delegate = SSLPinningDelegate(options: options)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

// Separate class for extracting certificate fingerprints
class CertificateExtractor: NSObject, URLSessionDelegate {
    var certificateFingerprint: String?
    
    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Extract certificate fingerprint
        let serverCertData = SecCertificateCopyData(serverCertificate)
        let data = CFDataGetBytePtr(serverCertData)
        let size = CFDataGetLength(serverCertData)
        let certData = Data(bytes: data!, count: size)
        
        self.certificateFingerprint = sha256Base64(data: certData)
        
        // Allow connection for fingerprint extraction
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
    
    private func sha256Base64(data: Data) -> String {
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = digest.withUnsafeMutableBytes { digestBytes in
            data.withUnsafeBytes { dataBytes in
                CC_SHA256(dataBytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), digestBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return digest.base64EncodedString()
    }
}

class SSLPinningDelegate: NSObject, URLSessionDelegate {
    private let options: NSDictionary
    private var pinnedCertificates: [Data] = []
    private var pinnedPublicKeys: [String] = []
    private var disableAllSecurity: Bool = false
    private var hasPinningEnabled: Bool = false
    
    init(options: NSDictionary) {
        self.options = options
        super.init()
        setupPinning()
    }
    
    private func setupPinning() {
        // SSL Certificate Pinning
        if let sslPinning = options["sslPinning"] as? [String: Any],
           let certs = sslPinning["certs"] as? [String], !certs.isEmpty {
            print("🔒 Setting up SSL Certificate Pinning with certs: \(certs)")
            loadCertificates(certNames: certs)
            hasPinningEnabled = true
        }
        
        // Public Key Pinning
        if let pkPinning = options["pkPinning"] as? [String: Any],
           let publicKeys = pkPinning["publicKeys"] as? [String], !publicKeys.isEmpty {
            print("🔒 Setting up Public Key Pinning with keys: \(publicKeys)")
            pinnedPublicKeys = publicKeys
            hasPinningEnabled = true
        }
        
        // Disable security (development only)
        if let disable = options["disableAllSecurity"] as? Bool {
            disableAllSecurity = disable
            if disable {
                print("⚠️ SSL Security DISABLED - Development mode only!")
            }
        }
        
        print("🔒 SSL Pinning Status:")
        print("  - Certificates loaded: \(pinnedCertificates.count)")
        print("  - Public keys loaded: \(pinnedPublicKeys.count)")
        print("  - Security disabled: \(disableAllSecurity)")
        print("  - Pinning enabled: \(hasPinningEnabled)")
    }
    
    private func loadCertificates(certNames: [String]) {
        for certName in certNames {
            // Try different extensions and paths
            let possiblePaths = [
                Bundle.main.path(forResource: certName, ofType: "crt"),
                Bundle.main.path(forResource: certName, ofType: "cer"),
                Bundle.main.path(forResource: certName, ofType: "pem"),
                Bundle.main.path(forResource: "certificates/\(certName)", ofType: "crt"),
                Bundle.main.path(forResource: "certificates/\(certName)", ofType: "cer"),
                Bundle.main.path(forResource: "certificates/\(certName)", ofType: "pem")
            ]
            
            var certLoaded = false
            for path in possiblePaths {
                if let certPath = path,
                   let certData = NSData(contentsOfFile: certPath) as Data? {
                    pinnedCertificates.append(certData)
                    print("✅ Loaded certificate: \(certName) from \(certPath)")
                    certLoaded = true
                    break
                }
            }
            
            if !certLoaded {
                print("❌ Failed to load certificate: \(certName)")
                print("   Searched paths: \(possiblePaths.compactMap { $0 })")
            }
        }
    }
    
    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        print("🔒 SSL Challenge received for: \(challenge.protectionSpace.host)")
        
        // Disable all security checks (development only)
        if disableAllSecurity {
            print("⚠️ SSL Security bypassed - development mode")
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }
        
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            print("❌ No server trust available")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // If no pinning is configured, use default validation
        if !hasPinningEnabled {
            print("ℹ️ No SSL pinning configured, using default validation")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }
        
        // Certificate pinning
        if !pinnedCertificates.isEmpty {
            print("🔍 Validating certificate pinning...")
            if validateCertificatePinning(serverTrust: serverTrust) {
                print("✅ Certificate pinning validation passed")
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            } else {
                print("❌ Certificate pinning validation failed")
            }
        }
        
        // Public key pinning
        if !pinnedPublicKeys.isEmpty {
            print("🔍 Validating public key pinning...")
            if validatePublicKeyPinning(serverTrust: serverTrust) {
                print("✅ Public key pinning validation passed")
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            } else {
                print("❌ Public key pinning validation failed")
            }
        }
        
        // All pinning validations failed
        print("❌ SSL Pinning failed - connection blocked")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
    
    private func validateCertificatePinning(serverTrust: SecTrust) -> Bool {
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            print("❌ Could not get server certificate")
            return false
        }
        
        let serverCertData = SecCertificateCopyData(serverCertificate)
        let serverCertDataRef = CFDataGetBytePtr(serverCertData)
        let serverCertDataLength = CFDataGetLength(serverCertData)
        let serverCertNSData = Data(bytes: serverCertDataRef!, count: serverCertDataLength)
        
        let serverFingerprint = sha256Base64(data: serverCertNSData)
        print("🔍 Server certificate fingerprint: \(serverFingerprint)")
        
        for (index, pinnedCert) in pinnedCertificates.enumerated() {
            let pinnedFingerprint = sha256Base64(data: pinnedCert)
            print("🔍 Pinned certificate \(index) fingerprint: \(pinnedFingerprint)")
            
            if serverCertNSData == pinnedCert {
                print("✅ Certificate match found (binary comparison)")
                return true
            }
            
            if serverFingerprint == pinnedFingerprint {
                print("✅ Certificate match found (fingerprint comparison)")
                return true
            }
        }
        
        return false
    }
    
    private func validatePublicKeyPinning(serverTrust: SecTrust) -> Bool {
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let serverPublicKey = SecCertificateCopyKey(serverCertificate) else {
            print("❌ Could not extract server public key")
            return false
        }
        
        guard let serverPublicKeyData = SecKeyCopyExternalRepresentation(serverPublicKey, nil) else {
            print("❌ Could not get public key data")
            return false
        }
        
        let keyHash = sha256Base64(data: serverPublicKeyData as Data)
        print("🔍 Server public key hash: \(keyHash)")
        
        for (index, pinnedKey) in pinnedPublicKeys.enumerated() {
            print("🔍 Comparing with pinned key \(index): \(pinnedKey)")
            if keyHash == pinnedKey {
                print("✅ Public key match found")
                return true
            }
        }
        
        return false
    }
    
    private func sha256Base64(data: Data) -> String {
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = digest.withUnsafeMutableBytes { digestBytes in
            data.withUnsafeBytes { dataBytes in
                CC_SHA256(dataBytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), digestBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return digest.base64EncodedString()
    }
}
