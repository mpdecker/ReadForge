//
//  SecurityService.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation
import CryptoKit
import CommonCrypto

/// Security service for input validation, encryption, and secure storage
enum SecurityService {
    
    // MARK: - Input Validation
    
    /// Validates file paths to prevent directory traversal attacks
    static func validateFilePath(_ path: String) -> Bool {
        // Check for directory traversal attempts
        let dangerousPatterns = ["../", "..\\", "~", "/etc", "/var", "/usr", "/bin"]
        
        for pattern in dangerousPatterns {
            if path.contains(pattern) {
                ReadForgeLogger.securityValidationFailed(component: "FilePath", reason: "Contains dangerous pattern: \(pattern)")
                return false
            }
        }
        
        // Check for null bytes
        if path.contains("\0") {
            ReadForgeLogger.securityValidationFailed(component: "FilePath", reason: "Contains null bytes")
            return false
        }
        
        // Check for extremely long paths
        if path.count > 4096 {
            ReadForgeLogger.securityValidationFailed(component: "FilePath", reason: "Path too long")
            return false
        }
        
        return true
    }
    
    /// Validates document content to prevent injection attacks
    static func validateDocumentContent(_ content: String) -> Bool {
        // Check for script injection patterns
        let scriptPatterns = [
            "<script", "javascript:", "vbscript:", "onload=", "onerror=",
            "eval(", "setTimeout(", "setInterval("
        ]
        
        let lowercaseContent = content.lowercased()
        for pattern in scriptPatterns {
            if lowercaseContent.contains(pattern) {
                ReadForgeLogger.securityValidationFailed(component: "DocumentContent", reason: "Contains script pattern: \(pattern)")
                return false
            }
        }
        
        // Check for extremely large content
        if content.count > 10_000_000 { // 10MB limit
            ReadForgeLogger.securityValidationFailed(component: "DocumentContent", reason: "Content too large")
            return false
        }
        
        return true
    }
    
    /// Validates model file names and paths
    static func validateModelFile(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        
        // Only allow specific model file extensions
        let allowedExtensions = ["onnx", "gguf", "bin"]
        let fileExtension = url.pathExtension.lowercased()
        
        if !allowedExtensions.contains(fileExtension) {
            ReadForgeLogger.securityValidationFailed(component: "ModelFile", reason: "Invalid file extension: \(fileExtension)")
            return false
        }
        
        // Check filename length
        if filename.count > 255 {
            ReadForgeLogger.securityValidationFailed(component: "ModelFile", reason: "Filename too long")
            return false
        }
        
        // Check for dangerous characters in filename
        let dangerousChars = ["<", ">", ":", "\"", "|", "?", "*", "\0"]
        for char in dangerousChars {
            if filename.contains(char) {
                ReadForgeLogger.securityValidationFailed(component: "ModelFile", reason: "Contains dangerous character: \(char)")
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Encryption
    
    /// Encrypts data using AES-256-GCM
    static func encrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        let sealedData = try AES.GCM.seal(data, using: key)
        guard let combined = sealedData.combined else {
            throw SecurityError.encryptionFailed
        }
        return combined
    }
    
    /// Decrypts data using AES-256-GCM
    static func decrypt(_ encryptedData: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Generates a secure encryption key
    static func generateEncryptionKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    /// Derives a key from a password using PBKDF2
    static func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let keyByteCount = 32
        var derivedKey = Data(count: keyByteCount)

        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordData.withUnsafeBytes { $0.bindMemory(to: Int8.self).baseAddress },
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100000, // iterations
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyByteCount
                )
            }
        }
        
        guard result == kCCSuccess else {
            throw SecurityError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKey)
    }
    
    // MARK: - Hashing
    
    /// Computes SHA-256 hash of data
    static func hash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Computes SHA-256 hash of file
    static func hashFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return hash(data)
    }
    
    // MARK: - Secure Storage
    
    /// Securely stores sensitive data in Keychain
    static func storeInKeychain(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keychainError(status)
        }
    }
    
    /// Retrieves sensitive data from Keychain
    static func retrieveFromKeychain(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw SecurityError.keychainError(status)
        }
        
        return result as? Data
    }
    
    /// Deletes data from Keychain
    static func deleteFromKeychain(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainError(status)
        }
    }
    
    /// Generates cryptographically secure random data
    static func generateSecureRandomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { bytes -> Int32 in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return errSecAllocate
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard result == errSecSuccess else {
            ReadForgeLogger.securityEncryptionOperation(operation: "Random data generation", success: false)
            throw SecurityError.randomDataGenerationFailed
        }
        return data
    }
    
    /// Generates a secure random string
    static func secureRandomString(length: Int) throws -> String {
        let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var result = ""
        
        for _ in 0..<length {
            let randomData = try generateSecureRandomData(count: 1)
            let randomIndex = Int(randomData[0]) % charset.count
            let index = charset.index(charset.startIndex, offsetBy: randomIndex)
            result.append(charset[index])
        }
        
        return result
    }
    
    // MARK: - File Security
    
    /// Securely deletes a file by overwriting it first
    static func secureDeleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        
        // Overwrite file with random data multiple times
        let handle = try FileHandle(forWritingTo: url)
        for _ in 0..<3 {
            let randomData = try generateSecureRandomData(count: fileSize)
            handle.write(randomData)
            handle.seek(toFileOffset: 0)
        }
        handle.closeFile()
        
        // Delete the file
        try FileManager.default.removeItem(at: url)
        
        ReadForgeLogger.securityEncryptionOperation(operation: "Secure file deletion", success: true)
    }
    
    /// Validates file integrity using hash
    static func validateFileIntegrity(at url: URL, expectedHash: String) -> Bool {
        do {
            let actualHash = try hashFile(at: url)
            let isValid = actualHash == expectedHash
            
            if !isValid {
                ReadForgeLogger.securityValidationFailed(component: "FileIntegrity", reason: "Hash mismatch")
            }
            
            return isValid
        } catch {
            ReadForgeLogger.securityValidationFailed(component: "FileIntegrity", reason: error.localizedDescription)
            return false
        }
    }
}

// MARK: - Security Errors

enum SecurityError: LocalizedError {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case keychainError(OSStatus)
    case validationFailed(String)
    case randomDataGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed:
            return "Failed to derive encryption key"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .randomDataGenerationFailed:
            return "Failed to generate secure random data"
        }
    }
}

// MARK: - Secure File Wrapper

/// A wrapper for secure file operations
struct SecureFile {
    let url: URL
    private let encryptionKey: SymmetricKey
    
    init(url: URL, encryptionKey: SymmetricKey) {
        self.url = url
        self.encryptionKey = encryptionKey
    }
    
    /// Writes data securely to file
    func write(_ data: Data) throws {
        let encryptedData = try SecurityService.encrypt(data, key: encryptionKey)
        try encryptedData.write(to: url)
    }
    
    /// Reads data securely from file
    func read() throws -> Data {
        let encryptedData = try Data(contentsOf: url)
        return try SecurityService.decrypt(encryptedData, key: encryptionKey)
    }
    
    /// Deletes the secure file
    func delete() throws {
        try SecurityService.secureDeleteFile(at: url)
    }
}
