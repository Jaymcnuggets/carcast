//
//  DashcamStorageManager.swift
//  DrivingMode
//
//  Manages segmented dashcam video files, rolling FIFO disk quota pruning,
//  and protected emergency recording storage.
//

import Foundation

public final class DashcamStorageManager: @unchecked Sendable {
    public let baseDirectory: URL
    public let recordingsDirectory: URL
    public let emergencyDirectory: URL
    public var quotaBytes: Int64
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(baseDirectory: URL? = nil, quotaBytes: Int64 = 3 * 1024 * 1024 * 1024) {
        let base: URL
        if let baseDirectory = baseDirectory {
            base = baseDirectory
        } else {
            let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            base = docDir.appendingPathComponent("Dashcam", isDirectory: true)
        }
        self.baseDirectory = base
        self.recordingsDirectory = base.appendingPathComponent("Recordings", isDirectory: true)
        self.emergencyDirectory = base.appendingPathComponent("Emergency", isDirectory: true)
        self.quotaBytes = quotaBytes

        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: emergencyDirectory, withIntermediateDirectories: true)
    }

    public func newSegmentURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return recordingsDirectory.appendingPathComponent("dashcam_\(timestamp).mp4")
    }

    public func enforceQuota() {
        lock.lock()
        defer { lock.unlock() }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        var filesWithSizeAndDate: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for file in contents {
            guard let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]),
                  let size = resourceValues.fileSize,
                  let date = resourceValues.creationDate else { continue }
            filesWithSizeAndDate.append((url: file, size: Int64(size), date: date))
            totalSize += Int64(size)
        }

        // Sort oldest first (FIFO)
        filesWithSizeAndDate.sort {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }

        for file in filesWithSizeAndDate {
            if totalSize <= quotaBytes { break }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    @discardableResult
    public func lockAsEmergency(fileURL: URL) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let targetURL = emergencyDirectory.appendingPathComponent(fileURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: fileURL, to: targetURL)
            return targetURL
        } catch {
            return nil
        }
    }
}
