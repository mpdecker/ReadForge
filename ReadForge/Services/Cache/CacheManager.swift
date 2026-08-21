//
//  CacheManager.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation

/// Intelligent caching system for ReadForge
@MainActor
@Observable
final class CacheManager {
    
    // MARK: - Properties
    
    private let memoryCache = NSCache<NSString, NSCacheItem>()
    private let diskCacheURL: URL
    private let fileManager = FileManager.default
    
    /// Current cache usage in MB
    private(set) var cacheUsageMB: Double = 0
    
    /// Cache configuration
    private let maxMemoryCacheSize: Int = 50 * 1024 * 1024 // 50MB
    private let maxDiskCacheSize: Int64 = 200 * 1024 * 1024 // 200MB
    
    // MARK: - Cache Item
    
    class CacheItem {
        let data: Data
        let timestamp: Date
        let accessCount: Int
        let size: Int
        
        init(data: Data, timestamp: Date, accessCount: Int, size: Int) {
            self.data = data
            self.timestamp = timestamp
            self.accessCount = accessCount
            self.size = size
        }
        
        init(data: Data) {
            self.data = data
            self.timestamp = Date()
            self.accessCount = 1
            self.size = data.count
        }
        
        func withAccess() -> CacheItem {
            return CacheItem(
                data: data,
                timestamp: timestamp,
                accessCount: accessCount + 1,
                size: size
            )
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Set up disk cache directory
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access cache directory")
        }
        diskCacheURL = cacheDir.appendingPathComponent("ReadForgeCache")
        
        // Create cache directory if needed
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = maxMemoryCacheSize
        
        // Clean up old cache on launch
        Task {
            await cleanupOldCache()
            updateCacheUsage()
        }
    }
    
    // MARK: - Public Methods
    
    /// Store data in cache
    func store<T: Codable>(_ object: T, forKey key: String) async {
        do {
            let data = try JSONEncoder().encode(object)
            await storeRaw(data, forKey: key)
        } catch {
            ReadForgeLogger.error(category: "Cache", message: "Failed to encode object for cache", error: error)
        }
    }
    
    /// Store raw data in cache
    func storeRaw(_ data: Data, forKey key: String) async {
        let cacheItem = CacheItem(data: data)
        
        // Store in memory cache
        memoryCache.setObject(NSCacheItem(cacheItem), forKey: key as NSString, cost: cacheItem.size)
        
        // Store in disk cache for large items
        if data.count > 1024 * 1024 { // 1MB
            await storeToDisk(data, forKey: key)
        }
        
        updateCacheUsage()
        ReadForgeLogger.debug(category: "Cache", message: "Cached data for key: \(key)")
    }
    
