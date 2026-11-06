//
//  ZIPArchive.swift
//  OpenIntelligence
//
//  Moved unchanged from DocumentProcessor.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os
import CryptoKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision
import CoreImage
import Metal
import Tokenizers
import Compression
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - ZIP Archive Helper for Office Documents

/// Lightweight ZIP archive reader for extracting Office XML content
/// Uses Foundation's compression framework for memory-efficient extraction
final class ZIPArchive {
    private let fileHandle: FileHandle
    private let fileSize: UInt64
    private var centralDirectory: [String: CentralDirectoryEntry] = [:]

    struct CentralDirectoryEntry {
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let compressionMethod: UInt16
    }

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.fileHandle = handle

        // Get file size
        do {
            let endOffset = try handle.seekToEnd()
            self.fileSize = endOffset
            try handle.seek(toOffset: 0)
        } catch {
            try? handle.close()
            return nil
        }

        // Parse central directory
        if !parseCentralDirectory() {
            try? handle.close()
            return nil
        }
    }

    deinit {
        try? fileHandle.close()
    }

    /// Extract a file from the archive as a string
    func extractString(path: String) -> String? {
        guard let data = extractData(path: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Extract a file from the archive as data
    func extractData(path: String) -> Data? {
        guard let entry = centralDirectory[path] else { return nil }

        do {
            try fileHandle.seek(toOffset: UInt64(entry.localHeaderOffset))

            // Read local file header
            guard let localHeader = try fileHandle.read(upToCount: 30) else { return nil }
            guard localHeader.count >= 30 else { return nil }

            // Parse local header to get filename length and extra field length
            let filenameLength = UInt16(localHeader[26]) | (UInt16(localHeader[27]) << 8)
            let extraLength = UInt16(localHeader[28]) | (UInt16(localHeader[29]) << 8)

            // Skip filename and extra field
            let dataOffset = UInt64(entry.localHeaderOffset) + 30 + UInt64(filenameLength) + UInt64(extraLength)
            try fileHandle.seek(toOffset: dataOffset)

            // Read compressed data
            guard let compressedData = try fileHandle.read(upToCount: Int(entry.compressedSize)) else { return nil }

            // Decompress if needed
            if entry.compressionMethod == 0 {
                // Stored (no compression)
                return compressedData
            } else if entry.compressionMethod == 8 {
                // Deflate compression
                return decompressDeflate(compressedData, uncompressedSize: Int(entry.uncompressedSize))
            }

            return nil
        } catch {
            return nil
        }
    }

    private func parseCentralDirectory() -> Bool {
        // Find End of Central Directory record (search from end)
        let searchSize = min(65557, Int(fileSize))  // Max comment size + EOCD size
        let searchStart = fileSize - UInt64(searchSize)

        do {
            try fileHandle.seek(toOffset: searchStart)
            guard let searchData = try fileHandle.read(upToCount: searchSize) else { return false }

            // Look for EOCD signature (0x06054b50) from the end
            var eocdOffset: Int?
            for i in stride(from: searchData.count - 22, through: 0, by: -1) {
                if searchData[i] == 0x50 && searchData[i+1] == 0x4b &&
                   searchData[i+2] == 0x05 && searchData[i+3] == 0x06 {
                    eocdOffset = i
                    break
                }
            }

            guard let offset = eocdOffset else { return false }

            // Parse EOCD
            let cdEntries = UInt16(searchData[offset + 10]) | (UInt16(searchData[offset + 11]) << 8)
            let cdSize = UInt32(searchData[offset + 12]) | (UInt32(searchData[offset + 13]) << 8) |
                         (UInt32(searchData[offset + 14]) << 16) | (UInt32(searchData[offset + 15]) << 24)
            let cdOffset = UInt32(searchData[offset + 16]) | (UInt32(searchData[offset + 17]) << 8) |
                           (UInt32(searchData[offset + 18]) << 16) | (UInt32(searchData[offset + 19]) << 24)

            // Read central directory
            try fileHandle.seek(toOffset: UInt64(cdOffset))
            guard let cdData = try fileHandle.read(upToCount: Int(cdSize)) else { return false }

            // Parse central directory entries
            var pos = 0
            for _ in 0..<cdEntries {
                guard pos + 46 <= cdData.count else { break }

                // Check signature
                guard cdData[pos] == 0x50 && cdData[pos+1] == 0x4b &&
                      cdData[pos+2] == 0x01 && cdData[pos+3] == 0x02 else { break }

                let compressionMethod = UInt16(cdData[pos + 10]) | (UInt16(cdData[pos + 11]) << 8)
                let compressedSize = UInt32(cdData[pos + 20]) | (UInt32(cdData[pos + 21]) << 8) |
                                     (UInt32(cdData[pos + 22]) << 16) | (UInt32(cdData[pos + 23]) << 24)
                let uncompressedSize = UInt32(cdData[pos + 24]) | (UInt32(cdData[pos + 25]) << 8) |
                                       (UInt32(cdData[pos + 26]) << 16) | (UInt32(cdData[pos + 27]) << 24)
                let filenameLength = UInt16(cdData[pos + 28]) | (UInt16(cdData[pos + 29]) << 8)
                let extraLength = UInt16(cdData[pos + 30]) | (UInt16(cdData[pos + 31]) << 8)
                let commentLength = UInt16(cdData[pos + 32]) | (UInt16(cdData[pos + 33]) << 8)
                let localHeaderOffset = UInt32(cdData[pos + 42]) | (UInt32(cdData[pos + 43]) << 8) |
                                        (UInt32(cdData[pos + 44]) << 16) | (UInt32(cdData[pos + 45]) << 24)

                // Extract filename
                let filenameStart = pos + 46
                let filenameEnd = filenameStart + Int(filenameLength)
                guard filenameEnd <= cdData.count else { break }

                if let filename = String(data: cdData[filenameStart..<filenameEnd], encoding: .utf8) {
                    centralDirectory[filename] = CentralDirectoryEntry(
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize,
                        localHeaderOffset: localHeaderOffset,
                        compressionMethod: compressionMethod
                    )
                }

                pos = filenameEnd + Int(extraLength) + Int(commentLength)
            }

            return !centralDirectory.isEmpty
        } catch {
            return false
        }
    }

    /// Decompress deflate-compressed data using Compression framework
    private func decompressDeflate(_ data: Data, uncompressedSize: Int) -> Data? {
        // Use raw deflate (not zlib wrapped)
        var decompressed = Data(count: uncompressedSize)
        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        return result > 0 ? Data(decompressed.prefix(result)) : nil
    }
}