    /// Retrieve data from cache
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        guard let data = await retrieveRaw(forKey: key) else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            ReadForgeLogger.error(category: "Cache", message: "Failed to decode object from cache", error: error)
            return nil
        }
    }
    
    /// Retrieve raw data from cache
    func retrieveRaw(forKey key: String) async -> Data? {
        // Check memory cache first
        if let nsCacheItem = memoryCache.object(forKey: key as NSString) {
            let cacheItem = nsCacheItem.cacheItem.withAccess()
            memoryCache.setObject(NSCacheItem(cacheItem), forKey: key as NSString, cost: cacheItem.size)
            return cacheItem.data
        }
        
        // Check disk cache
        if let diskData = await retrieveFromDisk(forKey: key) {
            // Promote to memory cache
            let cacheItem = CacheItem(data: diskData)
            memoryCache.setObject(NSCacheItem(cacheItem), forKey: key as NSString, cost: cacheItem.size)
            return diskData
        }
        
        return nil
    }
    
    /// Remove item from cache
    func remove(forKey key: String) async {
        memoryCache.removeObject(forKey: key as NSString)
        await removeFromDisk(forKey: key)
        updateCacheUsage()
    }
    
    /// Clear all cache
    func clearAll() async {
        memoryCache.removeAllObjects()
        await clearDiskCache()
        updateCacheUsage()
        ReadForgeLogger.debug(category: "Cache", message: "Cleared all cache")
    }
    
    /// Intelligent cache cleanup based on usage patterns
    func performIntelligentCleanup() async {
        let startTime = Date()
        
        // Remove least recently used items from memory cache
        await cleanupMemoryCache()
        
        // Remove old and rarely accessed items from disk cache
        await cleanupDiskCache()
        
        updateCacheUsage()
        
        let duration = Date().timeIntervalSince(startTime)
        ReadForgeLogger.performanceMetric(operation: "Intelligent Cache Cleanup", duration: duration)
    }
    
    // MARK: - Specialized Cache Methods
    
    /// Cache extracted text for documents
    func cacheExtractedText(_ text: String, for documentId: UUID) async {
        await store(text, forKey: "extracted_text_\(documentId.uuidString)")
    }
    
    /// Get cached extracted text
    func getCachedExtractedText(for documentId: UUID) async -> String? {
        return await retrieve(String.self, forKey: "extracted_text_\(documentId.uuidString)")
    }
    
    /// Cache cleaned text
    func cacheCleanedText(_ text: String, for documentId: UUID) async {
        await store(text, forKey: "cleaned_text_\(documentId.uuidString)")
    }
    
    /// Get cached cleaned text
    func getCachedCleanedText(for documentId: UUID) async -> String? {
        return await retrieve(String.self, forKey: "cleaned_text_\(documentId.uuidString)")
    }
    
    /// Cache section data — one `store` call per section, never the whole array in a single
    /// JSON blob. CLAUDE.md: "Store raw and clean text per section separately. Never load a
    /// full document into memory." The previous version JSON-encoded every section's raw+clean
    /// text for the whole document in one `JSONEncoder().encode([SectionData])` call.
    func cacheSectionData(_ sections: [SectionData], for documentId: UUID) async {
        for section in sections {
            await store(section, forKey: sectionCacheKey(documentId: documentId, order: section.order))
        }
        // A small index of which orders exist, so a reader can reconstruct the array without
        // guessing a section count — itself tiny (just integers), not document text.
        await store(sections.map(\.order), forKey: sectionIndexKey(for: documentId))
    }

    /// Get cached section data — reads each section individually and assembles the array here;
    /// only one section's text is ever decoded from disk/memory-cache at a time.
    func getCachedSectionData(for documentId: UUID) async -> [SectionData]? {
        guard let orders = await retrieve([Int].self, forKey: sectionIndexKey(for: documentId)) else { return nil }
        var result: [SectionData] = []
        for order in orders {
            guard let section = await retrieve(SectionData.self, forKey: sectionCacheKey(documentId: documentId, order: order)) else {
                return nil
            }
            result.append(section)
        }
        return result
    }

    private func sectionCacheKey(documentId: UUID, order: Int) -> String {
        "section_\(documentId.uuidString)_\(order)"
    }

    private func sectionIndexKey(for documentId: UUID) -> String {
        "sections_index_\(documentId.uuidString)"
    }
    
    /// Cache AI model results
    func cacheAIResult(_ result: String, for input: String) async {
        let hash = input.hash
        await store(result, forKey: "ai_result_\(hash)")
    }
    
    /// Get cached AI result
    func getCachedAIResult(for input: String) async -> String? {
        let hash = input.hash
        return await retrieve(String.self, forKey: "ai_result_\(hash)")
    }
    
    // MARK: - Private Methods
    
    private func storeToDisk(_ data: Data, forKey key: String) async {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        do {
            try data.write(to: fileURL)
        } catch {
            ReadForgeLogger.error(category: "Cache", message: "Failed to write to disk cache", error: error)
        }
    }
    
    private func retrieveFromDisk(forKey key: String) async -> Data? {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            return nil
        }
    }
    
    private func removeFromDisk(forKey key: String) async {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        try? fileManager.removeItem(at: fileURL)
    }
    
    private func clearDiskCache() async {
        do {
            let files = try fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            ReadForgeLogger.error(category: "Cache", message: "Failed to clear disk cache", error: error)
        }
    }
    
    private func cleanupMemoryCache() async {
        // NSCache automatically handles LRU eviction, but we can force cleanup if needed
        memoryCache.removeAllObjects()
    }
    
    private func cleanupDiskCache() async {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            
            var filesToRemove: [URL] = []
            var totalSize: Int64 = 0
            
            // Calculate total size and identify old files
            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                let modificationDate = attributes[.modificationDate] as? Date ?? Date.distantPast
                let size = attributes[.size] as? Int64 ?? 0
                
                totalSize += size
                
                // Remove files older than 7 days or if total cache exceeds limit
                let daysSinceModification = Date().timeIntervalSince(modificationDate) / (24 * 3600)
                if daysSinceModification > 7 || totalSize > maxDiskCacheSize {
                    filesToRemove.append(file)
                }
            }
            
            // Remove identified files
            for file in filesToRemove {
                try fileManager.removeItem(at: file)
            }
            
        } catch {
            ReadForgeLogger.error(category: "Cache", message: "Failed to cleanup disk cache", error: error)
        }
    }
    
    private func cleanupOldCache() async {
        // Remove cache files older than 30 days
        do {
            let files = try fileManager.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            
            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                let modificationDate = attributes[.modificationDate] as? Date ?? Date.distantPast
                let daysSinceModification = Date().timeIntervalSince(modificationDate) / (24 * 3600)
                
                if daysSinceModification > 30 {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            ReadForgeLogger.error(category: "Cache", message: "Failed to cleanup old cache", error: error)
        }
    }
    
    private func updateCacheUsage() {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            
            var totalSize: Double = 0
            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                let size = attributes[.size] as? Int64 ?? 0
                totalSize += Double(size)
            }
            
            cacheUsageMB = totalSize / 1024.0 / 1024.0
            
        } catch {
            cacheUsageMB = 0
        }
    }
}

// MARK: - NSCacheItem Wrapper

private class NSCacheItem: NSObject {
    let cacheItem: CacheManager.CacheItem
    
    init(_ cacheItem: CacheManager.CacheItem) {
        self.cacheItem = cacheItem
        super.init()
    }
}
